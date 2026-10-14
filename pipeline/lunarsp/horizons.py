"""JPL Horizons oracle for validation.

Queries the Horizons API for *airless apparent* azimuth/elevation (quantity
4) and range (20) of the Sun (10) and Earth (399) seen from a topocentric
site on the Moon (``coord@301``, geodetic, 1737.4 km sphere, MEAN_ME frame).
Responses are cached as JSON under ``pipeline/validation/horizons_cache`` so
the test-suite runs offline and deterministically.
"""

from __future__ import annotations

import hashlib
import json
import time
from dataclasses import asdict, dataclass

import requests

from .config import HORIZONS_CACHE_DIR
from .outio import write_json

API = "https://ssd.jpl.nasa.gov/api/horizons.api"
TARGETS = {"sun": "10", "earth": "399"}


@dataclass(frozen=True)
class Query:
    body: str  # "sun" | "earth"
    lat: float
    lon: float  # east
    alt_km: float
    start: str  # "YYYY-MM-DD HH:MM" UT
    stop: str
    step: str  # e.g. "4 h"

    def params(self) -> dict[str, str]:
        return {
            "format": "json",
            "COMMAND": f"'{TARGETS[self.body]}'",
            "OBJ_DATA": "'NO'",
            "MAKE_EPHEM": "'YES'",
            "EPHEM_TYPE": "'OBSERVER'",
            "CENTER": "'coord@301'",
            "COORD_TYPE": "'GEODETIC'",
            "SITE_COORD": f"'{self.lon:.6f},{self.lat:.6f},{self.alt_km:.6f}'",
            "START_TIME": f"'{self.start}'",
            "STOP_TIME": f"'{self.stop}'",
            "STEP_SIZE": f"'{self.step}'",
            "QUANTITIES": "'4,20'",
            "ANG_FORMAT": "'DEG'",
            "EXTRA_PREC": "'YES'",
            "CSV_FORMAT": "'YES'",
            "APPARENT": "'AIRLESS'",
            "TIME_TYPE": "'UT'",
            "TIME_DIGITS": "'SECONDS'",
        }

    def key(self) -> str:
        return hashlib.sha1(json.dumps(asdict(self), sort_keys=True).encode()).hexdigest()[:16]


MONTHS = {m: i + 1 for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}


def parse_result(text: str) -> list[dict]:
    """Parse the CSV block between $$SOE and $$EOE."""
    body = text.split("$$SOE", 1)[1].split("$$EOE", 1)[0]
    rows = []
    for line in body.strip().splitlines():
        parts = [p.strip() for p in line.split(",")]
        date = parts[0]  # e.g. 2026-Jan-01 00:00:00
        y, mon, rest = date.split("-", 2)
        d, hms = rest.split(" ")
        iso = f"{int(y):04d}-{MONTHS[mon]:02d}-{int(d):02d}T{hms}"
        rows.append({
            "utc": iso,
            "az": float(parts[3]),
            "el": float(parts[4]),
            "range_au": float(parts[5]),
        })
    return rows


def fetch(q: Query, refresh: bool = False, pause_s: float = 1.0) -> dict:
    """Return cached Horizons rows for a query, fetching if needed."""
    HORIZONS_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = HORIZONS_CACHE_DIR / f"{q.body}_{q.key()}.json"
    if path.exists() and not refresh:
        return json.loads(path.read_text())
    for attempt in range(5):
        try:
            r = requests.get(API, params=q.params(), timeout=120)
            r.raise_for_status()
            payload = r.json()
            break
        except (requests.RequestException, ValueError):
            time.sleep(5 * (attempt + 1))
    else:
        raise RuntimeError(f"Horizons query failed: {q}")
    result = payload["result"]
    header = result.split("$$SOE", 1)[0]
    rec = {
        "query": asdict(q),
        "horizons_version": payload.get("signature", {}).get("version"),
        "center_frame": next((ln.split(":", 1)[1].strip() for ln in header.splitlines() if ln.startswith("Center pole/equ")), None),
        "ephemeris_source": next((ln.split("{source:", 1)[1].rstrip("} ").strip() for ln in header.splitlines() if ln.startswith("Target body name")), None),
        "fetched_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "rows": parse_result(result),
    }
    write_json(path, rec, indent=1)
    time.sleep(pause_s)
    return rec


# ---------------------------------------------------------------------------
# The validation matrix: sites spanning 80-90 S and all longitudes, with one
# elevated site to exercise topocentric parallax; three 30-day windows spread
# over the supported span (2025-2035), 4-hour steps.
# ---------------------------------------------------------------------------

VALIDATION_SITES = [
    {"id": "v-pole", "lat": -89.90, "lon": 0.0, "alt_km": 0.0},
    {"id": "v-ridge", "lat": -89.45, "lon": -137.31, "alt_km": 1.5},
    {"id": "v-malapert", "lat": -86.00, "lon": 2.90, "alt_km": 5.0},
    {"id": "v-nobile", "lat": -85.30, "lon": 31.50, "alt_km": 0.0},
    {"id": "v-degerlache", "lat": -88.50, "lon": -87.10, "alt_km": 0.0},
    {"id": "v-mouton", "lat": -84.79, "lon": 29.20, "alt_km": 0.0},
    {"id": "v-far", "lat": -80.00, "lon": 135.00, "alt_km": 0.0},
    {"id": "v-haworth", "lat": -87.50, "lon": -5.00, "alt_km": 0.0},
]

VALIDATION_WINDOWS = [
    ("2025-03-01 00:00", "2025-03-31 00:00"),
    ("2028-07-10 00:00", "2028-08-09 00:00"),
    ("2035-10-01 00:00", "2035-10-31 00:00"),
]
VALIDATION_STEP = "4 h"


def validation_queries() -> list[Query]:
    qs = []
    for s in VALIDATION_SITES:
        for (a, b) in VALIDATION_WINDOWS:
            for body in ("sun", "earth"):
                qs.append(Query(body, s["lat"], s["lon"], s["alt_km"], a, b, VALIDATION_STEP))
    return qs


def fetch_all(refresh: bool = False) -> list[dict]:
    out = []
    qs = validation_queries()
    for i, q in enumerate(qs, 1):
        rec = fetch(q, refresh=refresh)
        print(f"[{i}/{len(qs)}] {q.body} {q.lat},{q.lon} {q.start}: {len(rec['rows'])} rows")
        out.append(rec)
    return out


if __name__ == "__main__":
    import sys

    fetch_all(refresh="--refresh" in sys.argv)
