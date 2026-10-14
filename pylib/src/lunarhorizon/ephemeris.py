"""Apparent Sun and Earth vectors from the Moon's centre, and DSN bits, over time.

Two implementations of one small protocol (:class:`Ephemeris`):

* :class:`CompactEphemeris`: the app's data and algorithm (``app/lib/core/ephemeris.dart``).
  Hourly float32 samples of the apparent (LT+S) Sun and Earth vectors from the Moon's
  centre in MOON_ME (km), 2025-01-01T00:00Z to 2035-12-31T23:00Z, bundled with the
  package, interpolated with the same 4-point Lagrange stencil; DSN bits of the
  nearest hourly sample. Reproduces the app sample for sample; no SPICE needed.
* :class:`SpiceEphemeris`: direct SPICE ``spkpos(body, et, "MOON_ME", "LT+S", "MOON")``
  for any epoch the kernels cover, and DSN evaluated at each sample's own epoch.

:func:`build_compact` writes new compact files in the app's format for any range (the
pipeline's ``ephemeris.build`` generalised), so coverage can be extended beyond 2035.

All times are Unix milliseconds (UTC); anything :func:`lunarhorizon.time.to_unix_ms`
accepts works. A scalar time gives a (3,) vector (and an int DSN mask); arrays give
(N, 3) (and a uint8 array).
"""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import threading
from pathlib import Path
from typing import Any, Protocol, Union, runtime_checkable

import numpy as np

from .constants import ABCORR, DSN_COMPLEXES, DSN_MIN_ELEV_DEG, EARTH_FRAME, FRAME
from .time import iso, to_unix_ms

__all__ = ["Ephemeris", "CompactEphemeris", "SpiceEphemeris", "build_compact", "resolve", "center_vectors"]


@runtime_checkable
class Ephemeris(Protocol):
    """What the series, sky and shadow code need from an ephemeris.

    ``start_ms`` and ``end_ms`` bound the epochs that can be evaluated (inclusive).
    ``sun``/``earth`` return apparent MOON_ME vectors (km) from the Moon's centre;
    ``dsn_mask`` returns DSN bits (bit 0 Goldstone, 1 Madrid, 2 Canberra).
    """

    start_ms: float
    end_ms: float

    def sun(self, t_ms: Any) -> np.ndarray:
        """Apparent Sun vector(s) in MOON_ME (km) from the Moon's centre: (3,) or (N, 3)."""
        ...

    def earth(self, t_ms: Any) -> np.ndarray:
        """Apparent Earth vector(s) in MOON_ME (km) from the Moon's centre: (3,) or (N, 3)."""
        ...

    def dsn_mask(self, t_ms: Any) -> Any:
        """DSN bits (1 Goldstone, 2 Madrid, 4 Canberra): an int for a scalar time, uint8 for arrays."""
        ...


# ---------------------------------------------------------------------------
# Compact (app) ephemeris
# ---------------------------------------------------------------------------

