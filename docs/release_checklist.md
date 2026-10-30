# Pre-store release checklist

## Accounts
- [ ] Store accounts are opened by a **parent or guardian** (the developer is under 18): Google Play
      Console (one-time fee) and Apple Developer Program (yearly fee). They own the accounts; the
      app can list the developer as the author.

## Build
- [ ] Bump `version:` in `app/pubspec.yaml` (build number must rise for every upload).
- [ ] Android: upload key in `app/android/key.properties` ([release_signing.md](release_signing.md)),
      then `flutter build appbundle --release`; Play App Signing on.
- [ ] iOS: on the Mac, set the team in Xcode (keep the team ID out of the repo), `flutter build ipa`,
      upload with Xcode or Transporter. `ITSAppUsesNonExemptEncryption` is already `false`.
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
- [ ] Screenshots: phone (Play: at least 2; App Store: 6.9" and 6.5" iPhone, 13" iPad as the app supports iPad),
      plus 7" and 10" tablet for Play if offered on tablets.
- [ ] Play feature graphic 1024x500, 512x512 icon; short and full description; credit NASA data sources.

## Testing status (before the first store upload)
- These notes were written at v1.1.0; re-check each line against the current release (1.9.1) before
  the first store upload.
- Planned end-to-end runs (record results here): Android emulator (Android 14, API 34) on normal
  and small screens, offline, rotation, backgrounding during Play; the same on the Mac's iOS simulators.
- Done: release App Bundle builds (debug-signed until the upload key exists).
- **Not tested:** Android 7 to 9 (only the API 34 system image is installed), real iPhones and iPads,
  real low-end Android phones, Play pre-launch report (runs after the first upload: check it).

## Competition / sideload release (GitHub Releases APK)
For the Space Apps entry and anyone installing from the QR code. This APK is not a store build.
- [ ] Bump `version:` in `app/pubspec.yaml` (for example `1.9.1+12`; the build number must rise, or
      Android refuses to install the update over the earlier one). After the build, check that the
      version the app shows matches.
- [ ] From `app/`: `flutter build apk --release`. Without `app/android/key.properties` the release APK
      is signed with the debug key, `~/.android/debug.keystore`.
- [ ] **Keep that signing key.** The owner keeps `~/.android/debug.keystore` (back it up; never commit
      it). Every sideload release must be signed with the same key, so updates install over earlier
      ones; a build signed with another key must be uninstalled first.
- [ ] Rename `app/build/app/outputs/flutter-apk/app-release.apk` to `lunar-horizon.apk` and record its
      checksum: `sha256sum lunar-horizon.apk` (PowerShell: `Get-FileHash lunar-horizon.apk`).
- [ ] Publish a GitHub release (tag `v1.9.1`, notes with the changes and the SHA-256), attach
      `lunar-horizon.apk`, and mark it **latest**.
- [ ] Check that <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/latest/download/lunar-horizon.apk>
      downloads the new file (same SHA-256), then install it over the previous version on a phone.
- [ ] Scan the QR code (`docs/get-app-qr.png`): it must open
      <https://localizedprojects.github.io/CLPS-MOON-BROWSER/get/>, which sends Android to the APK and
      iPhone/iPad to the web app.
- [ ] Merge to `main` and check that the *Deploy web app* workflow (`deploy-pages.yml`) succeeded and
      <https://localizedprojects.github.io/CLPS-MOON-BROWSER/> shows the new version.
- [ ] Refresh the README screenshots (`docs/screenshots/`) if the screens changed.
- [ ] Re-check the numbers in [judge_one_pager.md](judge_one_pager.md) (its source notes say where each
      comes from) and add the demo video link to [submission.md](submission.md) once it is uploaded.
