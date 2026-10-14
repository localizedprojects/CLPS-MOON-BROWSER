"""Per-site Sun/Earth visibility time series (port of ``app/lib/core/timeseries.dart``).

For every sample ``t_i = t0 + i * step`` (Unix ms, UTC) the series holds the
topocentric azimuth/elevation of the Sun and the Earth (degrees, azimuth
clockwise from north with north = away from the pole), the terrain horizon at
those azimuths (degrees), the visible share of each disc (0..1, 16-strip
integration), the power proxy (W/m^2), the DSN bitmask (bit 0 Goldstone, 1
Madrid, 2 Canberra) and the availability flags:

* ``FLAG_SUN`` (1): the Sun counts as up under the Sun criterion (power),
* ``FLAG_EARTH`` (2): the Earth counts as up under the Earth criterion, and with
  ``require_dsn`` a DSN complex also sees the Moon (direct-to-Earth contact),
* ``FLAG_BOTH`` (4): both at once.

Each sample stands for the interval ``[t_i, t_i + step)`` (metrics.py relies on
this). The arithmetic is the Dart code's, vectorised with numpy over samples:
the same formulas in the same order, so the app's numbers are reproduced.
"""
from __future__ import annotations

import csv
import datetime as _dt
import math
from dataclasses import dataclass, field, fields, replace
from typing import TYPE_CHECKING, Any, Union

import numpy as np

if TYPE_CHECKING:  # pragma: no cover - typing only
    from .horizon import HorizonMask
    from .sky import Observer
    from .sites import Site

__all__ = [
    "FLAG_SUN",
    "FLAG_EARTH",
    "FLAG_BOTH",
    "MAX_SAMPLES",
    "SeriesOptions",
    "Series",
    "auto_step_ms",
    "series_length",
    "compute_series",
    "site_series",
    "dart_round",
]

FLAG_SUN = 1  #: power available
FLAG_EARTH = 2  #: direct-to-Earth comms available
FLAG_BOTH = 4  #: both at once

#: Upper bound on the number of samples (``1 << 24``, as timeseries.dart).
MAX_SAMPLES = 1 << 24

_DAY_MS = 86_400_000.0
_HOUR_MS = 3_600_000.0
_CHUNK = 1 << 16  # samples per vectorised block (bounds the 16-strip temporaries)


# ----------------------------------------------------------------- helpers


def dart_round(x: float) -> int:
    """Dart ``double.round()``: nearest integer, halves rounded away from zero."""
    if math.isnan(x) or math.isinf(x):
        raise ValueError(f"cannot round {x!r}")
    if x >= 0:
        f = math.floor(x)
        return int(f) + (1 if x - f >= 0.5 else 0)
    return -dart_round(-x)


def _dart_round_array(x: np.ndarray) -> np.ndarray:
    """Vectorised :func:`dart_round` (int64)."""
    x = np.asarray(x, dtype=np.float64)
    a = np.abs(x)
    f = np.floor(a)
    r = f + (a - f >= 0.5)
    return (np.sign(x) * r).astype(np.int64)


def _to_ms(t: Any) -> float:
    """A time as Unix ms (UTC). Numbers pass through; other types go to ``time.to_unix_ms``."""
    if isinstance(t, (int, float, np.integer, np.floating)) and not isinstance(t, bool):
        return float(t)
    if isinstance(t, _dt.datetime):
        if t.tzinfo is None:
            t = t.replace(tzinfo=_dt.timezone.utc)
        return t.timestamp() * 1000.0
    from .time import to_unix_ms  # P-sky module (section 2.2)

    return float(to_unix_ms(t))


_SUN_ALIASES = {"upper_limb": "upper_limb", "upperlimb": "upper_limb", "upper-limb": "upper_limb",
                "center": "center", "centre": "center", "full_disk": "full_disk", "fulldisk": "full_disk",
                "full-disk": "full_disk"}
_EARTH_ALIASES = {"center": "center", "centre": "center", "any_part": "any_part", "anypart": "any_part",
                  "any-part": "any_part"}


