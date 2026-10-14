"""The transparent site score (port of ``score.dart``, the goals of ``ranking.dart``
and ``rank`` of ``summary.dart``; formula.md section 10).

All terms are 0..100::

    night_survival   = 100 x (1 - min(longest darkness / 720 h, 1))
    outage_tolerance = 100 x (1 - min(longest Earth outage / 720 h, 1))
    Power  = 0.6 x %sunlit + 0.4 x night_survival
    Comms  = 0.6 x %Earth  + 0.4 x outage_tolerance
    Score  = (1 - b) x [a x Power + (1 - a) x Comms] + b x %both

``a`` = power weight (comms weight = 1 - a), ``b`` = weight of simultaneous
Sun + Earth availability. The goals are presets of (a, b).
"""
from __future__ import annotations

import numbers
from dataclasses import dataclass
from enum import Enum
from typing import Mapping, Optional, Tuple, Union

import numpy as np

from .metrics import SiteMetrics
from .series import dart_round

__all__ = [
    "REFERENCE_WINDOW_HOURS",
    "ScoreWeights",
    "ScoreBreakdown",
    "Goal",
    "GOAL_LABELS",
    "weights_for",
    "goal_for",
    "as_weights",
    "score_terms",
    "score",
    "formula_text",
    "Ranked",
    "rank",
]

#: Gap length (hours) at which night survival / outage tolerance reach 0 (30 days).
REFERENCE_WINDOW_HOURS = 30 * 24.0


@dataclass(frozen=True)
class ScoreWeights:
    """``power``: weight of power vs comms (0 = comms only, 1 = power only);
    ``both``: weight of simultaneous Sun + Earth availability. Both must be in [0, 1]
    (``ValueError`` otherwise)."""

    power: float = 0.5
    both: float = 0.25

    def __post_init__(self) -> None:
        for name in ("power", "both"):
            v = getattr(self, name)
            ok = isinstance(v, numbers.Real) and 0.0 <= float(v) <= 1.0  # False for NaN and strings
            if not ok:
                raise ValueError(f"ScoreWeights.{name} must be a number in [0, 1], got {v!r}")

    @property
    def comms(self) -> float:
        """Comms weight, ``1 - power``."""
        return 1 - self.power

    def copy_with(self, power: Optional[float] = None, both: Optional[float] = None) -> "ScoreWeights":
        """A copy with ``power`` and/or ``both`` replaced (``comms`` follows as 1 - power - both)."""
        return ScoreWeights(self.power if power is None else power, self.both if both is None else both)

    def to_dict(self) -> dict:
        """Plain dict of the three weights."""
        return {"power": self.power, "both": self.both, "comms": self.comms}


@dataclass(frozen=True)
class ScoreBreakdown:
    """The score's terms (0..100). Fields are floats, or numpy arrays when
    :func:`score_terms` was given arrays."""

    power: float
    comms: float
    both: float
    night_survival: float
    outage_tolerance: float
    total: float

    def to_dict(self) -> dict:
        """Plain dict of the terms and the total (arrays become lists)."""

        def v(x):
            return x.tolist() if isinstance(x, np.ndarray) else x

        return {"power": v(self.power), "comms": v(self.comms), "both": v(self.both),
                "night_survival": v(self.night_survival), "outage_tolerance": v(self.outage_tolerance),
                "total": v(self.total)}


class Goal(str, Enum):
    """Named ranking goals ("What matters most?"), each a preset pair of weights."""

    BALANCED = "balanced"
    POWER = "power"
    EARTH = "earth"
    BOTH = "both"


_GOAL_WEIGHTS = {
    Goal.BALANCED: ScoreWeights(power=0.5, both=0.25),
    Goal.POWER: ScoreWeights(power=0.8, both=0.2),
    Goal.EARTH: ScoreWeights(power=0.2, both=0.2),
    Goal.BOTH: ScoreWeights(power=0.5, both=0.6),
}

#: The app's labels for the goals.
GOAL_LABELS = {Goal.BALANCED: "Balanced", Goal.POWER: "Power first", Goal.EARTH: "Earth contact first",
               Goal.BOTH: "Both at once"}


def weights_for(goal: Union[Goal, str]) -> ScoreWeights:
    """Weights of a goal: balanced (0.5, 0.25), power (0.8, 0.2), earth (0.2, 0.2), both (0.5, 0.6)."""
    return _GOAL_WEIGHTS[Goal(getattr(goal, "value", goal))]


def goal_for(w: ScoreWeights) -> Optional[Goal]:
    """The goal whose weights match ``w`` within 1e-9, or None for hand-tuned weights."""
    for g in Goal:
        x = _GOAL_WEIGHTS[g]
        if abs(x.power - w.power) < 1e-9 and abs(x.both - w.both) < 1e-9:
            return g
    return None


