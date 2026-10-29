export const meta = {
  name: 'map-colocated-sites',
  description: 'Explore map: stacked markers and overlapping names for sites less than 1 km apart (after the three new mission sites); build, review, verify, fix (each agent under 250k tokens)',
  phases: [
    { title: 'Build', detail: 'chooser for stacked markers, count badge, label de-collision, tests, screenshots' },
    { title: 'Review', detail: 'UI, a11y and correctness' },
    { title: 'Verify', detail: 'one skeptic per finding' },
    { title: 'Fix', detail: 'apply confirmed findings' },
  ],
}

const REPO = args.repo, SCRATCH = args.scratch
const SHOTS = `${SCRATCH}/map_shots`
const COMMON = `TOKEN CAP (from the user): this agent must use under 250k tokens in total, context included. The lead stops any agent that reaches 215k, so finish by 170k. Read only what you need (grep -n, sed -n ranges); run tests with output to a file and print only the summary and failures.

Repo: ${REPO}, branch ${args.branch}. Flutter at /opt/flutter/bin (export PATH=/opt/flutter/bin:$PATH). 4 CPUs: NEVER run the full flutter test suite; only named test files. Do not commit or push. CLAUDE.md rules apply (design tokens in app/lib/theme.dart; colour never the only encoding; Semantics on every interactive widget; tap targets >= 48 dp; IBM Plex Mono for numbers; marker positions are real coordinates and are never moved).

PROBLEM: the catalogue now has 19 preset sites, and four pairs sit less than 1 km apart on the Explore map (app/lib/widgets/map_view.dart): IM-2 Athena (landed) / IM-2 Athena (intended target) 0.37 km, Connecting ridge (CR1) / LUPEX / Chandrayaan-5 (candidate) 0.55 km, Mons Mouton / VIPER mission area 0.58 km, Peak near Shackleton (SV1) / Chang'e-7 (planned) 0.88 km; Malapert Massif / Malapert peak (MP1) are 3.95 km apart. The map is about 1.7 km per px on a phone at zoom 1 and mapMaxZoom is 8, so these markers sit on top of each other at every zoom: _onTap (map_view.dart ~612) silently picks whichever is nearest, the one drawn last hides the other, and with names shown (_MapPainter, ~1191) the labels print on top of each other.`

const RESULT = {
  type: 'object',
  properties: {
    filesChanged: { type: 'array', items: { type: 'string' } },
    testsRun: { type: 'array', items: { type: 'object', properties: { command: { type: 'string' }, result: { type: 'string' } }, required: ['command', 'result'] } },
    notes: { type: 'string', description: 'decisions and user-visible texts added (quote them)' },
    screenshots: { type: 'array', items: { type: 'string' } },
    openIssues: { type: 'array', items: { type: 'string' } },
  },
  required: ['filesChanged', 'testsRun', 'notes', 'screenshots', 'openIssues'],
}
const FINDINGS = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, file: { type: 'string' }, line: { type: 'number' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] }, failure_scenario: { type: 'string' }, suggested_fix: { type: 'string' } }, required: ['title', 'file', 'line', 'severity', 'failure_scenario', 'suggested_fix'] } } }, required: ['findings'] }
const VERDICT = { type: 'object', properties: { refuted: { type: 'boolean' }, reproduced: { type: 'boolean' }, evidence: { type: 'string' }, fix: { type: 'string' } }, required: ['refuted', 'reproduced', 'evidence', 'fix'] }
const FIX_SCHEMA = { type: 'object', properties: { fixed: { type: 'array', items: { type: 'string' } }, notFixed: { type: 'array', items: { type: 'object', properties: { title: { type: 'string' }, why: { type: 'string' } }, required: ['title', 'why'] } }, testsRun: RESULT.properties.testsRun }, required: ['fixed', 'notFixed', 'testsRun'] }

