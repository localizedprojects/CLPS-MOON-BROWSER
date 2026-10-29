# Lander's view: build spec (merged)

This spec was written against worktree `6ee08b1`. It merges two designs into one plan:
- **Design A (fidelity-first).** Its rules for geometry, light and honesty are **binding**.
- **Design B (experience-first).** Its placement, interaction, performance and accessibility plan is adopted wherever it does not conflict with A.

Every disagreement is resolved in the table in §0, with the reason. Anything that could not be built and tested by two builders in about 300k tokens is listed in "Out of scope".

## 0. Decisions on the disagreements

| # | Topic | A says | B says | Decision and reason |
|---|---|---|---|---|
| D1 | Where the view lives | New `Map \| Lander's view` switch | Third segment in the existing view switch | **B.** One switch, the same slot, and `_LightMapState` already owns request, pump, prefetch, eclipse and legend. Fidelity is unaffected because the near frame is the close-up map's own `LightRequest` (D2). |
| D2 | Same frames as the map | `lightRequestFor` helper | Reuse `_LightMapState`'s request | **Both.** Extract `LightRequest lightRequestFor(AppState s, {required LightExtent extent, double? tMs, bool? coarse})`. `_maybeRequest`, `_prefetch` and the lander all use it, so the map and the 3D view get identical keys and the same `CachedLightEngine` entry. |
| D3 | Mesh topology | Grid cells: pixel-centre vertices, 4-triangle fan per cell, polar near-field lattice | Polar rings with azimuth LOD, bilinear heights | **A** (binding geometry). Heights and light then attach to grid pixels by index, with no resampling. Measured skyline error against `computeCoarseHorizon` is ≤ 0.20°; B's lattice re-samples. |
| D4 | Light lookup | Exact pixel index | Nearest pixel by lat/lon | **A** (binding light). |
| D5 | Light beyond 64 km | New site-centred far frame (±300 km) | Reuse the pole-centred region frame, hatched past 80°S | **A**, with **B's scheduling**. The region frame stops 304 km from the pole, so for Mons Mouton-like sites (about 150 km from the pole) looking north it leaves skyline-defining terrain (up to about 200 km away) unlit. The far frame is requested only after the near frame lands. On the web it is skipped while playing. |
| D6 | Where the mesh is built | In the isolate | Main thread, `runSliced`, from `s.dem()` | **B.** No isolate protocol change, and the DEM is already on the main thread on every platform. The heights are still identical by construction (shared `blockMeanRow`, test T1). |
| D7 | Near ground (< 800 m) | Polar lattice from the same surface, see-through (alpha 0.35) above the far skyline | Flat hatched band under 600 m | **A** (binding). It follows the light engine's own 800 m cut (lag 2 px × 400 m). Opaque near ground would hide a Sun that the map, the masks and the sky plot all call visible. |
| D8 | Occlusion culling | Exact, conservative, 0.05° azimuth bins | Per column, −0.02° epsilon | **A**, made rigorous in §3.6. |
| D9 | Pitch range | ±(89° − vfov/2) | ±20° | **±30°.** This is B's interaction limit, widened so the near ground can be looked at. Within hfov ≤ 90° and \|pitch\| ≤ 30°, no drawn vertex crosses the camera plane (a near-plane guard is still kept), so the rectilinear projection needs no clipping. |
| D10 | Field of view | 50° default, zoom 5–100° | 60° (width ≥ 600) or 45°, zoom 10–90° | **B.** |
| D11 | "Heights ×2/×5" stretch | Yes, badged | No | **Cut.** Zooming to 10° magnifies 4.5–6× at true proportions. The stretch would need ellipse discs and an extra badge. |
| D12 | Sun/Earth state word | From the mesh skyline | From `nowAt` (precise mask) | **Both.** Line 2 of the callout is the app's own status word (`bodyStateShort`, the same as the status line and the sky plot). When the 400 m mesh disagrees, line 3 says so ("400 m terrain here: behind terrain, skyline +1.1°"). The disc itself is occluded geometrically by the drawn terrain. |
| D13 | Non-colour encoding of light classes | Stripe and dot pattern passes | Luminance ordering | **A.** In the Both layer, sunOnly and earthOnly differ by only about 0.015 in luminance (computed from `lightPixel` at albedo 0.55), so luminance alone fails "colour is never the only encoding". The centre probe text and the legend are kept as well. Fallback: §4.4. |
| D14 | Ridge outlines (drawing aid) | No | Yes | **Cut.** The sky/terrain edge and the dashed horizon line already outline the skyline. The aid would add an algorithm and a badge. |
| D15 | Full-screen `LanderViewPage` | No | Yes | **Cut.** Phone landscape already gives a full-height view (`LightMap.shortSideBySideFor`). |
| D16 | Probe | Tap terrain | Centre crosshair | **Merged.** A crosshair readout is always shown. Tapping anywhere turns that point to the centre (animated), so the probe reads it. |
| D17 | Azimuth ruler and compass strip | Ruler with N/E/S/W | 48 dp compass strip | **B's strip**, with A's "N = away from the pole" in its tooltip and Semantics. |
| D18 | "Light not computed" ground | Neutral grey | `#2A3346` with a 45° hatch | **Neutral grey `beyondMapGround` (`#6E737B`, already in `light_map.dart`), no hatch**, plus an on-view text label and the probe text. A diagonal hatch would read as the partSun stripes. |
| D19 | Fling inertia | No | Yes | **Kept.** It is about 20 lines and is off under reduced motion. |
| D20 | Main-thread slice length | (isolate) | 20 ms | **8 ms** (`runSliced(..., sliceMs: 8)`), because the mesh is built on the UI thread on native too. |

## 1. Goal

Show what you would see standing on the lander at the selected site, whether a preset or a custom spot. The eye is `observerHeightM` (2 m) above the terrain, at the time-bar moment, and the view looks around the horizon in a rectilinear perspective.

The view is built from three sources only:
- **Terrain:** the exact height grid the light & shadow engine uses (`ShadowGrid` heights, block-averaged from the shipped 400 m LOLA DEM).
- **Light and shadow:** the app's own `LightFrame` for that moment (`flags`, `shade`), after the same eclipse correction as the 2D map.
- **Sky:** the Sun and Earth at the same apparent az/el as the sky plot, at true angular size.

The 3D view therefore always agrees with the Light tab's 2D map. Some sources are deliberately excluded:
- No shape-from-shadow, no other height source, no texture, no stars, no fill light.
- The precise horizon mask appears only as a labelled dashed reference line.

## 2. Data path (exact functions and files)

