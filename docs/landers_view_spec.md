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
| D20 | Main-thread slice length | (isolate) | 20 ms | **4 ms, one unit per step** (`runSliced(..., rows: 1, sliceMs: 4)`), because the mesh is built on the UI thread on native too. Every unit is short (rows, 2048-triangle chunks, at most 16,384 elements of a sort or compaction pass), so a slice is at most 4 ms plus one unit, within the 8 ms of §8 (changed 2026-10-30 from rows 8 / 8 ms, review §14). |

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
2. **Mesh.** `LanderMeshWork` (core) runs on the main thread through `runSliced(work.step, pause: <next frame>, rows: 1, sliceMs: 4)` (`app/lib/state/light_engine.dart`), and stops at its next slice when the site changes or the panel is disposed.
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
- Near-field alpha: a part 0 vertex, or a part 1 vertex under 800 m, gets alpha 1 when its el ≤ the far skyline at its azimuth, else `landerNearAlpha` = 0.35. Every other vertex gets alpha 1. (Part 1 keeps the 400 m cells that straddle the 800 m ring; their vertices under 800 m are near ground and are never in the far skyline, so they follow the lattice's rule. Vertices at 800 m or more stay opaque, so far peaks are not made translucent by skyline sampling between 0.5° steps.)
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
- Build (1.9.1, after a review of emulator screenshots): a body inside the view but under the compass strip keeps its callout, placed under the strip with its leader up to the disc, and the strip's dimming leaves the disc (and the leader) out. The callout words keep off the centre crosshair (after Face the Sun the body sits on it) and no crosshair arm is drawn across them. Two edge chevrons on one edge sit side by side, each a 104 x 48 dp target, on a translucent band over the words' row only, so the ticks and azimuth labels under them stay in view.
- Build (1.9.2, after the 1.9.1 emulator run showed the Sun's second line under the centre readout on a Pixel 4):
  - Placement order. A callout never covers the centre readout, the legend, or an edge chevron's word row. Below those, the order is:
    1. the crosshair, its own glyph and disc;
    2. then the other body's callout and glyph.
  - Candidate places. Beside the glyph, rows above and under it, and places by the other body's callout and the crosshair. Then above the disc, beside the glyph raised clear of the crosshair, beside the disc at its top, and beside the other callout under the crosshair. In a short view a box may sit over the compass strip's sky, never over an edge chevron's words; it goes just under them where that fits.
  - Where Earth's words find no place clear of the Sun's, Earth is placed first and the Sun clear of it, so both keep their words in full where that fits.
  - The bottom-strip floor applies only where a legend or readout box sits under the candidate box.
  - Words before the readout. The centre readout is the secondary probe. It is dropped only when every callout then gets a clean place, or a body then keeps more of its words. A body's words outrank it.
  - Shortening order, when no clean place is left:
    1. Earth's callout (beside the Sun's) shortens to its position line.
    2. Then it merges into the Sun's callout as a second line.
    3. Then it shows its glyph alone.
    A lone body shortens the same way: its position line (with the status word when the glyph does not show it), then its glyph alone.
  - Two callout boxes are never stacked, a lunar eclipse included.
  - Over the compass strip, a box never covers an edge chevron's words or the other body's azimuth marker. The exception is a lunar eclipse, where the two markers lie on top of each other. Soft keeps are kept clear where a place that fits allows, and are given up before the crosshair, a glyph or the readout:
    1. the other body's disc and leader;
    2. the rest of a chevron's tap target;
    3. the body's own marker, since its callout repeats the azimuth;
    4. the heading pointer.
  - Both leaders are painted before both boxes, so a leader never crosses the other body's words.
  - Placement cost: every candidate list is built only when reached, and each place is tried once. Placement takes about 0.3–1.3 ms of a paint in `flutter test` on a desktop CPU.
  - The release gate is one harness painting the same 25,200 frames with the 1.9.1 and 1.9.2 code (5 view sizes × hfov 10/45/90° × pitch −30/0/+30° × 70 body positions × 8 scenes). 1.9.2 has no more overlaps than 1.9.1 in any category. It drops the readout more often, but only where that gives the callouts a clean place or a body more of its words. Tests W17–W24 cover it.

**Compass strip** (48 dp tall, inside the top edge, D17).
- Ticks every 5°, labels every 30° (`030`, Plex Mono tabular); N/E/S/W in larger type.
- Sun and Earth glyphs mark their azimuths.
- Tap to turn to that azimuth.
- Tooltip and Semantics: "Compass: N is away from the pole".

**Elevation scale** (left edge).
- Ticks at the screen y where the centre column has el = k° (1/2/5/10° steps, adaptive to the zoom), labelled `+2°`.
- Build (1.9.1): when no row of the step gets its label (zoomed in, or the rows fall under the strip or the callouts), one reference is still shown: the row nearest the centre at a finer step (5, 2, 1, 0.5, 0.2°, labelled `+0.5°` below 1°), else the centre row's own elevation.
- A hairline traces the el = 0° curve, labelled `0° (level)`. It is a visual aid.

**Reference line.**
- `s.mask` at the observer height, drawn as a dashed `PH.text` line at 70 % opacity on top of the terrain.
- Label for presets: `Horizon mask (LOLA 80 m/240 m)`. For custom spots: `Coarse horizon (400 m, this device)`, plus `FidelityBadge.customHorizon`.
- DEM-end segments are drawn as in §3.9.

## 6. Honesty and FidelityBadge texts

The first sentence is the ≤ 110-character summary (`FidelityBadge.summaryOf`). The rest is shown when the badge is expanded. Builders add the figures **measured by T5** to `formula.md` §12.11.

**Main badge** (always shown). Sentence 1 is exactly 100 characters:

> Approximate: the light map's own 400 m LOLA terrain and light; Sun and Earth at true size and place. Terrain is the grid the light map uses (400 m within 64 km, 800 m out to 300 km), block-averaged the same way, so rims and peaks are smoothed and the drawn skyline can differ from {preset: "this site's 80 m horizon mask (dashed) by about 1° and up to 5°" | custom: "80 m horizons by 0.5–1.4° (up to about 6° on sharp rims); it matches this spot's 400 m horizon (dashed) within about 0.4°"}. Ground within 800 m is not resolved by the 400 m grid: where it would rise above the distant skyline it is drawn see-through, because the light map leaves it out. Light and shadow are the Light tab's computed frame for this moment, pixel for pixel; Earth's direction there is taken from the Moon's centre, up to 0.3° higher than seen from the ground. Shadowed ground is drawn dark: Earthshine is not computed, and the ground colour is a flat grey, not a photo. The Sun and Earth are drawn in their meaning colours at true size and position (DE440, apparent, no refraction); glyphs, labels, the 0° line, the compass and the stripe and dot patterns are visual aids.

**Dynamic sentences**, appended to the main badge:
- (g) Presets only, when `|hGrid − site.terrainHeightM| > 5 m`: "The eye is 2 m above the 400 m surface, {N} m {below|above} this site's 80 m height." For SR1 that is about 29 m below.
- (h) When `demEnds` is non-empty: "Terrain data ends {N} km away toward azimuth {A0}–{A1}° (edge of the LOLA map)."
- During an eclipse: `lightEclipseFidelity`.

**Play badge** (a separate short `FidelityBadge` while `s.playing`), exactly 100 characters:

> Approximate: while playing, light from coarser grids (800 m, 1.6 km beyond 64 km); pause for detail.

On the web while playing, the second sentence is "Light beyond 64 km waits until you pause."

Build (1.9.1): in the stacked (portrait) layouts the main badge comes first under the view, followed by the play badge while playing; the 2D map's one-line short note and its play note are not shown with the Lander's view.

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
  - Build (deliberate difference, 2026-10-30): the panel sits in the map's square box (width = height = the box side). When the view, the buttons and the notes do not all fit, the view keeps its height (at least 120 dp, at most the box less one 48 dp button row), the first button row stays on screen under it, and the rest of the buttons and the notes scroll there. The notes are capped at 4 lines only in this finite box.
  - Build (1.9.1, 2026-10-30, after an Android 7 emulator run with a Pixel 4 profile, where the view was 410 x 99 dp and the side column cut the view switch in half): the view takes all the height above one row of buttons and only the notes scroll under them; the app's top bars hide while it is shown (as for Play; they come back with any other view or layout, or with a pull down in the side column), so at 781 x 393 dp the view is about 409 x 211 dp; the side column shows its scroll bar, so switches cut at its foot are seen to scroll.
- **Phone portrait** (Build, 1.9.1): the view always takes the full card width (never the 2D map's square side), with 8 dp of the card's padding each side so the seven buttons fit on one row from a 376 dp wide screen. Its height keeps the view and all its buttons above the pinned time bar, never under `max(160 dp, half the width)` (`LanderViewPanel.minFitViewHeightFor`); the notes scroll. Where the slot is too short to pin the time bar (360 x 640), the view scrolls with the page and one scroll shows it and all its buttons. The built mesh is kept by the app state for the current site and observer height, so Lander > Site > Lander and turning the phone do not build it again.
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
| Patches + mesh build + cull + sort | Once per (site, observerHeightM), main thread, `runSliced` rows 1 / 4 ms (D20) | Native ≤ 250 ms CPU total, web ≤ 1.2 s total. No slice > 8 ms of work. A "Building the view…" text shows until it is done (no placeholder terrain). **As built (2026-10-30):** the slice rule holds (longest unit about 7 ms in the test VM on the shipped DEM; test 'built one unit at a time'), but the total does not: about 2-3 s of CPU in the VM at SR1, spread over 4 ms slices, so the UI keeps running while the view builds. Most of it is the 750 × 750 far patch (about 2.2M triangles, about 97 % culled). Meeting the total needs a smaller or decimated far patch, or the build in an isolate on native (D6 keeps it on the main thread). |
| Mesh before culling | Transient | About 660k grid vertices (0.1M near + 0.56M far) + 2.3k lattice. Typed arrays only, freed after culling, ≤ 25 MB peak. |
| Kept mesh | Cached, LRU of 2, dropped when leaving lander mode | ≤ 150k vertices and ≤ 8 MB. T10 asserts this for the 4 test sites; if exceeded, the builder reports it rather than silently thinning. |
| Index rebuild | Sector set changes | ≤ 2 ms native. The merged ids are cached in `LanderProjection` per (mesh, sector set) (`mergeLanderSectors`: one marking pass and one linear pass, no sort); other repaints reuse them. |
| Projection | yaw/pitch/hfov/size change | Into reused `Float32List`s; ≤ 2 ms native / 6 ms web for ≤ 40k vertices |
| Recolour (gather) | New frame or layer | ≤ 3 ms native / 8 ms web. One pass for the base and every pattern buffer (`landerColors`); a vertex on one full-weight source pixel reads packed colour tables. The far frame landing after the near one still recolours once more. |
| Paint | Per frame | ≤ 80k triangles at the default hfov. 1 base pass + ≤ 2 pattern passes. `CustomPainter(repaint: controller)` inside a `RepaintBoundary`. `TextPainter`s cached by string. |
| Far light frame | Per moment, lander mode only | One region-sized frame (562k px; 141k px coarse). Requested after the near frame; never ahead of a pending near request. Skipped on the web while playing. Cache cost about 1.1 MB per far frame. |
| Probe and Semantics text | Gesture end, button press, frame change | Not per frame |

**Device check (lead):** paint time on the Android emulator (Impeller) at the default hfov for SR1, and on the web (CanvasKit). This is not a unit test.

## 9. Accessibility

- **Semantics container** labelled by the pure `describeLanderView(...)`, for example: "Lander's view, facing the Sun, azimuth 132 degrees. Sun 1.2 degrees up, in view. Earth below the horizon, azimuth 351 degrees. Ground at the centre, 23 kilometres away: sunlit."
  - It is updated at gesture end, on button presses and on frame change, and when the mesh is reset (a site switch) or fails.
  - While the view is not ready, the label starts with the canvas status line: 'Building the view…', 'Computing light…' or 'The view could not be built: …'.
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
int projectTriangles(LanderView v, LanderMesh m, List<int> sectors, LanderProjection out, {int maxBatchVertices}); // batched; the merged ids cached in `out` per (mesh, sector set)
Int32List mergeLanderSectors(LanderMesh m, List<int> sectors, Uint8List mark); // the sectors' triangle ids, ascending, each once
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
// added while building (core light):
const int landerNotComputedArgb = 0xFF6E737B; // = light_map.dart beyondMapGround (tested), since this file has no Flutter
const double landerAlbedo = 0.55;
Int32List landerPatternColors(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx, LightLayer layer, LightPattern p); // ARGB for §4.4 step 2: on-pattern colour lightPixel(cls, shade, 0, 0, 1), alpha = landerPatternAlpha
(Int32List, List<Int32List>) landerColors(LanderMesh m, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx, LightLayer layer, List<LightPattern> patterns); // the two above in one pass, value for value (what the panel calls, §8)
LightClass? landerVertexClass(LanderMesh m, int v, LightFrame? near, Int32List? nearIdx, LightFrame? far, Int32List? farIdx, LightLayer layer); // dominant weight of one vertex (S2, S6)
```

Ties in the dominant weight go to the first class in `LightClass` order, "not computed" last.

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
  - State is `belowHorizon` iff the top limb is at or under the skyline with el + ρ < 0, and `behindTerrain` iff it is under the skyline with el + ρ ≥ 0 (as `bodyStateShort`: from a high peak the skyline dips below 0°, and a body under 0° that clears it is up).
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

## 14. Review findings still to fix (review of 2026-10-29)

Three independent reviews (geometry and science, UI and accessibility, performance and platforms) of the build so far. Each finding was then checked by a separate skeptic; "confirmed" means it was reproduced on real data. Fix these before the 1.9.0 release.

### Geometry and science

- [x] **high**: Opaque 400 m cells straddling the 800 m ring hide a Sun that the map, the mask and the callouts all call visible (breaks D7) (`app/lib/core/lander_view.dart:541`)
  - Scenario: _cellRow drops a near cell only when all 4 corners are within 800 m. Cells that straddle the ring stay in part 1 and get alpha 1 (line 728). Their triangles have dmin < 800 m, so _skyChunk (line 572) leaves them out of the far skyline. That same skyline drives the near-field alpha (line 735) and skyBody's line-3 check. I measured this on the shipped DEM at the Shackleton rim preset (derosa2012-sr1-shackleton-rim). The 400 m eye is 29 m below the precise site height (1703.8 vs 1733.1 m). At az 80°, a ray at el 0.0 to +0.2° hits an opaque part-1 triangle about 290-300 m away (vertices at 283, 522 and 537 m horizontal), which rises to +0.33°. At that azimuth both the far skyline and horizons.js
  - Suggested fix: Apply the lattice's see-through rule to the near ground that part 1 keeps. One option: in _finish, give every part-1 vertex with _dh < landerNearFieldM alpha landerNearAlpha when _el[v] > skylineAt(_sky, _az[v]). Another: drop part-1 cells with any corner inside 800 m and extend the lattice rings to about 800 + 400·√2 m. Add a test that the opaque (alpha 1) drawn skyline never exceeds max(far skyline, horizons.json) by more than a small tolerance at the presets.
  - Fixed (2026-10-30): `_finish` gives part 1 vertices under 800 m the lattice's see-through rule (§3.9); test 'opaque near ground never rises above the far skyline (D7)' on the shipped DEM (SR1, Haworth, Mons Mouton, custom spot), tolerance 0.2°. Vertices at 800 m or more stay opaque.
- [x] **low**: A coarse far frame stays on screen next to a full near frame, unlabelled (stale check ignores `coarse`) (`app/lib/widgets/lander_view.dart:269`)
  - Scenario: _recolor (line 269), the probe (343) and the caption (509) show the far frame whenever its tMs equals the near frame's. §2.4 also requires `coarse` to match. On native, while playing, the far frame at T is computed on the 1.6 km grid. Pausing at T replaces the near frame with the full 400 m frame. Its tMs is still T, so the 1.6 km far light keeps showing beyond 64 km, yet the 'Approximate: while playing…' badge is gone because it keys on the near frame's coarse flag. If the full far compute then fails (the catch only clears _farSent), the unlabelled coarse light stays indefinitely. CLAUDE.md says any approximation is labelled.
  - Suggested fix: Compare `_far!.request.coarse == near.request.coarse` together with tMs in all three places, ideally through one shared getter, so a mismatched far frame drops to 'light not computed' grey until the matching one lands.
  - Fixed (2026-10-30): one `_farFrame` getter (tMs and `coarse` must equal the shown near frame's) serves the colours, the probe and the 'Grey ground' note; widget test W6b.
- [x] **low**: Far frame eclipse uses observer height 0 m, not the site's terrain height (`app/lib/widgets/lander_view.dart:293`)
  - Scenario: _syncFar calls lightFrameEclipse(raw) with the default terrainHeightM = 0. The near frame passes through light_map._drawn with site.terrainHeightM, and §4.3 requires the same for both frames. At Mons Mouton (6397 m) the far frame's eclipse observer is 6.4 km lower, which shifts Earth's apparent position by about 3 arcsec. For a few seconds around each eclipse contact the two frames then disagree: for example the near frame is total (Sun bits cleared, ground dark) while the far frame is partial (Sun bits kept), so ground beyond 64 km is drawn sunlit next to dark near ground at the same moment.
  - Suggested fix: Use `lightFrameEclipse(raw, terrainHeightM: _s.site.terrainHeightM)` (the far request's lat/lon is the site), or reuse the SunEclipse already computed for the shown near frame at the same tMs.
  - Fixed (2026-10-30): `_syncFar` passes `terrainHeightM: site.terrainHeightM`, read when the request is built (§4.3).

### UI and accessibility

- [x] **high**: Phone landscape: lander panel overflows its square box; the view shrinks to 120 dp and the buttons and notes are clipped (`app/lib/widgets/lander_view.dart:528`)
  - Scenario: In phone landscape (LightMap._short layout), light_map.dart:994 passes width = maxHeight = side, and side is usually below 336 dp (for example about 250 dp on a 915x412 phone). With width < 336 the seven buttons wrap to 2 rows (96 dp), and the 4-line notes need about 100 dp. viewH = max(120, ...) then hits its 120 floor, and the Column needs 120 + 4 + 96 + notes, which is more than side. A throwaway test with LanderViewPanel(width: 210, maxHeight: 210) in a 210-dp box gave 'A RenderFlex overflowed by 118 pixels on the bottom', with the view 210x120. In release, the button row (all 48 dp controls, including Face the Sun) and the caption are cut off. Spec §7.2 says the view takes the full heig
  - Suggested fix: When maxHeight is finite and the side-by-side short layout applies, either give the panel the full row width (the view wide and full height, with the buttons as one row or an overlay column) or put the notes and buttons in the side column. At minimum, wrap the panel body in a SingleChildScrollView when 120 + 4 + 48*rows + notesH > maxHeight. Add a widget test at width = maxHeight = 250 asserting no exception.
  - Fixed (2026-10-30): when the box has a finite height and the view, the buttons and the notes do not fit, the view keeps its height (at least 120 dp, at most the box less one 48 dp button row), the first button row (with Face the Sun) stays on screen and the rest of the buttons and the notes scroll under it, so the panel never overflows (§7.2 notes the difference); widget test 'phone landscape (short side by side)' pumps LightTab at 851x393 / 771x290 and 891x411 / 735x228.
- [x] **medium**: Canvas text (centre probe, callouts) is single-line and clipped at 320/360 px and text x2; caption ellipsised already at 400 dp (`app/lib/widgets/lander_view.dart:1047`)
  - Scenario: Widths measured with the bundled Plex fonts: the probe 'Centre: full Sun · 12.4 km · az 131.0° el +0.8°' is 310 px at x1 and 620 px at x2. 'Centre: Sun and Earth · …' is 343 px and 686 px. Callout line 1 'Sun · az 281.7° · el +0.5°' is 343 px at x2. Line 3 '400 m terrain here: partly hidden, skyline +0.2°' is 478 px at x2. On a 360 dp phone the view is about 316 dp wide (about 276 dp at 320). The probe box is clipped to size.width-12 (line 1047), so at x1 the 'el' value is already cut, and at x2 everything after the distance is lost. canvas text is clamped only at PH.maxCanvasTextScale = 2.0. In calloutBox's last fallback, callouts wider than the view are drawn from x=0 and run off the right
  - Suggested fix: Lay out canvas texts with layout(maxWidth: view width - margins) and allow wrapping, or split the probe into two lines (class · distance / az · el). For callouts, cap the width and wrap, falling back to a shorter line 3 such as '400 m: hidden, +0.2°'. Remove maxLines/ellipsis from the notes and caption, or keep it only in the landscape budget and expand there. Add a 320 px x2 widget test.
  - Fixed (2026-10-30): canvas labels lay out at a maximum width and wrap (the probe at the view width less 20, callouts less 6, the mask label less 40), so nothing is cut at the view's edge; the notes keep the 4-line cap only in a box of finite height (phone landscape) and show in full on a scrolling page; widget test '320 wide at text x2'.
- [x] **medium**: Lunar eclipse: Sun and Earth callouts drawn on top of each other (calloutBox fallback ignores the other callout) (`app/lib/widgets/lander_view.dart:886`)
  - Scenario: mp1_eclipse.png (MP1, 2026-03-03 11:30 UTC, Both layer, facing the Sun; captured after the calloutBox change) shows the 3-line Sun callout and the 2-line Earth callout overlapping, so 'hidden by Earth (lunar eclipse)' and the 400 m line cannot be read. The Sun box takes candidate 3 (centred under its disc). For Earth (avoid = Sun box), right and left are outside the view or hit Earth's own disc, and candidate 3 overlaps the Sun box. Candidate 4 (above the glyph) sits about 2 px into the compass strip (top < compassH+1), so it fails inside(). The second loop then returns candidate 3 without checking `avoid`, which puts it right over the Sun box. Coincident bodies are exactly the eclipse case 
  - Suggested fix: In the fallback, before ignoring `avoid`, try stacking directly below or above the other box (Rect at avoid.bottom+4 or avoid.top-4-h, clamped to the view). Or, when the two anchors are within a few degrees, merge both bodies into one callout box (Sun lines then Earth lines). Add the eclipse geometry (same az, el 3.9 vs 3.2, rPx 7 vs 25, view 356x330) to the calloutBox unit test.
  - Fixed (2026-10-30): `calloutBox` tries two more places, stacked directly below and above the other callout, before the fallback that ignores it; test '§5 lunar eclipse' (356x220, hfov 20.5 and 45).
- [x] **low**: Semantics label is stale and never states the view's status (building / computing / failed) after a site switch (`app/lib/widgets/lander_view.dart:561`)
  - Scenario: The label is _semantic, refreshed only in _recolor/_settled. Building the view…, Computing light… and 'The view could not be built: …' are painted on the canvas only. A throwaway test switched from the near-pole preset to another site with a failing DEM. Before: 'Lander's view, facing the Sun, azimuth 118 degrees…'. After: 'Lander's view, facing south-east, azimuth 118 degrees. Sun 4.6 degrees up, azimuth 345 degrees…'. That text was built in didUpdateWidget before _initCamera turned the camera to the new site's Sun (345°), so it names the wrong facing. It never says the view could not be built. On a successful switch the same stale facing is announced until the uncached mesh lands (up to ab
  - Suggested fix: Call _refreshText() after _initCamera changes the camera, and from _ensureMesh when it resets _mesh or sets _meshError. Have describeLanderView (or the panel) prepend the status string when status != null, for example 'Lander's view: building the view…' / '…: the view could not be built.'. Add a W test for the site switch and error states.
  - Fixed (2026-10-30): one `_status` getter feeds the canvas status line and the label, which now starts with it ('Building the view…', 'Computing light…', 'The view could not be built: …'); `_ensureMesh` refreshes the label when it resets the mesh (after `_initCamera` turned the camera) and when the build fails; widget test W12.

### Performance and platforms

- [x] **high**: Mesh build blocks the UI thread: two single-unit phases of 120-165 ms, slices of about 20 ms, 2.3 s in total (budget 250 ms native / 1.2 s web, no slice over 8 ms) (`app/lib/core/lander_view.dart:438`)
  - Scenario: Open the lander's view at SR1 (or switch site or observer height while in it). LanderViewPanelState._ensureMesh (widgets/lander_view.dart:232) runs LanderMeshWork on the UI thread with runSliced(rows: 8, sliceMs: 8). I measured it with a throwaway test on the shipped 400 m DEM (VM JIT, warmed up). The build took 2335 ms of CPU over 675 step(8) calls, and 86 of those calls each took more than 8 ms (typically 20-25 ms, because 8 units of the far-patch cell rows or the 4096-triangle cull/sky chunks run before the time check). Measured one unit at a time, two units are monolithic: _sortSweep() at 164 ms and _finish() at 120 ms. On the web build (dart2js, UI-thread engine) those become long tasks
  - Suggested fix: Split _sortSweep (the radix passes and the heap set-up) and _finish (remap, compaction, the final radix sort, the sector fill) into chunked units of no more than about 4096 elements. Call runSliced with rows: 1, or make LanderMeshWork.step time-bounded, so that no slice goes past 8 ms. On native, consider building the mesh in Isolate.run (as dem_load_io.dart already does for the DEM) and returning the typed arrays through Isolate.exit. Also add a test that checks the largest single-unit time aga
  - Fixed (2026-10-30): the dmin sort and the final compaction run as units of at most 16,384 elements (a resumable `_Radix`: histogram, prefix and scatter units per 16-bit pass; then key, mark, number, compact and sector-fill chunks), sky and cull chunks are 2048 triangles, and the panel calls `runSliced(rows: 1, sliceMs: 4)` (D20). The mesh is bit-identical to before (same hashes on the shipped DEM, cull on and off). Test 'built one unit at a time: the same mesh, and no long unit (§8)' on the shipped DEM. Not fixed: the 2-3 s total (§8 'As built'); no isolate (D6).
- [x] **high**: projectTriangles re-merges and re-sorts the visible sectors and allocates two list literals per triangle on every paint (~7 ms per frame vs a 2 ms budget) (`app/lib/core/lander_view.dart:887`)
  - Scenario: LanderPainter.paint (widgets/lander_view.dart:951) calls projectTriangles(v, m, visibleSectors(v), proj) on every repaint, and every repaint means every cam.notifyListeners tick of a drag, the 400 ms turn animation or a fling. Each call copies the sector lists into a new Int32List, runs ids.sort() over 25-40k ids, and then allocates `[a, b, c]` twice per triangle in its inner loop. Measured on the SR1 mesh (34k vertices, 62k triangles) at 411x560 px, pitch -10: mean 4.6-6.8 ms per call at hfov 45 and 7.2-7.5 ms at hfov 90, worst 15 ms. The merge and sort alone take 3-5.6 ms. The same projection loop over a cached id list, without the list literals, takes 0.56 ms. Spec §3.7/§8 says the index 
  - Suggested fix: Cache the merged, ordered triangle-id list in LanderProjection, keyed by the sector set: k-way merge the already-ascending sector lists, and rebuild only when visibleSectors changes. Replace the two `for (final q in [a, b, c])` loops with unrolled code for a, b and c. Keep xy/idx/batches cached and keyed by (yaw, pitch, hfov, w, h), so a repaint caused by a time step reuses the previous projection and only re-gathers colours.
  - Fixed (2026-10-30): `LanderProjection` caches the merged ids per (mesh, sector set) and rebuilds them with `mergeLanderSectors` (mark, then one linear pass, no sort) only when either changes; the per-triangle `[a, b, c]` literals are gone (unrolled count, indexed loop), same draw order and batches. Tests 'mergeLanderSectors: …' and 'projectTriangles reuses its merged ids: same output as a fresh projection'.
- [x] **medium**: A mesh build in flight is not cancelled on dispose: leaving lander mode keeps a multi-second UI-thread build (+104 MB transient) running, and re-entering starts a second one (`app/lib/widgets/lander_view.dart:232`)
  - Scenario: The runSliced stop predicate is `_meshKey != key || w.step(r)`. dispose() (line 200) only clears _meshes and never changes _meshKey, so the predicate stays false after the panel is gone. light_map.dart mounts LanderViewPanel only while kind == LightViewKind.lander. A user who opens the lander's view and switches back to the map within the 2+ s build (or toggles it twice) leaves the orphaned build running to the end, consuming UI-thread slices and the transient working set. I measured that working set with ProcessInfo.currentRss: RSS rose by 104 MB (164 to 268 MB) during one SR1 build, against the spec's ≤ 25 MB peak, because about 1.33M vertices (pixel plus centre vertices) carry Float64 az/
  - Suggested fix: Add a `_disposed` flag (or set `_meshKey = null`) in dispose, and include it in the runSliced predicate: `(r) => !mounted || _meshKey != key || w.step(r)`. Separately, shrink the transient set toward the 25 MB budget: Float32 for _az/_el/_dh, and build the fan centres per cell only where they are needed, or drop large phase arrays as soon as they are consumed.
  - Fixed (2026-10-30): dispose() sets `_meshKey = null`, the runSliced predicate is `!mounted || _meshKey != key || w.step(r)`, and `_ensureMesh` returns before allocating the work when the panel left during the DEM load. Widget test W7b (fails on the old code: the orphan ran the whole build). The transient memory is unchanged (a separate change).
- [x] **low**: Recolour on each new light frame takes 7-8 ms for the 'both' layer (budget 3 ms native), and runs twice per time step on native (`app/lib/state/lander_light.dart:156`)
  - Scenario: didUpdateWidget calls _recolor whenever the near frame's identity changes, i.e. on every play step or scrub. _recolor runs landerVertexColors and then landerPatternColors for each pattern of the layer, and each landerPatternColors call first runs landerPatternAlpha in full and then a second per-vertex pass that calls _source() (a record per vertex) and reads m.part/m.w through the object. Measured on the SR1 mesh with real computed frames: the base colours take 2.2-3.0 ms, the two patterns 4.2-5.2 ms, so 'both' costs about 7-8 ms per recolour in the VM, against spec §8's ≤ 3 ms native / 8 ms web. On native the far frame lands about 50-150 ms after the near one and triggers a second full reco
  - Suggested fix: Fuse the pattern alpha and the pattern colour into one pass, compute the base and all pattern buffers in a single loop over vertices, and hoist the near/far source selection out of the loop (vertices are grouped by part, so loop per part range instead of calling _source per vertex). When only the far frame arrives, recolour only the part-2 vertices.
  - Fixed (2026-10-30): `landerColors` computes the base and every pattern buffer in one loop with the near/far source hoisted, and reads packed (class, shade) tables for a vertex on one full-weight pixel; `_recolor` calls it once. Value for value equal to `landerVertexColors` / `landerPatternColors` (test S3b: SR1, every layer, near only and near + far, full and coarse). Not done: recolouring only part 2 when just the far frame lands.

### Skeptic verdicts so far

- CONFIRMED: The claim holds. I reproduced it with the real LightTab, not only a panel in an artificial box. The worktree HEAD is ecd4cd4, not 6ee08b1.  Code path: - In phone landscape, light_tab.dart takes the `LightMap.shortSideBySideFor` branch. - In that layout, light_map.dart:1182 sets side = min(c.maxHeigh
  - Fix: A small fix in app/lib/widgets/lander_view.dart only. I verified it: all 5 repro cases had no exception, and test/widget/lander_view_test.dart passed 16/16. I then reverted it, so the worktree is clean.  (1) At line 528, change `final viewH` to `var viewH` and add these lines after it: ```dart final scroll = widget.maxHeight.isFinite && viewH + 4 + 48.0 * rows + notesH > widget.maxHeight; if (scroll) viewH = math.max(0.0, math.min(viewH, widget.maxHeight - 4 - 48)); ```  (2) Replace the returned SizedBox/Column (lines 674-682) with this: ```dart final below = [buttons, for (final n in notes) T
- CONFIRMED: I reproduced this on the shipped DEM with a throwaway test in /home/user/lv-wt/app/test/_rev_tmp_v0/. The test is deleted and the worktree is clean. The worktree HEAD read ecd4cd4, not 6ee08b1, but the line numbers all match the report.  **Mechanism, confirmed in /home/user/lv-wt/app/lib/core/lander
  - Fix: This is the smallest fix: apply the lattice's see-through rule to the part-1 vertices under 800 m. Those vertices are never in the far skyline, because any triangle that contains one has dmin < 800. So comparing them with the skyline is safe. Leave vertices at 800 m or more alone, so far peaks are not made translucent by skyline sampling between 0.5° steps.  In app/lib/core/lander_view.dart `_finish`, change ```dart       part[o] = isFar ? 2 : 1; ``` to ```dart       part[o] = isFar ? 2 : 1;       // D7: near ground the 400 m cells keep inside 800 m (cells straddling the ring) is see-through a
- CONFIRMED: I could not refute it: the claim holds, and I reproduced it on the real SR1 mesh from the shipped DEM. Note that the worktree HEAD is ecd4cd4, not 6ee08b1; I reviewed the code as checked out there.  **What the code does** - `projectTriangles` (/home/user/lv-wt/app/lib/core/lander_view.dart:876-946) 
  - Fix: The smallest correct fix is in /home/user/lv-wt/app/lib/core/lander_view.dart only. It stays pure Dart and needs no widget change.  **1. Cache the merged ids in `LanderProjection`, keyed by mesh and sector set.**  Add these fields: ```dart LanderMesh? _idsMesh; List<int> _idsKey = const []; Int32List _ids = Int32List(0); ```  At the top of `projectTriangles`: ```dart if (!identical(out._idsMesh, m) || !_sameInts(out._idsKey, sectors)) {   out._ids = _mergeSectors(m, sectors);   out._idsMesh = m;   out._idsKey = List.of(sectors); } final ids = out._ids; ```  - `_sameInts` is a plain length chec
- CONFIRMED: I could not refute the claim. I reproduced it on the shipped DEM (dem_400m.bin.gz, size 2280, 400 m), and the numbers break the spec's own budget. docs/landers_view_spec.md §8 says: native ≤ 250 ms CPU total, web ≤ 1.2 s, no slice > 8 ms of work. Note: the worktree HEAD is ecd4cd4, which descends fr
  - Fix: The smallest correct fix keeps the results bit-identical, and the existing 'sliced build equals one-shot' test still covers that.  (1) In core/lander_view.dart, replace the one-shot `_radix` with a resumable class whose units each handle at most 65,536 elements. Per 16-bit pass the units are: histogram chunks, then one prefix-sum unit, then scatter chunks, then a buffer swap and a cnt reset. For example:  ``` class _Radix {   final Uint32List keys;   Int32List src, dst;   final cnt = Int32List(65537);   int pass = 0, stage = 0, i = 0;   _Radix(Int32List ids, this.keys) : src = ids, dst = Int32
- CONFIRMED: The claim holds. I checked it against the worktree at HEAD ecd4cd4 (the commit that added `LanderPainter.calloutBox`; line 886 is the return in the second fallback loop) and against the screenshot /tmp/claude-0/-home-user-CLPS-MOON-BROWSER/3f8ae6b1-fba8-5587-b499-4c90b54bab61/scratchpad/landers_shot
  - Fix: In `LanderPainter.calloutBox` (app/lib/widgets/lander_view.dart, around line 875), add two stacked candidates after the existing four. They sit directly below or above the other callout's box, centred on this body's glyph, so the first loop tries them with the full `clear()` check before the fallback loop ignores `avoid`:      final cands = [       Rect.fromLTWH(a.glyph.dx + 11, top, box.width, box.height),       Rect.fromLTWH(a.glyph.dx - 11 - box.width, top, box.width, box.height),       Rect.fromLTWH(cx, a.disc.dy + a.rPx + 6, box.width, box.height),       Rect.fromLTWH(cx, a.glyph.dy - 14 
- CONFIRMED: The claim holds. Checked in the worktree /home/user/lv-wt (HEAD shows ecd4cd4) with the bundled IBM Plex fonts (loadPlexFonts). I ran two throwaway tests: a text measure, and a copy of lander_view_test.dart with the real LanderViewPanel, fake engine and synthetic DEM. Both were deleted afterwards an
  - Fix: Smallest fix, all in app/lib/widgets/lander_view.dart: let canvas labels wrap to the view width, and stop truncating the notes when the panel has no height budget.  1. In `_text` (l.733), add `double maxWidth = double.infinity`, include it in the cache key (`'$s|$size|…|$maxWidth'`), and call `..layout(maxWidth: maxWidth)` instead of `..layout()`. With maxLines unset, TextPainter wraps, and `t.width <= maxWidth`.  2. Probe (l.1046-1047):    - `final t = _text(msg, size: 11, mono: status == null, maxWidth: size.width - 20);`    - `final r = Rect.fromLTWH(6, bottom - t.height - 4, t.width + 8, t

Not yet verified when work stopped: the eclipse callout overlap, clipped canvas text, and the mesh build not cancelled on dispose (and the low-severity ones).
