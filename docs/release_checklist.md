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

## Testing status (before v1.1.0 store upload)
- Planned end-to-end runs (record results here): Android emulator (Android 14, API 34) on normal
  and small screens, offline, rotation, backgrounding during Play; the same on the Mac's iOS simulators.
- Done: release App Bundle builds (debug-signed until the upload key exists).
- **Not tested:** Android 7 to 9 (only the API 34 system image is installed), real iPhones and iPads,
  real low-end Android phones, Play pre-launch report (runs after the first upload: check it).
