"""The LROC "Anthropogenic Features on the Moon" shapefile (coordinates of every global preset).

Product LRO-L-LROC-5-RDR-V1.0, LROLRC_2001 EXTRAS/SHAPEFILE/ANTHROPOGENIC_OBJECTS,
``ANTHROPOGENIC_OBJECTS_180.ZIP`` (longitudes -180..180), cached in
``$LUNAR_SP_CACHE/dem_global/sources/``. Only the ``.DBF`` attribute table is
read: a dBASE III file of fixed-width records, parsed here with the standard
library (no new dependency). It is untrusted input: field widths come from
its header and are bounds-checked, and nothing in it is executed.
"""

from __future__ import annotations

import hashlib
import json
import struct
import zipfile
from pathlib import Path

from .globe_dem import SOURCES_DIR

ZIP_NAME = "ANTHROPOGENIC_OBJECTS_180.ZIP"
DBF_NAME = "ANTHROPOGENIC_OBJECTS_180.DBF"
ZIP_URL = ("https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/EXTRAS/SHAPEFILE/"
           "ANTHROPOGENIC_OBJECTS/ANTHROPOGENIC_OBJECTS_180.ZIP")
LANDING_PAGE = "https://data.lroc.im-ldi.com/lroc/view_rdr/SHAPEFILE_ANTHROPOGENIC_OBJECTS"
CATALOG = Path(__file__).with_name("global_catalog.json")

NUMERIC = ("LATITUDE", "LON_360", "LONGITUDE", "RADIUS", "UNCERTAIN")


def parse_dbf(blob: bytes) -> list[dict]:
    """Records of a dBASE III table as {field: str or float} (deleted rows skipped)."""
    if len(blob) < 32:
        raise ValueError("DBF too short")
    n, header_len, rec_len = struct.unpack("<IHH", blob[4:12])
    fields = []
    o = 32
    while o < header_len - 1 and blob[o] != 0x0D:
        name = blob[o:o + 11].split(b"\0")[0].decode("ascii", "replace")
        ftype = chr(blob[o + 11])
        width = blob[o + 16]
        fields.append((name, ftype, width))
        o += 32
    if sum(w for _, _, w in fields) + 1 != rec_len:
        raise ValueError("DBF field widths do not match the record length")
    if header_len + n * rec_len > len(blob):
        raise ValueError("DBF truncated")
    rows = []
    for k in range(n):
        rec = blob[header_len + k * rec_len: header_len + (k + 1) * rec_len]
        if rec[:1] == b"*":
            continue
        p = 1
        row: dict = {}
        for name, ftype, width in fields:
            raw = rec[p:p + width].decode("utf-8", "replace").strip()
            p += width
            if ftype in ("N", "F") and raw:
                row[name] = float(raw)
            else:
                row[name] = raw
        rows.append(row)
    return rows


def zip_path() -> Path:
    return SOURCES_DIR / ZIP_NAME


def read_records(path: Path | None = None) -> tuple[list[dict], str]:
    """(records, SHA-256 of the ZIP) of the cached shapefile."""
    p = Path(path) if path else zip_path()
    data = p.read_bytes()
    with zipfile.ZipFile(p) as z:
        blob = z.read(DBF_NAME)
    return parse_dbf(blob), hashlib.sha256(data).hexdigest()


def by_object_id(records: list[dict]) -> dict[str, dict]:
    out = {}
    for r in records:
        oid = r.get("OBJECT_ID", "")
        if oid in out:
            raise ValueError(f"duplicate OBJECT_ID {oid}")
        out[oid] = r
    return out


def load_catalog() -> dict:
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def says(rec: dict) -> str:
    """The quoted record, as `sources[0].says`."""
    return (f"ANTHROPOGENIC_OBJECTS_180 record OBJECT_ID {rec['OBJECT_ID']}: SHORT_NAME \"{rec['SHORT_NAME']}\" "
            f"(VEHCL_NAME \"{rec['VEHCL_NAME']}\", MISSION \"{rec['MISSION']}\", OBJECT \"{rec['OBJECT']}\"), "
            f"LATITUDE {rec['LATITUDE']:.6f}, LONGITUDE {rec['LONGITUDE']:.6f}, "
            f"COORD_SRC \"{rec['COORD_SRC']}\", UNCERTAIN {rec['UNCERTAIN']:g} m, "
            f"REFERENCES \"{rec['REFERENCES']}\"")


def site_coordinates(catalog: dict | None = None, records: list[dict] | None = None) -> dict[str, dict]:
    """{site id: shapefile record} for every catalogue row found in the shapefile."""
    catalog = catalog or load_catalog()
    if records is None:
        records, _ = read_records()
    idx = by_object_id(records)
    return {s["id"]: idx[s["shapefileId"]] for s in catalog["sites"] if s["shapefileId"] in idx}
