# Space Apps submission

The facts to paste into the NASA Space Apps project page. Each one is checked against the
repository; the [README](../README.md) has the details and sources.

> **Before pasting.** The field names and character limits come from the 2026 Project
> Submission Guide, which is published on 13 November 2026. The sections below follow the
> fields of earlier years' form. Trim each answer to fit the 2026 limits then. Notes in quote
> blocks like this one are for the team and are not part of the answers. The form takes plain
> text, so paste the words without the Markdown marks (backticks, asterisks); the video
> description and the Use of AI answers are already plain text. This file is public and linked
> from the README and the judges' brief: delete the team notes once they are done.

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

## Demo video

> **Hosted.** The labelled 30-second cut (`lunar-horizon-demo-30s-v1.13.0.mp4`, 29.97 s, end card
> "Made with AI assistance (Claude Code)") and the tour are attached to the v1.13.3 GitHub release:
> <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/download/v1.13.3/lunar-horizon-demo-30s-v1.13.0.mp4>. That link needs no login but downloads the file rather than playing it in the
> page; a YouTube or Google Drive upload of the same file, with the title and description below,
> plays in the browser. Use whichever link the form accepts.

**Title:** Lunar Horizon: which Moon south-pole site, and when? (30-second demo)

**Description:**

```text
Lunar Horizon is a free, open-source planner for the Moon's south pole. It shows which landing site, on which dates, gets sunlight for power and a direct line of sight to Earth, computed from NASA/JPL SPICE ephemerides and LRO LOLA terrain data.

This 30-second demo shows the real web app, version 1.13.0, with its clock on 2 November 2026 (so "next 12 months" starts then): the goal question, 19 sites ranked by Sun and Earth above the real skyline, the best landing window for a 14-day mission at the top pick (Malapert peak, MP1), the computed light and shadow over LOLA terrain at the suggested landing, the lander's view facing the Sun (approximate, 400 m terrain), and the check against JPL Horizons.

Web app: https://localizedprojects.github.io/CLPS-MOON-BROWSER/
Code (MIT licence): https://github.com/localizedprojects/CLPS-MOON-BROWSER

Made with AI assistance: Claude Code (Anthropic's AI coding agent) recorded this video by driving the real app in a headless browser, so every frame of the app is a real screenshot of it running. AI-written code edited it and added the captions (written by AI and checked against the screen), the camera moves, crossfades, highlights and tap rings, and the end card, which animates the app's own icon. No image, video, music or voice generation model was used. The results on screen (the percentages, times, light map and lander's view) are computed by the app from NASA data, not made by AI.

Music: "South Pole Light", an original piano piece composed for Lunar Horizon by Claude Code, which wrote its notes as code. Piano sound: FluidR3_GM SoundFont by Frank Wen (MIT License). UI sounds: synthesised for this video by AI-written code.
```

**Line for the optional tour:** `Full tour (3:16), with captions: the question, when to land, Sky & time, light & shadow, Compare, your own spot and Learn. https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/download/v1.13.3/lunar-horizon-tour-v1.13.0.mp4`

## Links

- Repository (MIT licence): <https://github.com/localizedprojects/CLPS-MOON-BROWSER>
- Web app: <https://localizedprojects.github.io/CLPS-MOON-BROWSER/>
- Android app (APK, Android 7.0 or newer):
  <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/latest/download/lunar-horizon.apk>
- Demo video (30 s): <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/download/v1.13.3/lunar-horizon-demo-30s-v1.13.0.mp4>
- Full tour (3:16): <https://github.com/localizedprojects/CLPS-MOON-BROWSER/releases/download/v1.13.3/lunar-horizon-tour-v1.13.0.mp4>
- Brief for judges:
  <https://github.com/localizedprojects/CLPS-MOON-BROWSER/blob/main/docs/judge_one_pager.md>

> The APK link serves the latest GitHub release, v1.13.3 (7 November 2026), the same version as
> the web app.

## Project details

