# Pre-store release checklist

## Accounts
- [ ] Store accounts are opened by a **parent or guardian** (the developer is under 18): Google Play
      Console (one-time fee) and Apple Developer Program (yearly fee). They own the accounts; the
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
- These notes were written at v1.1.0; re-check each line against the current release (1.13.1) before
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
- **Not tested:** Android 8 and 9, real iPhones and iPads, real low-end Android phones, Play
  pre-launch report (runs after the first upload: check it).

## Competition / sideload release (GitHub Releases APK)
For the Space Apps entry and anyone installing from the QR code. This APK is not a store build.
- [ ] Bump `version:` in `app/pubspec.yaml` (for example `1.13.1+22`; the build number must rise, or
      Android refuses to install the update over the earlier one). After the build, check that the
      version the app shows matches.
- [ ] From `app/`: `flutter build apk --release`. Without `app/android/key.properties` the release APK
      is signed with the debug key, `~/.android/debug.keystore`.
- [ ] **Keep that signing key.** The owner keeps `~/.android/debug.keystore` (back it up; never commit
      it). Every sideload release must be signed with the same key, so updates install over earlier
      ones; a build signed with another key must be uninstalled first.
- [ ] Rename `app/build/app/outputs/flutter-apk/app-release.apk` to `lunar-horizon.apk` and record its
      checksum: `sha256sum lunar-horizon.apk` (PowerShell: `Get-FileHash lunar-horizon.apk`).
- [ ] Publish a GitHub release (tag `v1.13.1`, notes with the changes and the SHA-256), attach
      `lunar-horizon.apk`, and mark it **latest**.
- [ ] Check that <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/latest/download/lunar-horizon.apk>
      downloads the new file (same SHA-256), then install it over the previous version on a phone.
- [ ] Only then add the APK link to the Links line of `docs/judge_one_pager.md` (see the TODO there):
      until this release exists, that link serves v1.2.0, so it stays out of the judges' brief.
- [ ] Scan the QR code (`docs/get-app-qr.png`): it must open
      <https://localizedprojects.github.io/CLPS-MOON-BROWSER/get/>, which sends Android to the APK and
      iPhone/iPad to the web app.
- [ ] Merge to `main` and check that the *Deploy web app* workflow (`deploy-pages.yml`) succeeded and
      <https://localizedprojects.github.io/CLPS-MOON-BROWSER/> shows the new version.
- [ ] Refresh the README screenshots (`docs/screenshots/`) if the screens changed.
- [ ] Re-check the numbers in [judge_one_pager.md](judge_one_pager.md) (its source notes say where each
      comes from) and add the demo video link to [submission.md](submission.md) once it is uploaded.
