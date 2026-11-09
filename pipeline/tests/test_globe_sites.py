"""Whole Moon catalogue and validation report (lunarsp.globe_sites, globe_shapefile,
globe_validate): catalogue rules on the committed ``global/sites.json`` (plan §7 WP1,
contract §2), the shapefile quotes, the great-circle helpers, the ``validation.json``
contract keys and gates (contract §4, plan §10), and the cached JPL Horizons responses
for the global sites. Tests that need the shapefile ZIP or the SPICE kernels skip when
those are absent."""

from __future__ import annotations

import json
import re
from functools import lru_cache

import numpy as np
import pytest

from lunarsp import globe_shapefile as gs
from lunarsp import globe_sites as gsites
from lunarsp import globe_validate as gv
from lunarsp.config import REPO_ROOT, WEB_DATA_DIR
from lunarsp.geometry import enu_basis
from lunarsp.horizons import Query
from tests._support import record_max, requires_kernels

GLOBAL_SITES = WEB_DATA_DIR / "global" / "sites.json"
POLAR_SITES = WEB_DATA_DIR / "sites.json"
VALIDATION = WEB_DATA_DIR / "global" / "validation.json"
GROUP_ORDER = ["apollo", "robotic", "international", "commercial"]
EXPECTED_SITES = {
    "apollo-11-lm", "apollo-12-lm", "apollo-14-lm", "apollo-15-lm", "apollo-16-lm", "apollo-17-lm",
    "luna-16", "luna-17-lunokhod-1", "luna-21-lunokhod-2", "luna-24", "surveyor-1", "surveyor-3",
    "surveyor-7", "change-3", "change-4", "change-5", "change-6", "slim", "chandrayaan-3-vikram",
    "blue-ghost-1",
}
requires_shapefile = pytest.mark.skipif(not gs.zip_path().exists(),
                                        reason="LROC anthropogenic-objects shapefile not in the cache")


