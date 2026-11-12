# Pre-store release checklist

## Accounts
- [ ] Store accounts are opened by an account owner who meets Google's and Apple's age requirements:
      Google Play Console (one-time fee) and Apple Developer Program (yearly fee). They own the accounts; the
      app can list the developer as the author.

## Build
- [ ] Bump `version:` in `app/pubspec.yaml` (build number must rise for every upload).
- [ ] Android: upload key in `app/android/key.properties` ([release_signing.md](release_signing.md)),
      then `flutter build appbundle --release`; Play App Signing on.
- [ ] iOS: on the Mac, `bash tools/xcode_setup.sh`, set the team in Xcode (keep the team ID out of the
      repo: [xcode.md](xcode.md)), then Product > Archive (or `flutter build ipa`) and upload with Xcode
      or Transporter. `ITSAppUsesNonExemptEncryption` is already `false`.
- [ ] Application ID: still `org.spaceapps.polarhorizon.polar_horizon`. It cannot change after the
      first Play upload; rename it first if you want a new one.

## Betas
- [ ] Play **internal testing** track with a few testers, then closed testing (new personal accounts
      need a closed test with testers for 14 days before production).
- [ ] **TestFlight** internal testers, then external (needs a short beta review).

## Store forms
- [ ] Privacy policy URL: <https://localizedprojects.github.io/CLPS-MOON-BROWSER/privacy/>
- [ ] Content rating questionnaire (IARC): reference/education app, no violence, no user-generated
      content, no chat, no purchases: expect Everyone / 4+.
- [ ] Target audience: not designed for children under 13 (avoids the Families policy), or answer honestly.
- [ ] **Play Data safety:** no data collected, no data shared; no encryption-in-transit question
      applies (the Android app has no internet permission). Exported files are user-initiated
      shares, which are not "collection".
- [ ] **App Store privacy label:** Data Not Collected. No tracking (no App Tracking Transparency prompt).
- [ ] Ads: no. In-app purchases: no. Category: Education (or Reference).

