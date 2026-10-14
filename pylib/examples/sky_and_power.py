"""Sun and Earth over three days at a custom site: direction, horizon, visible share, power, DSN.

Places a site like the app's "custom site" (height and skyline from the bundled 400 m
LOLA DEM, labelled approximate), then evaluates every hour:

* the apparent Sun and Earth azimuth / elevation (``LT+S``, ``MOON_ME``, no refraction),
* the terrain horizon at those azimuths,
* the visible share of each disc (16-strip integration against the skyline),
* the power proxy 1361 W/m^2 x (1 au / r)^2 x visible share,
* which DSN complexes see the Moon (>= 10 deg; bundled hourly bits).

    python examples/sky_and_power.py [--lat -85.98] [--lon -0.26] [--start 2027-01-01] [--days 3] [--csv out.csv]
"""

from __future__ import annotations

import argparse

import numpy as np

import lunarhorizon as lh
from lunarhorizon.dsn import stations_in_view
from lunarhorizon.visibility import sun_angular_radius_deg


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--lat", type=float, default=-85.98, help="planetocentric latitude, deg")
    ap.add_argument("--lon", type=float, default=-0.26, help="east-positive longitude, deg")
    ap.add_argument("--start", default="2027-01-01")
    ap.add_argument("--days", type=float, default=3.0)
    ap.add_argument("--height", type=float, default=2.0, help="observer height above terrain, m")
    ap.add_argument("--csv", help="also write the hourly series as CSV")
    a = ap.parse_args()

    site = lh.Site.custom(a.lat, a.lon)  # the app's method: 400 m DEM, coarse horizon (approximate)
    t0 = lh.to_unix_ms(a.start)
    t1 = t0 + a.days * lh.DAY_MS
    print(f"{site.name} at ({site.lat_deg}, {site.lon_deg}E): terrain {site.terrain_height_m:.1f} m above "
          f"the 1737.4 km sphere, observer +{a.height:g} m, approximate horizon: {site.approximate}")

    # Low-level route: an observer, a horizon mask and the bundled ephemeris.
    eph = lh.CompactEphemeris.bundled()
    obs = site.observer(a.height)
    mask = site.mask(a.height)
    times = np.arange(t0, t1, lh.HOUR_MS)
    sun = obs.look(eph.sun(times))
    earth = obs.look(eph.earth(times))
    rho = sun_angular_radius_deg(sun.range_km)
    frac = lh.visible_fraction(sun.az_deg, sun.el_deg, rho, mask)
    power = lh.power_wm2(frac, sun.range_km)

    # High-level route: the same numbers as one Series (plus Earth, DSN and the flags).
    s = lh.compute_series(eph, obs, mask, t0, t1, lh.SeriesOptions(step_ms=lh.HOUR_MS))
    assert np.array_equal(s.sun_frac, frac) and np.array_equal(s.power, power)

    print(f"\n{'UTC':20} {'Sun az':>7} {'el':>6} {'hz':>6} {'vis%':>6} {'W/m2':>7} | "
          f"{'Earth az':>8} {'el':>6} {'hz':>6} | DSN")
    for i in range(0, s.n, 6):
        print(f"{lh.iso(s.time_at(i)):20} {s.sun_az[i]:7.2f} {s.sun_el[i]:6.2f} {s.sun_hz[i]:6.2f} "
              f"{100 * s.sun_frac[i]:6.1f} {s.power[i]:7.1f} | {s.earth_az[i]:8.2f} {s.earth_el[i]:6.2f} "
              f"{s.earth_hz[i]:6.2f} | {', '.join(stations_in_view(int(s.dsn[i]))) or '-'}")

    m = lh.compute_metrics(s)
    print(f"\nSunlit {m.pct_sunlit:.1f} %, Earth in view {m.pct_earth:.1f} %, both {m.pct_both:.1f} %, "
          f"DSN {m.pct_dsn:.1f} %, mean power {m.mean_power_wm2:.1f} W/m^2")
    if a.csv:
        s.to_csv(a.csv)
        print(f"wrote {a.csv}")


if __name__ == "__main__":
    main()