phase('Build')
const build = await agent(`${COMMON}

YOUR BUDGET IS 170k. Fix it, keeping every marker at its true position:
(a) STACKED MARKERS: when more than one site marker lies within the tap's hit radius (24 px / scale), do not pick one silently: open a small chooser (a menu or bottom sheet anchored to the tap, in the app's style) listing each of those sites with its marker shape glyph (map_view's markerPath/markerShapeOf), its short name and its group, each row >= 48 dp with Semantics; choosing one selects it exactly as a marker tap does; dismissing selects nothing. A single marker in range keeps today's behaviour (no chooser).
(b) COUNT BADGE: where markers overlap on screen at the current zoom (closer than about the marker size), draw one small count badge (e.g. '2', IBM Plex Mono, neutral colours, not amber) beside the stack so a stack reads as more than one site; the per-site Semantics nodes (map_view ~700-720) must still list every site, and the map's semantics label should not claim one site where there are two.
(c) NAMES: with names shown, place labels without overlap: the selected site's label first, then the rest; try above, then below, right and left of the marker; if every spot collides, merge the stack's names into one label (e.g. 'IM-2 Athena (landed) +1') rather than overprint. Pure placement logic goes in a testable function (lib/core if it has no Flutter imports, else a top-level function in the widget file) with unit tests.
Tests (app/test/widget/, app/test/core/ as fits): a tap on the IM-2 pair opens the chooser with both names and selecting the second selects 'im-2-intended-target'; a tap on an isolated site (e.g. Haworth) selects it with no chooser; label rects do not overlap with names on at 390x844 and 1280x800 at zoom 1 and at max zoom; semantics lists all 19 sites; keyboard/screen-reader access to the chooser. Update any existing map tests that break (test/widget/map_*_test.dart, explore_*_test.dart). Screenshots: a throwaway flutter test under app/test/zz_tmp_map_shots/ that renders the Explore map with names on at 390x844 (zoom 1 and zoomed on the IM-2 pair) and the chooser open, saved as PNGs to ${SHOTS}/ (RepaintBoundary.toImage inside tester.runAsync; load the fonts like app/test/widget/light_test_fonts.dart); then delete that folder. Look at the PNGs yourself with the Read tool and fix what is wrong. Run cd ${REPO}/app && flutter analyze and your tests plus test/widget/map_*_test.dart and test/widget/explore_screen_test.dart in one call.`, { label: 'build: stacked markers, badge, names', phase: 'Build', schema: RESULT })

phase('Review')
const review = await agent(`${COMMON}

Read-only on tracked files (throwaway tests in ${REPO}/app/test/_rev_tmp_map/, deleted afterwards). YOUR BUDGET IS 110k. Review the uncommitted map change (git -C ${REPO} diff -- app/lib/widgets/map_view.dart and the files it touched; builder notes: ${JSON.stringify(build && build.notes || '').slice(0, 1500)}). Lens: correctness of hit-testing and the chooser at every zoom and in the full-screen map, custom spots and the unconfirmed pin near a stack, label placement (no overlap, no label off-screen, the selected label always shown), Semantics and keyboard, 48 dp, design tokens, performance of label placement per paint. Look at the PNGs in ${SHOTS}. Report only concrete problems with a trigger; at most 4; an empty list is fine.`, { label: 'review: map stacks', phase: 'Review', schema: FINDINGS })

phase('Verify')
const found = ((review && review.findings) || []).slice(0, 4)
const verified = await parallel(found.map((f, i) => () => agent(`${COMMON}

Read-only (throwaway tests in ${REPO}/app/test/_rev_tmp_mv${i}/, deleted afterwards). YOUR BUDGET IS 70k. A reviewer claims: ${f.title} at ${f.file}:${f.line} (${f.severity}). Scenario: ${f.failure_scenario}. Suggested fix: ${f.suggested_fix}. Try to REFUTE it from the real code; reproduce where feasible. Default to refuted=true without a concrete trigger. If real, give the smallest correct fix.`, { label: `verify: ${f.title}`.slice(0, 70), phase: 'Verify', schema: VERDICT }).then(v => ({ ...f, verdict: v }))))
const confirmed = verified.filter(Boolean).filter(f => f.verdict && !f.verdict.refuted)
log(`${confirmed.length} confirmed of ${verified.filter(Boolean).length}`)

phase('Fix')
const fix = confirmed.length ? await agent(`${COMMON}

YOUR BUDGET IS 120k. Apply these confirmed findings, smallest correct change each, with a test where it makes sense; regenerate the screenshots into ${SHOTS}/ with the suffix _r2 the same way (throwaway app/test/zz_tmp_map_shots/, deleted afterwards). Then run cd ${REPO}/app && flutter analyze and the test files you touched plus test/widget/map_*_test.dart in one call. Findings: ${JSON.stringify(confirmed.map(f => ({ title: f.title, file: f.file, line: f.line, fix: f.verdict.fix, evidence: String(f.verdict.evidence).slice(0, 1000) })), null, 1)}`, { label: `fix: ${confirmed.length} confirmed findings`, phase: 'Fix', schema: FIX_SCHEMA }) : null

return { build, review, confirmed, refuted: verified.filter(Boolean).filter(f => f.verdict && f.verdict.refuted).map(f => f.title), fix }
