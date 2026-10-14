# Quick start

Every code block on this page runs as written (`tests/test_examples.py` executes them).

```python
import lunarhorizon as lh
```

## 1. Pick a site

```python
for p in lh.list_presets()[:3]:
    print(p["id"], p["lat"], p["lon"])

sr1 = lh.Site.preset("derosa2012-sr1-shackleton-rim")      # by id ...
haworth = lh.Site.preset("Haworth")                         # ... or short name
print(sr1.terrain_height_m, sr1.heights_m)                  # m above 1737.4 km; masks for 2 m and 10 m

spot = lh.Site.custom(-85.98, -0.26)                        # the app's custom site: 400 m DEM
print(spot.terrain_height_m, spot.approximate)              # approximate=True (coarse skyline)
```

A preset carries its LOLA 80 m / 240 m horizon masks for observers 2 m and 10 m above the
terrain. `Site.custom(lat, lon, dem="lola")` computes a full-resolution skyline instead (needs
`lunarhorizon fetch dems`).

## 2. Sun and Earth in the sky

```python
t = ["2027-01-15T00:00:00Z", "2027-01-15T06:00:00Z", "2027-01-15T12:00:00Z"]
sun = lh.sun_azel(sr1.lat_deg, sr1.lon_deg, t, terrain_height_m=sr1.terrain_height_m)
earth = lh.earth_azel(sr1.lat_deg, sr1.lon_deg, t, terrain_height_m=sr1.terrain_height_m)
print(sun.az_deg, sun.el_deg, sun.range_km)
print(earth.az_deg, earth.el_deg)

mask = sr1.mask(2.0)
print(mask.at(sun.az_deg))                                   # skyline elevation at the Sun's azimuth
```

Azimuth is clockwise from north, where north points away from the pole. Elevations are
geometric (no refraction; the Moon has no atmosphere).

## 3. Visible share, power and DSN

```python
from lunarhorizon.visibility import sun_angular_radius_deg
frac = lh.visible_fraction(sun.az_deg, sun.el_deg, sun_angular_radius_deg(sun.range_km), mask)
print(frac, lh.power_wm2(frac, sun.range_km))                # 0..1, W/m^2
print(lh.dsn_in_view(t, ephemeris="app"))                    # bundled hourly bits
```

## 4. A time series and its planning numbers

```python
s = lh.site_series(sr1, "2027-01-01", "2027-03-01")          # auto step: 10 min up to 60 days
m = lh.compute_metrics(s)
print(m.pct_sunlit, m.pct_earth, m.pct_both)                 # %
print(m.longest_dark_hours, m.longest_earth_outage_hours)    # h
print(m.mean_power_wm2, m.energy_kwh_m2)

days = lh.daily_summaries(s)
print(days[0].day, days[0].cls.value, days[0].describe())
s.to_csv("sr1_2027.csv")                                     # every sample, one row each
```

Criteria: `sun="center" | "upper_limb" | "full_disk"`, `earth="center" | "any_part"`,
`require_dsn=True` (Earth counts only with a DSN complex up).

## 5. Score and ranking

```python
print(lh.score(m, "balanced").total, lh.score(m, lh.Goal.POWER).total)
b = lh.score(m, lh.ScoreWeights(power=0.7, both=0.1))
print(b.power, b.comms, b.both, b.night_survival, b.outage_tolerance, b.total)

mh = lh.compute_metrics(lh.site_series(haworth, "2027-01-01", "2027-03-01"))
for r in lh.rank({sr1.id: (sr1.name, m), haworth.id: (haworth.name, mh)}, "earth"):
    print(r.id, round(r.score.total, 1))
```

## 6. Best landing window

```python
plan = lh.best_landing_window(s, 14, "balanced")
print(plan.status.value)                                     # full_fit | partial | period_too_short
w = plan.suggested
print(w.start, w.end, w.both_pct, w.longest_night_h, w.margin_deg)
later = lh.best_landing_window(s, 14, "balanced", not_before_ms="2027-02-01")
```

A full fit is a landing whose whole mission keeps Sun and Earth up; when none exists the
search returns the best partial window by the goal's score (formula.md 11.10).

## 7. Light and shadow map

```python
region = lh.light_map("2027-07-01T12:00:00Z")                # whole 80-90 S region, 800 m pixels
close = lh.light_map("2027-07-01T12:00:00Z", lat_deg=sr1.lat_deg, lon_deg=sr1.lon_deg)
print(region.size, region.shares["sun"], close.size, close.shares["both"])
flags = close.pack_flags()                                   # bit 1 Sun (any), 2 full Sun, 4 Earth
```

## 8. One call for everything

```python
r = lh.analyze_site("Haworth", "2027-01-01", "2028-01-01", mission_days=7, goal="earth")
print(r.summary_text())
d = r.to_dict()                                              # strict JSON-able
```

## 9. Exact mode (optional download)

```bash
lunarhorizon fetch kernels      # the pinned SPICE kernels (SHA-256 checked)
lunarhorizon fetch dems         # LOLA 80 m and 240 m DEMs
```

```python
if lh.data.have_kernels():
    eph = lh.SpiceEphemeris()
    print(lh.sun_azel(sr1.lat_deg, sr1.lon_deg, "2040-01-01", ephemeris=eph).el_deg)  # any year
```
