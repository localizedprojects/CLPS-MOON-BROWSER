export const meta = {
  name: 'landers-view',
  description: "3D lander's view at the selected landing site: terrain from the light & shadow engine's own height grid, lit by the app's computed light frame; design panel, core, UI, review, verify, fix, visual check (each agent under 250k tokens)",
  phases: [
    { title: 'Design', detail: 'two independent designs (fidelity-first, experience-first), then one spec' },
    { title: 'Core', detail: 'pure-Dart mesh, camera and light mapping with tests (two parts)' },
    { title: 'UI', detail: 'the view in the Light tab, synced to the time bar; sky, patterns, a11y; screenshots (two parts)' },
    { title: 'Review', detail: 'geometry/science, UI/a11y/design system, performance/platforms' },
    { title: 'Verify', detail: 'one skeptic per finding' },
    { title: 'Fix', detail: 'apply confirmed findings' },
    { title: 'Look', detail: 'visual check of the screenshots against the 2D light map; one more fix round if needed' },
  ],
}

const REPO = args.repo, SCRATCH = args.scratch, VENV = args.venv
const SHOTS = `${SCRATCH}/landers_shots`

const CAP = `TOKEN CAP (from the user): this agent must use under 250k tokens in total, context included. The lead stops any agent that reaches 215k, so finish by 170k. Read only what you need (grep -n, sed -n ranges; never cat whole large files, assets or logs); run tests with output to a file and print only the summary and failures. Do not re-read files.`

const COMMON = `${CAP}

Repo: ${REPO} (Flutter app in app/, React/Plotly charts in charts/, Python pipeline in pipeline/, Python library in pylib/), a detached git worktree at ${args.sha} (the v${args.version} work of branch ${args.branch}). Work ONLY inside ${REPO}; never read or write /home/user/CLPS-MOON-BROWSER (the lead is releasing from it). Throwaway logs go to ${SCRATCH}. Flutter at /opt/flutter/bin (export PATH=/opt/flutter/bin:$PATH). 4 CPUs shared with another agent and the lead's test runs and builds: NEVER run the full flutter test suite; only named test files; one heavy process at a time. Do not commit or push. CLAUDE.md rules apply: lib/core is pure Dart with a test for every function; science conventions (MOON_ME, planetocentric lat, east-positive lon, LT+S apparent directions, R = 1737.4 km, observer 2 m above terrain, local ENU on the spherical normal, azimuth clockwise from north where north = increasing latitude = away from the pole) are not changed; approximations labelled with FidelityBadge; design tokens from app/lib/theme.dart (deep-navy instrument panel; Sun amber #FFB000, Earth blue #3D8BFD, both teal #2EC4B6; colour carries meaning only and is never the only encoding); IBM Plex Mono with tabular figures for numbers; Semantics on every interactive widget; tap targets >= 48 dp. Render rules: real data only (LOLA terrain, SPICE Sun/Earth); no cosmetic textures, no fake stars, any visualisation aid labelled.

FEATURE (from the user, 2026-10-29): a 3D "lander's view": what you would see standing on the lander at the selected landing site (preset site or custom spot), 2 m above the terrain (the app's observer height), at the moment shown by the time bar, looking around the horizon.
USER DECISION (asked and answered): the terrain heights come from the exact height grid the app's light & shadow engine uses (app/lib/core/shadow.dart ShadowGrid, built in app/lib/state/light_engine.dart LightGrids from the shipped 400 m LOLA DEM, block-averaged the same way), and the light and shadow drawn on that terrain is the app's own computed light frame for that moment (LightFrame.flags: lightSunAny / lightSunFull / lightEarth, and LightFrame.shade, the Lambert term), so the 3D view always agrees with the 2D light map in the Light tab. No shape-from-shadow, no other height source for the mesh. The site's precise horizon mask (assets/data/horizons.json from the 80 m / 240 m DEM for presets; the on-device coarse horizon for custom spots) may be shown as a labelled reference line, never used to fake the mesh.`

