"""Blender (bpy) region turntable of the 80-90 S terrain with landing-site pins.

Inputs (from lunarsp.render_overview_prep): CACHE/renders/overview/grid_f32.bin
and overview_scene.json. Scene units are km in the south-pole ENU frame
(x = 90E, y = 0E, z = up at the pole).

Lighting is physical only: one SUN lamp from the SPICE direction with its real
angular diameter and irradiance (W/m^2), a grey Lambertian surface (albedo 0.12),
black world, no stars. Pins are emissive cones (not to scale) so they stay visible.

Camera heading h (deg) = map bearing the camera looks toward, clockwise from
0E toward 90E; h = 0 reproduces the map orientation (0E up, 90E right).

Outputs: frame_XX.png and pins_raw.json (per-frame normalised pin screen
positions, x right / y down from the top-left, plus a terrain-occlusion flag).

Run:
  blender -b --factory-startup -P pipeline/blender/render_overview.py -- \
      [--frames 0,9,18] [--res 1280x800] [--samples 64] [--dir <overview dir>]
"""

import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

ALBEDO = 0.12
N_FRAMES, STEP_DEG = 36, 10.0
CAM_ELEV_DEG = 35.0
CAM_DIST_KM = 1350.0  # from the look-at point; frames the whole 80S square
CAM_FOV_DEG = 40.0  # horizontal
CAM_SHIFT_Y = -0.085  # lens shift; pole lands ~0.36 from the top, whole square in frame at all headings
TARGET = Vector((0.0, 0.0, -12.0))  # pole, lowered a little for the curved edges
PIN_R_KM, PIN_H_KM = 3.0, 14.0  # pin cone size (display only)
PIN_EMISSION = 60.0  # ~white at the exposure below


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    default_dir = Path(os.environ.get("LUNAR_SP_CACHE", Path.home() / ".cache" / "lunar-sp")) / "renders" / "overview"
    p = argparse.ArgumentParser()
    p.add_argument("--dir", default=str(default_dir))
    p.add_argument("--frames", default="", help="comma list of frame indices (default all 36)")
    p.add_argument("--res", default="1280x800")
    p.add_argument("--samples", type=int, default=64)
    return p.parse_args(argv)


def srgb_to_linear(hex_colour):
    c = [int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c] + [1.0]


def build_terrain(path: Path, n: int):
    """Quad grid from (n, n, 3) float32 vertices via foreach_set (fast for ~1M verts)."""
    v = np.fromfile(path, dtype=np.float32)
    assert v.size == n * n * 3
    me = bpy.data.meshes.new("terrain")
    me.vertices.add(n * n)
    me.vertices.foreach_set("co", v)
    r, c = np.meshgrid(np.arange(n - 1), np.arange(n - 1), indexing="ij")
    i0 = (r * n + c).ravel()
    # Counter-clockwise seen from +z (row index grows toward -y): i0, i0+n, i0+n+1, i0+1
    quads = np.stack([i0, i0 + n, i0 + n + 1, i0 + 1], axis=1).ravel().astype(np.int32)
    nq = quads.size // 4
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads)
    me.polygons.add(nq)
    me.polygons.foreach_set("loop_start", np.arange(0, quads.size, 4, dtype=np.int32))
    me.update()
    me.validate()
    me.shade_smooth()
    ob = bpy.data.objects.new("terrain", me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new("regolith_grey")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfDiffuse")
    bsdf.inputs["Color"].default_value = (ALBEDO, ALBEDO, ALBEDO, 1.0)
    out = mat.node_tree.nodes["Material Output"]
    mat.node_tree.links.new(bsdf.outputs[0], out.inputs["Surface"])
    me.materials.append(mat)
    return ob


def emissive_material(name, hex_colour):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = srgb_to_linear(hex_colour)
    em.inputs["Strength"].default_value = PIN_EMISSION
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return mat


def build_pins(pins, colours):
    mats = {g: emissive_material(f"pin_{g}", c) for g, c in colours.items()}
    # Inverted cone: apex on the surface, base PIN_H_KM above it.
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.0, radius2=PIN_R_KM, depth=PIN_H_KM)
    proto = bpy.context.active_object
    proto.data.transform(Matrix.Translation((0, 0, PIN_H_KM / 2)))
    obs = []
    for p in pins:
        ob = bpy.data.objects.new("pin_" + p["id"], proto.data.copy())
        ob.data.materials.append(mats[p["group"]])
        ob.location = Vector(p["posKm"])
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
    bpy.data.objects.remove(proto)
    return obs


