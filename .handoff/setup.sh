#!/usr/bin/env bash
# Rebuilds, in a fresh cloud container, everything the lander's-view work used that is
# not in git: Flutter and npm packages, the Python tools, the SPICE kernels and LOLA DEMs,
# and a software Android emulator. Run from the repository root:  bash .handoff/setup.sh
# Each step is skipped when its output is already there. About 6 GB and 20-40 min.
# Delete .handoff/ before opening the release PR (it never belongs on main).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH=/opt/flutter/bin:$PATH
export ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk} ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-/opt/android-sdk}
VENV=${VENV:-$ROOT/.venv}

echo "== Flutter packages"
(cd "$ROOT/app" && flutter pub get >/dev/null)

echo "== Chart bundle packages"
[ -d "$ROOT/charts/node_modules" ] || (cd "$ROOT/charts" && npm ci --no-audit --no-fund >/dev/null)

echo "== Python: pipeline deps (system python) and the pylib venv ($VENV)"
python3 -c "import spiceypy, numpy, scipy, PIL, requests, pytest" 2>/dev/null \
  || python3 -m pip install -q -r "$ROOT/pipeline/requirements.txt"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/python" -c "import lunarhorizon" 2>/dev/null || "$VENV/bin/pip" install -q -e "$ROOT/pylib[all]"

echo "== SPICE kernels and LOLA DEMs into \${LUNAR_SP_CACHE:-~/.cache/lunar-sp} (about 570 MB)"
(cd "$ROOT/pipeline" && python3 -m lunarsp.fetch)

echo "== Android emulator and an API 30 x86_64 image (about 4 GB)"
SDKM=$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager
[ -x "$ANDROID_HOME/emulator/emulator" ] && [ -d "$ANDROID_HOME/system-images/android-30/default/x86_64" ] \
  || (yes | "$SDKM" --install "emulator" "system-images;android-30;default;x86_64" >/dev/null)
if ! "$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | grep -qx lh30; then
  echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd -n lh30 \
    -k "system-images;android-30;default;x86_64" -d pixel_4 --force >/dev/null
  sed -i 's/^hw.ramSize=.*/hw.ramSize=2048/' "$HOME/.android/avd/lh30.avd/config.ini"
fi

cat <<'EOF'
== Done. To boot the emulator (no KVM here, so software mode; boot takes ~15-20 min,
   and only when nothing else is using the CPU, or Android's system server dies):
   nohup $ANDROID_HOME/emulator/emulator -avd lh30 -no-window -no-audio -no-boot-anim \
     -no-snapshot -accel off -gpu swiftshader_indirect -cores 4 -memory 2048 > emu.log 2>&1 &
   until [ "$(adb -s emulator-5554 shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 15; done
EOF