const RESULT = {
  type: 'object',
  properties: {
    filesChanged: { type: 'array', items: { type: 'string' } },
    testsRun: { type: 'array', items: { type: 'object', properties: { command: { type: 'string' }, result: { type: 'string' } }, required: ['command', 'result'] } },
    notes: { type: 'string', description: 'decisions, user-visible texts added (quote them), numbers, deviations from the spec' },
    screenshots: { type: 'array', items: { type: 'string' }, description: 'absolute PNG paths written' },
    openIssues: { type: 'array', items: { type: 'string' } },
  },
  required: ['filesChanged', 'testsRun', 'notes', 'screenshots', 'openIssues'],
}
const DESIGN = { type: 'object', properties: { proposal: { type: 'string', description: 'the full design, concrete (files, functions, numbers, texts), at most 2500 words' }, risks: { type: 'array', items: { type: 'string' } } }, required: ['proposal', 'risks'] }
const FINDINGS = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, file: { type: 'string' }, line: { type: 'number' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] }, failure_scenario: { type: 'string' }, suggested_fix: { type: 'string' } }, required: ['title', 'file', 'line', 'severity', 'failure_scenario', 'suggested_fix'] } } }, required: ['findings'] }
const VERDICT = { type: 'object', properties: { refuted: { type: 'boolean' }, reproduced: { type: 'boolean' }, evidence: { type: 'string' }, fix: { type: 'string' } }, required: ['refuted', 'reproduced', 'evidence', 'fix'] }
const FIX_SCHEMA = { type: 'object', properties: { fixed: { type: 'array', items: { type: 'string' } }, notFixed: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, why: { type: 'string' } }, required: ['title', 'why'] } }, testsRun: RESULT.properties.testsRun, screenshots: RESULT.properties.screenshots }, required: ['fixed', 'notFixed', 'testsRun', 'screenshots'] }
const LOOK = { type: 'object', properties: { problems: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, screenshot: { type: 'string' }, evidence: { type: 'string' }, suggested_fix: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] } }, required: ['title', 'screenshot', 'evidence', 'suggested_fix', 'severity'] } }, verdict: { type: 'string' } }, required: ['problems', 'verdict'] }

const SCOUT = `Start by reading (sed -n ranges only): app/lib/core/shadow.dart (header and ShadowGrid/ShadowGridBuilder, computeLightField), app/lib/state/light_engine.dart (LightRequest, LightFrame, LightGrids, the close-up window: closeUpPx = 320 px of the 400 m grid = 128 km), app/lib/core/dem.dart (PolarGrid, latLonToXY), app/lib/core/geo.dart (ENU, az/el), app/lib/core/horizon_compute.dart (coarse horizon on the same 400 m DEM), app/lib/screens/site/light_tab.dart and the top of app/lib/widgets/light_map.dart (how the Light tab gets frames and follows the time bar and play).`