**What it does.** Lunar Horizon helps choose where and when to land near the Moon's south
pole. There the Sun stays within about 1.6° of the horizon, so mountains and crater rims
decide when a lander gets sunlight for power and when it can see Earth for direct radio
contact. For 19 preset sites (8 Artemis III candidate regions, 5 ESA Lunar Lander candidate
points from a published study, and 6 mission sites, including the IM-1 and IM-2 landers and the
VIPER area) and for any spot the user picks inside 80°S, the app:

- ranks the sites for the chosen dates (by default the next 12 months; the data covers
  2025–2035) by how often the Sun, the Earth and both are above the real terrain horizon, with
  a transparent score the user can adjust;
- finds the best landing window for a 1- to 30-day surface mission that keeps the Sun and Earth
  above the skyline for the whole mission;
- shows a sky plot of the terrain skyline with the Sun's and Earth's paths, a timeline, a
  good-days calendar, and the longest night that batteries and heaters must last;
- draws a computed light-and-shadow map and a 3D lander's view for any moment;
- compares two to four sites side by side, and exports CSV files that record their sources,
  and PNG charts.

**How it works.** An offline Python pipeline (SpiceyPy, NumPy) computes the apparent Sun and
Earth directions hourly for 2025–2035 from NASA/JPL SPICE kernels (DE440, `MOON_ME` frame,
light time and aberration), when a Deep Space Network station has the Moon in view, and each
preset site's horizon, ray-marched through LRO LOLA elevation models (80 m, then 240 m, with
rays out to 600 km). The app ships these compact results (about 10.5 MB) and does the rest on
the device, in a pure-Dart core: site geometry, the visible fraction of the Sun's and Earth's
disks against the jagged horizon (16-strip integration), lunar eclipses, a power proxy, the
metrics, the score, horizons for custom spots (from 400 m terrain) and the light-and-shadow
map. The charts are a render-only React + Plotly bundle. Every approximation is labelled in
the app.

**Benefits and intended impact.**

- **Mission planners** (for example for CLPS landers, Artemis and international missions) can
  compare candidate sites and dates on the two things a south-pole lander needs first: solar
  power and a direct line of sight to Earth. The landing-window finder, the longest night,
  the longest time without Earth and the exportable numbers support early site and date
  selection and first power and communication budgets.
- **Trust is checkable.** The Sun and Earth directions agree with JPL Horizons to within
  0.0016′, and the long-term visibility is compared with the LOLA team's maps. The app shows
  these checks on its *Validation & assumptions* page.
- **Students and the public** get a plain answer first, with explanations next to each view,
  a glossary and a Learn section.
- **Open and light:** free and open source (MIT), with no account and no server needed. The
  same calculations are also a Python library (`pylib/`).
- **Scope:** it is a planning and teaching aid. It does not assess landing hazards, ice,
  temperature or link budgets.

**Tools.** Claude Code, Anthropic's AI coding agent (see Use of AI); Git and
GitHub (repository, Actions for CI, Pages for the web app); the Flutter SDK 3.44.6 with Dart
3.12.2; the Android SDK and emulators; Node.js 24 and npm; Python 3.12 and 3.14; Blender 5.1
(the skyline cross-check only); and, for the demo videos, Playwright with headless Chromium,
FFmpeg 6.1.1 and FluidSynth 2.3.4.

**Coding languages.** Dart (the app and its science core), Python (the data pipeline, the
`lunarhorizon` library and tools) and TypeScript with React (the charts), plus small amounts
of Kotlin (Android host), Swift (iOS host), HTML and CSS, shell and PowerShell (install
scripts) and YAML (CI). The video tooling used Python and JavaScript; it is not in the
repository.

**Hardware.** None needed. The app runs in a modern web browser on a computer, tablet or
phone, and as an Android app on Android 7.0 or newer. It was developed on a laptop (CPU only)
with Android emulators.

**Software and libraries.**

- App: Flutter / Dart, with `provider`, `webview_flutter` and `webview_flutter_android`,
  `shared_preferences`, `share_plus`, `archive`, `intl` and `web` (`app/pubspec.yaml`).
- Charts: React 19, Plotly.js (`plotly.js-basic-dist-min`), Vite with
  `vite-plugin-singlefile`, TypeScript and Vitest (`charts/package.json`).
