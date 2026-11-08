# Store listing texts and form answers (Lunar Horizon 1.13.5)

Everything to paste into Google Play Console and App Store Connect for the first upload of
version 1.13.5. Nothing here has been uploaded: the store accounts are opened by an account owner who
meets Google's and Apple's age requirements ([release_checklist.md](../release_checklist.md#accounts)). The form answers follow the
checklist's [Store forms](../release_checklist.md#store-forms) section.

Every claim below is checked against the app (its Learn texts and `app/lib`), the
[README](../../README.md), [judge_one_pager.md](../judge_one_pager.md) and
[submission.md](../submission.md). The descriptions never imply NASA endorsement and end with the
app's own line: "Made for the NASA Space Apps Challenge. Not an official NASA product."

**Counts.** Each field shows *characters used / store limit*. A count is the number of Unicode
characters in the text block, line breaks included, measured with Python's `len()`. Paste the text
inside the block exactly (without the fence lines). If you change a text, count it again.

Links used below:
- Web app: <https://localizedprojects.github.io/CLPS-MOON-BROWSER/>
- Repository (MIT licence): <https://github.com/localizedprojects/CLPS-MOON-BROWSER>
- Privacy policy: <https://localizedprojects.github.io/CLPS-MOON-BROWSER/privacy/>

---

## Google Play

### App name (13/30)
```text
Lunar Horizon
```
This matches the name under the app icon (`android:label`).

### Short description (78/80)
```text
Compare Moon south-pole landing sites and dates by sunlight and Earth in view.
```

### Full description (3812/4000)
```text
Lunar Horizon compares landing sites and dates at the Moon's south pole by two things a lander needs: sunlight for solar power, and Earth above the horizon for direct radio contact. At the pole the Sun stays within about 1.6° of the horizon, so nearby hills and crater rims decide both. Lunar Horizon works out when the Sun and Earth are above each site's real terrain horizon and turns that into a plain answer.

What it does
• Ranks 19 south-pole sites for your dates and names the top pick: Artemis III candidate regions, well-lit points from research, and mission sites (the IM-1 and IM-2 landers, the VIPER area, and unofficial candidate points for Chang'e-7 and LUPEX).
• Finds the best landing window: for a surface mission of 1 to 30 days, the earliest landing times that keep the Sun and Earth above the skyline for the whole mission.
• Sky & time: a sky plot of the site's skyline with the Sun's and Earth's paths, a timeline, and countdowns to sunset and Earthset with the solar power right now.
• Light & shadow: computed sunlight, Earth in view and shadow on the terrain map, for any moment from 2025 to 2035.
• Lander's view: a 3D look around the horizon from 2 m above the ground, with a raised viewpoint to read the terrain (labelled approximate).
• Compare 2 to 4 sites with a score you can adjust (Balanced, Power first or Earth contact first) and see worked out step by step.
• Test your own spot: tap the map inside 80°S or type coordinates, and its horizon is computed on your device (labelled lower fidelity).
• Mission settings: the period, a 2 m lander or a 10 m mast, three rules for when the Sun counts as up, and an optional Deep Space Network check.
• Lunar eclipses: the part of the Sun hidden behind Earth does not count as sunlight.
• Export CSV tables (their header records the data and rules used) and chart images.
• Learn: plain explanations, a glossary, how the score works, and an "Explain as I go" switch.

Who it is for
Students, teachers and anyone curious about the Moon get a plain answer first. Space fans and mission planners can turn on exact numbers.

Can you trust the numbers?
The Sun and Earth directions agree with JPL Horizons to within 0.0016 arcminutes at worst (8,688 checks; the Sun's disk is about 32 arcminutes wide). Long-term sunlight and Earth visibility are compared with the LOLA team's own maps. The app shows these checks under Learn › Can I trust these numbers?, and every approximation is labelled on screen.

What it leaves out
Only sunlight and Earth line of sight are modelled. Power is an estimate from the visible part of the Sun, and Earth contact means line of sight, not a radio link. Ice, temperature and landing safety are not modelled. The Artemis III sites are approximate region centres, not official landing points.

Data sources and credits
• NASA/JPL NAIF SPICE: Sun and Earth positions (DE440 ephemeris) and the Moon's orientation.
• LRO LOLA: terrain heights and long-term visibility maps from the Lunar Orbiter Laser Altimeter on NASA's Lunar Reconnaissance Orbiter, from the NASA Planetary Data System (PDS) Geosciences Node.
• JPL Horizons: independent Sun and Earth positions used to check the app.
• Site positions: NASA, LRO LROC images and published studies, with the sources listed in the app.

Private and offline
All the data is built in and the app does its calculations on your phone or tablet, so it works offline. It asks for no permissions, not even internet access. No accounts, no ads, no purchases, no tracking, and no data collected.

Accessible: screen-reader labels on every control, large tap targets, and shapes as well as colours for the Sun, Earth and both.

Open source (MIT licence): github.com/localizedprojects/CLPS-MOON-BROWSER

Made for the NASA Space Apps Challenge. Not an official NASA product.
```

### Category, contact and links
| Field | Value |
|---|---|
| App or game | App |
| Category | Education |
| Tags (optional) | Pick the closest offered to astronomy, space and science |
| Contact email (shown publicly) | `<OWNER: contact email>`, filled in by the account owner (not invented here) |
| Website | <https://localizedprojects.github.io/CLPS-MOON-BROWSER/> |
| Privacy policy | <https://localizedprojects.github.io/CLPS-MOON-BROWSER/privacy/> |
| Price | Owner's choice (the app has no ads and no in-app purchases) |

### What's new in 1.13.4 (486/500)
From the 1.13.4 release notes, shortened. No v1.13.4 release was published; for the 1.13.5 upload,
add the main 1.13.5 changes from its release notes and keep the text within 500 characters.
```text
• Keyboard and screen readers: Tab starts at the top bar and shows a clear focus ring on the goal cards, bottom bar and time controls (and reaches the web links), Escape closes the licence and Validation pages, and the Site views are read as tabs.
• Lander's view: the seven controls fit in one row on most phones and in two even rows on the smallest.
• Learn › Credits opens every open-source licence the app uses.
• The status line makes the Sun's height and the countdowns stand out.
```

### Data safety (Play Console › App content › Data safety)
| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Encryption in transit, data deletion requests | Not asked once the answer above is No (the Android app has no internet permission) |
| Result shown on the listing | "No data collected", "No data shared with third parties" |

Why No is right: the app sends nothing anywhere. The three settings it remembers (the goal, whether
the time controls are hidden, which short guides were seen) stay on the device. Exported CSV and PNG
files go to the share sheet only when the user asks, which Play does not count as collection or
sharing.

Permissions in the 1.13.4 APK (`aapt2 dump permissions`; run it again on the 1.13.5 APK before uploading): only AndroidX's internal
`<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, the app's own signature permission, which users
never see or grant. There is no `INTERNET` permission in release builds (only the debug and profile
manifests add it).

### Content rating (IARC questionnaire)
| Question | Answer |
|---|---|
| Category | Reference, News, or Educational |
| Violence, fear, sexuality, crude humour, bad language | No |
| Drugs, alcohol, tobacco | No |
| Gambling (real or simulated) | No |
| Users can interact or exchange content (chat, voice, images) | No |
| Shares the user's location with other users | No |
| Lets users buy digital goods | No |
| Is a web browser or search engine | No |
| Expected result | Everyone / PEGI 3 / USK 0 (IARC 3+), the "Everyone / 4+" in the checklist |

### Other App content declarations
| Declaration | Answer |
|---|---|
| Ads | No ads |
| App access | All functionality is available without special access (no sign-in) |
| Target audience | Ages 13 and over (13–15, 16–17, 18+), which keeps the app outside the Families policy; choose younger groups only if the owner wants to target children and accept that policy |
| Advertising ID | Not used |
| News app, government app, financial features, health features | No / none |

---

## App Store (App Store Connect)

### Name (13/30)
```text
Lunar Horizon
```
This matches `CFBundleDisplayName`. If App Store Connect says the name is taken, a fallback is
`Lunar Horizon: South Pole` (25).

### Subtitle (28/30)
```text
Moon south-pole site planner
```

### Promotional text (156/170)
```text
Which Moon south-pole site has sunlight and Earth in view, and when? Find the best landing window for a 1 to 30 day mission, computed over the real terrain.
```

### Description (3846/4000)
```text
Lunar Horizon compares landing sites and dates at the Moon's south pole by two things a lander needs: sunlight for solar power, and Earth above the horizon for direct radio contact. At the pole the Sun stays within about 1.6° of the horizon, so nearby hills and crater rims decide both. Lunar Horizon works out when the Sun and Earth are above each site's real terrain horizon and turns that into a plain answer.

What it does
• Ranks 19 south-pole sites for your dates and names the top pick: Artemis III candidate regions, well-lit points from research, and mission sites (the IM-1 and IM-2 landers, the VIPER area, and unofficial candidate points for Chang'e-7 and LUPEX).
• Finds the best landing window: for a surface mission of 1 to 30 days, the earliest landing times that keep the Sun and Earth above the skyline for the whole mission.
• Sky & time: a sky plot of the site's skyline with the Sun's and Earth's paths, a timeline, and countdowns to sunset and Earthset with the solar power right now.
• Light & shadow: computed sunlight, Earth in view and shadow on the terrain map, for any moment from 2025 to 2035.
• Lander's view: a 3D look around the horizon from 2 m above the ground, with a raised viewpoint to read the terrain (labelled approximate).
• Compare 2 to 4 sites with a score you can adjust (Balanced, Power first or Earth contact first) and see worked out step by step.
• Test your own spot: tap the map inside 80°S or type coordinates, and its horizon is computed on your device (labelled lower fidelity).
• Mission settings: the period, a 2 m lander or a 10 m mast, three rules for when the Sun counts as up, and an optional Deep Space Network check.
• Lunar eclipses: the part of the Sun hidden behind Earth does not count as sunlight.
• Export CSV tables (their header records the data and rules used) and chart images.
• Learn: plain explanations, a glossary, how the score works, and an "Explain as I go" switch.

Who it is for
Students, teachers and anyone curious about the Moon get a plain answer first. Space fans and mission planners can turn on exact numbers.

Can you trust the numbers?
The Sun and Earth directions agree with JPL Horizons to within 0.0016 arcminutes at worst (8,688 checks; the Sun's disk is about 32 arcminutes wide). Long-term sunlight and Earth visibility are compared with the LOLA team's own maps. The app shows these checks under Learn › Can I trust these numbers?, and every approximation is labelled on screen.

What it leaves out
Only sunlight and Earth line of sight are modelled. Power is an estimate from the visible part of the Sun, and Earth contact means line of sight, not a radio link. Ice, temperature and landing safety are not modelled. The Artemis III sites are approximate region centres, not official landing points.

Data sources and credits
• NASA/JPL NAIF SPICE: Sun and Earth positions (DE440 ephemeris) and the Moon's orientation.
• LRO LOLA: terrain heights and long-term visibility maps from the Lunar Orbiter Laser Altimeter on NASA's Lunar Reconnaissance Orbiter, from the NASA Planetary Data System (PDS) Geosciences Node.
• JPL Horizons: independent Sun and Earth positions used to check the app.
• Site positions: NASA, LRO LROC images and published studies, with the sources listed in the app.

Private and offline
All the data is built in and the app does its calculations on your iPhone or iPad, so it works offline. It asks for no permissions; iOS asks only if you choose to save an exported chart to Photos. No accounts, no ads, no purchases, no tracking, and no data collected.

Accessible: VoiceOver labels on every control, large tap targets, and shapes as well as colours for the Sun, Earth and both.

Open source (MIT licence): github.com/localizedprojects/CLPS-MOON-BROWSER

Made for the NASA Space Apps Challenge. Not an official NASA product.
```

### Keywords (93/100)
Comma-separated, no spaces after commas. Words already in the name and subtitle (lunar, horizon,
moon, south, pole, site, planner) are left out because Apple indexes those anyway. Trademarks
(NASA, Artemis) are left out too (App Review Guideline 2.3.7).
```text
landing,sunlight,earth,terrain,shadow,space,astronomy,lander,solar,eclipse,crater,science,map
```

### URLs, category, copyright
| Field | Value |
|---|---|
| Support URL | <https://github.com/localizedprojects/CLPS-MOON-BROWSER> (questions go to its Issues, as the privacy policy says) |
| Marketing URL | <https://localizedprojects.github.io/CLPS-MOON-BROWSER/> |
| Privacy Policy URL | <https://localizedprojects.github.io/CLPS-MOON-BROWSER/privacy/> |
| Primary category | Education |
| Secondary category | Reference |
| Copyright | `<OWNER: year and name>`, filled in by the account owner |
| Price | Owner's choice (no in-app purchases) |

### Age rating (answers for 4+)
Answer **None** or **No** to every question:
- Features: parental controls, age assurance, unrestricted web access (the app opens no web pages;
  the lander-photo addresses are plain selectable text), user-generated content, messaging and chat,
  advertising: **No**.
- Mature themes (profanity or crude humour, horror or fear, alcohol, tobacco or drugs): **None**.
- Medical or wellness topics: **None / No**.
- Sexuality or nudity: **None**.
- Violence (cartoon, realistic, graphic, weapons): **None**.
- Chance-based activities (simulated gambling, contests, gambling, loot boxes): **None / No**.
- Made for Kids: **No**.

Expected rating: **4+**.

### App Privacy
| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** |
| Label shown on the listing | **Data Not Collected** |
| Tracking | None (no App Tracking Transparency prompt) |

### Export compliance
`ITSAppUsesNonExemptEncryption` is already `false` in `app/ios/Runner/Info.plist`, so App Store
Connect does not ask the encryption question for each build. The app makes no network connections
and has no encryption of its own.

### App Review information
| Field | Value |
|---|---|
| Sign-in required | No |
| Contact | `<OWNER: name, phone, email>` (seen only by Apple) |
| Notes | "No account or network is needed: all data is bundled and every calculation runs on the device. On first launch the app asks what matters most (for example Balanced), ranks the 19 sites and opens Explore; short guides then explain each screen. Made for the NASA Space Apps Challenge; not an official NASA product. The NASA data credits are under Learn › Credits." |

### What's New
The first App Store version has no "What's New" field. For a TestFlight "What to Test" note, use the
Play text above (every line applies on iPhone and iPad too).

---

## Screenshots and graphics

The images are the real 1.13.0 web build (`version.json` 1.13.0, build 21) showing real computed
data: no placeholder data, no device frames and no added text. They are not in the repository (about
28 MB); see [How the screenshots were made](#how-the-screenshots-were-made) to make them again.

Every set shows the same session: site **Malapert peak (MP1)**, goal **Balanced**, period **Next 12
months**, **2 m lander**, with the clock pinned to **2026-11-03 12:00 UTC**, so every device shows the
same numbers.

| Store | Folder | Pixels | Orientation |
|---|---|---|---|
| Play | `screens/play/phone/` | 1080x1920 | portrait |
| Play | `screens/play/tablet-7in/` | 1152x2048 (9:16) | portrait |
| Play | `screens/play/tablet-10in/` | 2560x1440 (16:9) | landscape |
| App Store | `screens/appstore/iphone-6.9in/` | 1320x2868 | portrait |
| App Store | `screens/appstore/iphone-6.5in/` | 1284x2778 | portrait |
| App Store | `screens/appstore/ipad-13in/` | 2752x2064 | landscape |
| Play | `play/feature-graphic-1024x500.png` | 1024x500 | feature graphic |
| Play | `play/icon-512.png` | 512x512 | store icon |

All screenshots are PNG, RGB without alpha, 0.18–1.98 MB each. The 10-inch tablet and 13-inch iPad
sets are landscape: at those widths the app uses its two-pane layout (list beside map, Overview beside
Sky & time). Both stores accept landscape at these sizes.

### Screenshot order and captions
Upload in this order. The captions are optional (neither store has a caption field; use them as
alt text or as overlay text if you add any) and are true for every device unless the row says
otherwise.

| File | Caption (optional) | What it shows |
|---|---|---|
| `01-explore.png` | 19 south-pole sites on real LOLA terrain | The south-pole map with the 19 site markers (overlapping ones grouped with a count) on shaded relief from NASA LOLA elevations. The map's note "Shaded relief computed from NASA LOLA laser-altimeter elevations (320 m per pixel)" shows below it on every set except the Play phone, where it falls just below the shot. The landscape tablets (10-inch, iPad) also show the top pick beside the map: "Best spot for the next 12 months: Malapert peak (MP1)", Sun and Earth both up 42% of the time, longest stretch with both 16 d 4 h from 8 Oct 2027, and the selected-site card (42%, longest night 6 d 23 h). On phones and the 7-inch tablet that card is below the map, out of shot. |
| `02-best-window.png` | Find the best landing window for your mission | "Best landing window in your dates" for a 14-day mission: land 16 Nov 2026 07:30 to 17 Nov 2026 08:30 UTC, suggested landing 17 Nov 2026 02:00 UTC, mission ends 1 Dec 2026 02:00 UTC, "Covers the whole mission". The two-pane tablets also show the sky plot. |
| `03-sky-time.png` | Phones, 7-inch: "The Sun and Earth above the real skyline". 10-inch, iPad: "A year of Sun and Earth in one timeline" | Phones and 7-inch: the sky plot at the suggested landing, 17 Nov 2026 02:00 UTC (Earth 3.17° and Sun 1.47° above level), above the time bar and "Next good stretch (24 h+ of Sun + Earth): 13 Dec 2026 · in 26 d 7 h · lasts 15 d 3 h". On the iPhones and the 7-inch tablet the status "Power + Earth in view now" also shows just above the time bar, its next line (Sun 1.5° above level, 0.4° above the hills; sunset in 57 d 22 h) partly under the bar; on the Play phone the status is under the bar. 10-inch and iPad: the Timeline full screen (the sky plot is already in 02): Sun 7058 h, Earth in view 4911 h, both 3700 h over the next 12 months. |
| `04-light-shadow.png` | Computed light and shadow for any moment | The light and shadow map around Malapert peak (MP1), layer Both, 17 Nov 2026 02:00 UTC, with the bearing labels "Earth 1° above the hills" and "Sun at the skyline"; on most sets a note that the shadows come from a 400 m terrain grid is in shot too. Only the 10-inch tablet also has the legend in shot: of the area within 64 km, Sun + Earth 3%, Sun only 5%, Earth only 36%, neither 55%. |
| `05-lander-sun.png` | Look around from the lander | The Lander's view from 2 m, facing the Sun: "Sun · az 91.3° · el +1.5° in view" above the skyline, with Earth's bearing (357°) marked at the left edge. |
| `06-lander-1km.png` | Raise the viewpoint to read the terrain | The Lander's view full screen from 1 km above the site, a labelled drawing aid: the Sun and Earth status stays the lander's at 2 m. |
| `07-compare.png` | Compare sites with a score you can check | Compare, top 3: "Best for your priorities", Malapert peak (MP1) and IM-1 Odysseus (landed) tied at 62 / 100 (Malapert 0.1 point ahead before rounding), with the Side by side chart. |
| `08-trust-checks.png` | Checked against JPL Horizons and LOLA maps | "Can I trust these numbers?": Sun and Earth directions against JPL Horizons, worst case 0.0016′ (the Sun's disk is about 32′ wide); long-term sunlit time against the NASA LOLA team's maps, 1.98 points average difference over 18.6 years; skylines against an independent ray tracer, mean 0.04° (16 of 19 preset sites). |

The extra folder `screens-extra/<store>/<device>/06-lander-1km-inpage.png` holds the same raised view
inside the Light & shadow page instead of full screen, if you prefer it for 06.

**Feature graphic** (`play/feature-graphic-1024x500.png`): the app icon, the name "Lunar Horizon",
the line "When and where the Sun and Earth stay up at the Moon's south pole", the words "SUN · EARTH ·
REAL TERRAIN HORIZON", and a crop of the app's computed light and shadow map at Malapert peak (MP1),
captioned as such. **Icon** (`play/icon-512.png`): the app icon at 512x512.

### How the screenshots were made
1. **Build.** From `app/` on the release commit: `flutter build web --release` (base href `/`), then
   check that `build/web/version.json` reads the release version. Serve it locally:
   `python3 -m http.server <port>` from `app/build/web` (run in the background; stop it by its PID).
2. **Browser.** Playwright with its Chromium, launched with `--use-gl=swiftshader
   --enable-unsafe-swiftshader --ignore-gpu-blocklist` (software WebGL, for the charts), a fresh
   persistent profile per device (so the first-launch flow runs), touch enabled, and this viewport,
   device scale factor and user agent per device:

   | Set | CSS viewport | Scale | Output | User agent |
   |---|---|---|---|---|
   | Play phone | 432x768 | 2.5 | 1080x1920 | Android 14, Pixel 8, Chrome 126 (mobile) |
   | Play 7-inch tablet | 576x1024 | 2 | 1152x2048 | Android 14, Pixel Tablet, Chrome 126 |
   | Play 10-inch tablet | 1280x720 | 2 | 2560x1440 | Android 14, Pixel Tablet, Chrome 126 |
   | iPhone 6.9" | 440x956 | 3 | 1320x2868 | iPhone, iOS 18 Safari |
   | iPhone 6.5" | 428x926 | 3 | 1284x2778 | iPhone, iOS 18 Safari |
   | iPad 13" | 1376x1032 | 2 | 2752x2064 | iPad, iOS 18 Safari |

   The Play phone uses 432x768 at 2.5 rather than 360x640 at 3: the output is the same 1080x1920, but
   more of each screen fits.
3. **Clock.** An init script shifts `Date` so the page's clock reads 2026-11-03 12:00 UTC at load
   (every set then shows the same "Next 12 months" numbers). It changes only the starting time; the
   data and calculations are the app's own.
4. **Drive the app** through its accessibility tree: after load, click Flutter's
   `flt-semantics-placeholder` to turn semantics on, then find controls by their labels. On first
   launch pick *Balanced* and wait for the ranking to finish (*See this site* appears); click through
   any feature guide before a shot. Then:
   01 Explore as it opens; 02 *See this site* › *Find the best landing window*, scrolled to "Best
   landing window in your dates"; 03 *Show me the landing* (Sky & time), scrolled to the sky plot; in
   the two-pane layout, *Open the Timeline full screen* instead; 04 *Light & shadow* › layer *Both*,
   view *Around the site* (time controls folded if they cover the map); 05 view *Lander* › *Face the
   Sun*; 06 *View height* › *1 km above the site* › *Open the Lander's view full screen*; 07 *Compare*
   › *Compare the top 3 sites*, scrolled to "Best for your priorities"; 08 *Learn* › *See the checks*.
   Before each shot wait until nothing is loading and no guide is open.
5. **Finish.** Save as PNG, flatten to RGB with no alpha (the stores reject alpha in screenshots), and
   check each file's pixel size, format and size (under 8 MB).
