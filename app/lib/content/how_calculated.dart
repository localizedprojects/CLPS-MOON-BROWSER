/// Plain-language content for Learn › "How it's calculated".
///
/// Every number here is measured, not estimated: sources are
/// app/assets/data/validation.json, app/test/core/shadow_test.dart and
/// formula.md (each section names its formula.md section). Keep this in step
/// with README.md ("Scope", "How it works", "Validation") when they change.
library;

/// One topic on the page: what it is in plain words, the maths in a few short
/// lines, how accurate it is, and where the full derivation lives.
class CalcSection {
  final String title;
  final String plain;
  final List<String> maths;
  final String accuracy;
  final String ref;
  const CalcSection({required this.title, required this.plain, required this.maths, required this.accuracy, required this.ref});
}

/// Opening statement: what the calculations answer and how the terrain enters.
const calcScope =
    'Every calculation in this app answers one question: when do sunlight and a line of sight to Earth reach a '
    'spot near the Moon\'s south pole? The ground enters only through its shape: NASA\'s laser-measured heights '
    'give the skyline around each spot and the shadows across the map.';

/// What the app does not model (shown as a short list under the scope).
const calcNotModelled = [
  'What the ground is made of, or whether it holds water ice',
  'Temperature, dust or boulders',
  'Bumps smaller than the elevation map\'s pixels (80 m for the preset sites, 400 m for your own spots)',
  'Whether a spot is safe to land on (the slope shown is a rough guide, not a hazard check)',
];

