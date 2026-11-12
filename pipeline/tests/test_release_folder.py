"""release/ holds the sideload APK committed with the app (since 1.14.0).

The APK in release/ is built by hand, so a version bump in app/pubspec.yaml can leave it behind.
These tests read the version straight from the APK's compiled AndroidManifest.xml (standard
library only, no Android tools), check SHA256SUMS.txt and the release notes against it, and,
when the APK is older than the app, require docs/submission.md and docs/release_checklist.md
to say so."""
import hashlib
import re
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELEASE = ROOT / "release"
APK = RELEASE / "lunar-horizon.apk"
DOCS = (ROOT / "docs" / "submission.md", ROOT / "docs" / "release_checklist.md")


def _strings(buf, off):
    """The string pool chunk at `off` of a binary XML file."""
    _, hsize, _, count, _, flags, start, _ = struct.unpack_from("<HHIIIIII", buf, off)
    utf8 = bool(flags & 0x100)
    out = []
    for i in range(count):
        p = off + start + struct.unpack_from("<I", buf, off + hsize + 4 * i)[0]
        if utf8:
            p += 2 if buf[p] & 0x80 else 1  # length in characters
            n = buf[p]
            if n & 0x80:
                n, p = ((n & 0x7F) << 8) | buf[p + 1], p + 2
            else:
                p += 1
            out.append(buf[p:p + n].decode("utf-8"))
        else:
            n = struct.unpack_from("<H", buf, p)[0]
            if n & 0x8000:
                n, p = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p + 2)[0], p + 4
            else:
                p += 2
            out.append(buf[p:p + 2 * n].decode("utf-16-le"))
    return out


def apk_version(path):
    """(versionName, versionCode) from the <manifest> element of an APK."""
    with zipfile.ZipFile(path) as z:
        buf = z.read("AndroidManifest.xml")
    assert struct.unpack_from("<H", buf, 0)[0] == 0x0003, "not a binary XML manifest"
    off, strings = 8, []
    while off < len(buf):
        ctype, _, size = struct.unpack_from("<HHI", buf, off)
        if ctype == 0x0001:
            strings = _strings(buf, off)
        elif ctype == 0x0102:  # start element
            name, astart, asize, acount = struct.unpack_from("<IHHH", buf, off + 20)
            if strings[name] == "manifest":
                attrs = {}
                for i in range(acount):
                    a = off + 16 + astart + i * asize
                    _, aname, raw, _, _, dtype, data = struct.unpack_from("<IIIHBBI", buf, a)
                    attrs[strings[aname]] = strings[raw] if dtype == 0x03 else data
                return attrs["versionName"], attrs["versionCode"]
        off += size
    raise AssertionError("no <manifest> element")


def pubspec_version():
    line = next(l for l in (ROOT / "app" / "pubspec.yaml").read_text(encoding="utf-8").splitlines()
                if l.startswith("version:"))
    name, build = line.split(":", 1)[1].strip().split("+")
    return name, int(build)


def _flat(path):
    return " ".join(path.read_text(encoding="utf-8").split())


def test_release_apk_matches_its_checksum_and_notes():
    name, code = apk_version(APK)
    assert re.fullmatch(r"\d+\.\d+\.\d+", name) and code > 0, (name, code)
    sums = dict(reversed(l.split()) for l in (RELEASE / "SHA256SUMS.txt").read_text().splitlines() if l.strip())
    assert sums["lunar-horizon.apk"] == hashlib.sha256(APK.read_bytes()).hexdigest()
    assert (RELEASE / f"RELEASE_NOTES_v{name}.md").is_file(), name


def test_docs_say_when_the_release_apk_is_older_than_the_app():
    """1.14.1: the version bump left release/ at 1.14.0 (build 27) with nothing saying so."""
    name, code = apk_version(APK)
    app_name, app_build = pubspec_version()
    stale = re.compile(r"`release/` still holds the (\d+\.\d+\.\d+) \(build (\d+)\) APK and notes")
    for doc in DOCS:
        found = stale.findall(_flat(doc))
        if (name, code) == (app_name, app_build):
            assert not found, f"{doc.name}: release/ is up to date, remove {found}"
        else:
            assert code < app_build, (name, code, app_name, app_build)
            assert found == [(name, str(code))], (
                f"{doc.name} must say: `release/` still holds the {name} (build {code}) APK and notes")