@lru_cache(maxsize=None)
def _json(path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _global() -> dict:
    return _json(GLOBAL_SITES)


def _sites() -> list[dict]:
    return _global()["sites"]


# --------------------------------------------------------------------------- catalogue rules

def test_all_twenty_sites_present_and_match_the_catalogue():
    ids = [s["id"] for s in _sites()]
    assert set(ids) == EXPECTED_SITES
    assert len(ids) == len(EXPECTED_SITES) == 20
    assert ids == [s["id"] for s in gs.load_catalog()["sites"]]
    assert _global()["region"] == "wholeMoon"
    tiers = {s["tier"] for s in _sites()}
    assert tiers <= {"core", "extended"}


def test_every_site_has_a_quoted_source():
    for s in _sites():
        assert s["sources"], s["id"]
        for src in s["sources"]:
            assert src.get("title"), s["id"]
            assert re.match(r"https://\S+$", src.get("url", "")), (s["id"], src.get("url"))
            assert len(src.get("says", "").strip()) >= 20, s["id"]
    cs = _global()["coordinateSource"]
    assert cs["url"].startswith("https://") and cs["says"] and cs["licence"]


def test_confidence_and_latitude_band():
    for s in _sites():
        assert s["confidence"] in {"high", "medium-high"}, s["id"]
        assert -80.01 < s["lat"] <= 80.0, s["id"]
        assert -180.0 <= s["lon"] < 180.0, s["id"]
    assert gsites.GLOBAL_LAT_MIN == -80.01 and gsites.GLOBAL_LAT_MAX == 80.0


def test_ids_unique_across_polar_and_global_catalogues():
    polar_files = (POLAR_SITES, gs.CATALOG.with_name("site_catalog.json"))
    global_files = (GLOBAL_SITES, gs.CATALOG)
    polar, glob = set(), set()
    for f in polar_files + global_files:
        ids = [s["id"] for s in _json(f)["sites"]]
        assert len(ids) == len(set(ids)), f"duplicate id in {f.name}"
        (polar if f in polar_files else glob).update(ids)
    assert polar and glob
    assert not polar & glob, f"ids in both regions: {sorted(polar & glob)}"
    assert gv.CROSS_REGION_SITE in polar


def test_side_follows_the_flat_earth_share():
    for s in _sites():
        assert 0.0 <= s["earthFlatPct"] <= 100.0, s["id"]
        assert s["side"] == gsites.side_of(s["earthFlatPct"]), s["id"]
    assert gsites.side_of(100.0) == "near" and gsites.side_of(0.0) == "far"
    assert gsites.side_of(50.0) == "limb" and gsites.side_of(99.99) == "limb" and gsites.side_of(0.01) == "limb"
    by_id = {s["id"]: s for s in _sites()}
    assert by_id["apollo-11-lm"]["side"] == "near"
    for sid in gv.FAR_SIDE_SITES:
        assert by_id[sid]["side"] == "far"


def test_groups_listed_in_order_and_used():
    groups = _global()["groups"]
    assert [g["id"] for g in groups] == GROUP_ORDER
    for g in groups:
        assert g["name"] and g["note"]
    ids = {g["id"] for g in groups}
    for s in _sites():
        assert s["group"] in ids, s["id"]


def test_long_term_numbers_and_masks_are_consistent():
    hz = _json(WEB_DATA_DIR / "global" / "horizons.json")
    by_id = {s["id"]: s for s in _sites()}
    for s in _sites():
        assert 0.0 <= s["longTermBothPct"] <= min(s["longTermSunlitPct"], s["longTermEarthPct"]) + 1e-9, s["id"]
        assert s["horizonMeanDeg"] <= s["horizonMaxDeg"], s["id"]
        assert s["nearField"]["source"], s["id"]
    assert set(hz["masks"]) == EXPECTED_SITES
    n_az = int(round(360.0 / hz["azStepDeg"]))
    for sid, m in hz["masks"].items():
        assert set(m) == {f"{h:g}" for h in hz["heightsM"]}, sid
        assert all(len(v) == n_az for v in m.values()), sid
        assert max(m["2"]) / 100.0 == pytest.approx(by_id[sid]["horizonMaxDeg"], abs=0.006), sid


@requires_shapefile
def test_sources_quote_the_shapefile_record():
    records, sha = gs.read_records()
    assert len(records) == 71
    assert sha == _global()["coordinateSource"]["sha256"]
    rec_by_site = gs.site_coordinates(records=records)
    assert set(rec_by_site) == EXPECTED_SITES
    for s in _sites():
        rec = rec_by_site[s["id"]]
        assert s["sources"][0]["says"] == gs.says(rec), s["id"]
        assert s["sources"][0]["url"] == gs.LANDING_PAGE
        assert s["lat"] == round(float(rec["LATITUDE"]), 6), s["id"]
        lon = ((float(rec["LONGITUDE"]) + 180.0) % 360.0) - 180.0
        assert s["lon"] == round(lon, 6), s["id"]


# --------------------------------------------------------------------------- coordinate frame note (plan §10 V1)

_FRAME_NOTE_FIGURES = re.compile(r"up to about (\d+) m \(mean about (\d+) m\) over 2000-2040")
_KERNEL_IAU_VS_ME = re.compile(r"amplitude of approximately ([\d.]+) degrees, which is equivalent to approximately "
                               r"(\d+) m, .*? average value is approximately ([\d.]+) degrees, or (\d+) m")


def _doc_paragraph(path, marker: str) -> str:
    paras = [p for p in path.read_text(encoding="utf-8").split("\n\n") if marker in p]
    assert len(paras) == 1, (path.name, marker)
    return paras[0]


def test_frame_note_says_what_the_shapefile_frame_is():
    """V1: "IAU Moon 2000" is only the shapefile's spherical datum (its .PRJ has a sphere and a prime
    meridian, no rotation model); the coordinates are tied to lunar laser ranging in the Mean Earth
    frame, so MOON_ME applies them as given. No unsourced IAU-vs-ME offset (the old "below about
    100 m" was wrong: the frames kernel gives up to about 155 m) and no "not corrected" wording."""
    note = gsites.FRAME_NOTE
    for bad in ("100 m", "not corrected", "difference from IAU-frame"):
        assert bad not in note, bad
    for want in ("spherical datum", "R = 1737.4 km", "no rotation model", "laser ranging", "Mean Earth",
                 "MOON_ME as given", "moon_de440_250416.tf"):
        assert want in note, want
    assert _FRAME_NOTE_FIGURES.search(note)
    assert _global()["coordinateFrameNote"] == note
    assert _json(VALIDATION)["frameNote"] == note
    for path, marker in ((REPO_ROOT / "formula.md", '"Anthropogenic Features on the Moon" shapefile'),
                         (REPO_ROOT / "docs" / "global_data_contract.md", "| `coordinateFrameNote` |")):
        text = _doc_paragraph(path, marker)
        assert "100 m" not in text and "not corrected" not in text, path.name
        for want in ("spherical datum", "Mean Earth", "laser ranging", "MOON_ME"):
            assert want in text, (path.name, want)


@requires_shapefile
def test_shapefile_frame_is_a_sphere_and_the_reflectors_cite_de430():
    """The facts the note rests on: the .PRJ defines only a sphere of 1737400 m and a prime meridian,
    and the five laser-ranging rows (the Apollo 11, 14, 15 and Lunokhod 1, 2 retroreflectors) cite the
    DE430 lunar coordinates document."""
    import zipfile
    with zipfile.ZipFile(gs.zip_path()) as z:
        prj = z.read(gs.DBF_NAME.replace(".DBF", ".PRJ")).decode("ascii")
    assert re.search(r'SPHEROID\["[^"]*",1737400(\.0)?,0(\.0)?\]', prj)
    assert 'PRIMEM["Reference_Meridian",0.0]' in prj
    assert "PROJECTION" not in prj and "TOWGS84" not in prj
    records, _ = gs.read_records()
    lrrr = [r for r in records if str(r.get("COORD_SRC", "")).strip() == "Laser Ranging"]
    assert {r["OBJECT_ID"] for r in lrrr} == {"A11_LRRR", "A14_LRRR", "A15_LRRR", "Lunokhod1", "Lunokhod2"}
    assert all("de430_moon_coord.pdf" in str(r.get("REFERENCES", "")) for r in lrrr)


@requires_kernels
def test_frame_note_figures_are_the_frames_kernel_ones():
    """The IAU_MOON vs DE440 ME figures the note quotes are the ones moon_de440_250416.tf states, and
    SPICE reproduces them over 2000-2040 (peak about 155 m, mean about 72 m on the 1737.4 km sphere)."""
    import spiceypy as sp
    from lunarsp import spice_env
    from lunarsp.config import KERNELS
    spice_env.load()
    peak_m, mean_m = (int(x) for x in _FRAME_NOTE_FIGURES.search(gsites.FRAME_NOTE).groups())
    k = _KERNEL_IAU_VS_ME.search(" ".join(KERNELS["moon_fk"].dest.read_text(encoding="latin-1").split()))
    assert k and (int(k[2]), int(k[4])) == (peak_m, mean_m)
    ets = np.linspace(spice_env.utc_to_et("2000-01-01T00:00:00"), spice_env.utc_to_et("2040-01-01T00:00:00"), 20000)
    ang = np.array([sp.raxisa(sp.pxform("IAU_MOON", "MOON_ME", float(et)))[1] for et in ets])
    assert float(ang.max()) * 1737.4e3 == pytest.approx(peak_m, abs=3.0)
    assert float(ang.mean()) * 1737.4e3 == pytest.approx(mean_m, abs=3.0)


# --------------------------------------------------------------------------- great-circle helpers

def _sep_m(lat1, lon1, lat2, lon2) -> float:
    a, b = (np.array(enu_basis(la, lo)[2]) for la, lo in ((lat1, lon1), (lat2, lon2)))
    return float(np.arctan2(np.linalg.norm(np.cross(a, b)), a @ b) * 1737.4e3)


@pytest.mark.parametrize("lat,lon", [(0.0, 0.0), (0.67416, 23.47314), (-45.4, 177.6), (44.1, -19.5),
                                     (-69.37, 32.32), (79.9, 179.99)])
@pytest.mark.parametrize("az", [0.0, 37.0, 90.0, 181.5, 270.0, 333.0])
def test_offset_latlon_round_trip(lat, lon, az):
    for d in (5.0, 80.0, 20_000.0, 300_000.0):
        la, lo = gsites.offset_latlon(lat, lon, az, d)
        assert -180.0 - 1e-9 <= lo <= 180.0 + 1e-9
        got_m = np.radians(gsites.great_circle_deg(lat, lon, la, lo)) * 1737.4e3
        assert got_m == pytest.approx(d, rel=1e-6, abs=1e-3)
        # Going back along the reverse direction (az + 180 deg at the far end) returns home.
        e, n, u = enu_basis(lat, lon)
        th, a = d / 1737.4e3, np.radians(az)
        tangent = -np.sin(th) * u + np.cos(th) * (np.cos(a) * n + np.sin(a) * e)  # direction of travel at the end
        e2, n2, _ = enu_basis(la, lo)
        back = np.degrees(np.arctan2(-tangent @ e2, -tangent @ n2))
        la2, lo2 = gsites.offset_latlon(la, lo, back, d)
        assert _sep_m(lat, lon, la2, lo2) < 1e-3  # (arccos in great_circle_deg cannot resolve < ~30 m)


def test_offset_latlon_cardinal_directions():
    la, lo = gsites.offset_latlon(10.0, 20.0, 0.0, 1737.4e3 * np.radians(1.0))
    assert (la, lo) == pytest.approx((11.0, 20.0), abs=1e-9)
    la, lo = gsites.offset_latlon(0.0, 179.5, 90.0, 1737.4e3 * np.radians(1.0))
    assert (la, lo) == pytest.approx((0.0, -179.5), abs=1e-9)  # wraps at the 180 deg seam
    assert gsites.great_circle_deg(0.0, 179.9, 0.0, -179.9) == pytest.approx(0.2, abs=1e-9)


class _Plane:
    """A tilted plane in the local tangent frame at (lat0, lon0): height = gx * east + gy * north."""

    def __init__(self, lat0, lon0, gx, gy):
        self.e, self.n, self.u = enu_basis(lat0, lon0)
        self.gx, self.gy = gx, gy

    def height_latlon(self, lat, lon):
        la, lo = np.radians(np.asarray(lat, float)), np.radians(np.asarray(lon, float))
        v = np.stack([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)], axis=-1) * 1737.4e3
        return self.gx * (v @ self.e) + self.gy * (v @ self.n)