const calcSections = <CalcSection>[
  CalcSection(
    title: 'Where the Sun and Earth are',
    plain: 'NASA/JPL\'s SPICE toolkit and the DE440 planetary ephemeris give the direction from the Moon to the Sun '
        'and to Earth, every hour from 2025 to 2035. The Moon\'s own rotation and wobble (libration) are included, as '
        'is the time light takes to travel. The app smoothly interpolates between the hourly values.',
    maths: [
      'direction = SPICE apparent position (light time + aberration, "LT+S")',
      'frame: Moon mean-Earth/polar-axis (MOON_ME, DE440)',
      'between hours: 4-point Lagrange interpolation',
    ],
    accuracy: 'Checked against JPL Horizons at 8 sites over three 30-day windows: the worst difference is 0.0016 '
        'arcminutes, about 0.1 arcseconds, roughly 20,000 times smaller than the Sun\'s disk (32 arcminutes).',
    ref: 'formula.md §1–2, §13.2–13.6',
  ),
  CalcSection(
    title: 'Looking up from the landing spot',
    plain: 'From the spot\'s position on the Moon (its height plus the 2 m or 10 m of the lander or mast), the app '
        'works out how far around the horizon (azimuth) and how high above it (elevation) the Sun and Earth appear. '
        'Near the pole, "north" means straight away from the pole.',
    maths: [
      'site → body = body vector − site vector',
      'azimuth = atan2(east, north), clockwise from north',
      'elevation = asin(up), with no atmosphere and no refraction',
    ],
    accuracy: 'The same check against SPICE at 2,000 random spots and times: worst 0.0016 arcminutes.',
    ref: 'formula.md §3',
  ),
  CalcSection(
    title: 'The mountains on the skyline',
    plain: 'Walking outward from the spot in every direction, the app reads NASA LOLA laser-altimeter heights and '
        'keeps the steepest angle up to the terrain, including the Moon\'s curvature. That traces the real skyline. '
        'The 16 preset sites use the 80 m elevation map, then the 240 m map beyond its edge, out to 600 km. Your own '
        'spots are computed on your device from the 400 m map out to 300 km (made from the 80 m map inside 80°S and '
        'LOLA\'s 120 m map beyond it, to about 75°S).',
    maths: [
      'angle to terrain = atan2((R + h)·cos θ − (R + h₀), (R + h)·sin θ)',
      'skyline(azimuth) = the largest angle along that direction',
      'R = 1737.4 km, h = terrain height, h₀ = spot height + mast, θ = distance as an angle',
    ],
    accuracy: 'On a perfectly smooth Moon it matches the exact formula to within 0.00002 arcminutes. A Blender '
        'ray-traced skyline of the same terrain agrees to 0.04° on average. Your own spots use the coarser 400 m '
        'map: typically 0.5–1.4° from the 80 m skyline, up to about 6° on sharp crater rims.',
    ref: 'formula.md §4–5, §13.7',
  ),
  CalcSection(
    title: 'How much of the Sun or Earth shows',
    plain: 'The Sun and Earth are discs, not points, so a jagged ridge can hide part of them. The app slices each '
        'disc into 16 strips and checks each strip against the skyline. You choose what counts as "up": any part of '
        'the disc (the default for the Sun), its centre (the default for Earth), or the whole disc.',
    maths: [
      'disc radius = asin(body radius ÷ distance)   (Sun about 0.27°, Earth about 0.95°)',
      'visible fraction = sum over 16 strips of the area above the skyline',
    ],
    accuracy: 'Tested against the exact area of a circle cut by a straight edge.',
    ref: 'formula.md §6',
  ),
  CalcSection(
    title: 'Solar power',
    plain: 'A rough guide to the sunlight a solar panel facing the Sun would catch: the Sun\'s brightness at the '
        'Moon\'s distance, times the part of the Sun\'s disc above the skyline.',
    maths: [
      'power = 1361 W/m² × (1 au ÷ Sun distance)² × visible fraction',
    ],
    accuracy: 'This is a proxy for comparing sites, not a power-system model: no panel efficiency, temperature or '
        'dust. A vertical panel turned toward the Sun would catch slightly less: under 0.1% less while the Sun is '
        'below 2.5° (most of the time near the pole), about 2% less at the 11° it can reach at 80°S.',
    ref: 'formula.md §7',
  ),
  CalcSection(
    title: 'Talking to Earth',
    plain: 'Direct radio contact needs Earth above the skyline. If you turn on "Require a DSN station", the app also '
        'needs one of NASA\'s Deep Space Network dishes (Goldstone, Madrid or Canberra) to see the Moon at least 10° '
        'above its own horizon.',
    maths: [
      'Earth in view = Earth\'s visible fraction meets your rule',
      'DSN = Moon\'s elevation ≥ 10° at any of the three stations (Earth orientation: ITRF93)',
    ],
    accuracy: 'The DSN check is precomputed hourly; at 10- and 30-minute steps each sample uses the nearest hour.',
    ref: 'formula.md §8',
  ),
  CalcSection(
    title: 'The light & shadow map',
    plain: 'For the moment you pick, the app sweeps the Sun\'s and Earth\'s light across the whole elevation map, '
        'row by row along the light\'s direction, and marks every pixel the terrain blocks. Slopes facing the Sun are '
        'drawn brighter. The close-up uses the 400 m map over 128 km; the whole region uses an 800 m map.',
    maths: [
      'a pixel is lit if its height ≥ the highest terrain toward the light, minus distance × tan(light elevation)',
      'run for the Sun\'s top edge, its bottom edge, and Earth\'s centre',
      'brightness of lit slopes is proportional to max(0, surface normal · light direction)',
    ],
    accuracy: '"Sunlit or not" agrees with the per-site skyline calculations 94% of the time for the close-up '
        '(87% against the sharper 80 m skylines) and 91% for the whole region (82%), over 960 checks.',
    ref: 'formula.md §12',
  ),
  CalcSection(
    title: 'Turning it into numbers',
    plain: 'The app repeats the calculation through your chosen period (every 10 minutes for up to 60 days, every '
        '30 minutes up to a year, hourly beyond) and counts: the share of time with sunlight, with Earth in view, '
        'and with both; the longest stretch of each; and the longest night and the longest gap without Earth.',
    maths: [
      '% sunlit = sunlit samples ÷ all samples',
      'longest night = the longest unbroken run with no sunlight',
      'a "good day" = Sun and Earth up together for at least half of that UTC day',
    ],
    accuracy: 'Over 18.6 years, our share of sunlit time agrees with the LOLA science team\'s own illumination maps '
        'to 1.8 percentage points on average for the landing regions.',
    ref: 'formula.md §9, §11.5, §13.9',
  ),
  CalcSection(
    title: 'The score',
    plain: 'Each site gets a score from 0 to 100 that you can re-weight. "Power" mixes sunlit time with how short the '
        'longest night is; "Comms" mixes Earth time with how short the longest outage is; "Both" is the time with '
        'Sun and Earth together. The goal buttons just set the weights, and the app shows the exact sum.',
    maths: [
      'score = (1 − b) × [a × Power + (1 − a) × Comms] + b × Both',
      'Power = 0.6 × % sunlit + 0.4 × night survival',
      'Comms = 0.6 × % Earth + 0.4 × outage tolerance',
      'night survival, outage tolerance: 100 for no gap, falling to 0 at a 30-day gap',
      'Balanced a 0.5, b 0.25 · Power first a 0.8, b 0.2 · Earth contact first a 0.2, b 0.2',
    ],
    accuracy: 'The score is a transparent way to compare sites, not a mission requirement. Change the weights to '
        'match your mission.',
    ref: 'formula.md §10, §11.6–11.7',
  ),
  CalcSection(
    title: 'At a glance',
    plain: 'The Overview of every site has a short card: what the place is, why it is on the list (or what stands '
        'out), what to watch out for and how it compares. For a catalogue site, the description comes from published '
        'sources, checked claim by claim, and the card lists them. That text never states a number the app computes, '
        'such as a share of sunlight, a distance from the pole or a slope: those come from the app. For your own spots, '
        'and for any site without checked text, every sentence is a fixed template filled with the app\'s own numbers, '
        'and the card says "Written by the app from its numbers". In the code the card is the "glance" engine and the '
        'checked text is "curated", because "Overview" already names the tab.',
    maths: [
      'watch out if the longest night ≥ 72 h, or Earth is out of view for ≥ 72 h at a time',
      'watch out if the slope at the point ≥ 10° on the 80 m map (a rough guide, not a hazard check)',
      'show at most 3 watch-outs; the rest are under Details',
      'stands out = better than at least half of the catalogue sites, on whole percents as shown',
      'name the nearest catalogue site within 20 km, and the nearest IAU feature centre within 60 km',
    ],
    accuracy: 'The catalogue text is only as good as its fact-check: claims the sources did not support were left '
        'out, and a person still confirms the wording. For your own spots the skyline, height and comparisons come '
        'from the 400 m map, so those lines are marked "(approx.)".',
    ref: 'formula.md §11.14',
  ),
];