phase('Design')
const [designA, designB] = await Promise.all([
  agent(`${COMMON}

Read-only. YOUR BUDGET IS 120k. ${SCOUT}
Write a FIDELITY-FIRST design for the lander's view: (1) geometry: how each mesh vertex is placed exactly in the site's local ENU (sphere R + h, the same block-averaged heights the ShadowGrid holds, curvature included; map-metre vs true distance), camera at 2 m above the site's terrain, projection (rectilinear perspective with yaw/pitch and a field of view; true vertical scale by default), draw order (far to near; precomputable per site) and level of detail; (2) extent: the 128 km close-up window vs terrain beyond it (the region grid / the whole DEM to about 75 S) so distant massifs on the skyline are there; (3) light: per-vertex or per-triangle state from the LightFrame flags/shade of the same grid pixels (Sun any / full Sun / Earth view layers, as the Light tab offers), consistent with the 2D map pixel for pixel; (4) the sky: Sun and Earth at their apparent az/el from the app's ephemeris for that moment, true angular size, plus glyph and label; behaviour when they are below the horizon or behind terrain; eclipse state from app/lib/core/eclipse.dart; (5) honesty: what the 400 m terrain cannot show (near field within ~1 km is flat-ish; the 400 m skyline vs the precise horizon mask: quantify the expected difference for 2-3 presets by reading horizons.json and the coarse horizon), and the FidelityBadge texts; (6) core functions with signatures and the tests that prove each (synthetic ridge at known distance -> exact elevation; skyline vs horizon_compute coarse horizon on the same DEM within a stated tolerance; lit pixel -> lit vertex; azimuth orientation: facing az 0, az 90 is on the RIGHT; Sun marker az/el equals the sky plot's).`, { label: 'design A: fidelity-first', phase: 'Design', schema: DESIGN }),
  agent(`${COMMON}

Read-only. YOUR BUDGET IS 120k. ${SCOUT} Also read app/lib/screens/site/site_screen.dart, app/lib/widgets/time_bar.dart (top), app/lib/widgets/feature_guide.dart (GuideTarget), and app/lib/theme.dart tokens.
Write an EXPERIENCE-FIRST design for the lander's view: (1) where it lives (Site screen, Light tab or its own sub-tab; first thing seen vs below the map; full-screen expand), on a 360 px phone, a tablet and the web (1280 px); (2) interaction: drag / swipe to look around, keyboard arrows on web, a compass strip with N/E/S/W where north = away from the pole, quick buttons 'face the Sun' / 'face Earth', pitch limits, field of view; synced to the time bar cursor and to play (coarse frames during play as the light map does, full frame on stop); (3) what is drawn: terrain lit by the computed light frame (Sun / Earth / both layers like the light map, its legend), Sun and Earth markers with glyph + label + elevation in IBM Plex Mono, horizon reference line from the precise mask, labelled; eclipse note; when the Sun is down: terrain in Earthshine? only if the app computes it (it does not: then show only what is computed, e.g. Earth-visible areas in the Earth layer) - no invented lighting; (4) performance budget: a 320 x 320 grid is ~200k triangles: level of detail, culling, precomputed far-to-near order, Canvas.drawVertices, recolour only when the frame changes, project only on yaw/pitch change; web main thread slicing like the light engine; memory on Android; (5) accessibility: Semantics label that describes the view in words (e.g. 'Facing the Sun, azimuth 132 degrees: Sun 1.2 degrees up, lit; Earth below the horizon'), 48 dp controls, focus ring, reduced motion; (6) the texts (FidelityBadge wording, caption, Learn/guide mention) and the widget tests and screenshot tests to write (render to PNG in a flutter test for review).`, { label: 'design B: experience-first', phase: 'Design', schema: DESIGN }),
])

const spec = await agent(`${COMMON}

YOUR BUDGET IS 100k. Two independent designs for the lander's view follow. Merge them into ONE concrete build spec: take the fidelity-first design's geometry, light and honesty rules as binding; take the experience-first design's placement, interaction, performance and a11y plan unless it conflicts with fidelity; resolve every disagreement explicitly (say which and why); cut anything that cannot be built and tested within about 300k tokens of agent work in total (two builders). Write it to ${REPO}/docs/landers_view_spec.md (this is the only file you write): sections Goal, Data path (exact functions and files), Geometry (formulas), Light mapping, Sky, Honesty and FidelityBadge texts, Placement and interaction, Performance budget, Accessibility, Core API (Dart signatures), Tests (each named), Screenshots (which sites/times: at least a sunlit preset at a moment with long shadows, the 2026-03-03 11:30 UTC eclipse at a sunlit preset, a custom spot, the Sun below the horizon), Out of scope. Then return the spec's path and a 10-line summary.
DESIGN A (fidelity-first): ${JSON.stringify(designA)}
DESIGN B (experience-first): ${JSON.stringify(designB)}`, { label: 'design: merge into one spec', phase: 'Design' })

