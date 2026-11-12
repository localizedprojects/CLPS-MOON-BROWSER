# Lunar Horizon 1.14.1: Whole Moon place names and fixes

Compare lunar landing sites and dates by when the Sun (power) and Earth (direct-to-Earth radio) are above the local horizon: the south pole first, and the whole Moon too. NASA Space Apps entry. Not an official NASA product.

**Download:** `lunar-horizon.apk` (Android 7.0 or newer, phones with 32- or 64-bit ARM, 61.2 MB). No internet permission: everything runs on the phone, the Whole Moon data included.
**Web app:** <https://localizedprojects.github.io/CLPS-MOON-BROWSER/>

> **Already have 1.14.0, 1.13.3, 1.13.2, 1.13.1, 1.13.0 (or a 1.9.2–1.12.0 test APK)?** Install this over it: it updates in place and keeps your settings.
>
> **Have an older Lunar Horizon from GitHub (1.0–1.2)?** Uninstall it first. That version is signed with a different key, so Android refuses to update it. The installer says "App not installed" and does not say why. Your goal choice is the only setting you lose.

No v1.13.4, v1.13.5 or v1.14.0 release was published, so these notes also summarize 1.14.0 (which includes 1.13.4 and 1.13.5).

## New in 1.14.1

- **Whole Moon place names.** Each of the 20 Whole Moon sites' position line now names its place, such as "26.13° N, 3.63° E · Hadley–Apennine" for Apollo 15, and the screen reader reads it. Every name is quoted from a www.nasa.gov or science.nasa.gov page (case, accents and dashes aside), and that page is listed with the site's sources.
- **Whole Moon map:** *Zoom in* works on the first tap, even while the map is still gliding, and more sites are named directly on a phone's map. A name taken out of a "+n" stack is placed only where it is nearer its own marker than any other, and its leader line crosses no other marker, chip or name.
- **The south-pole map keeps its zoom and pan** after a visit to the Whole Moon and back.
- **Scorecard CSV of a mixed shortlist:** when the shortlist mixes the south pole and the Whole Moon, the CSV has no rank column (there is no single ranking), and its Whole Moon rows give each site's lat, lon and its own horizon source.
- **The known issue "Screen readers during Play on Android 7" is resolved:** it was not a fault in the app. Any accessibility client that reads the screen, including the tool used to check it, brings back the bars that Play had hidden, and on the Android 7 emulator every check matched the screen shown while it ran.
- **The south pole is unchanged:** its sites, data, rankings and texts are the same as in 1.14.0.

## 1.14.0 in short: Whole Moon

- **A South pole | Whole Moon switch on Explore.** The app still starts at the south pole. Whole Moon adds 20 sites where missions landed (the six Apollo Lunar Modules, Luna 16, 17, 21 and 24, Surveyor 1, 3 and 7, Chang'e-3 to -6, SLIM, Chandrayaan-3's Vikram and Blue Ghost Mission 1), with coordinates from the LROC "Anthropogenic Features on the Moon" shapefile (Wagner et al. 2017).
- **A shaded whole-Moon map** with where Earth is ever above a flat horizon, and each region ranked on its own: an automatic choice never mixes them. The **Pole vs the rest** card and a Learn page compare the two.
- **Site pages** (Overview, Sky & time, the Lander's view) at the Whole Moon sites, with horizons from SLDEM2015 near the site and LOLA LDEM_64 further out; **Compare** shows a "Mixed regions" banner when you add sites from both; **custom spots** from 80°N to just north of 80°S, labelled approximate with their measured error.
- **Checked like the pole:** the Sun and Earth directions at 10 Whole Moon sites agree with JPL Horizons.
- From 1.13.4 and 1.13.5: Tab and the focus ring reach the goal cards, the bottom bar, the time slider and the web addresses, Light map labels that glide during Play, the sky now on Site › Overview, and Lander's view labels that keep clear of the Sun and Earth.
- The Light & shadow map, the LOLA long-term visibility cross-check, the Blender skyline cross-check and the Python library stay south-pole only. There is no north-pole region.

## Notes

- Sun and Earth positions come from NASA/JPL SPICE (DE440), terrain from LRO LOLA (the polar DEMs, LDEM_16 and LDEM_64) and SLDEM2015, site coordinates from LRO LROC, all checked against JPL Horizons (see Learn › Can I trust these numbers?).
- The charts need Android System WebView (or Chrome) 51 or newer, which every Android 7.0+ phone has. On older WebViews they show a short "update your WebView" message instead.
- The demo videos (30 s and the 3:16 tour) were recorded on 1.13.0, show the south pole only, and stay attached to the v1.13.3 release.

**SHA-256** of `lunar-horizon.apk`:
`bf423875be27b5f3ee52eb2495a04568d22a4aff2888ba6645f960991c2be128`