def _criterion(value: Any, aliases: dict, enum_name: str):
    """Normalise a criterion (enum member or string, '-'/'_' and case insensitive)."""
    raw = getattr(value, "value", value)
    key = str(raw).strip().lower()
    if key not in aliases:
        raise ValueError(f"unknown {enum_name} {value!r}; expected one of {sorted(set(aliases.values()))}")
    name = aliases[key]
    try:
        from . import visibility  # P-terrain module (section 2.3)

        return getattr(visibility, enum_name)(name)
    except (ImportError, AttributeError):  # visibility not available yet: keep the plain value
        return name


# ----------------------------------------------------------------- options


@dataclass(frozen=True)
class SeriesOptions:
    """How a series is sampled and how "available" is decided (timeseries.dart ``SeriesOptions``).

    Attributes:
        step_ms: sample step, ms (default 1 h). Use :func:`auto_step_ms` for the app's choice.
        sun_criterion: ``"upper_limb"`` (any part of the disc above the skyline, the default),
            ``"center"`` (disc centre above the skyline) or ``"full_disk"`` (visible share >= 0.999).
        earth_criterion: ``"center"`` (the default) or ``"any_part"``.
        require_dsn: Earth also needs a DSN complex seeing the Moon at >= 10 deg. In app mode the
            DSN state is the nearest hourly sample, so at sub-hour steps rise/set are +-30 min.
    """

    step_ms: float = _HOUR_MS
    sun_criterion: Any = "upper_limb"
    earth_criterion: Any = "center"
    require_dsn: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "step_ms", float(self.step_ms))
        if not (self.step_ms > 0 and math.isfinite(self.step_ms)):
            raise ValueError(f"step_ms must be positive and finite, got {self.step_ms!r}")
        object.__setattr__(self, "sun_criterion", _criterion(self.sun_criterion, _SUN_ALIASES, "SunCriterion"))
        object.__setattr__(self, "earth_criterion", _criterion(self.earth_criterion, _EARTH_ALIASES, "EarthCriterion"))
        object.__setattr__(self, "require_dsn", bool(self.require_dsn))

    def copy_with(self, **changes: Any) -> "SeriesOptions":
        """A copy with some fields replaced (Dart ``copyWith``)."""
        return replace(self, **changes)

    @staticmethod
    def auto_step_ms(range_ms: float) -> float:
        """See :func:`auto_step_ms`."""
        return auto_step_ms(range_ms)


def auto_step_ms(range_ms: float) -> float:
    """The app's step for a period of ``range_ms``: 600 s up to 60 days, 1800 s up to 366 days, else 3600 s."""
    if range_ms <= 60 * _DAY_MS:
        return 600e3
    if range_ms <= 366 * _DAY_MS:
        return 1800e3
    return 3600e3


def series_length(t0_ms: float, t1_ms: float, step_ms: float) -> int:
    """Samples in ``[t0_ms, t1_ms)`` at ``step_ms``: ``floor((t1 - t0) / step)`` clamped to 1 .. 2**24."""
    k = (float(t1_ms) - float(t0_ms)) / float(step_ms)
    if math.isnan(k):
        raise ValueError("series_length: NaN range")
    if k == math.inf:
        return MAX_SAMPLES
    if k == -math.inf:
        return 1
    return int(min(max(math.floor(k), 1), MAX_SAMPLES))


# ----------------------------------------------------------------- series

_FLOAT_FIELDS = ("sun_az", "sun_el", "sun_hz", "sun_frac", "earth_az", "earth_el", "earth_hz", "earth_frac",
                 "power", "sun_range_km", "earth_range_km")
_U8_FIELDS = ("dsn", "flags")