class CompactEphemeris:
    """Hourly float32 ephemeris with 4-point Lagrange interpolation (== ephemeris.dart).

    Args:
        start_ms: Unix ms of sample 0.
        step_ms: sample spacing (ms), 3 600 000 for the bundled data.
        data: float32 array (N, 6): Sun xyz, Earth xyz (km, MOON_ME, apparent, from the
            Moon's centre). Any (N*6,) array is reshaped.
        dsn: uint8 array (N,) of DSN bits per sample.
        manifest: the manifest dict the data came from (optional, informational).

    Interpolation is exactly the Dart ``_interp``: ``u = (t - start) / step``; epochs
    with ``u < -1e-9`` or ``u > count - 1 + 1e-9`` raise ValueError; the stencil is
    samples i-1..i+2 with ``i = min(floor(u), count - 2)``, shifted inward at both ends;
    weights are the cubic Lagrange basis at ``p = u - i0``; float32 samples are used as
    float64 and summed in the Dart order. ``dsn_mask`` takes the nearest sample
    (round half away from zero), clamped to the data.
    """

    _bundled: "CompactEphemeris | None" = None
    _bundled_lock = threading.Lock()

    def __init__(self, start_ms: float, step_ms: float, data: np.ndarray, dsn: np.ndarray,
                 manifest: dict | None = None):
        d = np.asarray(data)
        if d.dtype != np.float32:
            d = d.astype(np.float32)
        d = d.reshape(-1, 6)
        if d.shape[0] < 4:
            raise ValueError(f"need at least 4 samples for the 4-point stencil, got {d.shape[0]}")
        g = np.asarray(dsn, dtype=np.uint8).reshape(-1)
        if g.shape[0] != d.shape[0]:
            raise ValueError(f"dsn has {g.shape[0]} samples, data has {d.shape[0]}")
        self.start_ms = float(start_ms)
        self.step_ms = float(step_ms)
        self.data = d
        self.dsn = g
        self.count = int(d.shape[0])
        self.manifest = manifest
        self._f64 = d.astype(np.float64)  # exact widening, as Dart reads Float32List into doubles

    def __repr__(self) -> str:
        return (f"CompactEphemeris({iso(self.start_ms)} .. {iso(self.end_ms)}, "
                f"step {self.step_ms / 1000:g} s, {self.count} samples)")

    # -- construction -------------------------------------------------------
    @classmethod
    def bundled(cls) -> "CompactEphemeris":
        """The ephemeris shipped with the package (all years, 2.3 MB); loaded once and cached."""
        with cls._bundled_lock:
            if cls._bundled is None:
                from .data import bundled_path

                cls._bundled = cls.from_dir(bundled_path("ephem/manifest.json").parent.parent)
            return cls._bundled

    @classmethod
    def from_dir(cls, directory: Union[str, Path]) -> "CompactEphemeris":
        """Load an app-style data folder (``ephem/manifest.json``, ``ephem/<y>.bin``, ``dsn/<y>.bin``).

        ``directory`` is the data root (``app/assets/data``) or its ``ephem`` folder.
        Years are stitched in manifest order and must be contiguous.
        """
        root = Path(directory)
        if not (root / "ephem" / "manifest.json").exists() and (root / "manifest.json").exists():
            root = root.parent
        mpath = root / "ephem" / "manifest.json"
        if not mpath.exists():
            raise FileNotFoundError(f"no ephem/manifest.json under {directory}")
        m = json.loads(mpath.read_text(encoding="utf-8"))
        step_ms = float(m["stepSeconds"]) * 1000.0
        years = m["years"]
        if not years:
            raise ValueError(f"{mpath}: no years")
        blocks, dsns = [], []
        expect = float(years[0]["startUnixMs"])
        for y in years:
            if float(y["startUnixMs"]) != expect:
                raise ValueError(f"{mpath}: year {y['year']} starts at {y['startUnixMs']}, expected {expect:.0f} "
                                 "(years must be contiguous)")
            count = int(y["count"])
            blk = np.fromfile(root / y["file"], dtype="<f4")
            if blk.size < count * 6:
                raise ValueError(f"{y['file']}: {blk.size} floats, expected {count * 6}")
            blocks.append(blk[: count * 6].astype(np.float32).reshape(count, 6))
            g = np.fromfile(root / y["dsnFile"], dtype=np.uint8)
            if g.size < count:
                raise ValueError(f"{y['dsnFile']}: {g.size} bytes, expected {count}")
            dsns.append(g[:count])
            expect += count * step_ms
        return cls(float(years[0]["startUnixMs"]), step_ms, np.vstack(blocks), np.concatenate(dsns), manifest=m)

    # -- coverage -----------------------------------------------------------
    @property
    def end_ms(self) -> float:
        """Unix ms of the last sample (the last epoch that can be evaluated)."""
        return self.start_ms + (self.count - 1) * self.step_ms

    def covers(self, t0_ms: Any, t1_ms: Any) -> bool:
        """True when [t0, t1] lies inside [start_ms, end_ms] (Dart ``covers``)."""
        return float(to_unix_ms(t0_ms)) >= self.start_ms and float(to_unix_ms(t1_ms)) <= self.end_ms

    def clamp_period(self, start: Any, end: Any) -> tuple[float, float]:
        """The period [start, end) clamped to what the data can evaluate (Dart ``clampPeriod``).

        It starts at or after the first sample, its exclusive end is at most the last
        sample, and it lasts at least a day unless it starts within a day of the last
        sample (then it ends at the last sample).
        """
        day = 86400e3
        s, e = float(to_unix_ms(start)), float(to_unix_ms(end))
        first, last = self.start_ms, self.end_ms
        latest_start = last - self.step_ms if last - self.step_ms > first else first
        t0 = min(max(s, first), latest_start)
        min_end = t0 + day if t0 + day < last else last
        t1 = min(max(e, min_end), last)
        return t0, t1

    # -- evaluation ---------------------------------------------------------
    def _interp(self, t_ms: Any, off: int) -> np.ndarray:
        t = to_unix_ms(t_ms)
        scalar = np.ndim(t) == 0
        tt = np.atleast_1d(np.asarray(t, dtype=np.float64))
        u = (tt - self.start_ms) / self.step_ms
        bad = (u < -1e-9) | (u > self.count - 1 + 1e-9) | ~np.isfinite(u)
        if np.any(bad):
            k = int(np.argmax(bad))
            raise ValueError(f"epoch {iso(tt[k]) if np.isfinite(tt[k]) else tt[k]} outside the loaded ephemeris "
                             f"({iso(self.start_ms)} .. {iso(self.end_ms)})")
        i = np.floor(u).astype(np.int64)
        i = np.minimum(i, self.count - 2)
        i0 = i - 1
        i0 = np.maximum(i0, 0)
        i0 = np.minimum(i0, self.count - 4)
        p = u - i0
        w0 = -(p - 1) * (p - 2) * (p - 3) / 6.0
        w1 = p * (p - 2) * (p - 3) / 2.0
        w2 = -p * (p - 1) * (p - 3) / 2.0
        w3 = p * (p - 1) * (p - 2) / 6.0
        d = self._f64
        c = slice(off, off + 3)
        out = (w0[:, None] * d[i0, c] + w1[:, None] * d[i0 + 1, c]
               + w2[:, None] * d[i0 + 2, c] + w3[:, None] * d[i0 + 3, c])
        return out[0] if scalar else out

    def sun(self, t_ms: Any) -> np.ndarray:
        """Apparent Sun vector from the Moon's centre (km, MOON_ME): (3,) or (N, 3)."""
        return self._interp(t_ms, 0)

    def earth(self, t_ms: Any) -> np.ndarray:
        """Apparent Earth vector from the Moon's centre (km, MOON_ME): (3,) or (N, 3)."""
        return self._interp(t_ms, 3)

    def dsn_mask(self, t_ms: Any) -> Any:
        """DSN bits of the nearest hourly sample (not interpolated; about +-30 min at sub-hour steps)."""
        t = to_unix_ms(t_ms)
        x = (np.atleast_1d(np.asarray(t, dtype=np.float64)) - self.start_ms) / self.step_ms
        f = np.floor(x)
        r = np.where(x >= 0, np.where(x - f >= 0.5, f + 1, f), -np.floor(-x + 0.5))  # Dart round()
        i = np.clip(r, 0, self.count - 1).astype(np.int64)
        out = self.dsn[i]
        return int(out[0]) if np.ndim(t) == 0 else out