## Listing assets
All the texts (with character counts), the form answers and the screenshot list are in
[store/listing.md](store/listing.md).
- [ ] Screenshots: phone (Play: at least 2; App Store: 6.9" and 6.5" iPhone, 13" iPad as the app supports iPad),
      plus 7" and 10" tablet for Play if offered on tablets. Order, captions and how they were made:
      [store/listing.md › Screenshots and graphics](store/listing.md#screenshots-and-graphics).
- [ ] Play feature graphic 1024x500, 512x512 icon; short and full description; credit NASA data sources:
      [store/listing.md › Google Play](store/listing.md#google-play) and
      [App Store](store/listing.md#app-store-app-store-connect).

## Testing status (before the first store upload)
- These notes were written at v1.1.0; re-check each line against the current release (1.14.0) before
  the first store upload.
- Planned end-to-end runs (record results here): Android emulator (Android 14, API 34) on normal
  and small screens, offline, rotation, backgrounding during Play; the same on the Mac's iOS simulators.
- Done: release App Bundle builds (debug-signed until the upload key exists).
- Done: Android 7.0 (API 24, 32-bit ARM emulator, stock WebView 51): a walkthrough of every screen
  on 1.9.2, whose 16 bugs were fixed in 1.9.3, and the Explore map integration test
  (`map_75s_test.dart`) passed. Up to 1.12.0, on WebView 51 the charts show the "update your WebView"
  message, as designed. Since 1.13.0 the charts are built for Chrome 51, and the same emulator draws
  the classic sky plot and timeline on Site › Sky & time (slowly: about 2 min on its software CPU). A
  release build of the 1.13.0 branch there (2026-11-03) also drew the Simple view, Compare and their full-screen
  pictures, and shared the sky + timeline PNGs in one share. A full-screen picture too short for its rows
  (Compare's simple view, or the When view's Heights panel, on a phone held sideways) is now made taller
  and fitted to the screen; that is checked in the browser, not yet on the emulator.
  1.11.0 on the same emulator (2026-11-01): it updated in place over 1.9.3 with the settings kept; the
  Lander's view heights, relief switch, full screen with site switching, landscape, the IM-1 and IM-2
  photo cards and Back navigation worked, with no app errors in logcat.
- Done (1.14.1, 2026-11-12): the known issue "Screen readers during Play on Android 7" (1.13.2 to
  1.14.0), on the same emulator with the 1.14.0 release APK (Malapert peak (MP1), Light & shadow).
  The positions from `adb shell uiautomator dump` were those of the layout with the bars shown, and
  the screen showed that layout during each dump: the emulator's screen recording
  (`adb emu screenrecord`) shows the bars come back while the dump runs and hide again after it,
  during Play and after pausing; once a scroll to the top had brought them back, a dump matched a
  screenshot. The cause:
  Flutter's Android bridge reports "accessible navigation" to the app as soon as any accessibility
  client reads a control (`createAccessibilityNodeInfo` in `AccessibilityBridge.java`), and the app
  shows the hidden bars to screen readers (`hide_on_scroll.dart`), so the screenshots taken between
  dumps (bars hidden) showed another layout. A diagnostic build that ignored accessible navigation
  (not kept) left the bars hidden during the dump, and its dumps then matched the screenshots, during
  Play and after pausing. Not a fault in the app; no app code changed. TalkBack is not on this
  emulator image, so no screen reader itself was run. Check positions against a recording made
  during the dump. `play_reader_semantics_test.dart` covers it.
- **Not tested:** Android 8 and 9, real iPhones and iPads, real low-end Android phones, Play
  pre-launch report (runs after the first upload: check it).

## 1.14.0 Whole Moon checks (before merging `global-1.14`)
The polar regression guard: South pole stays the default and must not change. `85c472f` is 1.13.5.
Record each result in the PR description.
- [ ] **G1, polar data byte-identical:** `git diff --exit-code 85c472f -- app/assets/data
      ':(exclude)app/assets/data/global' app/test/fixtures/spice_truth.json pipeline/validation
      ':(exclude)pipeline/validation/global' pylib/src` prints nothing.
- [ ] **G2, polar code untouched:** `git diff --exit-code 85c472f --` over the polar pipeline modules
      (`pipeline/lunarsp/{sites,horizon,dem,basemap,visibility,fixtures,validate,horizons,ephemeris,geometry,config,curated,appmodel,outio,spice_env,fetch,build}.py`,
      `site_catalog.json`), `app/lib/widgets/{map_view,light_map,light_snapshot,map_focus}.dart`,
      `app/lib/screens/intro.dart`,
      `app/lib/core/{shadow,horizon_compute,score,summary,ranking,eclipse,visibility,geo,ephemeris,timeseries,metrics,relief,curated}.dart`,
      `app/lib/state/light_engine*.dart` and `light_loop.dart`. Only the Lander work may touch
      `dem.dart`, `lander_view.dart` and `lander_light.dart`, and only additively.
- [ ] **G3, assertions only added:** `git diff 85c472f -- app/test charts/src pipeline/tests pylib/tests | grep -E '^-[^-]'`
      is empty, apart from version-string lines listed in the PR description.
- [ ] **G4, polar behaviour:** `flutter test test/state/polar_baseline_test.dart` matches
      `test/fixtures/polar_baseline_1135.json` exactly (rankings, scores and top pick per goal, the
      glance, position and STANDS OUT lines, URL parsing, default region and selection).
- [ ] **G5, no Whole Moon bytes at a polar start:** `flutter test test/widget/global_explore_test.dart`
      (no request under `assets/data/global/` at a polar cold start); on a web build in headless
      Chrome, loading `/` requests nothing under `assets/data/global/`.
- [ ] **G6, layouts:** the same screens at 360 × 800 and 1280 × 800, rendered at `85c472f` and at HEAD,
      differ only in the region switch row and the site picker's "Whole Moon" header (scratch goldens,
      not committed), plus these **declared polar-mode differences**, which are intended content (plan
      §2, WP3b) and are cropped from the comparison or recorded as accepted in the PR's G6 result:
      - **Learn**, the coverage card: the reworded scope text ("South pole (the default): …"), the Whole
        Moon paragraph and the "Open Whole Moon" button;
      - **Learn**, "What each view shows": the "Whole Moon: landing sites beyond the pole" card;
      - **Learn**, the glossary: the "Near side" and "Far side" entries;
      - **Learn**, Credits: the Whole Moon sources (the LROC site coordinates, the LOLA global
        elevation grids and the others listed there);
      - **How it's calculated**: the new opening sentence (`calcScope`) and the "The whole Moon" section;
      - **the first-run Explore guide** (an overlay, not in the goldens): one more step, "South pole or
        whole Moon", pointing at the region switch, so it reads "step 1 of 7"; a returning user sees that
        step once on its own.
      Everything else on these screens, Learn included, must match `85c472f` pixel for pixel. Not a
      difference: Learn's Lander key row "N | Face north (away from the pole)" follows the region of
      the site the Lander shows and reads exactly so in South-pole mode; only at a Whole Moon site
      does it read "Face north (toward the north pole)" (`learn_north_key_test.dart`).
- [ ] **G7, charts:** the polar figure JSON equals the 1.13.5 baseline (`npm test`; `charts/src/global.test.ts`).
- [ ] **G8, device:** on the Android 7 emulator a cold start gives South pole, with Shackleton rim
      selected until the ranking finishes and then the goal's top pick, as in 1.13.5; the
      light map, the Lander, Compare and Learn match 1.13.5; switching to Whole Moon and back leaves the
      polar selection, goal and shortlist unchanged.
- [ ] **Budget:** `app/assets/data/global/` is at most 12.5 MB (measured on 2026-11-12 for 1.14.1: 9,534,942 bytes
      in 48 files; `du -cb app/assets/data/global`), and `pytest tests/test_globe_map.py tests/test_globe_tiles.py`
      passes its per-file budgets.
- [ ] **Validation gates:** from `pipeline/` with the cache, `python -m lunarsp.globe validate` ends
      without "gate(s) failed", and every entry of `gates` in `app/assets/data/global/validation.json`
      has `"pass": true`. Re-running it only changes `generatedUtc`; restore the committed file if so.
- [ ] **References:** `python3 -I docs/make_references.py --check` passes (it reads
      `app/assets/data/global/sites.json` too).
- [ ] **Place names (1.14.1):** from `pipeline/`, `pytest tests/test_globe_sites.py -k place` passes (each
      Whole Moon place is in its quoted NASA sentence, on an allowed https host), and from `app/`,
      `flutter test test/widget/global_place_overview_test.dart` finds "lat, lon · place" on all 20 Overviews.
- [ ] **Docs:** `python tools/check_formula_refs.py` (formula.md §18) and `python tools/check_workflows.py`.
- [ ] **Version:** `app/pubspec.yaml` says `1.14.0+27`.

## Competition / sideload release (GitHub Releases APK)
For the Space Apps entry and anyone installing from the QR code. This APK is not a store build.
- [ ] Bump `version:` in `app/pubspec.yaml` (for example `1.14.0+27`; the build number must rise, or
      Android refuses to install the update over the earlier one). After the build, check that the
      version the app shows matches.
- [ ] From `app/`: `flutter build apk --release`. Without `app/android/key.properties` the release APK
      is signed with the debug key, `~/.android/debug.keystore`.
- [ ] **Keep that signing key.** The owner keeps `~/.android/debug.keystore` (back it up; never commit
      it). Every sideload release must be signed with the same key, so updates install over earlier
      ones; a build signed with another key must be uninstalled first.
- [ ] Rename `app/build/app/outputs/flutter-apk/app-release.apk` to `lunar-horizon.apk` and record its
      checksum: `sha256sum lunar-horizon.apk` (PowerShell: `Get-FileHash lunar-horizon.apk`).
- [ ] Publish a GitHub release (tag `v1.14.0` for 1.14.0, notes with the changes and the SHA-256), attach
      `lunar-horizon.apk` and `SHA256SUMS.txt`, and mark it **latest**. No v1.13.4 release was
      published; the notes cover the changes since the previous published release.
- [ ] Check that <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/latest/download/lunar-horizon.apk>
      downloads the new file (same SHA-256), then install it over the previous version on a phone.
- [ ] Check that the APK and demo video links on the Links line of `docs/judge_one_pager.md` and in
      `docs/submission.md` still work. v1.13.3 (7 November 2026) holds both videos, so keep it; the
      video links point at it and do not change when a newer release is published. Then put the new APK's
      SHA-256 in the source note of `docs/judge_one_pager.md`, and update the "latest release" notes
      in `docs/submission.md` (Links and Development history) and the comment in `README.md`.
- [ ] Scan the QR code (`docs/get-app-qr.png`): it must open
      <https://localizedprojects.github.io/CLPS-MOON-BROWSER/get/>, which sends Android to the APK and
      iPhone/iPad to the web app.
- [ ] Merge to `main` and check that the *Deploy web app* workflow (`deploy-pages.yml`) succeeded and
      <https://localizedprojects.github.io/CLPS-MOON-BROWSER/> shows the new version.
- [ ] Refresh the README screenshots (`docs/screenshots/`) if the screens changed.
- [ ] Re-check the numbers in [judge_one_pager.md](judge_one_pager.md) (its source notes say where each
      comes from).
