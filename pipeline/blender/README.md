# pipeline/blender: Blender 360° site panoramas

`render_site.py` renders the equirectangular panorama a 2 m observer would see at a site, for
each epoch in the `scene.json` written by `lunarsp.render_prep` (best window, longest night).
Blender 5.1, Cycles, CPU. It uses only Blender's bundled Python and numpy.

## Run

```sh
B="C:/Program Files/Blender Foundation/Blender 5.1/blender.exe"
# a real site (scene.json and mesh_f32.bin from render_prep)
"$B" -b --factory-startup -P pipeline/blender/render_site.py -- \
    --scene ~/.cache/lunar-sp/renders/<siteId>/scene.json \
    --out   ~/.cache/lunar-sp/renders/<siteId>/out [--res 3072] [--samples 32] [--exposure -4.5]
# only print the verified pixel mapping
"$B" -b --factory-startup -P pipeline/blender/render_site.py -- --calibrate
# synthetic test scene (600 m cone 8 km east, Sun az 135/el 2, Earth az 10/el 5), for development only
"$B" -b --factory-startup -P pipeline/blender/render_site.py -- --make-synthetic ~/.cache/lunar-sp/renders/_synthetic
```

Outputs in `--out`:
- `<key>.png`: an RGBA 8-bit colour render for each epoch. The sky is alpha 0.
- `mask.png`: terrain-only coverage (2 samples, no Sun or Earth). Alpha is 1 on terrain. Used for the skyline check.
- `render_meta.json`: size, `centerAzimuthDeg`, `azimuthIncreasesTo`, elevation range, Blender version, samples, exposure, render seconds, and how the mapping was verified.

## Image mapping (verified, not assumed)

Every run first renders three emissive markers on an empty scene: green at az 0°/el 0°, red at
az 90°/el 10°, and blue at az 180°/el −5°. It renders them at 1024×512, finds their centroids with
numpy, and derives the mapping. If the centre is not north, it rotates the camera and calibrates again.
Blender 5.1.2 result: **centre = azimuth 0° (north, away from the pole), azimuth increases to the
right, top = +90°, bottom = −90°**. The maximum marker residual is 0.25° (under one calibration pixel). So the native output already follows the app contract (contract 3).
The camera is a panoramic equirectangular camera at (0, 0, eyeHeightM) with rotation X = 90°. Blender world axes are ENU (x = E, y = N, z = Up).

## Physics

| Element | Model |
|---|---|
| Terrain | `mesh_f32.bin` (LOLA, spherical Moon, local ENU). Quads link neighbouring rays and radii. A triangle fan from the site ground point covers the unresolved <120 m near field. Diffuse BSDF, albedo 0.12 grey, smooth shading. |
| Sun light | SUN lamp, strength = `irradianceWm2`, angle = 2 × angular radius, so penumbrae are real. |
| Sun disk | Emissive sphere 2000 km away along `dirEnu` with the true angular radius. It is visible to the camera only, so terrain can occlude it. Strength E/α² makes it clip to white. |
| Earth | Plain diffuse sphere 2000 km away with the true angular radius. RGB (0.26, 0.30, 0.38) is a disk-average colour, not a texture. It is lit by the Sun lamp, so the phase is geometric. Camera-only: it casts no shadow and adds no bounce light. |
| Earthshine | SUN lamp from Earth's direction, 0.11 W/m² × illuminated fraction. |
| Sky | Black. No stars, no ambient light. |
| Exposure | Fixed for all sites and epochs: AgX view, −4.5 EV (chosen on derosa2012-cr1 at 3072×1536: sunlit terrain p50 ≈ 15, p99 ≈ 75, max ≈ 200 of 255, nothing clipped; −5.5 was too dark, −4.0 leaves less headroom for steeper sun-facing walls at other sites). The Sun lamp uses the full-disk irradiance (not the visibility-weighted power proxy); terrain occludes the disk geometrically. At night only earthshine (0.11 W/m² × lit fraction) and any distant sunlit peaks show, which is physically correct at a fixed exposure. |

Measured convention (Cycles 5.1): an albedo-1 surface under a SUN lamp of strength E renders at about albedo × E
(0.87 × E measured through an 8-bit PNG). It is not E/π.

## Performance (6-core Ryzen, CPU)

- Mesh: 1440 rays × 1350 radii gives 1.94 M vertices and faces. It builds in 12 s with numpy `foreach_set`.
- Synthetic scene, 1024×512, 8 samples: 12.5 s per epoch, mask 1.9 s. Calibration and startup add about 15 s.
- Real site (derosa2012-cr1, 1.95 M faces, mesh built in 4 s), 1024×512: 8 samples 14.9 / 11.0 s (best / night),
  32 samples 34.3 / 27.7 s. That is about 0.8 s per sample per 0.5 MP plus about 8 s fixed cost per epoch.
- Estimate for 3072×1536 with 32 samples (9× the pixels): about 4 min per epoch and about 9 min per site including
  the mask and startup. All 16 sites take about 2.5 h. The measured value is written to `render_meta.json` → `renderSeconds`.

## Skyline check (real site)

For derosa2012-cr1 at 1024×512, the topmost terrain pixel of `mask.png` in each column was compared with the
`horizons.json` 2 m mask. Median difference +0.03°, p95 |Δ| 0.30°, max 0.43°. One pixel is 0.35°.
The ray-traced skyline therefore agrees with the ray-marched horizon to within about one pixel.

## Known limitations

- The Earth sphere could, in principle, be shadowed from the Sun lamp by distant terrain. This is negligible for Earth elevations of a few degrees at 2000 km, and it is not guarded.
- OIDN denoising is on for colour renders (`--no-denoise` to disable). The mask is never denoised.
- Near-field (<120 m) terrain is a flat fan, because the DEM does not resolve it.
