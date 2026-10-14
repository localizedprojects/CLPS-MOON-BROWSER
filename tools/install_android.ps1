<#
.SYNOPSIS
  Build the Lunar Horizon release APK, find a connected Android device, install the APK and open the app.

.DESCRIPTION
  1. Builds app/build/app/outputs/flutter-apk/app-release.apk (flutter build apk --release), unless -SkipBuild.
  2. Scans for Android devices over USB (or wireless debugging) with adb. Emulators are skipped unless
     -IncludeEmulator. If none is ready it waits up to -WaitSeconds, and says what to do on the device
     (USB debugging, "Allow" prompt, file-transfer mode).
  3. Installs the APK on every ready device (or only -Serial), retrying once if the USB link drops,
     then wakes the screen and opens the app.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\install_android.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\install_android.ps1 -SkipBuild -Serial <serial from adb devices>
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\install_android.ps1 -DartDefine PH_OPENINGS_PREVIEW=true
#>
param(
  [switch]$SkipBuild,                 # install the APK that is already built
  [string]$Serial = '',               # install on this device only (see 'adb devices')
  [switch]$IncludeEmulator,           # also install on running emulators
  [int]$WaitSeconds = 120,            # how long to wait for a device
  [switch]$Reinstall,                 # uninstall first (ERASES the app's data on the device); only for a signature mismatch
  [string]$Package = 'org.spaceapps.polarhorizon.polar_horizon',
  [string[]]$DartDefine = @()        # extra build settings, e.g. -DartDefine PH_OPENINGS_PREVIEW=true
)

# 'Continue': Windows PowerShell 5.1 turns a native tool's stderr into errors, which 'Stop' would make fatal
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repo 'app'
$apk = Join-Path $appDir 'build\app\outputs\flutter-apk\app-release.apk'

function Say([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Host "   $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "FAILED: $m" -ForegroundColor Red; exit 1 }

# ---- adb ----
function Find-Adb {
  $cands = @()
  foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    if ($root) { $cands += (Join-Path $root 'platform-tools\adb.exe') }
  }
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  $onPath = Get-Command adb -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  return $null
}
$adb = Find-Adb
if (-not $adb) { Fail 'adb not found. Install the Android SDK platform-tools, or set ANDROID_HOME.' }

# ---- 1. build ----
if ($SkipBuild) {
  Say 'Skipping the build'
} else {
  Say 'Building the release APK (a few minutes)'
  Push-Location $appDir
  try {
    $defs = @($DartDefine | ForEach-Object { "--dart-define=$_" })
    & flutter build apk --release @defs
    if ($LASTEXITCODE -ne 0) { Fail 'flutter build apk failed (see the output above).' }
  } finally { Pop-Location }
}
if (-not (Test-Path $apk)) { Fail "No APK at $apk. Run without -SkipBuild." }
$apkInfo = Get-Item $apk
Write-Host ("   {0}  ({1:N1} MB, built {2})" -f $apk, ($apkInfo.Length / 1MB), $apkInfo.LastWriteTime)

# ---- 2. find devices ----
# returns @{ ready = serials ready to use; other = 'serial state' lines (unauthorized, offline) }
function Get-Devices {
  & $adb start-server *> $null
  $lines = & $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' }
  $ready = @(); $other = @()
  foreach ($l in $lines) {
    $parts = $l -split '\s+'
    $s = $parts[0]; $state = $parts[1]
    if (-not $IncludeEmulator -and $s -like 'emulator-*') { continue }
    if ($Serial -and $s -ne $Serial) { continue }
    if ($state -eq 'device') { $ready += $s } else { $other += "$s ($state)" }
  }
  return @{ ready = $ready; other = $other }
}

Say 'Looking for an Android device'
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$hinted = $false
while ($true) {
  $d = Get-Devices
  if ($d.ready.Count -gt 0) { break }
  if (-not $hinted) {
    Warn 'No device ready yet. On the phone or tablet:'
    Warn '  - Settings > About > tap "Build number" 7 times (Developer options)'
    Warn '  - Developer options > USB debugging: on'
    Warn '  - plug in a data USB cable; choose "File transfer" if asked'
    Warn '  - tap "Allow" on the "Allow USB debugging?" prompt (tick "Always allow")'
    Warn "Waiting up to $WaitSeconds s..."
    $hinted = $true
  }
  foreach ($o in $d.other) { Warn "found ${o}: unlock the device and accept the USB debugging prompt" }
  if ((Get-Date) -gt $deadline) { Fail 'No Android device found. Connect one and run the script again (add -SkipBuild to reuse this APK).' }
  Start-Sleep -Seconds 3
}

# ---- 3. install and open ----
$ok = @(); $bad = @()
foreach ($s in $d.ready) {
  $model = (& $adb -s $s shell getprop ro.product.model 2>$null | Out-String).Trim()
  $android = (& $adb -s $s shell getprop ro.build.version.release 2>$null | Out-String).Trim()
  Say "Installing on $model (Android $android, $s)"
  if ($Reinstall) {
    Warn 'Uninstalling first (-Reinstall): the app''s data on this device is erased'
    & $adb -s $s uninstall $Package | Out-Null
  }
  $installed = $false
  for ($try = 1; $try -le 2 -and -not $installed; $try++) {
    $out = (& $adb -s $s install -r $apk 2>&1 | Out-String)
    if ($out -match 'Success') { $installed = $true; break }
    if ($out -match 'INSTALL_FAILED_VERIFICATION_FAILURE|INSTALL_FAILED_USER_RESTRICTED|INSTALL_FAILED_ABORTED') {
      Warn 'The device blocked the install over USB. On the device (Developer options):'
      Warn '  - turn on "Install via USB" (OnePlus/OPPO/realme/Xiaomi; may ask you to sign in)'
      Warn '  - if it still fails, turn off "Verify apps over USB" / "Disable permission monitoring"'
      Warn '  - accept the "Allow installation?" prompt on the screen within a few seconds'
      Warn 'Then run the script again with -SkipBuild.'
      break
    }
    if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
      Warn 'The installed copy was signed with a different key. Run again with -Reinstall (erases its data).'
      break
    }
    if ($try -eq 1) {
      Warn "Install failed ($($out.Trim())); waiting for the device to reconnect and retrying once"
      & $adb -s $s wait-for-device
    } else { Warn $out.Trim() }
  }
  if (-not $installed) { $bad += "$model ($s)"; continue }
  & $adb -s $s shell input keyevent KEYCODE_WAKEUP | Out-Null
  & $adb -s $s shell monkey -p $Package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
  Write-Host "   installed and opened (unlock the screen if it is locked)" -ForegroundColor Green
  $ok += "$model ($s)"
}

Say 'Done'
if ($ok.Count) { Write-Host ("   installed: " + ($ok -join ', ')) -ForegroundColor Green }
if ($bad.Count) { Write-Host ("   not installed: " + ($bad -join ', ')) -ForegroundColor Red; exit 1 }
