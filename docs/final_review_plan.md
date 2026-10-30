# Final deep review: plan

> **Status note (2026-10-30).** This plan is unchanged since 2026-10-10. The app has grown since
> (releases 1.1.0 to 1.9.1; see PLAN.md §4): the light & shadow map out to 75°S, lunar eclipses in the
> Sun fraction (`formula.md` §6.5), three more mission sites (IM-2's intended target, Chang'e-7, Chandrayaan-5/LUPEX), sunset and Earthset countdowns with live
> power, and the Lander's view (`docs/landers_view_spec.md`). A run of this plan must cover those
> too, in parts 3 to 6 and 10 to 12. No record of a complete run is kept in the repository.

The user asked for this on 2026-10-10. Once every step is done, run one complete
multi-agent workflow over the entire project, going deep into each part. This file
fixes its scope so nothing is skipped and every result can be traced.

## Shape

For every part below:

1. **Two independent deep readers**, each with a different lens (correctness and
   robustness for one, the user and judge view for the other). Each reads every file
   in the part and runs the part's own checks.
2. **Adversarial verification:** a skeptic per part tries to reproduce or refute each
   finding.
3. **Area fixers** with exclusive file ownership fix the confirmed high and medium
   findings and add a regression test for each.
4. **Re-check:** runtime re-runs on web and Android, plus a probe-test re-run for logic.
5. **Completeness critic:** asks what was not read, run or verified. Its answers become
   the next round. This loops until two rounds in a row find nothing new at high or
   medium severity.
6. **Judge panel:** NASA Space Apps-style scoring on impact, creativity, validity,
   relevance and presentation, from the README, demo script, one-pager and screenshots.

Every finding records its file:line or screenshot evidence, its repro, the verifier's
verdict and the fix commit.

## Parts and what "deep" means for each

| # | Part | Files | Deep checks |
|---|---|---|---|
| 1 | SPICE pipeline | `pipeline/lunarsp/{config,spice_env,geometry,ephemeris,horizons,validate,build,fetch,outio}.py`, `pipeline/lunarsp/site_catalog.json`, `pipeline/research/**` | Kernel set and frames match CLAUDE.md. `LT+S` everywhere. The Horizons cache was really produced from the stated query. `validate` tolerances are meaningful (the wrong-frame sensitivity proves this). DE442 cross-check. Every pytest passes and none is vacuous. |
| 2 | Terrain pipeline | `dem.py, horizon.py, visibility.py, sites.py, basemap.py, fixtures.py, appmodel.py`, the render modules `render_prep.py, render_post.py, render_overview_prep.py, render_overview_post.py` and `pipeline/blender/**` (skyline cross-check) | Projection orientation (Shackleton and Mons Mouton anchors). Ray-march distance schedule and near-field rule. The 16-strip fraction against the analytic segment. AVGVISIB comparison method. Basemap honesty (artificial light, ×2 heights). Fixtures regenerate bit-identically. |
| 3 | Committed data | `app/assets/data/**` | Manifest and file sizes. Encodings decode identically in Python and Dart. Year boundaries and span ends (2025-01-01 to 2036-01-01 exclusive). DSN masks. Regenerating them is deterministic. No orphaned files (`renders/` are not bundled). |
| 4 | Dart science core | `app/lib/core/**` | Line by line against `formula.md`. Property tests (az wrap, ±180°, pole, span ends, NaN). Interpolation error budget. Metrics and run edge cases (truncation). Score, ranking, scoreWhy arithmetic. Wording thresholds. Shadow sweep against the analytic cases and the agreement numbers. |
| 5 | State and engines | `app/lib/state/**` | Ranking slices and cancellation. Failure recovery. Cache keys cover every option. Light-engine lifecycle and the isolate on Android. Main-thread budget on web. Memory bounds. |
| 6 | Screens and widgets | `app/lib/screens/**, app/lib/widgets/**, theme.dart` | `docs/ux_review_rubric.md` at 320, 390, 800, 1280 and 1440 px and at 1× and 2× text. The click path in `docs/demo_script.md`. Every copy string checked for accuracy. FidelityBadges present. |
| 7 | Charts bundle | `charts/src/**`, `app/lib/widgets/chart_*` | Every plotted value traced to its payload field. The bridge schema matches on both sides. Message ordering (sequence numbers, pending replay). Min/max decimation. Alt text. PNG export once. Bundle size. |
| 8 | Web platform | `app/web/**`, build output | Hash routes and Back. iframe charts. Base href under GitHub Pages (a build with `--base-href /repo/` served from a subpath). PWA manifest and icons. First paint. Console clean. |
| 9 | Android platform | `app/android/**`, release APK | Install, launch, rotate, Back, WebView charts, the light-engine isolate, memory over 10 minutes, APK size, permissions (none needed), icon and label, logcat clean. |
| 10 | Accessibility | whole app | Flutter guideline matchers (tap target, labels, contrast) on every destination that can run in tests. TalkBack walk-through on the emulator. Keyboard-only walk-through on web. Reduced motion. |
| 11 | Performance | whole app | Startup to answer. Ranking time for 1-year and 11-year periods. Light-map frame time on web and Android. Playback rate. Payload sizes. Memory. |
| 12 | Docs | `README.md, formula.md, docs/*.md, CLAUDE.md, PLAN.md` | Every number, command, path and claim checked against the code and data. `formula.md` line references current. The demo script click path works. The one-pager is accurate. |
| 13 | Build, CI, deploy, hygiene | `.github/workflows/**`, `.gitignore`, licences | Clean-clone build (fresh clone outside OneDrive, follow the README). Workflow YAML is valid. Pinned versions. No secrets or large stray files. Credits and licences (OFL fonts, NASA data). `npm audit`: 0 issues in production dependencies as of 2026-10-10; review dev-only advisories. |

## Exit criteria

- Zero confirmed high or medium findings after the last round. Lows are fixed or listed
  with a reason.
- Every test suite passes (Flutter, vitest, pytest). Release web and APK builds succeed. A
  clean clone builds by following the README.
- The demo click path works on web and Android, and screenshots are refreshed in the
  README.
- The judge panel's top three improvements are either done or explicitly deferred.
