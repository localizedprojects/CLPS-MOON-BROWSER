# Space Apps submission

The facts to paste into the NASA Space Apps project page. Each one is checked against the
repository; the [README](../README.md) has the details and sources.

## Project title

Lunar Horizon

## High-level summary

Lunar Horizon answers one question for the Moon's south pole: which landing site, on which
dates, gives a lander the best solar power and direct-to-Earth contact? For 19 preset sites
and any spot you pick, it computes when the Sun and the Earth are above the real terrain
horizon, from NASA/JPL SPICE ephemerides and LRO LOLA elevation data, and turns that into
rankings, the best landing window for a mission, a computed light-and-shadow map, a 3D
lander's view and plain-language answers. It runs as a web app and on Android, with every
approximation labelled, and its Sun and Earth geometry is checked against JPL Horizons and the
LOLA team's own visibility maps.

## NASA data and resources used

- **LRO LOLA** (Lunar Reconnaissance Orbiter, Lunar Orbiter Laser Altimeter), from the PDS
  Geosciences Node: the south-pole elevation models `LDEM_80S_80M`, `LDEM_75S_240M` and
  `LDEM_75S_120M` (terrain horizons, the on-device 400 m terrain, the base map), and the
  LOLA team's average-visibility maps `AVGVISIB_75S_120M_201608` (Sun and Earth) for
  validation and the long-term overlays.
- **NASA/JPL NAIF SPICE kernels:** the DE440 planetary and lunar ephemeris (`de440s.bsp`),
  the DE440 lunar orientation (`moon_pa_de440_200625.bpc`) and frames
  (`moon_de440_250416.tf`, `MOON_ME`), leap seconds (`naif0012.tls`), body radii
  (`pck00011.tpc`), ITRF93 Earth orientation (`earth_1962_*_combined.bpc`) for the Deep
  Space Network check, and DE442 (`de442s.bsp`) for a cross-check only.
- **JPL Horizons:** the independent reference for the Sun and Earth directions (48 cached
  responses: 8 sites, three 30-day windows, Sun and Earth).
- **Deep Space Network station locations:** Goldstone (DSS-14), Madrid (DSS-63) and Canberra
  (DSS-43), from the JPL *DSN Telecommunications Link Design Handbook* (810-005), module 301.
- **Site coordinates:** NASA's Artemis III candidate regions (update of 28 October 2024) and
  LRO LROC images of the IM-1 and IM-2 landers, with the other published sources listed per
  site in `app/assets/data/sites.json`.

## Use of AI

Lunar Horizon was built with Anthropic's Claude Code, an AI coding assistant, for coding,
documentation and review. Automated tests check the app's Sun and Earth directions against
SPICE truth vectors and JPL Horizons. The long-term Sun and Earth visibility is compared with
the LOLA team's maps when the data is built. The results of both checks are shown in the app
on the *Validation & assumptions* page.

## Links

- Repository (MIT licence): <https://github.com/localizedprojects/CLPS-MOON-BROWSER>
- Web app: <https://localizedprojects.github.io/CLPS-MOON-BROWSER/>
- Android app (APK, Android 7.0 or newer):
  <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/latest/download/lunar-horizon.apk>
- Demo video: to be added
- Brief for judges: [judge_one_pager.md](judge_one_pager.md)

## Team and challenge

To be completed by the team.
