#!/bin/bash
# Get app/ios ready to open, run and archive in Xcode (macOS only).
#
#   bash tools/xcode_setup.sh            # check the tools, prepare app/ios, open the workspace in Xcode
#   bash tools/xcode_setup.sh --no-open  # the same, without opening Xcode (CI uses this)
#   bash tools/xcode_setup.sh --open     # open Xcode even when not started from a terminal
#
# It checks Xcode and Flutter, then runs `flutter pub get` and `flutter build ios --config-only
# --no-codesign` in app/. That writes the files Xcode needs and git does not hold, because they
# contain this Mac's paths: app/ios/Flutter/Generated.xcconfig and the Swift package that links the
# plugins (app/ios/Flutter/ephemeral/). It also applies any project update this Flutter wants.
# Nothing is signed; you choose your Team once in Xcode afterwards (steps: docs/xcode.md).
# Safe to run again at any time: after a git pull, after changing app/pubspec.yaml, after a Flutter
# upgrade, or whenever Xcode says "Generated.xcconfig not found". Written for macOS's bash 3.2.
set -u
unset CDPATH  # a CDPATH from the user's shell can make `cd` print, which would corrupt REPO below

# Flutter release line this project is built and tested with: keep it in step with
# `flutter-version` in .github/workflows/ci.yml and ios.yml (pipeline/tests/test_repo_hygiene.py checks).
FLUTTER_WANT="3.44"
FLUTTER_PIN="3.44.6"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/app"
WORKSPACE="$APP/ios/Runner.xcworkspace"
OPEN=auto
# A while loop over $#, not a for loop over $@: with set -u, macOS's bash 3.2 calls an empty $@
# unbound, so the script would stop when run without options.
while [ $# -gt 0 ]; do
  case "$1" in
    --open) OPEN=1 ;;
    --no-open) OPEN=0 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done
if [ "$OPEN" = auto ]; then
  if [ -t 1 ] && [ -z "${CI:-}" ]; then OPEN=1; else OPEN=0; fi
fi

say() { printf '== %s\n' "$*"; }
ok() { printf '   ok: %s\n' "$*"; }
warn() { printf '   WARNING: %s\n' "$*"; }
fail() {
  printf 'FAILED: %s\n' "$1"
  [ $# -gt 1 ] && printf '   Fix: %s\n' "$2"
  exit 1
}

[ "$(uname -s)" = Darwin ] || fail "this script needs macOS (Xcode only runs there)." \
  "run it on a Mac. On Windows or Linux, build Android or the web app instead (README.md)."
[ -d "$APP/ios" ] || fail "no iOS project at $APP/ios." "run the script from a clone of this repository."

# ---- Xcode -------------------------------------------------------------------------------------
say "Xcode"
XCODE_FIX="install Xcode from the App Store, open it once, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
DEV_DIR="$(xcode-select -p 2>/dev/null)" || fail "Xcode is not installed (xcode-select -p failed)." "$XCODE_FIX"
case "$DEV_DIR" in
  *CommandLineTools*) fail "the active developer folder is the Command Line Tools ($DEV_DIR), not Xcode." "$XCODE_FIX" ;;
esac
XCODE_OUT="$(xcodebuild -version 2>&1)" || {
  printf '%s\n' "$XCODE_OUT" | sed 's/^/   /'
  fail "xcodebuild does not run (see above)." \
    "accept the licence and install Xcode's components: sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch"
}
XCODE_VER="$(printf '%s\n' "$XCODE_OUT" | sed -n 's/^Xcode \([0-9][0-9.]*\).*/\1/p' | head -1)"
XCODE_MAJOR="${XCODE_VER%%.*}"
case "$XCODE_MAJOR" in ''|*[!0-9]*) XCODE_MAJOR=0 ;; esac
if [ "$XCODE_MAJOR" -lt 15 ]; then
  fail "Xcode ${XCODE_VER:-?} is too old: Flutter $FLUTTER_WANT needs Xcode 15 or newer." "update Xcode from the App Store."