@dataclass(eq=False)
class Series:
    """A site's time series (Dart ``SiteSeries``); every array has length ``n``.

    Angles in degrees (azimuth clockwise from north, north = increasing latitude),
    shares 0..1, ``power`` in W/m^2, ranges in km (``sun_range_km`` and
    ``earth_range_km`` are extras, not in the Dart class). ``dsn`` and ``flags`` are uint8.
    """

    t0_ms: float
    step_ms: float
    n: int
    sun_az: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    sun_el: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    sun_hz: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    sun_frac: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    earth_az: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    earth_el: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    earth_hz: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    earth_frac: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    power: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    sun_range_km: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    earth_range_km: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    dsn: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]
    flags: np.ndarray = field(default=None, repr=False)  # type: ignore[assignment]

    def __post_init__(self) -> None:
        self.t0_ms = float(self.t0_ms)
        self.step_ms = float(self.step_ms)
        self.n = int(self.n)
        if self.n < 0:
            raise ValueError("n must be >= 0")
        for name in _FLOAT_FIELDS:
            v = getattr(self, name)
            v = np.zeros(self.n, dtype=np.float64) if v is None else np.asarray(v, dtype=np.float64)
            if v.shape != (self.n,):
                raise ValueError(f"{name} has shape {v.shape}, expected ({self.n},)")
            setattr(self, name, v)
        for name in _U8_FIELDS:
            v = getattr(self, name)
            v = np.zeros(self.n, dtype=np.uint8) if v is None else np.asarray(v, dtype=np.uint8)
            if v.shape != (self.n,):
                raise ValueError(f"{name} has shape {v.shape}, expected ({self.n},)")
            setattr(self, name, v)

    @classmethod
    def alloc(cls, t0_ms: float, step_ms: float, n: int) -> "Series":
        """An all-zero series of ``n`` samples (Dart ``SiteSeries.alloc``; handy for tests)."""
        return cls(t0_ms, step_ms, n)

    @classmethod
    def from_flags(cls, flags, *, t0_ms: float = 0.0, step_ms: float = _HOUR_MS, **arrays: Any) -> "Series":
        """A series with the given ``flags`` (and optionally other arrays by name), zeros elsewhere."""
        f = np.asarray(flags, dtype=np.uint8)
        return cls(t0_ms, step_ms, len(f), flags=f, **arrays)

    # --- time ---------------------------------------------------------------

    @property
    def times_ms(self) -> np.ndarray:
        """Sample times, Unix ms (``t0 + i * step``, float64)."""
        return self.t0_ms + np.arange(self.n, dtype=np.float64) * self.step_ms

    @property
    def end_ms(self) -> float:
        """End of the last sample's interval, ``t0 + n * step``."""
        return self.time_at(self.n)

    def time_at(self, i: int) -> float:
        """Time of sample ``i`` (Unix ms); also valid for ``i == n`` (the end of the period)."""
        return self.t0_ms + int(i) * self.step_ms

    def index_at(self, t_ms: Any) -> int:
        """Index of the sample nearest to ``t_ms`` (Dart rounding, clamped to 0 .. n - 1)."""
        k = (_to_ms(t_ms) - self.t0_ms) / self.step_ms
        if math.isnan(k):
            raise ValueError("index_at: NaN time")
        if math.isinf(k):
            return 0 if k < 0 else max(self.n - 1, 0)
        return min(max(dart_round(k), 0), max(self.n - 1, 0))

    # --- copies and export ----------------------------------------------------

    def slice(self, a: int, m: int) -> "Series":
        """Copy of samples ``[a, a + m)`` (every array), starting at ``time_at(a)``."""
        a, m = int(a), int(m)
        if a < 0 or m < 0 or a + m > self.n:
            raise IndexError(f"slice [{a}, {a + m}) outside 0..{self.n}")
        arrays = {name: getattr(self, name)[a:a + m].copy() for name in _FLOAT_FIELDS + _U8_FIELDS}
        return Series(self.time_at(a), self.step_ms, m, **arrays)

    def copy(self) -> "Series":
        """A deep copy."""
        return self.slice(0, self.n)

    def to_dict(self) -> dict:
        """Plain-Python dict (lists), JSON-serialisable; keys are the attribute names."""
        out: dict = {"t0_ms": self.t0_ms, "step_ms": self.step_ms, "n": self.n}
        for name in _FLOAT_FIELDS:
            out[name] = getattr(self, name).tolist()
        for name in _U8_FIELDS:
            out[name] = getattr(self, name).astype(int).tolist()
        return out

    def to_csv(self, path) -> None:
        """Write one row per sample, with the app's CSV export columns plus the two ranges.

        Columns: utc, sun_az_deg, sun_el_deg, sun_horizon_deg, sun_visible_fraction,
        earth_az_deg, earth_el_deg, earth_horizon_deg, earth_visible_fraction,
        sun_available, earth_available, both_available, dsn_goldstone, dsn_madrid,
        dsn_canberra, power_w_m2, sun_range_km, earth_range_km. Values are written
        with full precision (the app rounds to 4/3/1 decimals).
        """
        cols = ["utc", "sun_az_deg", "sun_el_deg", "sun_horizon_deg", "sun_visible_fraction",
                "earth_az_deg", "earth_el_deg", "earth_horizon_deg", "earth_visible_fraction",
                "sun_available", "earth_available", "both_available", "dsn_goldstone", "dsn_madrid",
                "dsn_canberra", "power_w_m2", "sun_range_km", "earth_range_km"]
        with open(path, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(cols)
            t = self.times_ms
            for i in range(self.n):
                fl, d = int(self.flags[i]), int(self.dsn[i])
                ms = dart_round(float(t[i]))
                when = _dt.datetime(1970, 1, 1, tzinfo=_dt.timezone.utc) + _dt.timedelta(milliseconds=ms)
                w.writerow([
                    when.strftime("%Y-%m-%dT%H:%M:%S") + (f".{ms % 1000:03d}Z" if ms % 1000 else "Z"),
                    repr(float(self.sun_az[i])), repr(float(self.sun_el[i])), repr(float(self.sun_hz[i])),
                    repr(float(self.sun_frac[i])), repr(float(self.earth_az[i])), repr(float(self.earth_el[i])),
                    repr(float(self.earth_hz[i])), repr(float(self.earth_frac[i])),
                    1 if fl & FLAG_SUN else 0, 1 if fl & FLAG_EARTH else 0, 1 if fl & FLAG_BOTH else 0,
                    d & 1, (d >> 1) & 1, (d >> 2) & 1,
                    repr(float(self.power[i])), repr(float(self.sun_range_km[i])), repr(float(self.earth_range_km[i])),
                ])

    def __len__(self) -> int:
        return self.n


# ----------------------------------------------------------------- compute


def _azel_arrays(azel) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    az = np.atleast_1d(np.asarray(azel.az_deg, dtype=np.float64))
    el = np.atleast_1d(np.asarray(azel.el_deg, dtype=np.float64))
    rng = np.atleast_1d(np.asarray(azel.range_km, dtype=np.float64))
    return az, el, rng


def _fill(s: Series, eph, observer, mask, o: SeriesOptions, a: int, b: int) -> None:
    """Compute samples ``[a, b)`` of ``s`` in place (Dart ``fillSeries``, vectorised)."""
    from . import visibility as vis  # P-terrain module (section 2.3)
    from .constants import EARTH_RADIUS_KM, SUN_RADIUS_KM

    i = np.arange(a, b, dtype=np.float64)
    t = s.t0_ms + i * o.step_ms  # Dart: t0Ms + i * o.stepMs
    sun_az, sun_el, sun_rng = _azel_arrays(observer.look(np.asarray(eph.sun(t), dtype=np.float64)))
    earth_az, earth_el, earth_rng = _azel_arrays(observer.look(np.asarray(eph.earth(t), dtype=np.float64)))
    rs = vis.angular_radius_deg(SUN_RADIUS_KM, sun_rng)
    re = vis.angular_radius_deg(EARTH_RADIUS_KM, earth_rng)
    s_hz = np.asarray(mask.at(sun_az), dtype=np.float64)
    e_hz = np.asarray(mask.at(earth_az), dtype=np.float64)
    fs = np.asarray(vis.visible_fraction(sun_az, sun_el, rs, mask), dtype=np.float64)
    fe = np.asarray(vis.visible_fraction(earth_az, earth_el, re, mask), dtype=np.float64)
    dsn = np.asarray(eph.dsn_mask(t)).astype(np.uint8)
    s.sun_az[a:b] = sun_az
    s.sun_el[a:b] = sun_el
    s.sun_hz[a:b] = s_hz
    s.sun_frac[a:b] = fs
    s.earth_az[a:b] = earth_az
    s.earth_el[a:b] = earth_el
    s.earth_hz[a:b] = e_hz
    s.earth_frac[a:b] = fe
    s.power[a:b] = vis.power_wm2(fs, sun_rng)
    s.sun_range_km[a:b] = sun_rng
    s.earth_range_km[a:b] = earth_rng
    s.dsn[a:b] = dsn
    sv = np.asarray(vis.sun_visible(o.sun_criterion, fs, sun_el, s_hz), dtype=bool)
    ev = np.asarray(vis.earth_visible(o.earth_criterion, fe, earth_el, e_hz), dtype=bool)
    if o.require_dsn:
        ev = ev & (dsn != 0)
    s.flags[a:b] = (sv * FLAG_SUN) | (ev * FLAG_EARTH) | ((sv & ev) * FLAG_BOTH)


def compute_series(ephemeris, observer: "Observer", mask: "HorizonMask", t0_ms: Any, t1_ms: Any,
                   options: SeriesOptions = SeriesOptions()) -> Series:
    """The series for ``observer`` with horizon ``mask`` over ``[t0_ms, t1_ms)`` (Dart ``computeSeries``).

    Args:
        ephemeris: any :class:`lunarhorizon.ephemeris.Ephemeris` (``sun``/``earth`` give (N, 3)
            Moon-centred apparent vectors in km, MOON_ME; ``dsn_mask`` the DSN bits).
        observer: a :class:`lunarhorizon.sky.Observer` (height above the 1737.4 km sphere =
            terrain height + mast height).
        mask: the terrain horizon (:class:`lunarhorizon.horizon.HorizonMask`) for that height.
        t0_ms, t1_ms: period, Unix ms UTC (datetimes and ISO strings are accepted too).
        options: step and availability rules. The step is used as given (see :func:`auto_step_ms`).

    Samples are ``t_i = t0 + i * step`` for ``i = 0 .. n - 1`` with ``n = series_length(t0, t1, step)``.
    """
    t0 = _to_ms(t0_ms)
    t1 = _to_ms(t1_ms)
    n = series_length(t0, t1, options.step_ms)
    s = Series.alloc(t0, options.step_ms, n)
    for a in range(0, n, _CHUNK):
        _fill(s, ephemeris, observer, mask, options, a, min(n, a + _CHUNK))
    return s


def _resolve_ephemeris(ephemeris):
    if isinstance(ephemeris, str):
        from . import ephemeris as ephem  # P-sky module (section 2.2)

        key = ephemeris.lower()
        if key == "app":
            return ephem.CompactEphemeris.bundled()
        if key in ("spice", "exact"):
            return ephem.SpiceEphemeris()
        raise ValueError(f"unknown ephemeris {ephemeris!r}; use 'app', 'spice' or an Ephemeris instance")
    return ephemeris


def site_series(site: "Union[Site, str]", start: Any, end: Any, *, observer_height_m: float = 2.0,
                step_ms: Union[float, str] = "auto", sun: Any = "upper_limb", earth: Any = "center",
                require_dsn: bool = False, ephemeris: Any = "app") -> Series:
    """Convenience: the series of a :class:`~lunarhorizon.sites.Site` as the app computes it.

    The observer is ``Observer(lat, lon, terrain_height_m + observer_height_m)`` and the horizon
    is ``site.mask(observer_height_m)``. ``step_ms="auto"`` uses :func:`auto_step_ms` on
    ``end - start`` (the app's rule). ``site`` may be a preset id / short name.
    ``ephemeris``: ``"app"`` (bundled compact ephemeris, the default), ``"spice"`` or an instance.
    Raises ``ValueError`` when ``end`` is not after ``start`` (:func:`compute_series`, the Dart
    port, instead returns one sample for an empty period).
    """
    if isinstance(site, str):
        from .sites import Site as _Site  # P-terrain module

        site = _Site.preset(site)
    t0 = _to_ms(start)
    t1 = _to_ms(end)
    if not t1 > t0:
        raise ValueError(f"end must be after start (start {t0} ms, end {t1} ms)")
    step = auto_step_ms(t1 - t0) if (isinstance(step_ms, str) and step_ms == "auto") else float(step_ms)
    opts = SeriesOptions(step_ms=step, sun_criterion=sun, earth_criterion=earth, require_dsn=require_dsn)
    obs = site.observer(observer_height_m)
    mask = site.mask(observer_height_m)
    return compute_series(_resolve_ephemeris(ephemeris), obs, mask, t0, t1, opts)
