"""One-call site analysis: series, metrics, goal score and best landing window.

:func:`analyze_site` is a thin facade over the lower-level modules and does exactly
what the app does when you pick a site and a period:

1. resolve the site (a preset id / short name, a :class:`~lunarhorizon.sites.Site`, or a
   ``(lat_deg, lon_deg)`` pair placed like the app's custom sites),
2. build the time series with :func:`~lunarhorizon.series.compute_series` (step from
   :func:`~lunarhorizon.series.auto_step_ms` unless given: 10 min up to 60 days, 30 min up
   to a year, else 1 h),
3. :func:`~lunarhorizon.metrics.compute_metrics`, :func:`~lunarhorizon.score.score`,
4. :func:`~lunarhorizon.landing.best_landing_window` for the mission length (clamped like
   the app to 1 .. min(30, whole days in the period)).

Nothing is computed here that the lower-level calls do not compute; the test
``tests/test_report.py`` checks that the report equals their composition.

Conventions: times are Unix milliseconds (UTC) or anything
:func:`lunarhorizon.time.to_unix_ms` accepts (``datetime`` with naive = UTC, ISO-8601
strings, ``numpy.datetime64``). The period is ``[start, end)``.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Optional, Tuple, Union

from .landing import LandingPlan, best_landing_window, check_mission_days, clamp_mission_days
from .metrics import SiteMetrics, compute_metrics
from .score import Goal, ScoreBreakdown, ScoreWeights, as_weights, goal_for, score
from .series import Series, SeriesOptions, _resolve_ephemeris, auto_step_ms, compute_series
from .sites import Site
from .time import iso, to_unix_ms

__all__ = ["SiteReport", "analyze_site", "resolve_site"]

_DEFAULT_HEIGHTS = (2.0, 10.0)


def resolve_site(site: Union[Site, str, Tuple[float, float]], *, observer_height_m: float = 2.0,
                 dem: str = "app") -> Site:
    """A :class:`~lunarhorizon.sites.Site` from a Site, a preset id / short name, or ``(lat, lon)``.

    A ``(lat_deg, lon_deg)`` pair (planetocentric, east-positive, degrees) becomes
    ``Site.custom(lat, lon, dem=dem)`` with masks for 2 m, 10 m and ``observer_height_m``.
    ``dem="app"`` is the app's custom-site method (400 m DEM, coarse horizon, labelled
    approximate); ``dem="lola"`` uses the 80 m + 240 m LOLA DEMs (needs ``data.fetch("dems")``).
    """
    if isinstance(site, Site):
        return site
    if isinstance(site, str):
        return Site.preset(site)
    try:
        lat, lon = (float(v) for v in site)  # type: ignore[union-attr]
    except (TypeError, ValueError):
        raise TypeError(f"site must be a Site, a preset id or a (lat_deg, lon_deg) pair, got {site!r}") from None
    heights = tuple(sorted(set(_DEFAULT_HEIGHTS) | {float(observer_height_m)}))
    s = Site.custom(lat, lon, observer_heights_m=heights, dem=dem)  # validates lat, normalises lon
    s.name = f"Custom site ({s.lat_deg:.3f}, {s.lon_deg:.3f}E)"
    return s


def _ms(t: Any) -> float:
    if isinstance(t, (int, float)) and not isinstance(t, bool):
        return float(t)
    return float(to_unix_ms(t))


def _clean(x: Any) -> Any:
    """Non-finite floats to None, recursively (so the dict is strict JSON)."""
    if isinstance(x, float) and not math.isfinite(x):
        return None
    if isinstance(x, dict):
        return {k: _clean(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [_clean(v) for v in x]
    return x


@dataclass
class SiteReport:
    """Everything the app shows for one site and period (numbers only).

    Attributes:
        site: the resolved site (terrain height, masks, ``approximate`` flag).
        start_ms, end_ms: the period ``[start, end)``, Unix ms UTC.
        options: the :class:`~lunarhorizon.series.SeriesOptions` used (step and criteria).
        observer_height_m: mast height above the terrain, m.
        series: the per-sample time series.
        metrics: sunlit %, Earth %, both %, DSN %, mean power (W/m^2), energy (kWh/m^2) and
            the longest runs (sun, dark, Earth, Earth outage, both).
        score: the goal score with its terms (0..100).
        goal: the named goal whose weights were used, or None for hand-set weights.
        weights: the score weights.
        landing: the best landing window, or None when ``mission_days`` was None.
        mission_days: the mission length actually searched (after clamping), or 0.
    """

    site: Site
    start_ms: float
    end_ms: float
    options: SeriesOptions
    observer_height_m: float
    series: Series
    metrics: SiteMetrics
    score: ScoreBreakdown
    goal: Optional[Goal]
    weights: ScoreWeights
    landing: Optional[LandingPlan]
    mission_days: int

    def to_dict(self, *, include_series: bool = False) -> dict:
        """Plain JSON-able dict (non-finite numbers become None).

        The per-sample arrays are left out unless ``include_series`` is True.
        """
        o = self.options
        d = {
            "site": {
                "id": self.site.id,
                "name": self.site.name,
                "lat_deg": self.site.lat_deg,
                "lon_deg": self.site.lon_deg,
                "terrain_height_m": self.site.terrain_height_m,
                "approximate": bool(self.site.approximate),
            },
            "start": iso(self.start_ms),
            "end": iso(self.end_ms),
            "start_ms": self.start_ms,
            "end_ms": self.end_ms,
            "observer_height_m": self.observer_height_m,
            "options": {
                "step_ms": o.step_ms,
                "sun_criterion": getattr(o.sun_criterion, "value", str(o.sun_criterion)),
                "earth_criterion": getattr(o.earth_criterion, "value", str(o.earth_criterion)),
                "require_dsn": o.require_dsn,
            },
            "n": self.series.n,
            "metrics": self.metrics.to_dict(),
            "goal": None if self.goal is None else self.goal.value,
            "weights": {"power": self.weights.power, "both": self.weights.both},
            "score": self.score.to_dict(),
            "mission_days": self.mission_days,
            "landing": None if self.landing is None else self.landing.to_dict(),
        }
        if include_series:
            d["series"] = self.series.to_dict()
        return _clean(d)

    def summary_text(self) -> str:
        """A short plain-text summary (what the CLI prints)."""
        m, b, s = self.metrics, self.score, self.site
        lines = [
            f"{s.name} ({s.lat_deg:.4f}, {s.lon_deg:.4f}E), terrain {s.terrain_height_m:.1f} m, "
            f"observer +{self.observer_height_m:g} m" + ("  [approximate horizon: 400 m DEM]" if s.approximate else ""),
            f"Period {iso(self.start_ms)} .. {iso(self.end_ms)}, {self.series.n} samples every "
            f"{self.options.step_ms / 60000:g} min",
            f"Sunlit {m.pct_sunlit:6.2f} %   Earth in view {m.pct_earth:6.2f} %   Both {m.pct_both:6.2f} %"
            + (f"   DSN {m.pct_dsn:6.2f} %" if self.options.require_dsn else ""),
            f"Longest night {m.longest_dark_hours:7.1f} h   Longest Earth outage {m.longest_earth_outage_hours:7.1f} h",
            f"Mean power {m.mean_power_wm2:7.1f} W/m^2   Energy {m.energy_kwh_m2:8.2f} kWh/m^2",
            f"Score ({self.goal.value if self.goal else 'custom'}) {b.total:6.2f}  "
            f"[power {b.power:.2f}, comms {b.comms:.2f}, both {b.both:.2f}, "
            f"night survival {b.night_survival:.2f}, outage tolerance {b.outage_tolerance:.2f}]",
        ]
        p = self.landing
        if p is not None:
            st = p.status.value
            if p.suggested is None:
                lines.append(f"Best landing window ({self.mission_days} d): {st} (period too short)")
            else:
                w = p.suggested
                lines.append(
                    f"Best landing window ({self.mission_days} d): {st}, land {iso(w.start_ms)}, "
                    f"until {iso(w.end_ms)}; both {w.both_pct:.1f} %, sun {w.sun_pct:.1f} %, "
                    f"Earth {w.earth_pct:.1f} %, margin {w.margin_deg:.2f} deg")
                if p.is_full_fit and p.has_span:
                    lines.append(f"  any landing from {iso(p.span_start_ms)} to {iso(p.span_end_ms)} fits "
                                 f"({p.slack_h:.1f} h of slack)")
        return "\n".join(lines)


def analyze_site(site: Union[Site, str, Tuple[float, float]], start: Any, end: Any, *,
                 observer_height_m: float = 2.0, mission_days: Optional[int] = 14,
                 goal: Union[Goal, ScoreWeights, str] = Goal.BALANCED, sun: Any = "upper_limb",
                 earth: Any = "center", require_dsn: bool = False, step_ms: Union[float, str] = "auto",
                 ephemeris: Any = "app", dem: str = "app", not_before: Any = None) -> SiteReport:
    """Analyse one site over ``[start, end)`` the way the app does.

    Args:
        site: preset id / short name, a :class:`~lunarhorizon.sites.Site`, or ``(lat_deg, lon_deg)``
            (planetocentric latitude, east-positive longitude; placed like the app's custom sites).
        start, end: the period (Unix ms UTC, datetime, ISO string or datetime64).
        observer_height_m: mast height above the terrain, m (presets have masks for 2 and 10 m).
        mission_days: mission length for the landing search, whole days 1..30 (``ValueError``
            otherwise); shortened to the whole days in the period, as the app does. None skips
            the landing search.
        goal: a :class:`~lunarhorizon.score.Goal` (``"balanced"``, ``"power"``, ``"earth"``,
            ``"both"``) or :class:`~lunarhorizon.score.ScoreWeights`.
        sun: ``"upper_limb"`` (default, any part of the disc), ``"center"`` or ``"full_disk"``.
        earth: ``"center"`` (default) or ``"any_part"``.
        require_dsn: Earth also needs a DSN complex seeing the Moon at >= 10 deg.
        step_ms: sample step in ms, or ``"auto"`` (the app's rule).
        ephemeris: ``"app"`` (bundled, the app's numbers), ``"spice"`` (exact; needs kernels) or
            an Ephemeris instance.
        dem: for ``(lat, lon)`` sites: ``"app"`` (400 m) or ``"lola"`` (80 m + 240 m).
        not_before: earliest landing time offered (None = the period start).

    Returns:
        A :class:`SiteReport`.
    """
    s = resolve_site(site, observer_height_m=observer_height_m, dem=dem)
    t0, t1 = _ms(start), _ms(end)
    if not t1 > t0:
        raise ValueError(f"end must be after start ({iso(t0)} .. {iso(t1)})")
    step = auto_step_ms(t1 - t0) if (isinstance(step_ms, str) and step_ms == "auto") else float(step_ms)
    opts = SeriesOptions(step_ms=step, sun_criterion=sun, earth_criterion=earth, require_dsn=require_dsn)
    h = float(observer_height_m)
    series = compute_series(_resolve_ephemeris(ephemeris), s.observer(h), s.mask(h), t0, t1, opts)
    metrics = compute_metrics(series)
    weights = as_weights(goal)
    breakdown = score(metrics, weights)
    plan = None
    md = 0
    if mission_days is not None:
        md = clamp_mission_days(check_mission_days(mission_days), t0, t1)
        nb = -math.inf if not_before is None else _ms(not_before)
        plan = best_landing_window(series, md, weights, not_before_ms=nb)
    return SiteReport(site=s, start_ms=t0, end_ms=t1, options=opts, observer_height_m=h, series=series,
                      metrics=metrics, score=breakdown, goal=goal_for(weights), weights=weights,
                      landing=plan, mission_days=md)