- Pipeline: SpiceyPy 8.2.0 (the NAIF CSPICE toolkit), NumPy 2.5.3, SciPy 1.18.1, Pillow
  12.3.0, Requests 2.34.2 and pytest 9.1.1 (`pipeline/requirements.txt`).
- Fonts: IBM Plex Sans and IBM Plex Mono; Roboto in the web build.
- Licences are listed under References.

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
- **Lander photos (linked, not bundled):** the IM-1 and IM-2 site pages link to NASA's pages
  with each lander's own surface photos (© Intuitive Machines) and LRO's photos of the landers
  from orbit (NASA/Goddard/Arizona State University).

## Space agency partner data

None. Lunar Horizon uses no dataset from a Space Apps partner agency. All of its data
products are NASA's (listed above).

Three groups of preset sites take their coordinates from published sources outside NASA.
They are cited as references, not used as partner-agency data:

- **ESA Lunar Lander candidate sites** (5 points: SR1, CR1, SV1, MP1, GR1): from De Rosa et al.
  (2012), a peer-reviewed paper on ESA's Lunar Lander project (Table 2). These are coordinates
  printed in a paper, not an ESA dataset.
- **Chang'e-7 (China):** an unofficial, secondhand candidate point (88.8°S, 123.4°E) from a
  Wikipedia article that cites a social-media post. The sources checked give no official
  landing coordinates.
- **LUPEX / Chandrayaan-5 (ISRO and JAXA):** an unofficial candidate point (89.45°S,
  137.15°W) from a space newsletter's report of an ISRO talk at IAC 2024.

The app marks both international points as low confidence and as not announced landing
coordinates. The terrain, Sun and Earth calculations use NASA data for every site.

## References

File paths below are in the repository, <https://github.com/localizedprojects/CLPS-MOON-BROWSER>.

**NASA data**

- NASA/JPL NAIF SPICE generic kernels: <https://naif.jpl.nasa.gov/pub/naif/generic_kernels>
  (`naif0012.tls`, `pck00011.tpc`, `moon_de440_250416.tf`, `moon_pa_de440_200625.bpc`,
  `de440s.bsp`, `earth_1962_260806_2126_combined.bpc`, `de442s.bsp`).
- LRO LOLA, from the PDS Geosciences Node:
  - `LDEM_80S_80M`: <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/polar/img/ldem_80s_80m.img>
  - `LDEM_75S_240M`: <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/polar/img/ldem_75s_240m.img>
  - `LDEM_75S_120M`: <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/polar/img/ldem_75s_120m.img>
  - `AVGVISIB_75S_120M_201608` (Sun): <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/extras/illumination/img/avgvisib_75s_120m_201608.img>
  - `AVGVISIB_75S_120M_201608_EARTH`: <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/extras/illumination/img/avgvisib_75s_120m_201608_earth.img>
  - The same maps are on the LOLA team's mirror: <https://imbrium.mit.edu/EXTRAS/ILLUMINATION/IMG>
  - The maps follow the method of Mazarico, E., et al. (2011), "Illumination conditions of
    the lunar polar regions using LOLA topography", *Icarus* 211:1066–1081,
    doi:10.1016/j.icarus.2010.10.030: <https://doi.org/10.1016/j.icarus.2010.10.030>
- JPL Horizons API: <https://ssd.jpl.nasa.gov/api/horizons.api> (48 responses cached in
  `pipeline/validation/horizons_cache/`).
- JPL, *DSN Telecommunications Link Design Handbook* (810-005), module 301: the DSS-14, DSS-63
  and DSS-43 positions.

**Site coordinates** (each site's full source list, with URLs and notes, is in
`app/assets/data/sites.json`)

- NASA, "NASA Provides Update on Artemis III Moon Landing Regions" (28 October 2024):
  <https://www.nasa.gov/news-release/nasa-provides-update-on-artemis-iii-moon-landing-regions/>