fi
ok "Xcode $XCODE_VER ($DEV_DIR)"
[ "$XCODE_MAJOR" -lt 16 ] && warn "Flutter recommends Xcode 16 or newer, and App Store uploads need a current Xcode."
FIRST_LAUNCH_FIX="sudo xcodebuild -runFirstLaunch (or open Xcode once and click Install)."
# the same test as flutter doctor: simctl only runs once Xcode's additional components are installed
xcrun simctl list devices booted >/dev/null 2>&1 \
  || fail "Xcode still has to install its additional components (xcrun simctl does not run)." "$FIRST_LAUNCH_FIX"
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 \
  || warn "Xcode reports unfinished first-launch tasks; if the build fails, run: $FIRST_LAUNCH_FIX"
if xcrun simctl list runtimes 2>/dev/null | grep -q '^iOS'; then
  ok "iOS Simulator installed"
else
  warn "no iOS Simulator runtime (only needed to run on a simulator, not on an iPhone or iPad):" \
    "Xcode > Settings > Components > iOS, or: xcodebuild -downloadPlatform iOS"
fi

# ---- Flutter -----------------------------------------------------------------------------------
say "Flutter"
FLUTTER_FIX="install Flutter $FLUTTER_PIN: git clone -b $FLUTTER_PIN https://github.com/flutter/flutter.git \"\$HOME/development/flutter\", then add export PATH=\"\$HOME/development/flutter/bin:\$PATH\" to ~/.zshrc and open a new Terminal window."
for d in "$HOME/development/flutter/bin" "$HOME/flutter/bin"; do
  command -v flutter >/dev/null 2>&1 && break
  [ -x "$d/flutter" ] && export PATH="$d:$PATH"
done
command -v flutter >/dev/null 2>&1 || fail "Flutter is not on PATH." "$FLUTTER_FIX"
echo "   (the first run of a new Flutter downloads its Dart SDK and can take a few minutes)"
# stdout is kept to read the version and shown below; stderr (download progress, errors) goes straight to the terminal
FLUTTER_OUT="$(flutter --version)"
printf '%s\n' "$FLUTTER_OUT" | sed 's/^/   | /'
FLUTTER_VER="$(printf '%s\n' "$FLUTTER_OUT" | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -1)"
[ -n "$FLUTTER_VER" ] || fail "\`flutter --version\` did not run (see above; flutter is $(command -v flutter))." "$FLUTTER_FIX"
case "$FLUTTER_VER" in
  "$FLUTTER_WANT".*) ok "Flutter $FLUTTER_VER ($(command -v flutter))" ;;
  *) warn "Flutter $FLUTTER_VER: this project is built and tested with Flutter $FLUTTER_PIN. It may work;" \
       "if the build fails, switch with: git -C <your flutter folder> fetch --tags && git -C <your flutter folder> checkout $FLUTTER_PIN" ;;
esac

# The plugins are linked with Swift Package Manager (no CocoaPods, no Podfile). It is on by default
# in Flutter 3.44; it is off only if someone turned it off. Flutter reads the setting from
# app/pubspec.yaml, else from `flutter config`, else from FLUTTER_SWIFT_PACKAGE_MANAGER (where any
# value other than "true" means off).
SPM_FIX="flutter config --enable-swift-package-manager"
SPM_KEY='^[[:space:]]*enable-swift-package-manager:[[:space:]]*'
if grep -E -q "${SPM_KEY}false" "$APP/pubspec.yaml"; then
  fail "app/pubspec.yaml turns Swift Package Manager off." "remove enable-swift-package-manager: false from app/pubspec.yaml."
fi
if ! grep -E -q "${SPM_KEY}true" "$APP/pubspec.yaml"; then
  SPM_CFG="$(flutter config --list 2>/dev/null | sed -n 's/^[[:space:]]*enable-swift-package-manager:[[:space:]]*\([a-z]*\).*/\1/p' | head -1)"
  [ "$SPM_CFG" = false ] && fail "Swift Package Manager is turned off in your Flutter settings." "$SPM_FIX"
  if [ "$SPM_CFG" != true ] && [ -n "${FLUTTER_SWIFT_PACKAGE_MANAGER+x}" ]; then
    case "$(printf '%s' "$FLUTTER_SWIFT_PACKAGE_MANAGER" | tr '[:upper:]' '[:lower:]')" in
      true) ;;
      *) fail "FLUTTER_SWIFT_PACKAGE_MANAGER=$FLUTTER_SWIFT_PACKAGE_MANAGER turns Swift Package Manager off (Flutter takes only \"true\" as on)." \
           "unset FLUTTER_SWIFT_PACKAGE_MANAGER (and remove it from ~/.zshrc), or run: $SPM_FIX" ;;
    esac
  fi
