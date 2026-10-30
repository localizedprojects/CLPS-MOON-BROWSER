# Lunar Horizon: 30-second demo video

The cut for the Space Apps project demo video. It is **silent**, with **burned-in English
captions**, and runs 30 s or less. Record it from the web build
(<https://localizedprojects.github.io/CLPS-MOON-BROWSER/>); the longer, spoken version is
[demo_script.md](demo_script.md).

## Before recording

- Use the release web build (1.9.2 or later) in a desktop browser window about 1440 × 900,
  with the default settings: next 12 months, 2 m lander, goal **Balanced**.
- Rehearse once in the same browser profile, opening Explore, Site (each tab) and Learn, so
  the first-visit feature guides have been seen and do not cover the controls on the take.
  Shot 1 needs the first-launch goal question, so record it separately in a fresh private
  window.
- Times are UTC. The app recomputes everything for "the next 12 months" from the day you
  record, so the top pick, its numbers and the suggested landing time can differ from the
  screenshots in the README. Show what the app gives on the day; never edit the numbers.
- If the landing window card says no 14-day mission fits for the top pick, keep that site
  and set the mission length to 7 days before recording shot 3, so the caption stays true.
- Captions: white IBM Plex Sans on a solid `#060B16` band (opaque, below the app picture, so nothing shows through), lower third,
  at least 4.5:1 contrast, on screen for the whole shot.

## Shots

| # | Time | Caption (burned in) | Show (exact app state) |
|---|---|---|---|
| 1 | 0:00–0:04 (4 s) | Which lunar south-pole site, and when, gives sunlight and Earth contact? | First launch, the goal question "What matters most for your mission?". At about 0:03 tap **Balanced**. |
| 2 | 0:04–0:09 (5 s) | 19 sites ranked by Sun and Earth above the real skyline. | **Explore** once the ranking has finished: the map with the ranked sites and the top-pick card ("Sun and Earth both up N% of the time" and its longest stretch with both). Default dates (next 12 months), goal Balanced. |
| 3 | 0:09–0:15 (6 s) | Best landing window: Sun and Earth up for the whole mission. | Tap **See this site** on the top-pick card (Site › **Overview** of the top pick), then **Find the best landing window** (14-day mission). Hold on the result: the landing span, the suggested landing time and the Sun and Earth lines. |
| 4 | 0:15–0:21 (6 s) | Computed light and shadow over NASA LOLA terrain at landing. | Tap **Show me the landing** (Sky & time opens at the suggested landing; cut this), then the **Light & shadow** tab. The time stays at the suggested landing. View **Around site** (labelled **Site** in narrower windows, as in the 1280 px recording), layer **Both**. Hold still; do not scrub. |
| 5 | 0:21–0:26 (5 s) | The lander's view facing the Sun (approximate, 400 m terrain). | Same site and time. Switch the view to **Lander**, then tap **Face the Sun**. Keep the approximation badge in frame. |
| 6 | 0:26–0:29.9 (3.9 s) | Checked against NASA JPL Horizons: worst error 0.0016 arcminutes. | **Learn** › **Can I trust these numbers?** › **See the checks**, which opens *Validation & assumptions*. Frame the "In short" rows: directions vs NASA JPL Horizons (worst case) and long-term sunlit time vs the NASA LOLA team's maps. |

Total: 29.9 s (30 s or less). Captions are 9 to 11 words each.

## Notes for the edit

- Cut on the taps; do not show the loading scene or the Sky & time tab in between.
- Shot 6's caption quotes the value the page shows (0.0016 arcminutes at 1.9.0, the worst
  of the Sun and Earth checks in `app/assets/data/validation.json`, `app_vs_horizons`). If
  the page shows a different value, use that value.
- Shot 5: the Lander's view uses the light map's own 400 m terrain and computed light; it
  is approximate and labelled so in the app. The caption says so too.
- Put the title, links and credits in the video description (see
  [submission.md](submission.md)), not in the 30 s.
