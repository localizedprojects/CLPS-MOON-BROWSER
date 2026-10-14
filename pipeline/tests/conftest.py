"""pytest configuration: print the measured error statistics at the end of
the run so they are visible without ``-s``."""

from __future__ import annotations

from tests._support import METRICS


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    if not METRICS:
        return
    terminalreporter.section("measured errors / validation statistics")
    width = max(len(k) for k in METRICS)
    for name in sorted(METRICS):
        value, unit = METRICS[name]
        terminalreporter.write_line(f"{name:<{width}}  {value:.4g} {unit}")