def as_weights(w: Union[ScoreWeights, Goal, str, None]) -> ScoreWeights:
    """Accept weights, a :class:`Goal` or a goal name (None = balanced)."""
    if w is None:
        return _GOAL_WEIGHTS[Goal.BALANCED]
    if isinstance(w, ScoreWeights):
        return w
    return weights_for(w)


def _tolerance(hours):
    """``100 x (1 - clamp(hours / 720, 0, 1))``, scalars or arrays."""
    x = hours / REFERENCE_WINDOW_HOURS
    if isinstance(x, np.ndarray):
        c = np.clip(x, 0.0, 1.0)
    else:
        c = 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)
    return 100.0 * (1.0 - c)


def score_terms(*, pct_sunlit, pct_earth, pct_both, longest_dark_h, longest_outage_h,
                w: Union[ScoreWeights, Goal, str] = Goal.BALANCED) -> ScoreBreakdown:
    """The score formula on its own terms (percentages 0..100, gaps in hours).

    Accepts floats or equally shaped numpy arrays (elementwise, the same arithmetic, so a
    window scored in an array equals the same window scored alone). Used both for a whole
    period (:func:`score`) and for one mission window (landing.py).
    """
    w = as_weights(w)
    arrays = any(isinstance(x, np.ndarray) for x in (pct_sunlit, pct_earth, pct_both, longest_dark_h,
                                                       longest_outage_h))
    if arrays:
        pct_sunlit, pct_earth, pct_both, longest_dark_h, longest_outage_h = (
            np.asarray(x, dtype=np.float64) for x in (pct_sunlit, pct_earth, pct_both, longest_dark_h,
                                                      longest_outage_h))
    else:
        pct_sunlit, pct_earth, pct_both, longest_dark_h, longest_outage_h = (
            float(x) for x in (pct_sunlit, pct_earth, pct_both, longest_dark_h, longest_outage_h))
    night = _tolerance(longest_dark_h)
    outage = _tolerance(longest_outage_h)
    power = 0.6 * pct_sunlit + 0.4 * night
    comms = 0.6 * pct_earth + 0.4 * outage
    total = (1 - w.both) * (w.power * power + w.comms * comms) + w.both * pct_both
    return ScoreBreakdown(power, comms, pct_both, night, outage, total)


def score(m: SiteMetrics, w: Union[ScoreWeights, Goal, str] = Goal.BALANCED) -> ScoreBreakdown:
    """The score of a whole period's metrics (Dart ``score``)."""
    return score_terms(pct_sunlit=m.pct_sunlit, pct_earth=m.pct_earth, pct_both=m.pct_both,
                       longest_dark_h=m.longest_dark_hours, longest_outage_h=m.longest_earth_outage_hours, w=w)


def formula_text(w: Union[ScoreWeights, Goal, str] = Goal.BALANCED) -> str:
    """The formula in words with the weights as whole percentages (Dart ``formulaText``)."""
    w = as_weights(w)
    return (f"Score = {dart_round(100 * (1 - w.both))}% × [{dart_round(100 * w.power)}% Power + "
            f"{dart_round(100 * w.comms)}% Comms] + {dart_round(100 * w.both)}% × Both.  "
            "Power = 60% sunlit + 40% night-survival; Comms = 60% Earth-visible + 40% outage-tolerance; "
            "survival/tolerance fall linearly to 0 at a 30-day gap.")


@dataclass(frozen=True)
class Ranked:
    """One ranked site: id, display name, its metrics and its score breakdown."""

    id: str
    name: str
    metrics: SiteMetrics
    score: ScoreBreakdown

    def to_dict(self) -> dict:
        """Plain dict: id, name, metrics and score."""
        return {"id": self.id, "name": self.name, "metrics": self.metrics.to_dict(), "score": self.score.to_dict()}


def rank(sites: Mapping[str, Tuple[str, SiteMetrics]], w: Union[ScoreWeights, Goal, str] = Goal.BALANCED
         ) -> list[Ranked]:
    """Sites sorted by score total, highest first (Dart ``rank``).

    ``sites`` maps id -> (name, metrics). Python's sort is stable, so exact ties keep the
    input order; the Dart ``List.sort`` gives the same order for up to 32 sites (insertion
    sort), and ties are not otherwise specified there.
    """
    w = as_weights(w)
    r = [Ranked(k, v[0], v[1], score(v[1], w)) for k, v in sites.items()]
    r.sort(key=lambda x: x.score.total, reverse=True)
    return r