1. **Heights.**
   - Source: `AppState.dem()` → `PolarGrid` (`heights: Int16List`, `size` = 2280, `scaleM` = 400).
   - New pure helper `blockMeanRow` in `app/lib/core/shadow.dart`. It is the inner loop of `ShadowGridBuilder.step` (lines 111–118 today), with the same summation order and `sum / (ds*ds)`. `ShadowGridBuilder.step` calls it, and so does `blockMeanPatch` (core, `lander_view.dart`).
   - Near patch: ds = 1. The window is the close-up frame's window, `windowAround(pixelOf(site), closeUpPx = 320)` on the 400 m grid (2280 px).
   - Far patch: ds = 2. The window is `windowAround(pixelOf(site), landerFarPx(800) = 750)` on the 800 m grid (1140 px).
   - Both windows use the pure functions `gridPixelOf` and `gridWindowAround`, extracted from `ShadowGrid.pixelOf` and `ShadowGrid.windowAround` so the mesh and `_work` share one implementation.
2. **Mesh.** `LanderMeshWork` (core) runs on the main thread through `runSliced(work.step, pause: <next frame>, rows: 8, sliceMs: 8)` (`app/lib/state/light_engine.dart`).
   - It is started by the lander widget once `s.dem()` resolves.
   - It is cached in an LRU of 2 meshes keyed `'${site.lat}|${site.lon}|$observerHeightM'`, held by the lander widget's state and dropped when the light view leaves lander mode.
3. **Near light frame.** The close-up frame `_LightMapState` already requests: `LightRequest(closeUp: true, ...)`, coarse while playing, debounced 60 ms, prefetched.
   - It is built through `lightRequestFor(s, extent: LightExtent.closeUp)` (D2).
   - Apply `lightFrameEclipsed(raw, lightFrameEclipse(raw, terrainHeightM: site.terrainHeightM))` (`app/lib/widgets/light_map.dart:74/89`), exactly as `_eclipsed` does today.
4. **Far light frame.** This is a new request variant.
   - `LightRequest` gets a field `final bool far` (default false, sent through the isolate unchanged because the record carries the object).
   - `key` gains `'f|$lat|$lon|$tMs|$observerHeightM'` (+ `'|k'` when coarse).
   - `_work` (`light_engine.dart:146`) gets a branch: `g = q.coarse ? grids.coarse : grids.region` and `win = g.windowAround(row, col, (2 * coarseMaxM / g.pxM).ceil())`. That is 750 px of 800 m, or 375 px of 1.6 km while playing.
   - `LightExtent { closeUp, region, far }` exists only in `lightRequestFor`. The request keeps its `closeUp` bool, and `far` implies `closeUp == false`.
   - Scheduling, in `_LightMapState._pump`:
     - Only in lander mode, request the far frame **after** the near frame for the same `tMs` lands, and only when no newer near request is queued.
     - On `engine.onUiThread` (web), do not request it while `s.playing`.
     - A far frame is shown only if its `tMs` and `coarse` equal the shown near frame's. A stale far frame is never shown; those vertices go to "not computed" (D18).
     - The far frame gets the same eclipse correction.
