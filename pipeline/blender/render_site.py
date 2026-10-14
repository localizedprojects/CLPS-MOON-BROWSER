"""Lunar Horizon: 360-degree site panorama renderer (Blender 5.1, Cycles, CPU).

Run headless:
  blender -b --factory-startup -P pipeline/blender/render_site.py -- \
      --scene <scene.json> --out <dir> [--res 3072] [--samples 32] [--exposure EV] [--calibrate]
  blender -b --factory-startup -P pipeline/blender/render_site.py -- --make-synthetic <dir>

Inputs follow the render_prep contract (scene.json + mesh_f32.bin, local ENU metres,
x=East, y=North, z=Up, origin = site ground point). Blender world axes are used as ENU
directly, so azimuth a / elevation e maps to (sin a cos e, cos a cos e, sin e).

Outputs in --out: <key>.png per epoch (RGBA, sky alpha 0), mask.png (terrain coverage)
and render_meta.json (empirically verified pixel -> azimuth/elevation mapping).

Physics (no cosmetic content): terrain is a grey Lambertian surface (albedo 0.12) lit
by a SUN lamp with the real irradiance and the real solar angular diameter (so penumbrae
are physical); the visible Sun disk is an emissive sphere seen by the camera only; Earth
is a plain diffuse sphere lit by the same Sun lamp (so its phase is geometric); earthshine
is a weak SUN lamp from Earth (0.11 W/m^2 x illuminated fraction). Sky is black.
"""
import argparse
import json
import math
import os
import sys
import tempfile
import time

import bpy
import numpy as np
from mathutils import Vector

DIST_M = 2.0e6              # distance of the Sun/Earth proxy spheres from the eye
TERRAIN_ALBEDO = 0.12       # LOLA-typical highland normal albedo, grey
EARTH_RGB = (0.26, 0.30, 0.38)  # plain disk-averaged Earth colour (bond albedo ~0.3), no texture
EARTHSHINE_FULL_WM2 = 0.11  # earthshine irradiance at full Earth (contract)
SOLAR_CONSTANT_WM2 = 1361.0  # same constant as lunarsp.config (power proxy)
AU_KM = 149597870.7
DEFAULT_EV = -2.0           # one fixed exposure for every site/epoch (see README)
FILL_STRENGTH = 0.0         # set from --fill (visualisation aid; 0 = purely physical lighting)
DEFAULT_FILL = 3.0
NEAR_FIELD_RGB = (0.16, 0.18, 0.24)  # unlit slate: unresolved ground < 120 m (not real terrain)
NEAR_FIELD_EMIT = 0.25


# ----------------------------------------------------------------------------- helpers
def azel_to_vec(az_deg, el_deg):
    a, e = math.radians(az_deg), math.radians(el_deg)
    return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))


def vec_to_azel(v):
    v = Vector(v).normalized()
    return math.degrees(math.atan2(v.x, v.y)) % 360.0, math.degrees(math.asin(max(-1, min(1, v.z))))


def emission_mat(name, rgb, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def diffuse_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    d = nt.nodes.new("ShaderNodeBsdfDiffuse")
    d.inputs["Color"].default_value = (*rgb, 1.0)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(d.outputs[0], out.inputs["Surface"])
    return m


def add_sphere(name, centre, radius, mat, segments=64):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2,
                                         radius=radius, location=centre)
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return ob


