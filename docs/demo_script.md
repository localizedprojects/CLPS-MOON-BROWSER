# Lunar Horizon: 3-minute demo script

Replace each `{…}` with the value on screen on the day. Never read numbers from this file
aloud: the app recomputes them for "the next 12 months" from today's date.

**Setup.** Use the release web build, or the Android release APK on a phone, with the
default settings (next 12 months, 2 m lander). Close other tabs. Have the "Can I trust
these numbers?" page one tap away. Total: about 3:00.

**What it should look like** (version 1.9.1 web build of 30 October 2026; the dates will differ
on the day): the [landing window and Sky & time](screenshots/site-landing-sky-desktop.webp)
for Malapert peak (MP1), the [phone landing card](screenshots/landing-phone.webp) and
[Sky & time on a phone](screenshots/sky-phone.webp), the [Lander view](screenshots/lander-desktop.webp)
([on a phone](screenshots/lander-phone.webp)), and [Compare](screenshots/compare-desktop.webp).

---

## 0:00–0:20 · The question (Explore, no taps)

**Show:** the app opening on "What matters most for your mission?". Tap **Balanced**
(the sites are ranked meanwhile), and Explore appears with the top-pick card.

**Say:** "Artemis landers will go to the Moon's south pole. There the Sun skims the
horizon and mountains block it for days. A lander needs two things: sunlight for
power, and Earth above the skyline to radio home. So which spot, and when? Lunar
Horizon answers that in one screen."

**Point at:** the top pick, "Sun and Earth both up {47}% of the time", and the longest
stretch with both.

## 0:20–0:55 · When to land (tap 1: "See this site", tap 2: "Find the best landing window")

**Show:** Site › Overview. The first card asks "When should you land here?" with the
mission length already on 14 days. Tap **Find the best landing window**. A progress bar
counts the landing times it checks, then the answer: "Land any time between {date} and {date}",
the suggested landing date and time, and a verdict in words.

**Say:** "These aren't guesses. For every half hour of the next year we compute exactly
where the Sun and Earth are, with NASA/JPL's SPICE ephemeris, and check them against the
real skyline traced from NASA's laser-altimeter map. The app then slides a 14-day mission
across the year and finds the window where the lander has sunlight and Earth in view the
whole time, and lands with the most margin."

**Point at:** the Sun and Earth lines under the verdict, and the approximation badge
under the buttons. If a site has no full fit, it says so and shows the closest fit
instead, never "fits". It only suggests touchdowns with the Sun and Earth at least 0.25°
above the hills, and says so plainly if no time in the dates meets that.

## 0:55–1:30 · See it (tap 3: "Show me the landing")

**Show:** Sky & time opens at the suggested landing. The status line reads what is up at
the time shown. Below it is the **sky plot**: the site's real skyline from the LOLA
terrain, the paths of the Sun and Earth over the whole period, and their positions at the
time shown, with their heights in degrees. Under it is the **timeline**: the heights of the
Sun and Earth over the period against the skyline beneath each, with bars for when the
Sun, Earth and both together are up.

**Say:** "This is the sky from the landing site, looking up. The filled shape is the
real horizon, mountains included. Where the Sun's or Earth's path rises above it, that body
is up. The timeline shows the same thing over the year: whenever a curve is above its
skyline line, the bar below is filled. Touch a chart to see it alone, full screen (the X closes it); the time bar moves the time."

**Point at:** the Sun and Earth markers on the sky plot, then the "Both" bar on the
timeline. Press Play for a few seconds, then pause. (For a plain-words version, the
**Simple view** switch shows short answers like "Sun + Earth
together: NOW · … more" and "Where to look".)

## 1:30–2:10 · See it on the terrain (tab: "Light & shadow", then "Lander")

**Show:** the Light & shadow tab, around the site. Scrub a few hours forward and watch
the shadows swing. Switch to "Both".

**Say:** "Here is the same moment over 128 km of real terrain: everything the Sun
reaches, and where Earth is in view. Near the pole even small hills cast shadows tens of
kilometres long, which is why a few hundred metres can decide a landing site."

**Then, about 12 s: the Lander's view.** Switch the view from "Around site" to
**Lander** (the same label on a phone), then tap **Face the Sun**. Leave the time where it is.

**Say:** "And this is what the lander itself would see, looking at the Sun. The terrain
and the light are the map's own: the same 400 m heights and the same computed sunlight,
so it is approximate, and the badge says so."

**Point at:** the Sun on the skyline and the approximation badge.

## 2:10–2:30 · Compare and decide (Compare)

**Show:** Compare with the top 3 shortlisted. The chart under "Best for your priorities"
says "Best: {site}" (or "almost tied with {site}" when the scores are close), with one
block per site: sunlight, Earth and Sun + Earth bars and the longest dark. Tap "Earth
contact first" and the order changes live.

**Say:** "Different missions weigh power and communications differently. The score is
not a black box: the line under the chart says exactly how it is weighted, and you can
re-weight it."

## 2:30–2:50 · Your own spot (Explore › Map)

**Show:** tap near a crater rim, then "Check this spot". The "Your spot" card appears
under the map with its own numbers and a badge saying they are approximate.

**Say:** "Planners can test any point inside 80°S. The skyline is traced on the device
from the coarser 400 m map, and the app says so."

## 2:50–3:00 · Why you can trust it (Learn › Can I trust these numbers?)

**Show:** the validation page.

**Say:** "Every direction is checked against JPL Horizons: the worst error is about 0.1
arcseconds, roughly 20,000 times smaller than the Sun's disk. For the landing regions, our
sunlight statistics match the LOLA science team's own maps to about 2 percentage points.
And every approximation is labelled on screen."

---

## Backup lines (if asked)

- **"Is the map a photo?"** No. It is shaded relief computed from LOLA laser heights,
  with an artificial light so you can read it. The light & shadow layer is the real
  computed sunlight for the chosen moment.
- **"Can I see the exact numbers?"** Tap "Exact numbers" on any chart: the sky plot gets
  degree rings and azimuths, the timeline gets the height curves, and Compare gets the
  score stars.
- **"What don't you model?"** What the ground is made of, ice, temperature, dust,
  boulders, and landing safety. We model only when sunlight and Earth contact reach a spot.
- **"Accessibility?"** Colour always comes with a shape, pattern or word (Sun disc, Earth
  crescent, hatched diamond for both). Everything works with a keyboard and a screen
  reader, and "Explain as I go" adds plain-language notes.