phase('Core')
// split after the first core agent ran out of tokens: each part continues from the tree
const CONT = `A previous agent started this build and stopped at its token cap; its uncommitted work is in the tree (git -C ${REPO} status; git -C ${REPO} diff --stat; read only what you need). Continue from it: keep what is right, finish what is missing, fix what is wrong. Read only the spec sections named below (grep -n '^##' ${REPO}/docs/landers_view_spec.md, then sed -n ranges).`
const coreA = await agent(`${COMMON}

YOUR BUDGET IS 150k AND IT IS STRICT: two earlier agents ran out of tokens by reading whole files. Never read a whole file: lander_view.dart is ~1050 lines and lander_view_test.dart ~700; use grep -n to find a function and sed -n on at most 80 lines at a time. Do not read the spec except the one subsection a failure needs (grep -n '^##' first).
STATE: app/lib/core/lander_view.dart (geometry, camera, culling, projection, describeLanderView) and app/test/core/lander_view_test.dart are written and committed; the shadow.dart refactor is in and flutter analyze is clean. cd ${REPO}/app && flutter test test/core/lander_view_test.dart gives 30 pass, 3 FAIL:
1. 'flat sphere: everything beyond the geometric horizon is culled' (test line ~252-306, expect at 276): a kept triangle at 3065.3 m > limit 3036.2 m.
2. 'shipped DEM skyline matches computeCoarseHorizon on the shipped DEM' (~307-324, expect at 319): max difference 0.0544 deg > 0.05.
3. 'culling is conservative' (~512-570): the expected skyline list (values ~13.7..14.06 deg) differs from the actual.
For each, find the root cause from the code (culling in LanderMeshWork ~364-772, _skyTri ~243, meshSkyline ~318, _bulge ~229) and decide honestly whether the CODE or the TEST is wrong: a test tolerance may be widened only with a stated geometric reason (e.g. one 400 m cell straddling the horizon, the coarse horizon's sampling step) written as a comment next to it; never weaken a test just to pass. Fix, then run in ONE call: flutter analyze && flutter test test/core/lander_view_test.dart test/core/shadow_test.dart test/core/series_sliced_test.dart > ${SCRATCH}/lv_coreA2.log 2>&1; tail -3. All must pass. Leave screenshots [].`, { label: 'core A2: fix the 3 failing geometry tests', phase: 'Core', schema: RESULT })
const coreB = await agent(`${COMMON}

YOUR BUDGET IS 170k. ${CONT}
Never read a whole file: grep -n then sed -n at most 80 lines at a time; lander_view.dart is ~1050 lines. PART: CORE LIGHT. The geometry part is done: ${JSON.stringify({ files: coreA && coreA.filesChanged, notes: coreA && String(coreA.notes).slice(0, 1200) })}. Spec sections 4 (Light mapping), 5 (Sky: the core functions only), 10 (Core API: light_engine.dart additions, app/lib/state/lander_light.dart) and the lander_light_test.dart part of 11. Pure Dart (no package:flutter in lib/core or lander_light.dart). Run cd ${REPO}/app && flutter analyze, then in ONE call flutter test test/state/lander_light_test.dart test/state/light_engine_test.dart test/core/lander_view_test.dart > ${SCRATCH}/lv_coreB.log 2>&1; tail. Leave screenshots [].`, { label: 'core B: light mapping, far frame, sky', phase: 'Core', schema: RESULT })
const core = { filesChanged: [...((coreA && coreA.filesChanged) || []), ...((coreB && coreB.filesChanged) || [])], notes: `${coreA && coreA.notes || ''}\n${coreB && coreB.notes || ''}` }