def earth_phase_mat(name, rgb, sun_dir, irradiance):
    """Unlit Lambertian-phase Earth: emission = albedo * E * max(0, N.S).

    Identical to what the Sun lamp gives a diffuse sphere, but immune to the
    camera-invisible fill light, so Earth's night side stays dark and the
    phase stays exactly geometric."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sv = nt.nodes.new("ShaderNodeCombineXYZ")
    sv.inputs[0].default_value, sv.inputs[1].default_value, sv.inputs[2].default_value = sun_dir
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = "MAXIMUM"
    mx.inputs[1].default_value = 0.0
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = irradiance
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])
    nt.links.new(sv.outputs[0], dot.inputs[1])
    nt.links.new(dot.outputs["Value"], mx.inputs[0])
    nt.links.new(mx.outputs[0], mul.inputs[0])
    nt.links.new(mul.outputs[0], em.inputs["Strength"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def camera_only(ob):
    """Visible to camera rays only (no shadows, no indirect light)."""
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    ob.visible_transmission = False
    ob.visible_volume_scatter = False


def sun_lamp(name, direction, strength, angle_rad):
    """SUN lamp shining FROM `direction` (unit ENU vector toward the source)."""
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = strength
    ld.angle = angle_rad
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector(direction).normalized().to_track_quat("Z", "Y")  # lamp +Z -> source
    return ob


def render_png(scene, path, samples, transparent=True):
    scene.cycles.samples = samples
    scene.render.film_transparent = transparent
    s = scene.render.image_settings
    s.file_format = "PNG"
    s.color_mode = "RGBA"
    s.color_depth = "8"
    scene.render.filepath = path
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    return time.time() - t0


# ----------------------------------------------------------------------------- scene setup
BAND_DEG = 30.0  # set from --band


def band_height(res):
    return int(round(res * 2 * BAND_DEG / 360.0))


def setup_scene(res, eye_h):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.resolution_x = res
    scene.render.resolution_y = band_height(res)
    scene.render.resolution_percentage = 100
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 4
    scene.cycles.glossy_bounces = 0
    scene.cycles.transmission_bounces = 0
    scene.cycles.transparent_max_bounces = 0
    scene.cycles.sample_clamp_indirect = 0.0
    # Sky: black to the camera (no stars). Optional uniform FILL light that only
    # non-camera rays see: a labelled visualisation aid that lifts shadowed
    # terrain so its shape is readable; sunlit terrain stays far brighter.
    w = bpy.data.worlds.new("black")
    w.use_nodes = True
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    lp = nt.nodes.new("ShaderNodeLightPath")
    fill = nt.nodes.new("ShaderNodeBackground")
    fill.inputs["Color"].default_value = (1, 1, 1, 1)
    fill.inputs["Strength"].default_value = FILL_STRENGTH
    black = nt.nodes.new("ShaderNodeBackground")
    black.inputs["Color"].default_value = (0, 0, 0, 1)
    black.inputs["Strength"].default_value = 0.0
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(fill.outputs["Background"], mix.inputs[1])
    nt.links.new(black.outputs["Background"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    scene.world = w
    # panoramic equirectangular camera at the eye; rot X=90 deg makes the view level, looking +Y (north)
    cd = bpy.data.cameras.new("pano")
    cd.type = "PANO"
    cd.panorama_type = "EQUIRECTANGULAR"
    # only render the +-BAND_DEG elevation band (all horizon/Sun/Earth content): square angular pixels
    cd.latitude_min, cd.latitude_max = math.radians(-BAND_DEG), math.radians(BAND_DEG)
    cd.clip_start = 0.05
    cd.clip_end = 5.0e6
    cam = bpy.data.objects.new("pano", cd)
    scene.collection.objects.link(cam)
    cam.location = (0.0, 0.0, eye_h)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = cam
    return scene, cam


# ----------------------------------------------------------------------------- calibration
MARKERS = [(0.0, 0.0, (0, 1, 0)), (90.0, 10.0, (1, 0, 0)), (180.0, -5.0, (0, 0, 1))]


def calibrate(scene, cam, res=1024):
    """Render three coloured markers at known az/el on an empty scene, locate them in the
    image with numpy and derive the pixel -> (az, el) mapping. Returns a dict."""
    vs = scene.view_settings
    saved = (scene.render.resolution_x, scene.render.resolution_y, vs.view_transform, vs.exposure,
             scene.render.filepath)
    scene.render.resolution_x, scene.render.resolution_y = res, band_height(res)
    vs.view_transform, vs.exposure = "Standard", 0.0
    objs = []
    for az, el, rgb in MARKERS:
        r = 1000.0 * math.sin(math.radians(0.6))  # ~0.6 deg angular radius at 1 km
        objs.append(add_sphere(f"marker_{az:g}", azel_to_vec(az, el) * 1000.0 + cam.location, r,
                               emission_mat(f"m{az:g}", rgb, 1.0), segments=24))
    path = os.path.join(tempfile.gettempdir(), "polar_horizon_calib.png")
    render_png(scene, path, samples=1)
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[::-1]  # row 0 = top
    bpy.data.images.remove(img)
    for ob in objs:
        bpy.data.objects.remove(ob, do_unlink=True)
    scene.render.resolution_x, scene.render.resolution_y, vs.view_transform, vs.exposure, scene.render.filepath = saved

    found = {}
    for az, el, rgb in MARKERS:
        ch = int(np.argmax(rgb))
        others = [c for c in range(3) if c != ch]
        sel = (px[..., ch] > 0.5) & (px[..., others].max(-1) < 0.2)
        ys, xs = np.nonzero(sel)
        if xs.size == 0:
            raise RuntimeError(f"calibration marker az={az} not found")
        ang = 2 * np.pi * (xs + 0.5) / w  # circular mean handles wrap at the image edge
        xf = (math.atan2(np.sin(ang).mean(), np.cos(ang).mean()) / (2 * np.pi)) % 1.0
        found[az] = (xf, (ys.mean() + 0.5) / h, el)
    x0 = found[0.0][0]
    d90 = ((found[90.0][0] - x0 + 0.5) % 1.0) - 0.5
    sign = 1.0 if d90 > 0 else -1.0
    centre = (sign * (0.5 - x0) * 360.0) % 360.0
    # check every marker against the derived mapping
    err = 0.0
    for az, (xf, yf, el) in found.items():
        az_pred = (centre + sign * (xf - 0.5) * 360.0) % 360.0
        el_pred = BAND_DEG - 2.0 * BAND_DEG * yf
        err = max(err, abs(((az_pred - az + 180) % 360) - 180), abs(el_pred - el))
    return {"centerAzimuthDeg": round(centre, 3), "azimuthIncreasesTo": "right" if sign > 0 else "left",
            "maxMarkerErrorDeg": round(err, 3), "calibResolution": [w, h]}


def verified_mapping(scene, cam):
    cal = calibrate(scene, cam)
    print("calibration:", cal)
    c = cal["centerAzimuthDeg"]
    if min(c, 360 - c) > 0.05:
        # rotating the camera +c about world Z (counter-clockwise from above) moves the view centre by -c
        cam.rotation_euler.z += math.radians(c if cal["azimuthIncreasesTo"] == "right" else -c)
        cal = calibrate(scene, cam)
        print("calibration after camera correction:", cal)
    if cal["maxMarkerErrorDeg"] > 0.5:
        raise RuntimeError(f"calibration residual too large: {cal}")
    return cal


# ----------------------------------------------------------------------------- terrain
def build_terrain(scene_dir, meshinfo):
    nAz, nR = meshinfo["nAz"], meshinfo["nR"]
    V = np.fromfile(os.path.join(scene_dir, meshinfo["file"]), "<f4")
    assert V.size == nAz * nR * 3, "mesh size mismatch"
    verts = np.concatenate([np.zeros(3, np.float32), V])  # vertex 0 = site ground point (fan apex)
    i = np.arange(nAz)[:, None]
    i1 = (i + 1) % nAz
    vid = lambda ii, jj: 1 + ii * nR + jj
    j = np.arange(nR - 1)[None, :]
    # quads ordered counter-clockwise from above (normals up): (i,j) (i+1,j) (i+1,j+1) (i,j+1)
    quads = np.stack([vid(i, j), vid(i1, j), vid(i1, j + 1), vid(i, j + 1)], -1).reshape(-1, 4)
    # fan from the site ground point to the first ring (stands in for the unresolved <120 m near field)
    fan = np.stack([np.zeros(nAz, int), vid(i1[:, 0], 0), vid(i[:, 0], 0)], -1)
    loops = np.concatenate([fan.ravel(), quads.ravel()]).astype(np.int32)
    starts = np.concatenate([np.arange(nAz) * 3, nAz * 3 + np.arange(len(quads)) * 4]).astype(np.int32)

    me = bpy.data.meshes.new("terrain")
    me.vertices.add(len(verts) // 3)
    me.vertices.foreach_set("co", verts)
    me.loops.add(len(loops))
    me.loops.foreach_set("vertex_index", loops)
    me.polygons.add(len(starts))
    me.polygons.foreach_set("loop_start", starts)
    me.update(calc_edges=True)
    me.shade_smooth()
    me.materials.append(diffuse_mat("regolith", (TERRAIN_ALBEDO,) * 3))
    # near-field fan: constant, unlit colour so it cannot fake lit/shadowed sectors
    me.materials.append(emission_mat("near_field_unresolved", NEAR_FIELD_RGB, NEAR_FIELD_EMIT))
    mi = np.zeros(len(starts), np.int32)
    mi[:nAz] = 1
    me.polygons.foreach_set("material_index", mi)
    ob = bpy.data.objects.new("terrain", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ----------------------------------------------------------------------------- epoch lighting
def build_epoch(ep):
    """Create Sun lamp + disk, Earth sphere and earthshine lamp for one epoch; return objects."""
    s, e = ep["sun"], ep["earth"]
    objs = []
    sd = Vector(s["dirEnu"]).normalized()
    a_s = math.radians(s["angRadiusDeg"])
    # Lamp strength = FULL-disk irradiance at this range. scene.json's irradianceWm2 is the site's
    # power proxy (already x visibleFraction); using it here would double-count the horizon, because
    # the lamp's real angular size already makes terrain occlude part of the disk (penumbra), and it
    # would leave distant sunlit peaks and Earth unlit whenever the Sun is below the site's horizon.
    e_full = SOLAR_CONSTANT_WM2 * (AU_KM / s["rangeKm"]) ** 2
    objs.append(sun_lamp("sun", sd, e_full, 2 * a_s))
    # disk radiance: E / solid angle; Cycles shows emission strength S as pixel S, and a Lambertian
    # surface under irradiance E as albedo*E, i.e. pixel = pi*radiance -> S = E / (pi a^2) * pi = E / a^2
    disk_strength = e_full / (a_s * a_s)
    disk = add_sphere("sun_disk", sd * DIST_M, DIST_M * math.sin(a_s),
                      emission_mat("sun_disk", (1, 1, 1), disk_strength), segments=48)
    camera_only(disk)
    objs.append(disk)

    ed = Vector(e["dirEnu"]).normalized()
    a_e = math.radians(e["angRadiusDeg"])
    earth = add_sphere("earth", ed * DIST_M, DIST_M * math.sin(a_e),
                       earth_phase_mat("earth", EARTH_RGB, tuple(sd), e_full))
    camera_only(earth)  # seen by camera only; geometric phase from the Sun direction, casts no shadow
    objs.append(earth)
    objs.append(sun_lamp("earthshine", ed, EARTHSHINE_FULL_WM2 * e["illuminatedFraction"], 2 * a_e))
    return objs


# ----------------------------------------------------------------------------- synthetic test scene
def make_synthetic(out_dir):
    """Write a synthetic scene.json + mesh: a 600 m cone hill 8 km east of the site on a
    spherical Moon; Sun az 135 el 2; Earth az 10 el 5 (gibbous). For development only."""
    os.makedirs(out_dir, exist_ok=True)
    R = 1737.4e3
    radii = list(np.arange(120.0, 2000.0, 20.0))
    r = 2000.0
    while r <= 300e3:
        radii.append(r)
        r *= 1.004
    d = np.array(radii)
    nAz = 1440
    a = np.radians(np.arange(nAz) * 360.0 / nAz)[:, None]
    t = d[None, :] / R
    hx, hy = np.sin(t) * np.sin(a) * R, np.sin(t) * np.cos(a) * R   # horizontal offsets
    h = 600.0 * np.clip(1 - np.hypot(hx - 8000.0, hy) / 4000.0, 0, 1)  # cone hill at E 8 km
    xyz = np.stack([(R + h) * np.sin(t) * np.sin(a), (R + h) * np.sin(t) * np.cos(a),
                    (R + h) * np.cos(t) - R], -1).astype("<f4")
    xyz.tofile(os.path.join(out_dir, "mesh_f32.bin"))

    def body(az, el, rng, rad_km, extra):
        v = azel_to_vec(az, el)
        return dict(az=az, el=el, rangeKm=rng, angRadiusDeg=math.degrees(math.asin(rad_km / rng)),
                    visibleFraction=1.0 if el > 0 else 0.0, dirEnu=[v.x, v.y, v.z], **extra)

    def epoch(key, sun_az, sun_el, e_az, e_el):
        ang = azel_to_vec(sun_az, sun_el).angle(azel_to_vec(e_az, e_el))
        frac = (1 + math.cos(math.pi - ang)) / 2  # phase at Earth ~ 180 deg - Sun-Moon-Earth angle
        sun = body(sun_az, sun_el, 1.496e8, 695700.0, {"irradianceWm2": 1361.0 if sun_el > 0 else 0.0})
        return {"key": key, "label": f"synthetic {key}", "utc": "2026-10-09T00:00:00Z", "unixMs": 0,
                "sun": sun, "earth": body(e_az, e_el, 384400.0, 6378.1366, {"illuminatedFraction": frac})}

    scene = {"siteId": "_synthetic", "name": "Synthetic cone test", "lat": -89.5, "lon": 0.0,
             "groundHeightM": 0.0, "eyeHeightM": 2.0,
             "mesh": {"file": "mesh_f32.bin", "nAz": nAz, "nR": len(radii), "radiiM": [round(x, 3) for x in radii],
                      "noDataFilled": 0},
             "epochs": [epoch("best", 135.0, 2.0, 10.0, 5.0), epoch("night", 200.0, -3.0, 10.0, 5.0)],
             "notes": ["SYNTHETIC test scene, not real data"]}
    with open(os.path.join(out_dir, "scene.json"), "w") as f:
        json.dump(scene, f, indent=1)
    print("synthetic scene written to", out_dir)


# ----------------------------------------------------------------------------- main
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene")
    ap.add_argument("--out")
    ap.add_argument("--res", type=int, default=3072)
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--exposure", type=float, default=DEFAULT_EV)
    ap.add_argument("--band", type=float, default=30.0, help="render elevations -band..+band deg only")
    ap.add_argument("--fill", type=float, default=DEFAULT_FILL, help="camera-invisible uniform fill light (0 = physical only)")
    ap.add_argument("--calibrate", action="store_true", help="only run the marker calibration and print it")
    ap.add_argument("--no-denoise", action="store_true")
    ap.add_argument("--make-synthetic", metavar="DIR")
    a = ap.parse_args(argv)
    global FILL_STRENGTH, BAND_DEG
    FILL_STRENGTH = a.fill
    BAND_DEG = a.band
    if a.make_synthetic:
        return make_synthetic(a.make_synthetic)

    sc = json.load(open(a.scene)) if a.scene else {"eyeHeightM": 2.0}
    scene, cam = setup_scene(a.res, sc["eyeHeightM"])
    cal = verified_mapping(scene, cam)  # always run: cheap (~1 s) and proves the mapping for this build
    if a.calibrate:
        print(json.dumps(cal))
        return
    os.makedirs(a.out, exist_ok=True)

    vs = scene.view_settings
    vs.view_transform = "AgX"
    vs.look = "None"
    vs.exposure = a.exposure
    scene.cycles.use_denoising = not a.no_denoise

    t0 = time.time()
    terrain = build_terrain(os.path.dirname(os.path.abspath(a.scene)), sc["mesh"])
    print(f"terrain built: {len(terrain.data.vertices)} verts, {len(terrain.data.polygons)} faces, "
          f"{time.time() - t0:.1f} s")

    times = {}
    for ep in sc["epochs"]:
        objs = build_epoch(ep)
        times[ep["key"]] = render_png(scene, os.path.join(a.out, f"{ep['key']}.png"), a.samples)
        print(f"rendered {ep['key']} in {times[ep['key']]:.1f} s")
        for ob in objs:
            bpy.data.objects.remove(ob, do_unlink=True)

    # terrain-only coverage mask: no Sun/Earth objects, alpha = terrain
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    times["mask"] = render_png(scene, os.path.join(a.out, "mask.png"), 2)

    meta = {"width": scene.render.resolution_x, "height": scene.render.resolution_y,
            "centerAzimuthDeg": cal["centerAzimuthDeg"], "azimuthIncreasesTo": cal["azimuthIncreasesTo"],
            "elevationTopDeg": BAND_DEG, "elevationBottomDeg": -BAND_DEG,
            "blender": bpy.app.version_string, "samples": a.samples, "exposureEv": a.exposure, "fillLight": a.fill,
            "nearField": "unlit uniform slate fan (< 120 m, unresolved by the DEM)",
            "verified": (f"marker test in this run: emissive spheres at az/el (0,0) (90,10) (180,-5) rendered "
                         f"{cal['calibResolution'][0]}x{cal['calibResolution'][1]} and located by numpy centroid; "
                         f"max residual {cal['maxMarkerErrorDeg']} deg"),
            "renderSeconds": {k: round(v, 1) for k, v in times.items()},
            "siteId": sc.get("siteId"), "viewTransform": "AgX", "denoise": not a.no_denoise,
            "terrainAlbedo": TERRAIN_ALBEDO,
            "sunLamp": "strength = full-disk irradiance 1361 W/m^2 x (1 au/r)^2, angle = true solar diameter; "
                       "terrain occludes the disk geometrically (no visibleFraction factor)"}
    with open(os.path.join(a.out, "render_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("done:", json.dumps(meta["renderSeconds"]))


if __name__ == "__main__":
    main()
