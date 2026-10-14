"""Planning numbers for the Shackleton rim (De Rosa et al. 2012 site SR1) over 2027.

Metrics (sunlit %, Earth in view %, both %, longest night, longest Earth outage), the
goal score with its terms under each goal, and the best 14-day landing window, all
with the bundled data (no download) and the same numbers as the Lunar Horizon app.

    python examples/site_report.py [--site ID] [--year 2027] [--mission-days 14] [--json]
"""

from __future__ import annotations

import argparse
import json

import lunarhorizon as lh
from lunarhorizon.daily import DayClass


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--site", default="derosa2012-sr1-shackleton-rim")
    ap.add_argument("--year", type=int, default=2027)
    ap.add_argument("--mission-days", type=int, default=14)
    ap.add_argument("--json", action="store_true", help="print the report as JSON")
    a = ap.parse_args()

    start, end = f"{a.year}-01-01", f"{a.year + 1}-01-01"
    report = lh.analyze_site(a.site, start, end, mission_days=a.mission_days, goal="balanced")
    if a.json:
        print(json.dumps(report.to_dict(), indent=2))
        return
    print(report.summary_text())

    # The same series scored under every goal (the score is plain arithmetic on the metrics).
    print("\nScore by goal:")
    for goal in lh.Goal:
        b = lh.score(report.metrics, goal)
        print(f"  {goal.value:9}  {b.total:6.2f}")

    # The best landing window under each goal (the two-tier rule of formula.md 11.10).
    print(f"\nBest {report.mission_days}-day landing window by goal:")
    for goal in lh.Goal:
        plan = lh.best_landing_window(report.series, report.mission_days, goal)
        w = plan.suggested
        when = "none" if w is None else f"{lh.iso(w.start_ms)} (both {w.both_pct:.1f} %)"
        print(f"  {goal.value:9}  {plan.status.value:16} {when}")

    # Good days per month (a day is "both" when Sun and Earth are up together >= half of it).
    print("\nGood days (Sun and Earth together >= 12 h) per month:")
    for mc in lh.monthly_counts(lh.daily_summaries(report.series)):
        print(f"  {mc.year}-{mc.month:02d}  {mc.counts[DayClass.BOTH]:2d} of {mc.days}")


if __name__ == "__main__":
    main()
