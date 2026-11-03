# iPhone and iPad: open, run and archive in Xcode

One setup command, then a few clicks in Xcode. The iOS project is `app/ios`; its plugins (web views for
the charts, the share sheet, settings) come in through Swift Package Manager, so there is no CocoaPods
step and no `pod install` (if `flutter doctor` suggests installing CocoaPods, that does not apply here).

## What you need (once)

| | Version | Notes |
|---|---|---|
| Mac | a macOS that runs the Xcode below | Apple silicon or Intel |
| Xcode | 16 or newer (15 is the minimum for Flutter 3.44) | From the App Store. Open it once and let it install its components. For the simulator, also add the iOS platform: Xcode > Settings > Components (*Platforms* in Xcode 15). App Store uploads need a current Xcode. |
| Flutter | **3.44.6** (what CI uses) | `git clone -b 3.44.6 https://github.com/flutter/flutter.git ~/development/flutter`, then add `export PATH="$HOME/development/flutter/bin:$PATH"` to `~/.zshrc` and open a new Terminal window. |
| Apple ID | free or paid | Free (Personal Team): your own devices, 7 days per install. TestFlight and the App Store need the paid Apple Developer Program. |

## The one command

```bash
git clone https://github.com/localizedprojects/CLPS-MOON-BROWSER
cd CLPS-MOON-BROWSER
git checkout xcode-ready        # only until this branch is merged into main
bash tools/xcode_setup.sh
```

`tools/xcode_setup.sh` checks Xcode and Flutter (and says how to fix whatever is missing), runs
`flutter pub get` and `flutter build ios --config-only --no-codesign` in `app/`, and opens
`app/ios/Runner.xcworkspace` in Xcode (`--no-open` skips that). Those two Flutter steps write the files
that hold this Mac's paths and therefore are not in git: `app/ios/Flutter/Generated.xcconfig` and the
plugin package in `app/ios/Flutter/ephemeral/`. Run the script again after every `git pull`, after
changing `app/pubspec.yaml` (including the version number), and after a Flutter upgrade. Running it
twice does no harm.

## In Xcode

1. Open **`app/ios/Runner.xcworkspace`** (the script does this), not `Runner.xcodeproj`.
2. Click **Runner** at the top of the left sidebar, then **TARGETS > Runner > Signing & Capabilities**.
   Keep *Automatically manage signing* on and choose your **Team** (*Add an Account...* signs in with
   your Apple ID).
3. If Xcode says the bundle identifier `org.spaceapps.polarhorizon.polarHorizon` is not available,
   change **Bundle Identifier** on the same page to one of your own, for example
   `com.yourname.lunarhorizon`.
4. Pick a simulator or a connected iPhone or iPad in the bar at the top, and press **Run** (Cmd+R).
5. Release: pick **Any iOS Device (arm64)**, then **Product > Archive**, then **Distribute App** in the
   Organizer. The version and build number come from `version:` in `app/pubspec.yaml`
   (`1.11.2+18` becomes 1.11.2 (18)); run the setup script after changing it.

To install a release build on every connected device from the Terminal instead, use
`bash tools/install_ios.sh` (see the README).

## Keep your Team out of git

Choosing a Team writes its ID into `app/ios/Runner.xcodeproj/project.pbxproj`. Never commit it (nor
certificates or profiles). Tell git to leave your copy of that file alone:

```bash
git update-index --skip-worktree app/ios/Runner.xcodeproj/project.pbxproj
```

If a later `git pull` stops because that file changed upstream:

```bash
git update-index --no-skip-worktree app/ios/Runner.xcodeproj/project.pbxproj
git stash && git pull && git stash pop
git update-index --skip-worktree app/ios/Runner.xcodeproj/project.pbxproj
bash tools/xcode_setup.sh
```

## Troubleshooting

- **"Generated.xcconfig not found"** (or *could not find included file 'Generated.xcconfig'*, or
  *FLUTTER_ROOT is not set*): run `bash tools/xcode_setup.sh`. The file is made on each Mac and is not
  in git. Also needed after moving the folder or upgrading Flutter.
- **Swift package errors** (*Missing package product 'FlutterGeneratedPluginSwiftPackage'*, a package
  that does not resolve): quit Xcode, run the setup script, open the workspace again, then
  **File > Packages > Reset Package Caches**. If it persists: `cd app && flutter clean`, then the
  script again. There should be no `app/ios/Podfile`; if one appeared, delete it with `Podfile.lock`
  and `Pods/`, and check `flutter config --list` shows `enable-swift-package-manager` not `false`.
- **Signing errors:** *Signing for "Runner" requires a development team*: step 2 above. *Failed to
  register bundle identifier* or *not available*: step 3. *No profiles for ...* or *Communication with
  Apple failed*: connect the device with a cable, unlock it, tap Trust, and build once more so Xcode
  registers it. A free team can have 3 apps per device at a time. Product > Test also needs a Team on
  the **RunnerTests** target.
- **"Bad CPU type in executable"** on an Apple silicon Mac: install Rosetta once with
  `sudo softwareupdate --install-rosetta --agree-to-license`, then run the script again.
- **"Untrusted Developer"** on the device: Settings > General > VPN & Device Management > your Apple ID
  > Trust. If Xcode says the device is not ready, turn on Settings > Privacy & Security >
  **Developer Mode** (the device restarts).
- **The app closes when opened from the home screen** after a Run from Xcode: that was a Debug build,
  which runs only while Xcode or Flutter is attached. For a copy that stays, set Product > Scheme >
  Edit Scheme > Run > Build Configuration to **Release**, or use `tools/install_ios.sh`.
- **Simulator or device:** a simulator needs no Team and no signing; a device always does. Xcode's
  *iOS XX is not installed* means the simulator platform is missing (Xcode > Settings > Components,
  or `xcodebuild -downloadPlatform iOS`).
  Debug builds (Run) are much slower than Release, on a simulator and on a device; judge speed with a
  Release build.

## Checked on every change

`.github/workflows/ios.yml` repeats these steps on a macOS runner (no signing, no secrets): the setup
script, the same Xcode build as Run with a simulator, `flutter build ios --release --no-codesign`, and
one integration test on an iPhone simulator. It runs on pushes to `xcode-ready`, on pull requests that
touch `app/ios`, `app/pubspec.*` or the script, and by hand from the Actions tab.
