# Handoff: the lander's view (paused 2026-10-29)

**Delete this whole `.handoff/` folder before opening the 1.9.0 PR.** It is a work cache on the
branch `claude/explore-repo-data-v6c8he`, not part of the app.

## Where things stand

- Released: **1.8.0** is merged to `main` (PR #28): fixes 1-5 of the challenge brief, three
  mission sites (19 in all), stacked map markers. Its APK was sent in the session.
- On this branch, not released: the **lander's view**, a 3D view of what you see from the
  lander 2 m above the selected site at the time on the time bar.
  - Spec: `docs/landers_view_spec.md`; section 14 lists the review findings still to fix.
  - Core (pure Dart): `app/lib/core/lander_view.dart`, plus `app/lib/state/lander_light.dart`.
    It also changes `app/lib/core/shadow.dart`, but only in structure: the results stay
    bit-identical.
  - Light-engine change: a light frame for terrain out to 300 km (`app/lib/state/light_engine.dart`).
  - UI: `app/lib/widgets/lander_view.dart`, plus a third segment ("Lander") in the Light tab's
    view switch (`app/lib/widgets/light_map.dart`). It is also described in
    `content/guides.dart` and `content/how_calculated.dart`.
  - Tests:
    - `app/test/core/lander_view_test.dart` (14);
    - `app/test/state/lander_light_test.dart` (8);
    - `app/test/widget/lander_view_test.dart` (15);
    - `flutter analyze` is clean.
  - Terrain heights come from the shadow engine's own 400 m grid; light comes pixel for pixel
    from the Light tab's computed frames. The user chose this.
- Review: three reviews (geometry, UI, performance) found 11 issues.
  - 6 are confirmed by a skeptic who reproduced them on real data.
  - 5 are not yet verified (1 medium, 4 low).
  - All 11 are in `landers_view/findings.json`, with scenarios, evidence and the verified fixes.

## Continue directly

The remaining steps are encoded in the workflow `landers_view/continue_wf.js`:
1. Verify the 5 open findings.
2. Fix the confirmed ones, one agent per area (geometry, performance, UI).
3. Regenerate the screenshots, including phone landscape.
4. Do a visual check against the 2D map, with up to 2 fix rounds.

Every agent is briefed to stay under the 250k-token cap, with strict reading rules.

1. In a fresh container: `bash .handoff/setup.sh`. It installs the packages, the Python tools,
   the kernels and DEMs, and the software emulator.
2. Run the workflow with
   `args = {repo: <repo root>, scratch: <a scratch dir>, venv: <repo>/.venv,
   branch: "claude/explore-repo-data-v6c8he", sha: <HEAD>, version: "1.8.0"}`.
   In the same container as before, the old run can also be resumed with
   `resumeFromRunId: "wf_990e8245-126"` (script: `landers_view/workflow_full.js`).
3. Then, by hand:
   - Run the full suites: `flutter analyze` and `flutter test` in `app/`, `npm test` in
     `charts/`, `python -m pytest` in `pipeline/` and in `pylib/`.
   - Refresh the pylib golden provenance, because `shadow.dart` changed. See
     `pylib/docs/parity.md` "Regenerating the goldens"; the values should come out identical.
   - Update the README test counts.
   - Bump `app/pubspec.yaml` to `1.9.0+11`.
   - Delete `.handoff/`.
   - Open the PR, merge it once CI is green, build the release APK
     (`flutter build apk --release`), and send it.
4. Emulator test:
   - Boot `lh30` as `setup.sh` prints, with nothing else running.
   - `adb install -r` the APK.
   - Run `flutter test integration_test/map_75s_test.dart -d emulator-5554` from `app/`,
     plus a lander's-view smoke test; take screenshots with `adb exec-out screencap -p`.
   - Software mode boots in about 17 min. On 2026-10-29 Android's system server died
     while agents were also running, so run the emulator alone.

## Contents

- `landers_view/continue_wf.js`: the continuation workflow, with the findings built in.
- `landers_view/workflow_full.js`: the whole workflow as it last ran (split core and UI
  parts, split fixes).
- `landers_view/findings.json`: the 11 review findings, with status, evidence and fixes.
- `landers_view/agent_results/journal.jsonl`: every agent's returned result (designs, spec
  summary, build notes, reviews, verdicts).
- `landers_view/screenshots/`: the lander's view and its 2D map partner at four moments,
  before the review fixes.
- `map_stacks_workflow.js`: the map stacked-markers workflow (done, merged in 1.8.0).
- `setup.sh`: rebuilds the environment.

## Notes

- On 360 dp phones the Light tab's two switches now take two rows, because 3+3 segments at
  48 dp do not fit on one. Phones 390 dp and wider keep one row.
- The lander segment's screen-reader label hard-codes "2 m up". It should follow the
  observer height (2 m / 10 m). Fix this with the UI findings.