- Henriksen et al. (2023), "Optimized Illuminated Terrain Coverage of the Candidate Artemis III
  Landing Sites with LROC NAC Controlled Mosaics", ELS 2023 abstract:
  <https://sservi.directus.app/assets/2483b7e0-a336-443d-8739-3d5f4756e1fb.pdf>
- LROC NAC controlled mosaics (Arizona State University and NASA Goddard): one product page per
  Artemis III region on data.lroc.im-ldi.com, listed per site in `sites.json`.
- De Rosa et al. (2012), "Characterisation of potential landing sites for ESA's Lunar Lander
  project", *Planetary and Space Science* 74:224–246: <https://arxiv.org/pdf/1208.5587>
- LROC images of the landers: IM-1 <https://lroc.im-ldi.com/images/1360>; IM-2
  <https://www.lroc.im-ldi.com/images/1408>; IM-2 landing region and target
  <https://lroc.im-ldi.com/images/1401>
- Beyer et al. (2025), "VIPER Site Analysis", *Planetary Science Journal* 6(10):236,
  doi:10.3847/PSJ/ae061a: <https://iopscience.iop.org/article/10.3847/PSJ/ae061a>
- Chang'e-7 (unofficial point): Wikipedia, "Chang'e 7":
  <https://en.wikipedia.org/wiki/Chang%27e_7>
- LUPEX / Chandrayaan-5 (unofficial point): *Indian Space Progress*, issue 25 (4 April 2025):
  <https://jatan.space/indian-space-issue-25/>

**Lander photos** (linked from the app, not bundled; links, dates and credits in
`app/lib/content/lander_photos.dart`)

- <https://www.nasa.gov/image-article/odysseus-lands-on-the-moon/>
- <https://science.nasa.gov/image-article/apod-2024-march-2-odysseus-on-the-moon/>
- <https://www.nasa.gov/missions/lro/nasas-lro-images-intuitive-machines-odysseus-lander/>
- <https://www.nasa.gov/news-release/nasa-receives-some-data-before-intuitive-machines-ends-lunar-mission/>
- <https://www.nasa.gov/image-article/nasas-lunar-reconnaissance-orbiter-views-im-2-on-moons-surface/>

**Software** (licences as stated by the installed packages)

- Flutter SDK (BSD 3-Clause). Dart packages: `provider` and `archive` (MIT);
  `webview_flutter`, `webview_flutter_android`, `shared_preferences`, `share_plus`,
  `intl` and `web` (BSD 3-Clause).
- Inlined in the chart bundle (`app/assets/charts/index.html`): React and React DOM (MIT,
  Copyright (c) Meta Platforms, Inc. and affiliates) and Plotly.js, as
  `plotly.js-basic-dist-min` (MIT, Copyright (c) Plotly Technologies Inc.). Build tools:
  Vite, `@vitejs/plugin-react`, `vite-plugin-singlefile` and Vitest (MIT), and TypeScript
  (Apache 2.0).
- Pipeline: SpiceyPy (MIT), on NAIF's CSPICE toolkit; NumPy (BSD 3-Clause); SciPy (BSD);
  Pillow (MIT-CMU); Requests (Apache 2.0); pytest (MIT).
- Used as tools only (none of them ships with the app): Blender 5.1 (Cycles) for the skyline
  cross-check; Playwright (Apache 2.0) with headless Chromium, FFmpeg 6.1.1 and FluidSynth
  2.3.4 (LGPL 2.1 or later) for the demo videos.

**Fonts**

- IBM Plex Sans and IBM Plex Mono, Copyright © 2017 IBM Corp., SIL Open Font License 1.1
  (`app/assets/fonts/`, and the `@fontsource` packages in the chart bundle).
- Roboto, Apache License 2.0 (`app/web/fonts/roboto/LICENSE.txt`).

**Soundtrack of the demo videos**

- Music: "South Pole Light", an original solo piano piece composed for Lunar Horizon by
  Claude Code, which wrote its chords and melody note by note as data in a Python script
  (with small seeded random variation in timing and loudness) and turned them into MIDI. It
  does not quote or adapt any existing song or melody.
