# Android release signing

Google Play needs every upload signed with your own **upload key**. The build reads it from
`app/android/key.properties`; without that file, release builds are signed with the debug key
(fine for local testing, refused by Play).

## 1. Create the upload key (once)

Run this outside the repository, for example in your user folder. `keytool` ships with the JDK
(Android Studio has one under `jbr/bin`):

```
keytool -genkey -v -keystore %USERPROFILE%\lunar-horizon-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a password and your name; pick a strong password and remember it.

## 2. Create `app/android/key.properties`

```
storePassword=<the password you chose>
keyPassword=<the same password, unless you set a separate one>
keyAlias=upload
storeFile=C:/Users/<you>/lunar-horizon-upload.jks
```

`storeFile` may be absolute (as above) or relative to `app/android/app/`. Then
`flutter build appbundle --release` signs `build/app/outputs/bundle/release/app-release.aab`
with the upload key.

## 3. Keep them safe

- **Never commit** `key.properties`, `*.jks` or `*.keystore`. They are git-ignored in
  `app/android/.gitignore`; check `git status` before every commit anyway (this repository is public).
- **Back up** the `.jks` file and its password somewhere private (a password manager plus an offline copy).

## 4. Play App Signing

When you create the app in the Play Console, keep **Play App Signing** on (the default). Google then
holds the key that signs what users install, and your key is only the upload key: if you lose it,
the Play Console can reset it, so losing it does not lock you out of updates.

## 5. Switching keys breaks updates for sideloaded installs

Android only installs an update signed with the same key as the installed copy. The GitHub release
APK has been signed with the debug key, a locally built release APK is signed with your upload key once
`key.properties` exists, and Play installs are signed with Google's app signing key. So anyone moving
between these (GitHub APK to Play, or GitHub APK to a new-key APK) gets `INSTALL_FAILED_UPDATE_INCOMPATIBLE`
("App not installed") and must **uninstall the old copy first** (the app keeps only the goal and the
hidden-time-controls setting, so nothing important is lost).

Without `key.properties`, Gradle now prints a warning on every release build and **refuses
`bundleRelease`**, so a debug-signed App Bundle can never be produced by mistake.

**Decision to make once:** which key signs the GitHub APK from now on. Keep the debug key (no change
for existing sideloaded users, but it can never match Play), or switch to the upload key (one-time
uninstall for existing users; later GitHub APKs then update each other). Either way, a Play install and
a GitHub APK will not update each other.