# ---------------------------------------------------------------------------
# Exact (SPICE) ephemeris
# ---------------------------------------------------------------------------

#: SPICE names of the bodies (target of spkpos).
_BODY = {"sun": "SUN", "earth": "EARTH"}


def center_vectors(body: str, ets: Any) -> np.ndarray:
    """Apparent (LT+S) body position from the Moon's centre in MOON_ME, km, at ET epochs (N, 3)."""
    import spiceypy as sp

    from . import spice

    spice.load()
    e = np.atleast_1d(np.asarray(ets, dtype=np.float64))
    pos, _lt = sp.spkpos(_BODY[body], e, FRAME, ABCORR, "MOON")
    return np.asarray(pos, dtype=np.float64).reshape(-1, 3)


class SpiceEphemeris:
    """Direct SPICE ephemeris (exact mode).

    ``sun``/``earth``: ``spkpos(body, et, "MOON_ME", "LT+S", "MOON")`` at each epoch;
    ``dsn_mask``: :func:`lunarhorizon.dsn.dsn_mask` at each sample's own epoch (not
    held to the hour). Needs the kernels (``lunarhorizon.data.fetch("kernels")``).

    Args:
        kernel_dir: folder holding the kernel files (default ``data.cache_dir()/kernels``).
        spk: ``None`` (DE440, production) or ``"de442"`` (cross-check; every call then
            runs inside :func:`lunarhorizon.spice.kernel_set`).

    ``start_ms``/``end_ms`` are the DE440s span (1850-01-01 to 2150-01-01, rounded
    inward); DSN also needs the ITRF93 kernel span (1962 to 2126).
    """

    start_ms = -3_786_825_600_000.0  # 1850-01-01T00:00Z
    end_ms = 5_680_281_600_000.0  # 2150-01-01T00:00Z

    def __init__(self, kernel_dir: Union[str, Path, None] = None, spk: str | None = None):
        from . import spice

        self.kernel_dir = Path(kernel_dir) if kernel_dir is not None else None
        self.spk = spk
        spice.kernel_paths(self.kernel_dir, spk)  # fail early with a clear message
        spice.load(self.kernel_dir)

    def __repr__(self) -> str:
        return f"SpiceEphemeris(spk={self.spk or 'de440'!r})"

    def _run(self, fn, *args):
        from . import spice

        if self.spk:
            with spice.kernel_set(self.spk, self.kernel_dir):
                return fn(*args)
        spice.load(self.kernel_dir)
        return fn(*args)

    def _vec(self, body: str, t_ms: Any) -> np.ndarray:
        from .time import unix_ms_to_et

        t = to_unix_ms(t_ms)
        out = self._run(lambda: center_vectors(body, unix_ms_to_et(t)))
        return out[0] if np.ndim(t) == 0 else out

    def sun(self, t_ms: Any) -> np.ndarray:
        """Apparent Sun vector from the Moon's centre (km, MOON_ME) by SPICE: (3,) or (N, 3)."""
        return self._vec("sun", t_ms)

    def earth(self, t_ms: Any) -> np.ndarray:
        """Apparent Earth vector from the Moon's centre (km, MOON_ME) by SPICE: (3,) or (N, 3)."""
        return self._vec("earth", t_ms)

    def dsn_mask(self, t_ms: Any) -> Any:
        """DSN bits at each epoch (exact; Moon centre >= 10 deg, ITRF93)."""
        from . import dsn

        return self._run(lambda: dsn.dsn_mask(t_ms))