phase('UI')
const uiA = await agent(`${COMMON}

YOUR BUDGET IS 150k AND IT IS STRICT: earlier agents ran out by reading whole files. Never read a whole file; grep -n, then sed -n at most 80 lines at a time (app/lib/widgets/lander_view.dart ~800 lines, light_map.dart ~2000, the core lander_view.dart ~1050).
STATE: the core is done and tested (app/lib/core/lander_view.dart, app/lib/state/lander_light.dart, light_engine.dart far frame; 34 + 33 tests pass). A previous UI agent wrote app/lib/widgets/lander_view.dart, wired it into light_map.dart (a third segment "From the lander" in the Light tab's view switch) and app_state.dart, and wrote app/test/widget/lander_view_test.dart (8 tests W1-W8 + layout); flutter analyze is clean. ALL 8 widget tests FAIL the same way: the helper meshReady (test line ~100-110) gets null 'after 5000 pumps', i.e. the lander mesh never becomes ready under the widget-test binding. Find the root cause (e.g. the DEM load or light frames run in an isolate or a real-time Timer/Future that fake time never completes; see how the existing light-map widget tests wait for frames: grep -n 'runAsync' app/test/widget/light_*_test.dart) and fix it the right way: in the TEST harness if the app code is correct for real devices, in the CODE if it is a real bug (for example a slice scheduler that never reschedules). Then make W1-W8 and the layout test pass honestly (no weakening). Run in ONE call: cd ${REPO}/app && flutter analyze && flutter test test/widget/lander_view_test.dart test/widget/light_map_test.dart > ${SCRATCH}/lv_uiA2.log 2>&1; tail -3. Leave screenshots [].`, { label: 'ui A2: widget tests (mesh never ready in tests)', phase: 'UI', schema: RESULT })
const uiB = await agent(`${COMMON}

YOUR BUDGET IS 150k AND IT IS STRICT: earlier agents ran out by reading whole files. Never read a whole file; grep -n, then sed -n at most 80 lines at a time (app/lib/widgets/lander_view.dart, light_map.dart ~2000 lines, the core lander_view.dart ~1050).
STATE: the lander's view is built and committed (core: app/lib/core/lander_view.dart, app/lib/state/lander_light.dart; UI: app/lib/widgets/lander_view.dart, the "Lander" segment in light_map.dart's view switch, texts in content/guides.dart and content/how_calculated.dart). flutter analyze is clean. cd ${REPO}/app && flutter test test/widget/lander_view_test.dart gives 14 pass, 1 FAIL: 'compass strip: Semantics and tooltip, tap turns there; callout and edge chevron turn to the body' (expect at test line ~380 finds no widget with a semantics label starting "Compass: N is"). Decide from the spec (grep -n -i compass ${REPO}/docs/landers_view_spec.md, read only those lines) whether the code lacks the label or the test expects the wrong text, and fix the right side.
Then check, by grep only, that spec §4.4 (non-colour patterns), §5 (Sun/Earth discs and callouts), §6 (FidelityBadge texts) and §9 (Semantics) each have code; add only what is clearly missing, with a test.
Then SCREENSHOTS: write a throwaway flutter test under app/test/zz_tmp_landers_shots/ that pumps the real LanderViewPanel inside the app (Light tab, Lander segment) with real data (fonts as in app/test/widget/light_test_fonts.dart; fakes installed inside the test body as lander_view_test.dart's installFakes does) for: (1) Malapert peak MP1 at a sunlit moment with long shadows, (2) MP1 at 2026-03-03 11:30 UTC (total lunar eclipse), (3) a custom spot near 85°S, (4) a moment with the Sun below the horizon; save PNGs to ${SHOTS}/ (RepaintBoundary.toImage inside tester.runAsync; File.writeAsBytes) and also the 2D Light-tab map ('Around site') for the same site and moment as <name>_map.png; then delete app/test/zz_tmp_landers_shots/. Look at two PNGs with the Read tool and fix anything plainly wrong (mirrored azimuths, upside-down, black frame, Sun in the wrong place). Run cd ${REPO}/app && flutter analyze && flutter test test/widget/lander_view_test.dart test/widget/light_map_test.dart in one call. Return the PNG paths in screenshots.`, { label: 'ui B2: compass label, gaps, screenshots', phase: 'UI', schema: RESULT })
const ui = { filesChanged: [...((uiA && uiA.filesChanged) || []), ...((uiB && uiB.filesChanged) || [])], notes: `${uiA && uiA.notes || ''}\n${uiB && uiB.notes || ''}`, screenshots: (uiB && uiB.screenshots) || [] }

