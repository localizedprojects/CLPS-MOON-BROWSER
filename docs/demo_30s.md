# Lunar Horizon: 30-second demo video

The cut for the Space Apps project demo video. It has **burned-in English captions**, an
original piano soundtrack with soft UI sounds (no voice), and runs 30 s or less. It ends on
the app's animated logo. Record it from the web build
(<https://localizedprojects.github.io/CLPS-MOON-BROWSER/>); the longer version is
[demo_script.md](demo_script.md).

## The finished cut (1.13.0)

- `lunar-horizon-demo-30s-v1.13.0.mp4`: 29.97 s (899 frames at 30 fps), 1440 × 1040 (the
  1440 × 900 app picture above the caption band), H.264 video with AAC stereo sound. It was
  recorded on 4 November 2026 from the 1.13.0 web build, with the app's clock on 2 November
  2026 (UTC). Upload notes and the video description: [submission.md](submission.md#demo-video).
- Sound: "South Pole Light", an original slow piano piece, with soft tap and whoosh sounds
  on the taps and cuts. The credits are in [submission.md](submission.md) (Soundtrack of the
  demo videos).
- Shots 3, 4 and 5 were shortened (by 0.7 s, 1.3 s and 0.3 s) to make room for the end card.
  The captions did not change.
- End card: the app's own icon builds up with "Lunar Horizon" and "Made with AI assistance
  (Claude Code)" under it, then holds still to the end.

## Before recording

- Use the release web build (1.13.0 or later) in a desktop browser window about 1440 × 900,
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
| 3 | 0:09–0:14.3 (5.3 s) | Best landing window: Sun and Earth up for the whole mission. | Tap **See this site** on the top-pick card (Site › **Overview** of the top pick), then **Find the best landing window** (14-day mission). Hold on the result: the landing span, the suggested landing time and the Sun and Earth lines. |
| 4 | 0:14.3–0:19 (4.7 s) | Computed light and shadow over NASA LOLA terrain at landing. | Tap **Show me the landing** (Sky & time opens at the suggested landing; cut this), then the **Light & shadow** tab. The time stays at the suggested landing. View **Around site** (labelled **Site** in narrower windows), layer **Both**. Hold still; do not scrub. |
| 5 | 0:19–0:23.7 (4.7 s) | The lander's view facing the Sun (approximate, 400 m terrain). | Same site and time. Switch the view to **Lander**, then tap **Face the Sun**. Keep the approximation badge in frame. |
| 6 | 0:23.7–0:27.6 (3.9 s; caption to 0:27.3) | Checked against NASA JPL Horizons: worst error 0.0016 arcminutes. | **Learn** › **Can I trust these numbers?** › **See the checks**, which opens *Validation & assumptions*. Frame the "In short" rows: directions vs NASA JPL Horizons (worst case) and long-term sunlit time vs the NASA LOLA team's maps. |
| End | 0:27.3–0:29.97 (2.6 s) | None: the card carries its own text. | The end card fades in over 0:27.3–0:27.6, under shot 6's last 0.3 s, and covers the whole frame, caption band included. The logo is finished at 0:28.6 and holds to the end. |

Total: 29.97 s (899 frames; 30 s or less). Captions are 9 to 11 words each.

## Notes for the edit

- Cut on the taps; do not show the loading scene or the Sky & time tab in between.
- Shot 6's caption quotes the value the page shows (0.0016 arcminutes at 1.13.0, the worst
  of the Sun and Earth checks in `app/assets/data/validation.json`, `app_vs_horizons`). If
  the page shows a different value, use that value.
- Shot 5: the Lander's view uses the light map's own 400 m terrain and computed light; it
  is approximate and labelled so in the app. The caption says so too. Keep the height button
  at **2 m** (the lander's own eye): from 200 m, 1 km or 5 km the view says "… up,
  not the lander's", and the caption would no longer hold. The README's Lander shots are from
  1 km.
- The end card is the only text after shot 6: the name and the AI label. Put the title,
  links and the other credits in the video description (see [submission.md](submission.md)),
  not in the 30 s.