fi
ok "Swift Package Manager on"

# ---- Prepare app/ios -----------------------------------------------------------------------------
cd "$APP" || fail "no app folder at $APP."
say "flutter pub get"
flutter pub get || fail "flutter pub get failed (see above)." \
  "check the internet connection, then run this script again."
say "flutter build ios --config-only --no-codesign (writes the Xcode configuration; no compile)"
flutter build ios --config-only --no-codesign \
  || fail "Flutter could not prepare the iOS project (see above)." \
     "run flutter doctor -v and fix what it lists under Xcode (its CocoaPods hint does not apply: this project does not use CocoaPods), then run this script again."

missing=""
for f in ios/Flutter/Generated.xcconfig ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift; do
  [ -f "$f" ] || missing="$missing app/$f"
done
[ -z "$missing" ] || fail "Flutter did not write:$missing." \
  "run flutter doctor -v, check Swift Package Manager ($SPM_FIX), then run this script again."
ok "app/ios/Flutter/Generated.xcconfig and the plugin Swift package are in place"
grep -q webview_flutter_wkwebview ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift \
  || warn "the plugin Swift package does not list webview_flutter_wkwebview: charts may not load." \
       "cd app && flutter clean, then run this script again."
[ -f ios/Podfile ] && warn "app/ios/Podfile exists: this project links its plugins with Swift Package Manager, not CocoaPods." \
  "Unless you added it on purpose, delete app/ios/Podfile, Podfile.lock and Pods/ and run this script again."

changed="$(git -C "$REPO" status --porcelain -- app/ios 2>/dev/null)"
if [ -n "$changed" ]; then
  echo "   These files in app/ios differ from git (your Team choice in Xcode, or a project update this"
  echo "   Flutter made; keep Flutter's updates, and keep the Team out of git: docs/xcode.md):"
  printf '%s\n' "$changed" | sed 's/^/     /'
fi

# ---- Open Xcode -------------------------------------------------------------------------------
if [ "$OPEN" = 1 ]; then
  say "Opening app/ios/Runner.xcworkspace in Xcode"
  # open it in the Xcode checked above (xcode-select), not whichever Xcode Finder prefers
  XCODE_APP="${DEV_DIR%/Contents/Developer}"
  case "$XCODE_APP" in
    *.app) open -a "$XCODE_APP" "$WORKSPACE" ;;
    *) open "$WORKSPACE" ;;
  esac || warn "could not open it; open $WORKSPACE in Xcode yourself."
fi

cat <<EOF

DONE. In Xcode (open app/ios/Runner.xcworkspace, not Runner.xcodeproj):
  1. Click Runner (blue icon, top of the left sidebar) > TARGETS Runner > Signing & Capabilities.
     Keep "Automatically manage signing" on and choose your Team (Add an Account... signs in with
     your Apple ID; a free Personal Team runs the app on your own devices for 7 days at a time).
  2. If Xcode says the bundle identifier is not available, change Bundle Identifier there to one
     of your own, for example com.yourname.lunarhorizon.
  3. Pick an iPhone or iPad simulator, or a connected device, in the bar at the top
     (a device needs Developer Mode: Settings > Privacy & Security > Developer Mode).
  4. Press Run (the triangle, or Cmd+R).
  5. For a release: choose "Any iOS Device (arm64)", then Product > Archive > Distribute App
     (TestFlight and the App Store need the paid Apple Developer Program).
Keep your Team out of git (once per clone):
  git -C "$REPO" update-index --skip-worktree app/ios/Runner.xcodeproj/project.pbxproj
Run this script again after every git pull. Help and troubleshooting: docs/xcode.md
EOF