def resolve(ephemeris: Any) -> Any:
    """``"app"`` -> :meth:`CompactEphemeris.bundled`, ``"spice"`` -> :class:`SpiceEphemeris`, else as is."""
    if isinstance(ephemeris, str):
        key = ephemeris.lower()
        if key in ("app", "compact", "bundled"):
            return CompactEphemeris.bundled()
        if key in ("spice", "exact"):
            return SpiceEphemeris()
        raise ValueError(f"unknown ephemeris {ephemeris!r}; use 'app', 'spice' or an Ephemeris instance")
    if not (hasattr(ephemeris, "sun") and hasattr(ephemeris, "earth")):
        raise TypeError(f"{ephemeris!r} is not an Ephemeris")
    return ephemeris


# ---------------------------------------------------------------------------
# Building compact files
# ---------------------------------------------------------------------------

def _year_start_ms(year: int) -> float:
    return _dt.datetime(year, 1, 1, tzinfo=_dt.timezone.utc).timestamp() * 1000.0


def build_compact(start: Any, end: Any, out_dir: Union[str, Path], step_s: float = 3600.0) -> dict:
    """Write a compact ephemeris for [start, end) in the app's format; return the manifest.

    Writes ``out_dir/ephem/<year>.bin`` (little-endian float32, 6 values per sample:
    apparent Sun xyz and Earth xyz, km, MOON_ME, from the Moon's centre),
    ``out_dir/dsn/<year>.bin`` (uint8 DSN bits per sample) and
    ``out_dir/ephem/manifest.json``. Samples are ``start + k * step_s`` per UTC calendar
    year (each year's file starts at ``max(start, Jan 1)``), exactly as
    ``pipeline/lunarsp/ephemeris.build``; the result loads with
    :meth:`CompactEphemeris.from_dir`. Needs the kernels.

    For whole-hour starts this reproduces the bundled bytes exactly.
    """
    import spiceypy as sp

    from . import data, spice
    from .dsn import dsn_mask_et
    from .time import unix_ms_to_et

    spice.load()
    t0, t1 = float(to_unix_ms(start)), float(to_unix_ms(end))
    if not t1 > t0:
        raise ValueError("end must be after start")
    step_ms = float(step_s) * 1000.0
    out = Path(out_dir)
    ephem_dir, dsn_dir = out / "ephem", out / "dsn"
    ephem_dir.mkdir(parents=True, exist_ok=True)
    dsn_dir.mkdir(parents=True, exist_ok=True)

    years = []
    y0 = _dt.datetime.fromtimestamp(t0 / 1000.0, _dt.timezone.utc).year
    next_ms = t0
    year = y0
    while next_ms < t1:
        y_end = min(_year_start_ms(year + 1), t1)
        # whole grid in seconds like the pipeline (np.arange(u0, u1, step) in Unix s)
        unix_s = np.arange(next_ms / 1000.0, y_end / 1000.0, float(step_s))
        if unix_s.size:
            ets = np.asarray(unix_ms_to_et(unix_s * 1000.0), dtype=np.float64)
            sun = center_vectors("sun", ets)
            earth = center_vectors("earth", ets)
            block = np.hstack([sun, earth]).astype("<f4")
            path = ephem_dir / f"{year}.bin"
            path.write_bytes(block.tobytes())
            mask = dsn_mask_et(ets)
            (dsn_dir / f"{year}.bin").write_bytes(mask.tobytes())
            years.append({
                "year": year,
                "file": f"ephem/{year}.bin",
                "dsnFile": f"dsn/{year}.bin",
                "startUnixMs": int(round(unix_s[0] * 1000.0)),
                "count": int(unix_s.size),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()[:16],
            })
            next_ms = (unix_s[-1] + step_s) * 1000.0
        else:
            next_ms = y_end
        year += 1

    last = years[-1]
    manifest = {
        "version": 1,
        "generatedUtc": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "frame": f"{FRAME} (= MOON_ME_DE440_ME421, aligned with LOLA DE421 mean-Earth frame)",
        "abcorr": ABCORR,
        "observer": "Moon centre; site parallax applied on the device",
        "stepSeconds": float(step_s),
        "startUnixMs": years[0]["startUnixMs"],
        "endUnixMs": int(round(last["startUnixMs"] + last["count"] * step_ms)),
        "columns": ["sun_x_km", "sun_y_km", "sun_z_km", "earth_x_km", "earth_y_km", "earth_z_km"],
        "dtype": "float32-le",
        "kernels": [{"file": data.KERNELS[k].filename, "note": data.KERNELS[k].note}
                    for k in data.PRODUCTION_KERNELS],
        "toolkit": sp.tkvrsn("TOOLKIT"),
        "dsn": {
            "minElevationDeg": DSN_MIN_ELEV_DEG,
            "earthFrame": f"{EARTH_FRAME} ({data.KERNELS['earth_bpc'].filename})",
            "bits": [{"bit": i, "id": k, **v} for i, (k, v) in enumerate(DSN_COMPLEXES.items())],
        },
        "years": years,
    }
    (ephem_dir / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    return manifest