phase('Review')
const REV = `Read-only on tracked files (throwaway tests in ${REPO}/app/test/_rev_tmp_X/ or ${SCRATCH}/rev_X/, deleted afterwards). YOUR BUDGET IS 120k: read the spec ${REPO}/docs/landers_view_spec.md and only the diff hunks you need (git -C ${REPO} diff ${args.sha} -- app/lib; git -C ${REPO} status for new files). Report only concrete problems with a trigger; at most 4; an empty list is fine.`
const reviews = await parallel([
  () => agent(`${COMMON}

${REV.replace(/_X/g, '_geo')} Lens: GEOMETRY AND SCIENCE. Independently recompute a few vertices' positions and on-screen elevations by hand for a preset site; check the skyline against the coarse horizon on the same DEM and against horizons.json; check left/right orientation (facing az 0, az 90 on the right), the Sun/Earth marker positions against app/lib/core/visibility.dart az/el at the same moment, curvature, the light flags mapping (the 3D lit area = the 2D map's lit pixels), eclipse handling, and that nothing is invented (no lighting the engine did not compute).`, { label: 'review: geometry + science', phase: 'Review', schema: FINDINGS }),
  () => agent(`${COMMON}

${REV.replace(/_X/g, '_ui')} Lens: UI, ACCESSIBILITY AND DESIGN SYSTEM. Semantics text true for every state, 48 dp, keyboard, focus ring, reduced motion, colour never the only encoding, design tokens and fonts, FidelityBadge wording honest, layout at 320/360/1280 px and text x2, time-bar and play sync, behaviour when switching sites/custom spots and when data is still loading. Look at the PNGs in ${SHOTS} with the Read tool.`, { label: 'review: UI + a11y', phase: 'Review', schema: FINDINGS }),
  () => agent(`${COMMON}

${REV.replace(/_X/g, '_perf')} Lens: PERFORMANCE AND PLATFORMS. Work per frame vs per pan vs per time step; allocations in paint; triangle counts; the web build (main-thread slicing like the light engine, no long tasks), Android (isolate use, memory), dispose/leaks, rebuild churn on the time bar, behaviour while playing. Measure where cheap (a throwaway test that times the mesh build and a projection pass).`, { label: 'review: performance + platforms', phase: 'Review', schema: FINDINGS }),
])
const sev = { high: 0, medium: 1, low: 2 }
const all = reviews.filter(Boolean).flatMap((r, i) => (r.findings || []).map(f => ({ ...f, from: ['geometry review', 'ui review', 'performance review'][i] }))).sort((a, b) => sev[a.severity] - sev[b.severity])
const found = all.slice(0, 7)
log(all.length > found.length ? `verifying the ${found.length} most severe of ${all.length}; not verified: ${all.slice(found.length).map(f => f.title).join(' | ')}` : `${found.length} findings to verify`)

phase('Verify')
const verified = await parallel(found.map((f, i) => () => agent(`${COMMON}

Read-only (throwaway tests in ${REPO}/app/test/_rev_tmp_v${i}/ or ${SCRATCH}/lv_v${i}/, deleted afterwards). YOUR BUDGET IS 80k. A ${f.from} agent claims: ${f.title} at ${f.file}:${f.line} (${f.severity}). Scenario: ${f.failure_scenario}. Suggested fix: ${f.suggested_fix}. Try to REFUTE it from the real code and data; reproduce where feasible. Default to refuted=true without a concrete trigger. If real, give the smallest correct fix.`, { label: `verify: ${f.title}`.slice(0, 70), phase: 'Verify', schema: VERDICT }).then(v => ({ ...f, verdict: v }))))
const confirmed = verified.filter(Boolean).filter(f => f.verdict && !f.verdict.refuted)
log(`${confirmed.length} confirmed of ${verified.filter(Boolean).length}`)