5. **Pixel indices.** For each frame geometry `(x0M, y0M, pxM, size)`:
   - `landerFrameIndex` computes, once per geometry (4 variants: near full/coarse, far full/coarse), every vertex's 4 source pixels into that frame.
   - Formula: `col = floor((x − x0M)/pxM)`, `row = floor((y0M − y)/pxM)`, `−1` outside, where (x, y) is the source grid pixel centre's map position.
   - For a frame on the vertex's own grid this is `(R − r0)·size + (C − c0)`. For the 2× coarser play grid it is `(R÷2 − r0')·size + (C÷2 − c0')` (A).
6. **Colours.** `landerVertexColors` (new, `app/lib/state/lander_light.dart`, pure Dart, imports `light_engine.dart`) uses `classify(flags, layer)` + `lightPixel(k, shade/255, …)` (`light_engine.dart:205/220`). It gathers by index and recolours only on a new frame or layer change.
7. **Sky.**
   - Observer: `s.observer` (`Observer(site.lat, site.lon, site.terrainHeightM + observerHeightM)`).
   - Directions: `obs.look(eph.sun(t))` and `obs.look(eph.earth(t))`. These are the calls `nowAt` (`app/lib/widgets/chart_bridge.dart:419`) makes, so they equal the sky plot.
   - Status word: `bodyStateShort` (`app/lib/core/wording.dart:159`) with the `nowAt` visibility from `s.mask`.
8. **Reference line.** `s.mask` (`HorizonMask` at the observer height).
   - Presets: the shipped `horizons.json` (80 m / 240 m DEM).
   - Custom spots: the on-device coarse horizon (`computeCoarseHorizon`, 400 m).

## 3. Geometry (formulas)

Units are metres, R = `rM` = 1 737 400 m (the constant `shadow.dart` uses). The map is polar stereographic: x points to 90°E (right) and y to 0°E (up).

### 3.1 Grid vertices

Pixel (r, c) of a grid of n px at p m has its centre at:

```text
x = (c + 0.5 − n/2)·p        y = (n/2 − 0.5 − r)·p
```

This is the same expression as `ShadowGridBuilder.step`. Its height h is the block mean from `blockMeanRow`: the DEM integer for ds = 1, `sum/(ds·ds)` otherwise, stored as Float64.

### 3.2 True position (inverse of `latLonToXY`)

```text
ρ = √(x² + y²)         g = 2·atan(ρ / 2R)        λ = atan2(x, y)
u = (sin g·cos λ, sin g·sin λ, −cos g)            P = (R + h)·u
```

No map-scale shortcut is used. The mesh uses true positions, and the light attaches by pixel index (§2.5).

### 3.3 Eye and local frame

- `hGrid` is the bilinear height of the **near patch** at the site's (x, y). This equals `PolarGrid.sampleLatLon`, the `hSite` of `computeCoarseHorizon`.
- `eye = (R + hGrid + observerHeightM)·unitUp(lat, lon)`. `Enu.at(lat, lon)` (`geo.dart`) gives E, N, U. N is increasing latitude, away from the pole, and at −90° it is the site meridian.
- For v = P − eye:

```text
e = v·E   n = v·N   u = v·U   az = atan2(e, n) mod 360   el = atan2(u, hypot(e, n))   d = |v|
```

This is `Observer.look`'s formula. In the plane of a great circle it reduces to `computeCoarseHorizon`'s `el = atan2((R+h)cos t − (R+h0), (R+h) sin t)`.

The eye stays on the 400 m grid while playing; only the colours go coarse.

### 3.4 Cells

- **Cell.** Adjacent pixel centres (r, c), (r, c+1), (r+1, c), (r+1, c+1) form a cell. It is drawn as **4 triangles** fanned around a centre vertex. The centre's height is the mean of the 4 corners, i.e. the bilinear centre. The fan surface is the only surface; `patchFanHeightAt(x, y)` evaluates it anywhere.
- **Near part (part 1).** Cells of the near patch, except cells whose 4 corners all lie within `landerNearFieldM` = 800 m horizontal distance (hypot(e, n)).
- **Far part (part 2).** Cells of the far patch with centre horizontal distance ≤ `coarseMaxM` = 300 km. Exclude cells lying entirely inside the near patch inset by one far cell (2 fine px). The one-cell overlap at the seam is hidden by draw order.
- **Near field (part 0).** A polar lattice centred under the eye:
  - one nadir vertex
  - rings at 0.5, 1, 2, 3, 5, 10, 20, 40, 80, 160, 320, 560 and 800 m
  - 180 spokes (2°)

  Heights come from `patchFanHeightAt`, the same surface re-cut, so triangles are narrow in azimuth and looking down works.
- **Source pixels and weights.** Every vertex carries exactly **4 source pixels and 4 weights** (summing to 1):
  - grid vertex: (k, k, k, k; 1, 0, 0, 0)
  - fan centre: the 4 corners at 0.25 each
  - lattice vertex in fan triangle (A, B, centre) with barycentrics (a, b, c): A → a + c/4, B → b + c/4, the other two → c/4

  Heights and light both use these weights, so every vertex shows what `drawVertices` would interpolate on the fan surface.

### 3.5 Draw order (static per site)

The camera never moves, so draw order is computed once per site:
- Sort cells by the true distance `d` of their centre vertex, far to near. Use a radix sort on `uint32` decimetres.
- Within a cell, sort its 4 triangles by centroid `d`.
- Lattice triangles join the same order by their centroid `d`.

### 3.6 Occlusion culling (conservative, once per site)

- **Bins and sweep.** Use bins of 0.05° (7200). Process triangles near → far by `dmin`, the 2-D distance from the origin to the triangle in the eye's (e, n) plane.
- **Per triangle.** Each triangle has an azimuth span [a0, a1] (unwrapped; spans > 90° are never culled and never occlude) and a vertex elevation range [elMin, elMax]. Its bulge bound is β = max over edges of `|atan(tan|e|max / cos(Δaz_edge/2))| − |e|max`, an upper bound on how far a great-circle arc leaves its endpoints.
- **Occluder.** A kept triangle becomes an occluder only after every triangle with `dmin` < its `dmax` (max vertex hypot(e, n)) has been tested (a min-heap keyed by `dmax`). It is then committed as `O[b] = max(O[b], elMin − β)` for every bin b lying **wholly** inside [a0, a1].
- **Cull test.** Drop triangle t iff `elMax + β < O[b] − 1e-6°` for **every** bin b that [a0, a1] touches.
- **Exempt.** Part 0 (the near field) is never culled and never occludes.

The argument: ground is a continuous radial height profile from the nadir, so every elevation below the nearer profile's maximum is already covered by nearer ground. The bulge term makes the vertex bounds safe.

A measured on the shipped DEM that about 10–12 % of vertices within 300 km survive (50–63k of 520k).

### 3.7 Sectors and batches

- Kept triangles go into 36 sectors of 10° by centroid azimuth, each list in global draw order.
- A paint uses the sectors overlapping `yaw ± (hfov/2 + 10°)`, merged in global order.
- The index list is rebuilt only when that sector set changes.
- `Canvas.drawVertices` takes Uint16 indices, so emit batches of ≤ 65 535 vertices. Each batch is a contiguous slice of the far-to-near order, drawn in order.

### 3.8 Projection (rectilinear)

`LanderView{yawDeg ψ, pitchDeg θ, hfovDeg, w, h}`:

```text
f  = cos θ·(sin ψ·E + cos ψ·N) + sin θ·U     r = cos ψ·E − sin ψ·N     up' = r × f
F  = (w/2) / tan(hfov/2)
x  = w/2 + F·(v·r)/(v·f)       y = h/2 − F·(v·up')/(v·f)
```

- Facing az 0, az 90 lands on the right.
- Pitch is clamped to [−30°, +30°] and hfov to [10°, 90°].
- Near-plane guard: drop a triangle if any vertex has `v·f ≤ 0.01·|v|`. Within these limits only off-screen margin triangles hit the guard.

### 3.9 Skyline and DEM end

- `meshSkyline(m, azStepDeg: 0.5, minDistM)` is exact. For each azimuth it takes the max elevation over intersections of triangle edges with the vertical half-plane at that azimuth (the edge intersection is linear in 3-D), over triangles with `dmin ≥ minDistM`. Elevation along a segment in a vertical plane through the eye is monotonic, so edges suffice.
  - It is stored in the mesh with minDist 800 m (parts 1–2): the "far skyline".
  - The test compares it with minDist 600 m (`coarseMinM`) against `computeCoarseHorizon` (T5).
- Near-field alpha: a part 0 vertex gets alpha 1 when its el ≤ the far skyline at its azimuth, else `landerNearAlpha` = 0.35.
- `demEnds`:
  - For each 0.5° azimuth, step the great circle at `coarseDistances()` (`horizon_compute.dart`) and record the first distance outside the DEM grid.
  - Merge consecutive azimuths into ranges `(az0, az1, distM)`. `distM` is the minimum in the range.
  - Draw a dashed segment on the skyline over each range, labelled "terrain data ends at N km".

## 4. Light mapping

### 4.1 Classes and colour

- For each source pixel k: `cls = classify(flags[k], layer)` and `(m, s) = lightPixel(cls, shade[k]/255, 2, 0, 1)`.
  - (x = 2, y = 0) is a position where neither the stripe nor the dot predicate is on, so this is the base colour of patterned classes.
  - The `fullSun` Lambert normalisation `(shade/0.25)` is the map's own.
- Vertex RGB = Σᵢ wᵢ·clamp(0.55·mᵢ + sᵢ), i.e. a constant neutral albedo of 0.55: no texture, no relief shading.
- `canvas.drawVertices(v, BlendMode.dst, paint)`, i.e. the vertex colours are used. Interpolation runs between pixel centres, as `LightOverlayWork` blends neighbours.

### 4.2 Which frame

- Parts 0 and 1 use the near frame; part 2 uses the far frame.
- If a source index is −1, or the frame is absent, pending or stale, that source pixel contributes `beyondMapGround` (#6E737B), "light not computed".
- While that is the case, the view shows a label: "Computing light beyond 64 km…", or on the web while playing "Light beyond 64 km: paused while playing".
- No placeholder light is ever drawn.

### 4.3 Eclipse

Both frames pass through `lightFrameEclipsed(f, lightFrameEclipse(f, terrainHeightM: site.terrainHeightM))` before indexing, exactly as on the map. The view shows the `lightEclipseNote` lines, and `lightEclipseFidelity` joins the badge.

### 4.4 Non-colour encoding

**Patterns.** These are the map's patterns in screen space:
- **stripe:** `(lx + ly) % 6 < 2`, for partSun / sunOnly
- **dot:** `lx % 5 < 2 && ly % 5 < 2`, for earthOnly

`lightPatternOn(p, x, y)` (pure) is the single predicate, and `lightPixel` is refactored to call it. Each pattern present in the layer gets its own pass:
1. `canvas.saveLayer`.
2. Redraw the same visible triangles in the same order with `canvas.drawVertices(v, BlendMode.dst, Paint()..blendMode = BlendMode.src)`. The colours are the class's **on-pattern** colour `lightPixel(cls, shade, 0, 0, 1)`, with alpha = Σ wᵢ·[class i uses this pattern] × vertex alpha.
3. `drawRect(full, Paint()..blendMode = BlendMode.dstIn..shader = ImageShader(tile))`, where the tile is a 30×30 logical-px repeating mask from `lightPatternOn`.
4. `restore`.

With `src`, nearer triangles overwrite farther ones, so occlusion is preserved.

**Fallback.** This applies if test W11 shows a renderer that does not keep triangle order with `src` inside one `drawVertices` call. Issue one `drawVertices` per sector batch in order. If that also fails, drop the pattern passes and keep the probe text and legend. Then FidelityBadge text gains: "Stripes and dots of the map are not drawn here; read classes with the centre probe."

**Legend and probe.**
- The legend reuses the map's `_Legend` swatches. It adds: "Light not computed" (grey), "Near ground, see-through" and "Horizon (dashed)".
- The centre probe text (Plex Mono tabular) reads, for example: `Centre: full Sun · Earth hidden · 12.4 km · az 131.0° el +0.8°`. Sky reads `Centre: sky · az … el …`.

### 4.5 Sun down

Draw only what is computed: shadowed ground is dark, and the Earth layer still shows where Earth is in view. There is no Earthshine and no fill light. Line on the Sun layer: "No direct sunlight here now. Ground in shadow is drawn dark; Earthshine is not computed."

## 5. Sky

**Background.** Flat `PH.bg` #060B16. No stars, no glow, no atmosphere.

**Sun and Earth discs.**
- Direction is from `s.observer.look` (§2.7) as a unit ENU vector. The angular radius ρ is `asin(695700/r)` for the Sun and `asin(6378.1366/r)` for Earth, with r the range in km.
- Each disc is a 64-gon at angular radius ρ around the direction, projected with §3.8.
- They are painted **before** the terrain (Sun, then Earth on top). Terrain therefore occludes them, and during an eclipse Earth's disc covers the Sun's by itself.
- Fill colours are `PH.sun` / `PH.earth` (meaning colours, not photometry).
- On a 348 px view at hfov 60° the radii are about 1.4 px (Sun, ρ ≈ 0.27°) and 5 px (Earth, ρ ≈ 0.95°). Each disc therefore gets a 1 px `PH.text` outline (a visual aid), and zooming in shows them at size.

**Callouts.**
- Content: a `MeaningGlyph` (sun / earth, `glyphs.dart`) 24 dp above the disc, a leader line, and up to three lines of `numStyle` (Plex Mono, tabular):
  1. `Sun · az 123.4° · el +1.2°`
  2. the status word from `bodyStateShort` (precise mask: "in view", "partly hidden", "behind terrain", "below horizon")
  3. only when `skyBody(...).state`, judged against the mesh's own skyline, differs from (2): `400 m terrain here: behind terrain, skyline +1.1°`
- The glyph is filled when (2) says in view or partly hidden. It is hollow and dashed, drawn on top of the terrain, when (2) says behind terrain or below horizon.
- An off-view body gets an edge chevron with `SUN 132°` on the compass strip.
- Tap targets are 48 dp; tapping turns to the body.
- Labels are laid out clear of each other, as `ArrowLabelMemory` does.

**Compass strip** (48 dp tall, inside the top edge, D17).
- Ticks every 5°, labels every 30° (`030`, Plex Mono tabular); N/E/S/W in larger type.
- Sun and Earth glyphs mark their azimuths.
- Tap to turn to that azimuth.
- Tooltip and Semantics: "Compass: N is away from the pole".

**Elevation scale** (left edge).
- Ticks at the screen y where the centre column has el = k° (1/2/5/10° steps, adaptive to the zoom), labelled `+2°`.
- A hairline traces the el = 0° curve, labelled `0° (level)`. It is a visual aid.

**Reference line.**
- `s.mask` at the observer height, drawn as a dashed `PH.text` line at 70 % opacity on top of the terrain.
- Label for presets: `Horizon mask (LOLA 80 m/240 m)`. For custom spots: `Coarse horizon (400 m, this device)`, plus `FidelityBadge.customHorizon`.
- DEM-end segments are drawn as in §3.9.

## 6. Honesty and FidelityBadge texts

The first sentence is the ≤ 110-character summary (`FidelityBadge.summaryOf`). The rest is shown when the badge is expanded. Builders add the figures **measured by T5** to `formula.md` §12.11.

**Main badge** (always shown). Sentence 1 is exactly 100 characters:

> Approximate: the light map's own 400 m LOLA terrain and light; Sun and Earth at true size and place. Terrain is the grid the light map uses (400 m within 64 km, 800 m out to 300 km), block-averaged the same way, so rims and peaks are smoothed and the drawn skyline can differ from {preset: "this site's 80 m horizon mask (dashed) by about 1° and up to 5°" | custom: "80 m horizons by 0.5–1.4° (up to about 6° on sharp rims); it matches this spot's 400 m horizon (dashed) within about 0.4°"}. Ground within 800 m is not resolved by the 400 m grid: where it would rise above the distant skyline it is drawn see-through, because the light map and the horizon masks ignore it. Light and shadow are the Light tab's computed frame for this moment, pixel for pixel; Earth's direction there is taken from the Moon's centre, up to 0.3° higher than seen from the ground. Shadowed ground is drawn dark: Earthshine is not computed, and the ground colour is a flat grey, not a photo. The Sun and Earth are drawn in their meaning colours at true size and position (DE440, apparent, no refraction); glyphs, labels, the 0° line, the compass and the stripe and dot patterns are visual aids.

**Dynamic sentences**, appended to the main badge:
- (g) Presets only, when `|hGrid − site.terrainHeightM| > 5 m`: "The eye is 2 m above the 400 m surface, {N} m {below|above} this site's 80 m height." For SR1 that is about 29 m below.
- (h) When `demEnds` is non-empty: "Terrain data ends {N} km away toward azimuth {A0}–{A1}° (edge of the LOLA map)."
- During an eclipse: `lightEclipseFidelity`.

**Play badge** (a separate short `FidelityBadge` while `s.playing`), exactly 100 characters:

> Approximate: while playing, light from coarser grids (800 m, 1.6 km beyond 64 km); pause for detail.

On the web while playing, the second sentence is "Light beyond 64 km waits until you pause."

**Caption** (under the view): "From the lander: {observerHeight} above the ground at {site}, {UTC}. Terrain and light come from the same 400 m LOLA grid and the same computed frame as the map; the Sun and Earth are at their exact positions."

**Guide and Learn.**
- Guide step (`content/guides.dart`, `site.light`, target `light-lander` on the third segment): `GuideStep('light-lander', 'Stand on the lander', 'See the horizon from 2 m up. Drag to look around; the light is the map\'s own.')`
- Learn › How it's calculated: a "Lander's view" entry covering the mesh source, eye height, light frames, culling, the see-through near ground, and what is not drawn.

**Never.** No stars, no textures, no Earthshine, no fill light, no smoothing of shadow edges beyond vertex interpolation, no use of `horizons.json` to shape the mesh, no other height source.

## 7. Placement and interaction

### 7.1 Switch

- `SegmentedButton<LightViewKind>` with `enum LightViewKind { closeUp, region, lander }` replaces the `bool closeUp` switch (`light_map.dart:868`).
- Labels: 'Around the site (64 km)' | 'Whole region (inside 80°S)' | 'From the lander (2 m up)'. Switch labels: ['Around site', 'Whole region', 'Lander']; short labels: ['Site', 'Region', 'Lander']. The lander icon is `Icons.landscape_outlined`, with tooltip "What you would see standing on the lander, 2 m above the ground".
- PageStorage id `light-map-view` stores the enum name. Migration: an old bool under `light-map-close-up` maps true → closeUp, false → region.
- Lander mode keeps the layer switch, status line, legend, notes and the pinned TimeBar. The 3D view replaces the map canvas in the same slot.

### 7.2 Layouts

- **Phone 360 portrait.** The view fills the width, with height `clamp(0.62·w, 220, slot)`. The compass strip sits inside at the top. Under the view is a row of seven 48 dp icon buttons: Turn left 15°, Face the Sun, Face Earth, Level, Zoom out, Zoom in, Turn right 15° (7 × 48 = 336 dp). Legend, caption and badges scroll below.
- **Phone landscape** (`LightMap.shortSideBySideFor`). The view takes the full height; the time bar is in the side column, as for the map.
- **Tablet and web (≥ 600 wide).** The same row with text labels ('Face the Sun', 'Face Earth', 'Level').

### 7.3 Camera

- `LanderCameraController extends ChangeNotifier { yaw, pitch, hfov }`.
- Defaults: pitch 0; hfov 60° when the view is ≥ 600 wide, else 45°.
- Initial yaw: the Sun if its el > −5°, else Earth if its el > −5°, else 0 (N).
- Yaw, pitch and hfov are remembered per site in PageStorage (`lander-camera-<siteId>`).

### 7.4 Gestures

- The view is wrapped in `NoPageSwipe`, so tabs never turn under it.
- Scale gestures: a drag "grabs the world". 1 px = hfov/width degrees of yaw (and of pitch vertically). A pinch zooms.
- Fling: friction 0.9 per 16 ms.
- Ctrl + mouse wheel zooms (`Listener.onPointerSignal`).
- A tap turns the tapped point to the centre (D16).

### 7.5 Keyboard

- The view is a `Focus` node that consumes these keys before the Site page's `_PageArrowAction`: ←/→ 5° (Shift 1°), ↑/↓ 2°, +/− zoom, S face the Sun, E face Earth, N face north, Home level.
- When focused, the painter draws a 2 px `PH.ice` ring.

### 7.6 Animation and time

- Turns animate over 400 ms the shortest way (`turnDelta`).
- Under `MediaQuery.disableAnimations` they jump and there is no fling.
- Time sync (§2.3–2.4): coarse frames while playing, full frames on stop, the same 60 ms debounce and prefetch as the map. The mesh is unchanged by time; only colours and the sky change.

## 8. Performance budget

| Item | When | Budget |
|---|---|---|
| Patches + mesh build + cull + sort | Once per (site, observerHeightM), main thread, `runSliced` rows 8 / 8 ms | Native ≤ 250 ms CPU total, web ≤ 1.2 s total. No slice > 8 ms of work. A "Building the view…" text shows until it is done (no placeholder terrain). |
| Mesh before culling | Transient | About 660k grid vertices (0.1M near + 0.56M far) + 2.3k lattice. Typed arrays only, freed after culling, ≤ 25 MB peak. |
| Kept mesh | Cached, LRU of 2, dropped when leaving lander mode | ≤ 150k vertices and ≤ 8 MB. T10 asserts this for the 4 test sites; if exceeded, the builder reports it rather than silently thinning. |
| Index rebuild | Sector set changes | ≤ 2 ms native |
| Projection | yaw/pitch/hfov/size change | Into reused `Float32List`s; ≤ 2 ms native / 6 ms web for ≤ 40k vertices |
| Recolour (gather) | New frame or layer | ≤ 3 ms native / 8 ms web |
| Paint | Per frame | ≤ 80k triangles at the default hfov. 1 base pass + ≤ 2 pattern passes. `CustomPainter(repaint: controller)` inside a `RepaintBoundary`. `TextPainter`s cached by string. |
| Far light frame | Per moment, lander mode only | One region-sized frame (562k px; 141k px coarse). Requested after the near frame; never ahead of a pending near request. Skipped on the web while playing. Cache cost about 1.1 MB per far frame. |
| Probe and Semantics text | Gesture end, button press, frame change | Not per frame |

**Device check (lead):** paint time on the Android emulator (Impeller) at the default hfov for SR1, and on the web (CanvasKit). This is not a unit test.

## 9. Accessibility

- **Semantics container** labelled by the pure `describeLanderView(...)`, for example: "Lander's view, facing the Sun, azimuth 132 degrees. Sun 1.2 degrees up, in view. Earth below the horizon, azimuth 351 degrees. Ground at the centre, 23 kilometres away: sunlit."
  - It is updated at gesture end, on button presses and on frame change.
  - `liveRegion` is set only after a button or key press.
- **customSemanticsActions:** Turn left 15°, Turn right 15°, Look up, Look down, Face the Sun, Face Earth, Level, Zoom in, Zoom out.
- **Focus:** the view is focusable, with a 2 px `PH.ice` focus ring.
- **Buttons:** every button is ≥ 48 dp, with a tooltip and a Semantics label. The compass strip is 48 dp tall. Disc callouts have 48 dp tap targets.
- **Motion:** reduced motion means no fling and no animated turns.
- **Text:** canvas text is clamped by `PH.maxCanvasTextScale`. The three-segment switch must fit at 360 dp and text scale 2 with the short labels (W1).
- **Encoding:** colour is never the only encoding. Light classes use the patterns, legend labels and centre probe. Sun and Earth use glyph shapes and text. Status uses words.

## 10. Core API (Dart signatures)

### `app/lib/core/shadow.dart` (refactor, behaviour bit-identical)

```dart
/// Block means of DEM row-block r, columns c0..c1-1, of a downsample-ds grid
/// (the arithmetic of ShadowGridBuilder.step: double sum in i,j order, / (ds*ds)).
void blockMeanRow(Int16List heights, int demSize, int ds, int r, int c0, int c1, Float64List out, int outOffset);
(double, double) gridPixelOf(int gridSize, double pxM, double latDeg, double lonDeg); // = ShadowGrid.pixelOf
GridWindow gridWindowAround(int gridSize, double row, double col, int side);         // = ShadowGrid.windowAround
```

### `app/lib/core/lander_view.dart` (new, pure Dart)

```dart
const double landerNearFieldM = 800, landerNearAlpha = 0.35, landerBinDeg = 0.05, landerNearPlane = 0.01;
const List<double> landerNearRingsM = [0.5, 1, 2, 3, 5, 10, 20, 40, 80, 160, 320, 560, 800];
const int landerNearSpokes = 180, landerSectorCount = 36;
const double landerPitchMax = 30, landerHfovMin = 10, landerHfovMax = 90;
int landerFarPx(double pxM); // (2 * coarseMaxM / pxM).ceil()

class TerrainPatch {
  final int gridSize, ds, r0, c0, side; final double pxM; final Float64List h;
  double at(int r, int c); // grid row/col
}
TerrainPatch blockMeanPatch(Int16List heights, int demSize, double demPxM, int ds, GridWindow win);
(double, double) gridCentreM(int gridSize, double pxM, int row, int col);
V3 mapPointM(double xM, double yM, double hM);              // (R+h)·u, §3.2
double patchBilinearAt(TerrainPatch p, double xM, double yM);
double patchFanHeightAt(TerrainPatch p, double xM, double yM);

class LanderCamera { final double latDeg, lonDeg, groundM, eyeHeightM; final Enu enu; final V3 eyeM; }
LanderCamera landerCamera(TerrainPatch near, double latDeg, double lonDeg, double observerHeightM);
({double az, double el, double dist}) lookAt(LanderCamera c, V3 pM);

class LanderMesh {
  final LanderCamera cam;
  final Float32List e, n, u, alpha;      // per vertex, metres from the eye (ENU)
  final Uint8List part;                  // 0 near field, 1 near grid (400 m), 2 far grid (800 m)
  final Int32List src;                   // 4 per vertex: pixel index in its grid (fine for parts 0/1, region for 2)
  final Float32List w;                   // 4 per vertex, sum 1
  final Uint32List tri;                  // 3 per kept triangle, draw order far→near
  final List<Int32List> sectors;         // triangle ids per 10° sector, ascending
  final Float64List skyline;             // far skyline, 0.5° steps, minDist 800 m
  final List<({double az0, double az1, double distM})> demEnds;
  final int gridVerticesBeforeCull;
}
// A source pixel's map centre follows from its index and its part's grid (§3.1): fine 2280 px × 400 m, region 1140 px × 800 m.

class LanderMeshWork {
  LanderMeshWork(Int16List heights, int demSize, double demPxM,
      {required double latDeg, required double lonDeg, required double observerHeightM, bool cull = true});
  bool step(int rows); // resumable; true when done
  bool get done;
  LanderMesh get mesh;
}
LanderMesh buildLanderMesh(Int16List heights, int demSize, double demPxM,
    {required double latDeg, required double lonDeg, required double observerHeightM, bool cull = true});

Float64List meshSkyline(LanderMesh m, {double azStepDeg = 0.5, double minDistM = landerNearFieldM, Set<int> parts = const {1, 2}});

class LanderView { final double yawDeg, pitchDeg, hfovDeg, w, h; }
({double x, double y, bool front}) projectView(LanderView v, double e, double n, double u);
({double az, double el}) unprojectView(LanderView v, double x, double y);
List<int> visibleSectors(LanderView v);
int projectTriangles(LanderView v, LanderMesh m, List<int> sectors, Float32List xy, Uint16List idx /*batched*/);
double clampPitch(double deg); double clampHfov(double deg);
double turnDelta(double fromDeg, double toDeg); // shortest signed turn, (-180, 180]

enum SkyState { up, partlyBehindTerrain, behindTerrain, belowHorizon }
({double az, double el, double rhoDeg, SkyState state}) skyBody(Observer obs, V3 fromCentreKm, double radiusKm, Float64List skyline, {double azStepDeg = 0.5});
List<({double e, double n, double u})> discOutline(double azDeg, double elDeg, double rhoDeg, {int sides = 64});

({int tri, double distM, double az, double el})? meshProbe(LanderMesh m, double azDeg, double elDeg);
String describeLanderView({required String facing, required double yawDeg, required ({double az, double el, String state}) sun,
    required ({double az, double el, String state}) earth, String? centre});
```

### `app/lib/state/light_engine.dart` (additions)

```dart
// LightRequest: + final bool far (default false); key 'f|lat|lon|tMs|h' (+'|k'); _work far branch (§2.4)
enum LightExtent { closeUp, region, far }
bool lightPatternOn(LightPattern p, int x, int y); enum LightPattern { stripe, dot }
LightPattern? lightPatternOf(LightClass k);
```

### `app/lib/state/lander_light.dart` (new, pure Dart, no Flutter)

```dart
Int32List landerFrameIndex(LanderMesh m, LightFrame f, {required bool far}); // 4 per vertex, -1 outside / other part
Int32List landerVertexColors(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx, LightLayer layer); // ARGB
Uint8List landerPatternAlpha(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx, LightLayer layer, LightPattern p);
LightClass? landerClassAt(LanderMesh m, int tri, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx, LightLayer layer); // dominant weight, null = not computed
```

### Widgets and app

- `lightRequestFor(AppState s, {required LightExtent extent, double? tMs, bool? coarse})` lives in `app/lib/widgets/light_map.dart`, next to `lightFrameEclipse`.
- `app/lib/widgets/lander_view.dart`: `LanderViewPanel`, `LanderCameraController`, `LanderPainter`, `_CompassStrip`, `_LanderButtons`.
- `formula.md` gets a new §12.11 "Lander's view" (§3–§5 formulas and the T5 figures).

## 11. Tests (each named)

### `app/test/core/lander_view_test.dart`

- **T1 `blockMeanRow keeps ShadowGrid z bit-identical (ds 1, 2, 4)`.** On a random synthetic Int16 DEM, `(rM + h)·cos(colat) − rM` from `blockMeanPatch` equals `ShadowGrid.fromHeights(...).z` element-wise, Float32 bitwise.
- **T2 `mapPointM inverts latLonToXY`.** 1000 random points: lat/lon round trip to 1e-9°. Lon 90°E maps to +x.
- **T3 `ridge at 20 km and 150 km: exact elevation with curvature`.** Synthetic flat h = 0 PolarGrid, site at −88°, with a 500 m ridge along the circle at true distance 20 km and then 150 km.
  - `meshSkyline` at the ridge azimuth equals `atan2((R+H)cos t − (R+2), (R+H) sin t)` within 0.01°.
  - Each vertex's `lookAt` el and dist are exact to 1e-9° / 1e-6 m.
  - With H = 0 the 150 km dip equals the formula.
- **T4 `flat sphere: everything beyond the geometric horizon is culled`.** Flat h = 0: no kept part 1/2 triangle has `dmin > √(2R·2 m) + √2 cells` (about 2.6 km + 566 m; the ground's elevation is stationary at the horizon, so the cull's vertex and bulge bounds prove hiding only about one cell diagonal beyond it). Every triangle nearer than 2.6 km − 1 cell is kept.
- **T5 `skyline matches computeCoarseHorizon on the shipped DEM`.**
  - Sites: SR1 (`derosa2012-sr1-shackleton-rim`), Haworth (`artemis3-haworth`), Mons Mouton (`artemis3-mons-mouton`), and the custom spot (−80.05°, 1.44°E).
  - Compare the unculled mesh at 2 m, minDist 600, 0.5° steps (the culled mesh's minDist-0 skyline must equal the unculled one). A minDist-600 skyline holds no ground nearer than 600 m and all ground beyond 600 m + 1 cell, so Δ is the distance from the mesh skyline to the interval [coarse horizon from 1000 m, coarse horizon from 600 m] (the plain difference wherever the two coincide; they must coincide at more than a third of the azimuths). Required: mean Δ ≤ 0.05°, p95 ≤ 0.2°, max ≤ 0.4° (A's prototype: max 0.20°).
  - Print the per-site figures for formula.md.
- **T6 `projectView orientation`.**
  - Yaw 0: az 90 → x > w/2 and az 270 → x < w/2.
  - Yaw 90: az 90 → centre and az 180 → right.
  - el > pitch → y < h/2.
  - `unprojectView ∘ projectView` = identity to 1e-9.
  - `turnDelta(350, 10) = 20`, `turnDelta(10, 350) = −20`, `turnDelta(0, 180) = 180`.
  - `clampPitch` / `clampHfov` limits hold.
  - `visibleSectors` wraps across 0°.
- **T7 `skyBody equals Observer.look and true radius`.**
  - For 50 times on a synthetic ephemeris vector set, az/el equal `obs.look` to 1e-12.
  - `discOutline` points lie at angular distance ρ = asin(695700/r) within 1e-9.
  - State is `belowHorizon` iff el + ρ < 0, and `behindTerrain` iff the top limb is under the skyline with el + ρ ≥ 0.
- **T8 `culling is conservative`.**
  - On 5 random synthetic DEMs (smooth noise ± 2 km), `meshSkyline(culled, minDistM: 0) == meshSkyline(cull: false, minDistM: 0)` exactly, and the stored far skyline equals the unculled minDist-800 skyline (a minDist-800 skyline of the culled mesh may be lower: far ground hidden by a part 1 triangle with dmin < 800 m is rightly culled).
  - Every triangle containing a vertex visible by brute force (el above the max el of all unculled triangles with smaller `dmax` at that azimuth) is kept.
- **T9 `painter order vs ray-cast id buffer`.** On a 200×100 view of a synthetic scene, the last triangle in draw order covering each pixel centre (in projected 2-D) equals the nearest ray hit (brute-force ray/triangle) for ≥ 99.5 % of pixels.
- **T10 `near field: lattice, alpha and budget`.**
  - Every triangle within 800 m is part 0, and its vertices' alpha is 1 iff el ≤ the far skyline.
  - No part 1 cell has all 4 corners within 800 m.
  - Lattice heights equal `patchFanHeightAt`.
  - For the 4 T5 spots, kept vertices ≤ 150k.
- **T11 `sliced build equals one-shot`.** `LanderMeshWork` stepped 1, 7 and 1000 rows at a time gives a bit-identical mesh to `buildLanderMesh`.
- **T12 `demEnds near 80°S`.** For (−80.05°, 1.44°E), the ranges are non-empty toward the north (az near 0) and empty toward the pole (az 180). The custom-spot DEM-end distance lies within one coarse step of the first out-of-grid sample.
- **T13 `meshProbe on the ridge`.** A centre ray at the ridge azimuth, el 0.5° below its crest, hits a ridge triangle at a distance within one cell of 20 km. Above the crest it returns null (sky).
- **T14 `describeLanderView texts`.** Sun in view, Sun behind terrain, Sun below the horizon, eclipse, custom spot: exact strings.

### `app/test/state/lander_light_test.dart`

- **S1 `each vertex gets its own pixel (synthetic frame)`.** Random flags/shade on a synthetic frame whose window equals the near patch: every part 1 grid vertex's colour equals the colour of its pixel. Fan centres equal the mean of 4.
- **S2 `real close-up frame: vertex classes equal the 2D classification`.** `computeLightFrame` for SR1 at a fixed time on the shipped DEM: for every part 1 grid vertex, `classify(flags[idx], layer)` equals `landerClassAt`, for all 3 layers.
- **S3 `coarse frames index by halving`.** On the 800 m close-up frame, the index equals `(R÷2 − r0')·size + (C÷2 − c0')`.
- **S4 `far frame equals the region frame where they overlap`.**
  - For SR1 at a fixed time, the far frame's flags/shade equal the region frame's (`closeUp: false`) bit for bit on overlapping pixels.
  - If that fails only within the window's upstream margin, the builder reports the margin width instead of loosening the test silently.
- **S5 `far request key and window`.** The key has the `f|` prefix and the `|k` suffix when coarse. The window side is 750 / 375 px and site-centred unless clamped. Every part 2 vertex maps inside the far frame and every part 0/1 vertex inside the near frame, for the 4 T5 spots.
- **S6 `eclipsed frames clear the bits as on the map`.** At MP1, 2026-03-03 11:30 UTC, the vertex classes after `lightFrameEclipsed` equal the map's eclipsed frame classes.
- **S7 `pattern predicate is the map's`.** `lightPatternOn` equals the stripe/dot predicates inside `lightPixel` over a 60×60 block. `lightPixel(…, 2, 0, 1)` is off-pattern for both.
- **S8 `skyBody equals nowAt`.** For 50 moments at SR1, `skyBody(s.observer, eph.sun(t))` az/el equals `nowAt(...)`'s sun az/el to 1e-12, and the same for Earth.

### `app/test/widget/lander_view_test.dart`

These use the fake engine (`AppState.lightEngineForTest`) on a 64-px synthetic DEM.

- **W1 `third segment appears, persists and migrates the old bool`.** Also checks that the short labels fit at 360 dp and text scale 2.
- **W2 `drag turns the view and the site tab stays`.** A 100 px drag gives Δyaw = 100·hfov/width.
- **W3 `arrow keys turn the view and do not change the tab`.**
- **W4 `Face the Sun sets the Semantics label (liveRegion)`.**
- **W5 `az 90 lands right of centre when facing north`.** Uses the painter's projected disc position.
- **W6 `play requests coarse near then far; stop requests full`.** Native fake.
- **W7 `web engine skips the far frame while playing`.** `onUiThread` fake.
- **W8 `reduced motion: no running animation after Face the Sun`.**
- **W9 `eclipse note and badge are shown`.**
- **W10 `custom spot: coarse-horizon label and customHorizon badge`.**
- **W11 `pattern pass: nearer plain triangle hides farther striped one`.** Paint two overlapping triangles via `LanderPainter` into `toImage`. No stripe pixels may appear in the overlap; stripes must appear in the far-only part (D13 fallback check).
- **W12 `tap targets and labels meet guidelines`.** `androidTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline`.

Run only these files (never the full suite). Order: `flutter test test/core/lander_view_test.dart`, then `test/state/lander_light_test.dart`, then `test/widget/lander_view_test.dart`, then the existing `test/core/shadow_test.dart`, `test/state/light_engine_test.dart`, `test/state/light_engine_cache_test.dart`, `test/widget/light_map_test.dart` and `test/widget/light_eclipse_test.dart` (regressions from the refactors). Then `flutter analyze`.

## 12. Screenshots

The test is `app/test/widget/lander_view_shots_test.dart`. It is opt-in: it runs only when the env var `PH_SHOTS=<dir>` is set.
- It uses `loadAppFonts()` (as `test/openings/video_frames_test.dart`), the real 400 m DEM, real `computeLightFrame` frames (near + far), and the real ephemeris.
- Each shot is rendered through a `RepaintBoundary` to PNG.
- Sizes: phone 360×640 for every shot, and web 1280×800 for shots 1, 2 and 3.
- Moments are found by deterministic rules, using `nowAt` for visibility and `s.observer.look` for el, searched in 1 h steps from 2026-01-01T00:00Z. Each shot prints the chosen UTC time.

| # | Site | Moment | Layer, camera | Shows |
|---|---|---|---|---|
| 1 | SR1 (`derosa2012-sr1-shackleton-rim`) | First hour where the Sun is "in view" with centre el between +0.3° and +1.5° | Sun layer, facing the Sun, hfov 45° | Long shadows from a low Sun; badge (g) about 29 m |
| 1b | SR1 | Same moment | Sun layer, facing away (Sun az + 180°) | Lit far rims vs shadowed foreground, pattern stripes |
| 2 | MP1 (`derosa2012-mp1-malapert-peak`) | **2026-03-03 11:30 UTC** (total lunar eclipse; Sun about 4° up, per `light_eclipse_test.dart`) | Both layer, facing the Sun, hfov 20° | Earth's disc over the Sun's, eclipse note and badge, ground re-classed |
| 2b | MP1 | 2026-03-03 11:30 UTC | Sun layer, facing the Sun | Eclipse shadowing on the terrain |
| 3 | Custom spot `addCustomSite(-80.05, 1.44)` | First hour where the Sun is "in view" at the spot (coarse horizon) | Sun layer, facing the Sun | Coarse-horizon line label and customHorizon badge |
| 3b | Same custom spot | Same moment | Both layer, yaw 0 (north) | "Terrain data ends at N km" segment (h) |
| 4 | Haworth (`artemis3-haworth`) | First hour where Sun el + ρ < −1° and Earth el > +1° | Earth layer, facing the Sun's azimuth | Sun "below horizon" callout, dark ground, Earth layer still drawn, sun-down line |
| 5 (optional) | SR1 | Shot 1's moment, `playing = true` with coarse frames | Sun layer | Play badge |

The lead visually checks the shots for:
- no cracks at the 64 km seam
- no painter's-order artifacts
- see-through near ground labelled
- dashed reference line labelled
- no stars, no texture

## 13. Out of scope

- The height stretch (D11), ridge outlines (D14), and the full-screen `LanderViewPage` (D15).
- Building the mesh in the isolate (D6), and a `FragmentProgram` / WebGL renderer (only the D13 fallback chain).
- Shape-from-shadow, any height source other than the 400 m DEM block means, `horizons.json` shaping the mesh, and the 80 m / 240 m DEMs in the mesh.
- Earthshine, fill light, relief shading, albedo maps, textures, stars, atmosphere, Earth's phase or night side on its disc, and the Sun's corona.
- Changing formula.md §12.2 (Earth cast along the Moon-centre direction, about 0.26° optimistic). It is badged here and needs the user's OK first.
- Unifying the 600 m (`computeCoarseHorizon`) and 800 m (light engine) near-field cuts. That is a separate decision.
- Eclipses in the pipeline's 18.6-year averages.
- Moving the eye anywhere other than the site (no walking or flying), choosing the eye height from the view (it follows `observerHeightM`), and VR / device orientation.
- Light prefetch of far frames during play, and far frames on the web during play.
- Blender renders (no longer shown in the app).
- On-device performance measurement as a unit test (a lead device check, §8).

## Build split (two builders, about 300k tokens)

**Builder 1: core and engine (about 150k).**
- The `shadow.dart` refactor (`blockMeanRow`, `gridPixelOf`, `gridWindowAround`).
- `core/lander_view.dart`.
- `LightRequest.far` + `_work` branch.
- `lightPatternOn` / `lightPatternOf`.
- `state/lander_light.dart`.
- Tests T1–T14 and S1–S8.
- formula.md §12.11.

**Builder 2: UI (about 150k).** It starts from the §10 signatures and stubs until Builder 1 lands.
- `LightViewKind` and `lightRequestFor` in `light_map.dart`, with far-frame scheduling in `_pump`.
- `widgets/lander_view.dart`: painter (base pass, pattern passes, discs, callouts, compass, elevation scale, reference and DEM-end lines, probe), controller, gestures, keys, buttons and Semantics.
- Badges, caption, guide step and Learn entry.
- Tests W1–W12 and the shots test.

**Cut order if over budget:**
1. Shot 5.
2. Fling.
3. Learn entry.
4. Elevation scale ticks (keep the 0° line).
5. Guide step.

Never cut the patterns, badges, near-field see-through, culling tests or the far frame.
