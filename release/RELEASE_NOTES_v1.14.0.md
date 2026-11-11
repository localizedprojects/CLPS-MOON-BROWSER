# Lunar Horizon 1.14.0: Whole Moon

Compare lunar landing sites and dates by when the Sun (power) and Earth (direct-to-Earth radio) are above the local horizon: the south pole first, and now the whole Moon. NASA Space Apps entry. Not an official NASA product.

**Download:** `lunar-horizon.apk` (Android 7.0 or newer, phones with 32- or 64-bit ARM, 61.2 MB). No internet permission: everything runs on the phone, the Whole Moon data included.
**Web app:** <https://localizedprojects.github.io/CLPS-MOON-BROWSER/>

> **Already have 1.13.3, 1.13.2, 1.13.1, 1.13.0 (or a 1.9.2–1.12.0 test APK)?** Install this over it: it updates in place and keeps your settings.
>
> **Have an older Lunar Horizon from GitHub (1.0–1.2)?** Uninstall it first. That version is signed with a different key, so Android refuses to update it. The installer says "App not installed" and does not say why. Your goal choice is the only setting you lose.

No v1.13.4 or v1.13.5 release was published, so these notes also cover 1.13.4 and 1.13.5.

## New in 1.14.0: Whole Moon

- **A South pole | Whole Moon switch on Explore.** The app still starts at the south pole, with Shackleton rim selected. Whole Moon adds 20 sites where missions landed: the six Apollo Lunar Modules; Luna 16, 17, 21 and 24; Surveyor 1, 3 and 7; Chang'e-3, -4, -5 and -6; SLIM; Chandrayaan-3's Vikram; and Blue Ghost Mission 1. Their coordinates come from the LROC "Anthropogenic Features on the Moon" shapefile (Wagner et al. 2017), and each site quotes its record.
- **A whole-Moon map:** near side centred, north up, shaded from LOLA heights, with a computed overlay of where Earth is ever above a flat horizon. Each marker's shape shows its group and every site is named, without covering another marker or the NEAR SIDE / FAR SIDE labels; Zoom in, Zoom out and Reset buttons. The hatched cap south of 80°S takes you back to the south pole.
- **Each region is ranked on its own** with the same "What matters most?" chips. Near the equator a site has sunlight about half the time and Earth always up (on the far side, at Chang'e-4 and Chang'e-6, never), a different trade-off from the pole, so an automatic choice never mixes them. The **Pole vs the rest** card and a Learn page, *South pole vs the rest of the Moon*, put the two side by side with computed numbers.
- **Site pages:** Overview, Sky & time and the Lander's view work at the Whole Moon sites. Their horizons come from SLDEM2015 (LOLA and JAXA Kaguya Terrain Camera, Barker et al. 2016) near the site and LOLA LDEM_64 further out; the Lander's view uses a 400 m LOLA tile and says it is approximate. Its button sits right under At a glance, and its dotted "terrain data ends" line shows only where the tile's edge is the skyline you see. On the far side the app says that Earth never rises there.
- **Compare** mixes the regions only when you add sites from both: a "Mixed regions" banner and one verdict per goal then replace the single winner, and neither the chart nor the shortlist numbers the sites as one ranking. A Whole Moon site added to the shortlist while Explore shows the south pole is ranked right away; Compare shows "N of M Whole Moon sites ranked" until its numbers are ready.
- **Custom spots** anywhere from 80°N to just north of 80°S. Their horizon is computed on the phone from a 3.8 km whole-Moon terrain grid and is labelled approximate, with its measured error.
- **Checked like the pole:** the Sun and Earth directions at 10 Whole Moon sites agree with JPL Horizons (responses cached in the repository).

## What stays south-pole only

- The Light & shadow map (the site page says so), the LOLA long-term visibility cross-check, the Blender skyline cross-check and the Python library (`pylib/`).
- There is no north-pole region, and no custom spot north of 80°N.
- The south pole itself is unchanged: its sites, data, rankings and texts are the same as in 1.13.5, apart from Learn and How it's calculated, which now describe the new region, and one more step in the Explore guide that points out the region switch.

## New in 1.13.5 (not released on its own)

- **Light map labels glide during Play** instead of hopping, and a label that changes side goes round the site.
- **Site › Overview shows the sky now:** the Sun's height and when the Sun and Earth next set or rise.
- **Lander's view labels keep clear of the Sun and Earth**, wrapping their words first.
- **Feature guides put the page back** where it was, and **focus rings follow the keyboard** everywhere.

## New in 1.13.4 (not released on its own)

- **Keyboard and screen readers:** Tab reaches the goal cards, the bottom-bar destinations, the time slider and the web addresses, each with the focus ring; Escape closes the licence and Validation pages; the Site views read as tabs.
- **Lander's view controls fit phones**, and **Learn › Credits opens every open-source licence** the app and its charts use.

## Known issue

- **Screen readers during Play on Android 7** (unchanged since 1.13.2): on an Android 7 test emulator, once Play had hidden the bars, the screen reader still placed each control where it sat with the bars shown.

## Notes

- Sun and Earth positions come from NASA/JPL SPICE (DE440), terrain from LRO LOLA (the polar DEMs, LDEM_16 and LDEM_64) and SLDEM2015, site coordinates from LRO LROC, all checked against JPL Horizons (see Learn › Can I trust these numbers?).
- The charts need Android System WebView (or Chrome) 51 or newer, which every Android 7.0+ phone has. On older WebViews they show a short "update your WebView" message instead.
- The demo videos (30 s and the 3:16 tour) were recorded on 1.13.0, show the south pole only, and stay attached to the v1.13.3 release.

**SHA-256** of `lunar-horizon.apk`:
`7656dac95cfff7d55fa96b2031872b7cc85a45ad29c02088980f53a7443046fb`
