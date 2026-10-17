#!/bin/bash
# Build Lunar Horizon for iOS and install it on every connected iPhone/iPad (macOS only).
#
#   bash tools/install_ios.sh                  # pull, build (release), install + open on all connected devices
#   bash tools/install_ios.sh --device NAME    # only the device whose name or identifier contains NAME
#   bash tools/install_ios.sh --list           # list the connected devices and stop
#   bash tools/install_ios.sh --no-pull        # build the code as it is (skip git pull)
#   bash tools/install_ios.sh --no-build       # install the last build again
#
# Needs: Xcode, Flutter, and a signing team chosen once in Xcode (Runner target > Signing & Capabilities;
# a free Apple ID "Personal Team" works for your own devices, its apps run for 7 days). Keep the team out
# of git: `git update-index --skip-worktree app/ios/Runner.xcodeproj/project.pbxproj`.
#
# Code signing only works in a logged-in desktop session (the keychain is locked for SSH logins), so when
# started over SSH this script re-runs itself in the Mac's Terminal app and shows its log here.
# Written for macOS's bash 3.2.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/tools/install_ios.sh"
APP="$REPO/app"
LOG="${TMPDIR:-/tmp}/lunar-horizon-ios.log"
PULL=1 BUILD=1 LIST=0 PICK=""
for a in "$@"; do
  case "$a" in
    --no-pull) PULL=0 ;;
    --no-build) BUILD=0; PULL=0 ;;
    --list) LIST=1 ;;
    --device) PICK="__next__" ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) if [ "$PICK" = "__next__" ]; then PICK="$a"; else echo "unknown option: $a"; exit 2; fi ;;
  esac
done
[ "$PICK" = "__next__" ] && { echo "--device needs a name or identifier"; exit 2; }

say() { printf '== %s\n' "$*"; }
fail() { printf 'FAILED: %s\n' "$*"; exit 1; }
command -v xcrun >/dev/null || fail "Xcode is not installed (no xcrun)."
command -v flutter >/dev/null || export PATH="$HOME/development/flutter/bin:$PATH"
command -v flutter >/dev/null || fail "Flutter not found. Add it to PATH (e.g. export PATH=\"\$HOME/development/flutter/bin:\$PATH\" in ~/.zshrc)."

# connected physical iOS devices: "identifier<TAB>name" lines
devices() {
  local j="${TMPDIR:-/tmp}/lh-devices.json"
  xcrun devicectl list devices --json-output "$j" >/dev/null 2>&1 || return 0
  /usr/bin/python3 - "$j" "$PICK" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
pick = sys.argv[2].lower()
for d in data.get("result", {}).get("devices", []):
    hw, conn, props = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    if hw.get("platform") != "iOS" or hw.get("reality") != "physical":
        continue
    # connected now (cable or network), not just paired some time ago
    if conn.get("tunnelState") != "connected" and not conn.get("transportType"):
        continue
    name, ident = props.get("name", "?"), d.get("identifier", "")
    if pick and pick not in name.lower() and pick not in ident.lower():
        continue
    print(f"{ident}\t{name} ({hw.get('marketingName', hw.get('productType', ''))})")
PY
}

if [ "$LIST" = 1 ]; then
  say "Connected iPhones and iPads"
  devices | sed 's/^/   /'
  exit 0
fi

# over SSH: run in the desktop Terminal (signing needs the unlocked login keychain) and follow the log
if [ -n "${SSH_CONNECTION:-}" ] && [ -z "${LH_IN_TERMINAL:-}" ]; then
  : > "$LOG"
  args=""; for a in "$@"; do args="$args '$a'"; done
  osascript -e "tell application \"Terminal\" to do script \"LH_IN_TERMINAL=1 bash '$SCRIPT' $args 2>&1 | tee '$LOG'\"" >/dev/null \
    || fail "could not open Terminal (allow automation of Terminal in System Settings > Privacy & Security)."
  say "Running in the Mac's Terminal; following its log"
  i=0
  while ! grep -q -E '^(DONE|FAILED)' "$LOG" 2>/dev/null; do sleep 3; i=$((i + 1)); [ $i -gt 600 ] && fail "timed out after 30 min"; done
  grep -E '^(==|   |DONE|FAILED)' "$LOG"
  grep -q '^DONE' "$LOG"; exit $?
fi

cd "$APP" || fail "no app folder at $APP"
if [ "$PULL" = 1 ]; then
  say "Updating the code (git pull)"
  git -C "$REPO" pull --ff-only || fail "git pull failed (local changes? commit or stash them, or use --no-pull)."
fi
say "Code: $(git -C "$REPO" log --oneline -1 | cut -c1-70)"

LIST_OUT="$(devices)"
[ -n "$LIST_OUT" ] || fail "no iPhone or iPad connected${PICK:+ matching '$PICK'}. Plug one in with a cable, unlock it and tap Trust."

if [ "$BUILD" = 1 ]; then
  say "Building the iOS release (a few minutes)"
  flutter build ios --release 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" = 0 ] || fail "the build failed (see above). Signing errors: open app/ios/Runner.xcworkspace in Xcode and pick your team under Signing & Capabilities."
fi
APPDIR="$APP/build/ios/iphoneos/Runner.app"
[ -d "$APPDIR" ] || fail "no build at $APPDIR (run without --no-build)."
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APPDIR/Info.plist")"

ok=0
while IFS="$(printf '\t')" read -r ident name; do
  [ -n "$ident" ] || continue
  say "Installing on $name (keep it unlocked)"
  if xcrun devicectl device install app --device "$ident" "$APPDIR" >/dev/null 2>&1; then
    xcrun devicectl device process launch --device "$ident" "$BUNDLE" >/dev/null 2>&1 \
      && echo "   installed and opened" \
      || echo "   installed; open it on the device (first time: Settings > General > VPN & Device Management > trust the developer)"
    ok=$((ok + 1))
  else
    echo "   install failed: unlock the device, tap Trust, and check Developer Mode (Settings > Privacy & Security)"
  fi
done <<EOF
$LIST_OUT
EOF
[ $ok -gt 0 ] || fail "no device took the install"
echo "DONE ($ok device(s))"