@pytest.mark.parametrize("lat,lon", [(0.5, 23.0), (-45.0, 177.0), (60.0, -179.99)])
@pytest.mark.parametrize("gx,gy", [(0.0, 0.0), (np.tan(np.radians(5.0)), 0.0), (0.0, -0.2), (0.1, 0.05)])
def test_local_slope_on_a_synthetic_plane(lat, lon, gx, gy):
    got = gsites.local_slope_deg_latlon(_Plane(lat, lon, gx, gy), lat, lon)
    assert got == pytest.approx(np.degrees(np.arctan(np.hypot(gx, gy))), abs=1e-4)


# --------------------------------------------------------------------------- validation.json (contract §4)

CONTRACT_KEYS = {"generatedUtc", "frameNote", "spiceTruth", "horizons", "horizonQuality", "longTerm",
                 "coordinates", "historicSun", "crossRegion", "gates"}
CONTRACT_GATES = {"V2.apollo15MaskMaxDeg", "V2.apollo11MaskMeanDeg", "V3.apollo11EarthPct", "V3.apollo11SunPct",
                  "V3.farSideEarthPct", "V4.surveyor3Apollo12M", "V4.heightVsLdem64M"}


def test_validation_has_every_contract_key():
    v = _json(VALIDATION)
    assert CONTRACT_KEYS <= set(v)
    assert re.match(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", v["generatedUtc"])
    assert v["frameNote"] == gsites.FRAME_NOTE
    for k in ("spiceTruth", "horizons", "horizonQuality", "longTerm", "coordinates", "crossRegion"):
        assert v[k]["description"], k
    st = v["spiceTruth"]
    assert len(st["sites"]) >= 8 and set(st["sites"]) <= EXPECTED_SITES
    assert any(s in st["sites"] for s in gv.FAR_SIDE_SITES) and "chandrayaan-3-vikram" in st["sites"]
    for b in ("sun", "earth"):
        assert {"n", "maxArcmin", "rmsArcmin", "p95Arcmin", "maxRangeRelErr"} <= set(st[b])
    hz = v["horizons"]
    assert {"horizonsSettings", "sun", "earth", "sites"} <= set(hz)
    assert len(hz["sites"]) >= 8 and set(hz["sites"]) <= EXPECTED_SITES
    hq = v["horizonQuality"]
    assert {"description", "sites", "onDevice", "ldem64Only", "sunriseMinPerDeg"} <= set(hq)
    assert set(hq["sites"]) == EXPECTED_SITES
    for sid, row in hq["sites"].items():
        assert {"maskMaxDeg", "maskMeanDeg", "vsLdem64Only", "vsOnDevice"} <= set(row), sid
        assert {"rmsDeg", "biasDeg", "maxAbsDeg"} <= set(row["vsOnDevice"]), sid
        assert {"rmsDeg", "biasDeg"} <= set(row["vsLdem64Only"]), sid
    assert {"n", "medianRmsDeg", "worstRmsDeg", "worstSiteId", "meanBiasDeg"} <= set(hq["onDevice"])
    assert hq["onDevice"]["worstSiteId"] in EXPECTED_SITES
    assert {"n", "medianRmsDeg", "worstRmsDeg", "meanBiasDeg"} <= set(hq["ldem64Only"])
    assert hq["sunriseMinPerDeg"]["equator"] > 0
    lt = v["longTerm"]
    assert {"earthPct", "sunPct"} <= set(lt["apollo11"])
    assert set(lt["farSide"]) == set(gv.FAR_SIDE_SITES)
    assert isinstance(lt["sideAgreesWithMap"], bool) and lt["sideAgreesWithMap"]
    assert {"nearSideSunEclipseMax", "farSideSunEclipseMax", "nearSiteId", "farSiteId"} <= set(lt["eclipse20281231"])
    co = v["coordinates"]
    assert co["shapefile"]["version"] == "2026-08-14" and co["shapefile"]["records"] == 71
    assert re.match(r"[0-9a-f]{64}$", co["shapefile"]["sha256"])
    assert set(co["sites"]) == EXPECTED_SITES
    for sid, row in co["sites"].items():
        assert row["inShapefile"] is True, sid
        assert {"shapefileName", "coordSrc", "uncertain", "candidateDiffDeg"} <= set(row), sid
    assert set(co["heightVsLdem64M"]) <= EXPECTED_SITES and co["heightVsLdem64M"]
    assert v["historicSun"]["status"] in {"not checked", "checked"}
    if v["historicSun"]["status"] == "checked":
        for row in v["historicSun"]["sites"].values():
            assert row["source"]["url"].startswith("https://") and row["source"]["says"]
    assert v["crossRegion"]["siteId"] == gv.CROSS_REGION_SITE
    assert {"rmsDeg", "biasDeg"} <= set(v["crossRegion"]["ldem64VsPolarMask"])


def test_validation_gates_all_pass():
    gates = _json(VALIDATION)["gates"]
    ids = [g["id"] for g in gates]
    assert len(ids) == len(set(ids))
    assert CONTRACT_GATES <= set(ids)
    for g in gates:
        assert {"id", "value", "range", "pass", "note"} <= set(g), g["id"]
        assert g["pass"] is True, g
        if g["range"] is not None:
            lo, hi = g["range"]
            assert lo is None or g["value"] >= lo, g
            assert hi is None or g["value"] <= hi, g
    by_id = {g["id"]: g for g in gates}
    assert by_id["V3.apollo11EarthPct"]["value"] == 100.0
    assert by_id["V3.farSideEarthPct"]["value"] == 0.0
    for k in ("V1b.horizonsMaxArcmin", "V1.appVsSpiceMaxArcmin", "V1b.appVsHorizonsMaxArcmin"):
        assert by_id[k]["value"] <= gv.TOL_ARCMIN, k
    assert by_id["V1b.horizonsMaxRangeKm"]["value"] <= gv.TOL_RANGE_KM


def test_gate_function_reproduces_the_committed_gates():
    v = _json(VALIDATION)
    rebuilt = gv.gates(v)
    assert [g["id"] for g in rebuilt] == [g["id"] for g in v["gates"]]
    assert all(g["pass"] for g in rebuilt)


# --------------------------------------------------------------------------- cached Horizons responses

def _cached() -> list:
    paths = sorted(gv.GLOBAL_HORIZONS_DIR.glob("*.json"))
    assert paths, "no cached global Horizons responses"
    return paths


def test_cached_horizons_files_are_well_formed():
    rows = {s["id"]: s for s in _sites()}
    seen = set()
    for p in _cached():
        rec = json.loads(p.read_text())
        sid, q = rec["siteId"], rec["query"]
        assert sid in rows, p.name
        assert q["body"] in {"sun", "earth"}
        assert p.name == f"{sid}_{q['body']}_{Query(**q).key()}.json"
        assert p == gv.cache_path(sid, Query(**q))
        assert q["lat"] == pytest.approx(rows[sid]["lat"], abs=1e-6)
        assert q["lon"] == pytest.approx(rows[sid]["lon"], abs=1e-6)
        assert -12.0 < q["alt_km"] < 12.0
        assert q["step"] == gv.HORIZONS_STEP and [q["start"], q["stop"]] in [list(w) for w in gv.HORIZONS_WINDOWS]
        assert len(rec["rows"]) == 181, p.name
        for r in rec["rows"][:3]:
            assert {"utc", "az", "el", "range_au"} <= set(r)
            assert 0.0 <= r["az"] < 360.0 and -90.0 <= r["el"] <= 90.0
        seen.add((sid, q["body"], q["start"]))
    sites = {s for s, _, _ in seen}
    assert len(sites) >= 8 and set(gv.HORIZONS_SITES) == sites
    assert len(seen) == len(_cached()) == len(gv.HORIZONS_SITES) * len(gv.HORIZONS_WINDOWS) * 2
    assert sites == set(_json(VALIDATION)["horizons"]["sites"])


@requires_shapefile
def test_cached_horizons_files_are_the_shapefile_queries():
    """With the shapefile, the cache holds exactly the queries `horizons_queries()` builds from it."""
    want = {p for p in (gv.cache_path(sid, q) for sid, q in gv.horizons_queries())}
    assert want == set(_cached())


@requires_kernels
def test_spice_and_app_match_horizons_at_global_sites():
    from lunarsp import spice_env
    spice_env.load()
    worst = {"sep": 0.0, "dRangeKm": 0.0, "appSep": 0.0}
    for p in _cached():
        c = gv.compare_horizons(json.loads(p.read_text()))
        for k in worst:
            worst[k] = max(worst[k], float(np.max(c[k])))
        assert np.max(c["sep"]) < gv.TOL_ARCMIN, p.name
        assert np.max(c["dRangeKm"]) < gv.TOL_RANGE_KM, p.name
        assert np.max(c["appSep"]) < gv.APP_TOL_ARCMIN, p.name
    record_max("global SPICE vs Horizons, max separation", worst["sep"])
    record_max("global SPICE vs Horizons, max range diff", worst["dRangeKm"], "km")
    record_max("global app vs Horizons, max separation", worst["appSep"])
