"""Repository hygiene: CI workflow pins (tools/check_workflows.py), tools/make_icons.py, and the
Xcode setup (tools/xcode_setup.sh, .github/workflows/ios.yml, app/ios)."""
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"


def test_workflows_pass_hygiene_check():
    r = subprocess.run([sys.executable, str(TOOLS / "check_workflows.py")], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_workflow_check_flags_node20_pins_and_cancelling_pages(tmp_path):
    sys.path.insert(0, str(TOOLS))
    try:
        import check_workflows
    finally:
        sys.path.remove(str(TOOLS))
    (tmp_path / "deploy.yml").write_text(
        "concurrency:\n  group: pages\n  cancel-in-progress: true\n"
        "jobs:\n  b:\n    steps:\n      - uses: actions/checkout@v4\n"
        "      - uses: actions/deploy-pages@v4\n",
        encoding="utf-8",
    )
    probs = check_workflows.check(tmp_path)
    assert any("checkout@v4" in p for p in probs)
    assert any("deploy-pages@v4" in p for p in probs)
    assert any("cancel-in-progress" in p for p in probs)


def _check_one(tmp_path, steps, concurrency="concurrency:\n  group: ci\n  cancel-in-progress: true\n"):
    sys.path.insert(0, str(TOOLS))
    try:
        import check_workflows
    finally:
        sys.path.remove(str(TOOLS))
    body = "".join(f"      - uses: {s}\n" for s in steps)
    (tmp_path / "ci.yml").write_text(concurrency + "jobs:\n  a:\n    steps:\n" + body, encoding="utf-8")
    return check_workflows.check(tmp_path)


def test_workflow_check_accepts_reviewed_major_pins(tmp_path):
    assert _check_one(tmp_path, ["actions/checkout@v7", "subosito/flutter-action@v2",
                                 "./.github/actions/local", "'actions/setup-node@v5'"]) == []


@pytest.mark.parametrize("ref, needle", [
    ("actions/checkout@" + "a" * 40, "commit SHA"),
    ("actions/checkout@main", "not a major tag"),
    ("actions/checkout@v5.0.0", "not a major tag"),
    ("actions/checkout", "no @ref"),
    ("actions/cache@v4", "not in the reviewed list"),
    ("actions/upload-artifact@v9", "not in the reviewed list"),
    ("someone/else-action@v3", "not in the reviewed list"),
    ("subosito/flutter-action@v1", "older than v2"),
])
def test_workflow_check_flags_unreviewed_or_uncheckable_refs(tmp_path, ref, needle):
    probs = _check_one(tmp_path, ["actions/checkout@v7", ref])
    assert len(probs) == 1 and needle in probs[0], probs
    assert probs[0].startswith("ci.yml:")


def test_workflow_check_requires_cancelling_concurrency_outside_pages(tmp_path):
    probs = _check_one(tmp_path, ["actions/checkout@v7"], concurrency="")
    assert any("cancel-in-progress: true" in p for p in probs), probs
    probs = _check_one(tmp_path, ["actions/checkout@v7"],
                       concurrency="concurrency:\n  group: ci\n  cancel-in-progress: false\n")
    assert any("cancel-in-progress: true" in p for p in probs), probs


def test_ci_workflow_cancels_superseded_runs():
    yaml = pytest.importorskip("yaml")
    ci = yaml.safe_load((ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8"))
    assert ci["concurrency"]["cancel-in-progress"] is True
    assert "github.ref" in ci["concurrency"]["group"]
    pages = yaml.safe_load((ROOT / ".github" / "workflows" / "deploy-pages.yml").read_text(encoding="utf-8"))
    assert pages["concurrency"]["cancel-in-progress"] is False


def test_make_icons_preview_creates_missing_dir(tmp_path):
    pytest.importorskip("PIL")
    out = tmp_path / "new" / "preview"
    r = subprocess.run([sys.executable, str(TOOLS / "make_icons.py"), "preview", str(out)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    for name in ("icon_preview.png", "maskable_preview.png", "favicon_zoom.png"):
        assert (out / name).stat().st_size > 0


SETUP = TOOLS / "xcode_setup.sh"
needs_bash = pytest.mark.skipif(shutil.which("bash") is None or os.name == "nt", reason="needs a POSIX bash")


@needs_bash
@pytest.mark.parametrize("script", sorted(TOOLS.glob("*.sh")), ids=lambda p: p.name)
def test_shell_tools_parse(script):
    r = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_shell_tools_are_executable_in_git():
    if shutil.which("git") is None:
        pytest.skip("no git")
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-s", "--", "tools/*.sh"], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        pytest.skip("not a git checkout")
    modes = {line.split("\t")[1]: line.split()[0] for line in r.stdout.splitlines()}
    assert "tools/xcode_setup.sh" in modes
    assert all(m == "100755" for m in modes.values()), modes


@needs_bash
def test_xcode_setup_options_and_refusal_off_macos():
    def run(*args):
        return subprocess.run(["bash", str(SETUP), *args], capture_output=True, text=True, cwd=ROOT)

    h = run("--help")
    assert h.returncode == 0 and "--no-open" in h.stdout and "set -u" not in h.stdout
    assert run("--bogus").returncode == 2
    if platform.system() == "Darwin":
        pytest.skip("the refusal is for other systems")
    r = run("--no-open")
    assert r.returncode == 1
    assert "needs macOS" in r.stdout and "Fix:" in r.stdout


def test_xcode_setup_flutter_version_matches_workflows():
    text = SETUP.read_text(encoding="utf-8")
    pin = re.search(r'^FLUTTER_PIN="([0-9.]+)"', text, re.M).group(1)
    want = re.search(r'^FLUTTER_WANT="([0-9.]+)"', text, re.M).group(1)
    assert pin.startswith(want + ".")
    for wf in ("ci.yml", "ios.yml"):
        found = re.findall(r"flutter-version:\s*([0-9.]+)", (ROOT / ".github" / "workflows" / wf).read_text(encoding="utf-8"))
        assert found and set(found) == {pin}, (wf, found, pin)


def test_ios_workflow_builds_like_xcode():
    text = (ROOT / ".github" / "workflows" / "ios.yml").read_text(encoding="utf-8")
    assert "bash tools/xcode_setup.sh --no-open" in text
    assert "-workspace app/ios/Runner.xcworkspace -scheme Runner" in text
    assert "CODE_SIGNING_ALLOWED=NO" in text
    assert "flutter build ios --release --no-codesign" in text
    # it runs on pull requests and by hand; the old xcode-ready branch has been in main since 1.11.3
    triggers = text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
    assert "  pull_request:" in triggers and "  workflow_dispatch:" in triggers
    assert "xcode-ready" not in text and "  push:" not in triggers
    # every step that builds or runs on the simulator has its own timeout, and so does the job
    assert text.count("timeout-minutes:") >= 5


def test_ios_project_holds_no_signing_identity():
    """A signing team, certificate or profile chosen on someone's Mac never goes into git."""
    pbx = (ROOT / "app" / "ios" / "Runner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
    assert "DEVELOPMENT_TEAM" not in pbx
    assert "PROVISIONING_PROFILE" not in pbx
    assert not list((ROOT / "app" / "ios").rglob("*.mobileprovision"))
    assert not list((ROOT / "app" / "ios").rglob("*.p12"))
    # the plugins come in through Swift Package Manager, set up on each Mac by tools/xcode_setup.sh
    assert "FlutterGeneratedPluginSwiftPackage" in pbx
    assert not (ROOT / "app" / "ios" / "Podfile").exists()
    ignored = (ROOT / "app" / "ios" / ".gitignore").read_text(encoding="utf-8")
    for entry in ("Flutter/Generated.xcconfig", "Flutter/ephemeral/", "Flutter/flutter_export_environment.sh"):
        assert entry in ignored


def test_xcode_setup_avoids_bash4_only_forms():
    """macOS runs the script with bash 3.2: with set -u it calls an empty "$@" unbound."""
    text = SETUP.read_text(encoding="utf-8")
    assert 'in "$@"' not in text and '"${@' not in text
    for bash4 in ("declare -A", "mapfile", "readarray", ",,}", "^^}", "|&", "&>>"):
        assert bash4 not in text, bash4


_STUBS = {
    "uname": "echo Darwin",
    "xcode-select": "echo /Applications/Xcode.app/Contents/Developer",
    "xcodebuild": 'case "$1" in -version) printf "Xcode 16.4\\nBuild version 16F6\\n" ;; esac',
    "xcrun": '[ "$2 $3" = "list runtimes" ] && echo "iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5"; exit 0',
    "open": 'echo "OPEN $*"',
    "flutter": "\n".join([
        'echo "$*" >> "$STUB_LOG"',
        'case "$1" in',
        '  --version) echo "Flutter 3.44.6 • channel stable" ;;',
        '  config) printf "All Settings:\\n  enable-swift-package-manager: (Not set)\\n" ;;',
        '  build) p=ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage; mkdir -p "$p"',
        '         echo x > ios/Flutter/Generated.xcconfig; echo webview_flutter_wkwebview > "$p/Package.swift" ;;',
        'esac',
    ]),
}


@needs_bash
def test_xcode_setup_runs_through_with_stubbed_mac_tools(tmp_path):
    """The whole script, with no options (as a person runs it), against stand-ins for Xcode and Flutter."""
    repo = tmp_path / "a clone"  # a space in the path, as in ~/Documents/My Projects
    (repo / "tools").mkdir(parents=True)
    (repo / "app" / "ios" / "Flutter").mkdir(parents=True)
    shutil.copy(SETUP, repo / "tools" / SETUP.name)
    shutil.copy(ROOT / "app" / "pubspec.yaml", repo / "app" / "pubspec.yaml")
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    for name, body in _STUBS.items():
        (stubs / name).write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8")
        (stubs / name).chmod(0o755)
    log = tmp_path / "flutter.log"
    env = {k: v for k, v in os.environ.items() if k not in ("CI", "FLUTTER_SWIFT_PACKAGE_MANAGER", "CDPATH")}
    env.update(PATH=str(stubs) + os.pathsep + env.get("PATH", ""), STUB_LOG=str(log), HOME=str(tmp_path))

    def run(**extra):
        return subprocess.run(["bash", str(repo / "tools" / SETUP.name)], capture_output=True, text=True,
                              cwd=tmp_path, env={**env, **extra})

    r = run()
    assert r.returncode == 0, r.stdout + r.stderr
    assert "DONE." in r.stdout and "OPEN" not in r.stdout  # not a terminal: Xcode is not opened
    assert f'git -C "{repo}" update-index --skip-worktree' in r.stdout
    calls = log.read_text(encoding="utf-8").splitlines()
    assert "pub get" in calls and "build ios --config-only --no-codesign" in calls

    off = run(FLUTTER_SWIFT_PACKAGE_MANAGER="FALSE")  # Flutter reads anything but "true" as off
    assert off.returncode == 1 and "FAILED" in off.stdout and "FLUTTER_SWIFT_PACKAGE_MANAGER" in off.stdout