- Piano sound: the FluidR3_GM SoundFont by Frank Wen (MIT licence), from the Debian/Ubuntu
  package `fluid-soundfont-gm` (upstream:
  <http://www.musescore.org/download/fluid-soundfont.tar.gz>).
- UI sounds (taps, whooshes, chimes): synthesised with NumPy and SciPy by code that Claude
  Code wrote, with no samples or recordings.
- Mixed by Python scripts that Claude Code wrote (NumPy, SciPy, mido, pyloudnorm) and FFmpeg.

**AI tool**

- Claude Code, by Anthropic: <https://claude.com/claude-code>

**Code licence:** MIT (<https://github.com/localizedprojects/CLPS-MOON-BROWSER/blob/main/LICENSE>).
The full list of third-party licences is in <https://github.com/localizedprojects/CLPS-MOON-BROWSER/blob/main/THIRD_PARTY_NOTICES.md>, and the README credits the data under Data sources and credits:
<https://github.com/localizedprojects/CLPS-MOON-BROWSER#data-sources-and-credits>

## Use of AI

> **Form label.** The 2026 FAQ uses "Super Intelligence (SI)" for AI: "Each team's project
> submission must include a description of how SI tools were used during the development of
> their project." (<https://www.spaceappschallenge.org/resources/participant-faqs/>, read 7 November 2026). If the form labels this field "SI", paste
> the same answer there. The answers below keep the word "AI".

```text
Lunar Horizon was built with Claude Code, Anthropic's AI coding agent. The team set the goals, chose the features and options, and reviewed the results. Claude Code wrote essentially all of the code (the Flutter/Dart app and its science core, the Python data pipeline, the React charts, the Python library, the tests and the CI workflows) and the documentation, including the app's own text (Learn, the glossary and the explanations). It also ran the tests, the Android emulator checks and independent AI review passes. Claude Code research agents found the preset sites' published coordinates and sources by web search, and separate AI agents fact-checked them; the same process drafted the site descriptions shown in the app, each listed with its sources. The app's icon and logo are drawn by a script that Claude Code wrote, and Claude Code agents captured the screenshots from the real app.

Claude Code agents also made the demo videos. They recorded the real web app by driving it in a headless browser, so every frame of the app is a real screenshot of it running. AI-written code then edited the cuts and added the captions (written by AI and checked against the screen), the camera moves, crossfades, highlights and tap rings, and the end card, which animates the app's own icon. The music, "South Pole Light", is an original piano piece that Claude Code composed by writing its notes as code; FluidSynth played it with the FluidR3_GM piano SoundFont (MIT licence). The UI sounds were synthesised by AI-written code. Both videos end on a card that reads "Made with AI assistance (Claude Code)", and their file metadata (comment, description and the keyword "AI-assisted") describes the same AI use.

Not AI output: the results. Claude Code wrote the code, but every visibility, power and timing result in the app (its numbers, charts, maps and terrain views) is computed by that deterministic code from NASA data (NAIF SPICE DE440, LRO LOLA terrain), not produced by an AI model. The Sun and Earth directions are checked against SPICE and 48 JPL Horizons responses, the long-term visibility against the LOLA team's maps, and the light map against the site horizons (82–94% agreement); the app shows these checks under Validation & assumptions. Claude Code wrote code, text and the music's notes; no image, video, music or voice generation model was used, there is no voice in the videos, and no NASA insignia appears.
```

**Short version** (for a tight field):

```text
Claude Code (Anthropic's AI coding agent) wrote the code, tests and documentation, researched the site sources (fact-checked by separate AI agents) and made the demo videos and their music, with the team setting the goals and reviewing the results. The videos end on a "Made with AI assistance (Claude Code)" label. The results are not AI output: every visibility number, chart and map is computed by that code from NASA SPICE and LOLA data, and the Sun and Earth geometry is checked against JPL Horizons and the LOLA team's maps.
```

## Team and challenge

**Team name:** NASASTARS

**Challenge:** Lunar Landing Site Navigator (NASA Space Apps Challenge 2026):
<https://www.spaceappschallenge.org/2026/challenges/lunar-landing-site-navigator/>

> **Team check.** The challenge title above was copied from the official challenge page on
> 7 November 2026; pick that challenge in the form.

> **Rules for the team.** From the Participant FAQ (<https://www.spaceappschallenge.org/resources/participant-faqs/>), the
> home page (<https://www.spaceappschallenge.org/2026/>) and the Terms
> (<https://www.spaceappschallenge.org/legal/>), all read on 7 November 2026:
>
> - **When:** submission opens on Saturday 14 November at 9:00 AM and closes on Sunday
>   15 November at 11:59 PM local time. Submit "according to the ending time of your Local
>   Event", from the Project tab of the team's page.
> - **Read first:** the Project Submission Guide, the Judging and Awards Guide and the
>   challenge's resources come out on 13 November. Cite any resource you use: "You must cite
>   every source that is used in the creation of your project, even if it is open source or
>   freely available."
> - **Team:** "Teams may have no more than six (6) members". A Universal Event team needs "at
>   least two (2)" people to be eligible for global judging. "You may only be on one team and
>   teams are only permitted to work on one challenge."
> - **Under 18:** such participants "must be registered for the event by a parent or legal
>   guardian and must be accompanied by a parent or legal guardian at all times during the
>   event". They should not "Upload a photo of themselves as their Avatar or as part of their
>   Team page", nor "Use photo, video, voices, or likenesses of themselves or others under the
>   age of 18 in their project demonstration or project submission". The Terms add:
>   "Recognizable names, voices, and likenesses of persons under the age of 18 should not be
>   included in any submission." Use the team name or handles in the submission, not real
>   names.

## Development history (draft for the team)

> **Draft, not for pasting yet.** The Participant FAQ says: "Teams are not allowed to begin
> working on the challenges prior to the hackathon."
> (<https://www.spaceappschallenge.org/resources/participant-faqs/>, read 7 November 2026.)
> The dates below are before the hackathon of 14–15 November 2026. Before the event, ask the
> Local Lead, or the NASA Space Apps GO Team at info@spaceappschallenge.org, whether this
> project can be entered, and whether and how to state these facts in the submission. That
> is the team's decision. Keep every fact below unchanged and visible.

- Planning and set-up began on 8 October 2026 (`PLAN.md`, section 1).
- First commit in the public repository: `5838d00`, 14 October 2026.
- GitHub releases (Android APK): v1.0.0 on 15 October 2026; v1.1.0 and v1.2.0 on 17 October
  2026; v1.13.3 on 7 November 2026, with the APK and both demo videos, now the latest.
- 1.13.0 was `main` at `06be9e4` (4 November 2026, UTC+5:30; 3 November, 19:45 UTC).
- The demo videos were recorded on 4 November 2026 from the 1.13.0 web build, with the app's
  clock set to 2 November 2026 (UTC). On 5 November 2026 both gained the end-card label "Made
  with AI assistance (Claude Code)" and AI metadata; nothing else in them changed.
- 6 November 2026: app version 1.13.1 committed to `main`: during Play the light map's labels no
  longer jump and the time bar's controls no longer shift, and six more test files pin their dates.
  The demo videos stay as recorded on 1.13.0.
- 6 November 2026: app version 1.13.2 committed to `main`: on phones the light map's labels keep
  to the part of the map on screen, the Lander's view stays readable at large text, and Learn ›
  Credits gains a Use of AI note and the missing credits. The demo videos stay as recorded on 1.13.0.
- 6 November 2026: app version 1.13.3 committed to `main`: the light map's labels follow their
  arrows during Play and stay readable, Simple view's timeline and sky frames never cut their
  content, and the Lander's view callouts stay clear of its buttons. The demo videos stay as
  recorded on 1.13.0.
- 7 November 2026: `main` at `6f80997` (07:27 UTC), app version 1.13.3. The web app is
  deployed from `main`, so it always runs the newest version.
- All 80 commits on `main` up to `6f80997` (7 November 2026) carry a `Co-authored-by: Claude`
  trailer.
- The NASA Space Apps Challenge 2026 hackathon is on 14–15 November 2026.