phase('Fix')
const fixPrompt = (items, round) => `${COMMON}

YOUR BUDGET IS 150k AND IT IS STRICT: never read a whole file; grep -n, then sed -n at most 80 lines at a time. Apply these confirmed problems in the lander's view, smallest correct change each, with a test where it makes sense; keep docs/landers_view_spec.md true (update it where the build deliberately differs). Then regenerate the screenshots into ${SHOTS}/ (round ${round}: same cases, file names suffixed _r${round}) the way the UI agent did (temporary app/test/zz_tmp_landers_shots/, deleted afterwards), and run cd ${REPO}/app && flutter analyze and the test files you touched in one call. Problems: ${JSON.stringify(items, null, 1)}`
const STRICT = `YOUR BUDGET IS 150k AND IT IS STRICT: earlier agents ran out by reading whole files. Never read a whole file; grep -n, then sed -n at most 80 lines at a time (app/lib/widgets/lander_view.dart, light_map.dart ~2000 lines, app/lib/core/lander_view.dart ~1050, app/lib/state/lander_light.dart).`
const fixes = []
for (const area of ['geometry review', 'performance review', 'ui review']) {
  const items = confirmed.filter(f => f.from === area)
  if (!items.length) continue
  fixes.push(await agent(`${COMMON}

${STRICT} Apply these confirmed problems in the lander's view (${area}), smallest correct change each, with a test where it makes sense; keep docs/landers_view_spec.md true where the build deliberately differs. Other agents fix the other areas before or after you; touch only what these need. Run in ONE call at the end: cd ${REPO}/app && flutter analyze && flutter test test/core/lander_view_test.dart test/state/lander_light_test.dart test/widget/lander_view_test.dart test/widget/light_map_test.dart > ${SCRATCH}/lv_fix_${area.split(' ')[0]}.log 2>&1; tail -3. Problems: ${JSON.stringify(items.map(f => ({ title: f.title, file: f.file, line: f.line, fix: f.verdict.fix, evidence: String(f.verdict.evidence).slice(0, 1000) })), null, 1)}`, { label: `fix: ${area} (${items.length})`, phase: 'Fix', schema: FIX_SCHEMA }))
}
const fix = { fixes }
const shots = await agent(`${COMMON}

${STRICT} Regenerate the lander's-view screenshots after the fixes: a throwaway flutter test under app/test/zz_tmp_landers_shots/ (pump the real app Light tab with the Lander segment, real data, fonts as in app/test/widget/light_test_fonts.dart, fakes installed inside the test body as lander_view_test.dart's installFakes does) for: MP1 sunlit with long shadows, MP1 at 2026-03-03 11:30 UTC (eclipse), a custom spot near 85°S, a moment with the Sun below the horizon, and MP1 in phone landscape (844x390); save PNGs with suffix _r1 to ${SHOTS}/ and each one's 2D 'Around site' map as <name>_r1_map.png; delete the throwaway folder. Return the paths in screenshots.`, { label: 'screenshots after the fixes', phase: 'Fix', schema: RESULT })

phase('Look')
const looks = []
const fixes2 = []
for (let round = 1; round <= 2; round++) {
  const look = await agent(`${COMMON}

Read-only. YOUR BUDGET IS 80k. You are the visual critic. Look (Read tool) at the newest lander's-view screenshots in ${SHOTS}/ (ls -t; prefer the highest _rN suffix) and at each one's 2D map partner (_map.png). For each: does the lit/shadowed terrain in 3D match the 2D map's lit area around the site; is the skyline plausible against the site's horizon (horizons.json); are the Sun/Earth markers where the status line says (elevation numbers); is anything mirrored, upside-down, clipped, unlabelled, unreadable, overlapping, or invented (texture, stars, light the engine did not compute)? Report only problems you can point at in a named PNG; an empty list is fine.`, { label: `look: screenshots round ${round}`, phase: 'Look', schema: LOOK })
  looks.push(look)
  const real = ((look && look.problems) || []).filter(p => p.severity !== 'low')
  if (!real.length) break
  const f2 = await agent(fixPrompt(real, round + 1), { label: `fix: ${real.length} visual problems (round ${round + 1})`, phase: 'Look', schema: FIX_SCHEMA })
  fixes2.push(f2)
}

return { designA, designB, spec, core, ui, reviews, confirmed, refuted: verified.filter(Boolean).filter(f => f.verdict && f.verdict.refuted).map(f => f.title), unverified: all.slice(found.length).map(f => f.title), fix, looks, fixes2 }