def setup_scene(sc, args, cfg):
    w, h = (int(x) for x in args.res.lower().split("x"))
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = args.samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    # Exposure: a sun-facing albedo-0.12 surface (radiance E*a/pi) maps to ~0.9.
    radiance = cfg["sunIrradianceWm2"] * ALBEDO / math.pi
    sc.view_settings.exposure = math.log2(0.9 / radiance)
    world = bpy.data.worlds.new("black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    sc.world = world

    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = cfg["sunIrradianceWm2"]  # W/m^2
    sun.angle = math.radians(cfg["sunAngularDiameterDeg"])
    sun_ob = bpy.data.objects.new("sun", sun)
    # Lamp shines along its local -Z, i.e. away from the Sun.
    sun_ob.rotation_euler = (-Vector(cfg["sunDirEnu"])).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(sun_ob)

    cam = bpy.data.cameras.new("cam")
    cam.sensor_fit = "HORIZONTAL"
    cam.angle = math.radians(CAM_FOV_DEG)
    cam.clip_start, cam.clip_end = 1.0, 10000.0
    cam.shift_y = CAM_SHIFT_Y  # recentre the foreshortened square (pole sits slightly above centre)
    cam_ob = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(cam_ob)
    sc.camera = cam_ob
    return cam_ob


def place_camera(cam_ob, heading_deg):
    hd, el = math.radians(heading_deg), math.radians(CAM_ELEV_DEG)
    look = Vector((math.sin(hd), math.cos(hd), 0.0))  # horizontal look direction
    cam_ob.location = TARGET - look * CAM_DIST_KM * math.cos(el) + Vector((0, 0, CAM_DIST_KM * math.sin(el)))
    cam_ob.rotation_euler = (TARGET - cam_ob.location).to_track_quat("-Z", "Y").to_euler()


def pin_screen(sc, cam_ob, terrain, pins, depsgraph):
    """Normalised screen position of each pin's surface anchor + terrain occlusion."""
    out = []
    for p in pins:
        anchor = Vector(p["posKm"]) + Vector((0, 0, 0.3))  # just above the surface
        s = world_to_camera_view(sc, cam_ob, anchor)
        d = anchor - cam_ob.location
        dist = d.length
        hit, loc, _n, _i, ob, _m = sc.ray_cast(depsgraph, cam_ob.location, d.normalized(), distance=dist)
        occluded = bool(hit and ob is not None and ob.name == terrain.name and (loc - cam_ob.location).length < dist - 0.5)
        on_screen = 0.0 <= s.x <= 1.0 and 0.0 <= s.y <= 1.0 and s.z > 0
        out.append({"id": p["id"], "x": round(s.x, 5), "y": round(1.0 - s.y, 5),
                    "onScreen": on_screen, "visible": on_screen and not occluded})
    return out


def main():
    args = parse_args()
    odir = Path(args.dir)
    cfg = json.loads((odir / "overview_scene.json").read_text(encoding="utf-8"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    t0 = time.time()
    terrain = build_terrain(odir / "grid_f32.bin", cfg["gridSize"])
    build_pins(cfg["pins"], cfg["groupColours"])
    cam_ob = setup_scene(sc, args, cfg)
    print(f"[overview] scene built in {time.time() - t0:.1f} s")

    frames = [int(f) for f in args.frames.split(",")] if args.frames else list(range(N_FRAMES))
    raw_path = odir / "pins_raw.json"
    raw = json.loads(raw_path.read_text()) if raw_path.exists() else {}
    for i in frames:
        heading = i * STEP_DEG
        place_camera(cam_ob, heading)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        pins = pin_screen(sc, cam_ob, terrain, cfg["pins"], dg)
        sc.render.filepath = str(odir / f"frame_{i:02d}.png")
        t = time.time()
        bpy.ops.render.render(write_still=True)
        dt = time.time() - t
        raw[f"{i:02d}"] = {"cameraAzimuthDeg": heading, "renderSeconds": round(dt, 1),
                           "res": args.res, "samples": args.samples, "pins": pins}
        print(f"[overview] frame {i:02d} heading {heading:.0f} deg: {dt:.1f} s, "
              f"{sum(p['visible'] for p in pins)}/{len(pins)} pins visible")
        raw_path.write_text(json.dumps(raw, indent=1))


if __name__ == "__main__":
    main()
