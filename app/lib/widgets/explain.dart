/// Explain mode: plain-language glossary terms (tap or hover) and short
/// "what am I looking at" cards for each view.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'sheets/explain_sheet.dart';
import 'site_card.dart' show FocusRingInkWell;

const glossary = <String, String>{
  'Azimuth': 'Compass direction along the horizon, measured clockwise from north (0°) through east (90°). '
      'Near the south pole "north" means directly away from the pole.',
  'Elevation': 'Angle above (+) or below (−) the flat local horizon. Near the pole the Sun never climbs more than a few degrees.',
  'Terrain horizon': 'The skyline formed by real mountains and crater rims (from NASA LOLA laser altimetry). '
      'The Sun or Earth must rise above this line, not just above 0°, to be seen.',
  'Libration': 'The Moon\'s slight rocking as seen from Earth (about ±7°). It makes Earth bob up and down in the lunar sky '
      'over each month, so polar sites see Earth only part of the time.',
  'DTE': 'Direct-to-Earth communication: radio contact straight to Earth without a relay satellite. It needs Earth above '
      'the local terrain horizon (and a ground antenna on Earth that can see the Moon).',
  'DSN': 'NASA\'s Deep Space Network: big antennas in Goldstone (USA), Madrid (Spain) and Canberra (Australia). '
      'Turn on "Require a DSN station in view" in Mission settings to also need one of them to see the Moon at least '
      '10° up (checked on the hourly data, so to about ±30 minutes).',
  'Upper limb': 'The top edge of the Sun\'s disk. Counting the Sun as "up" when any part of the disk shows is how '
      'NASA\'s LOLA illumination maps define sunlight.',
  'PSR': 'Permanently shadowed region: crater floors the Sun never reaches, cold traps that may hold water ice.',
  'Power proxy': 'Sunlight on a solar panel that faces the Sun: 1361 W/m² at 1 au, scaled by distance and '
      'by how much of the Sun\'s disk is visible above the terrain.',
  'SPICE': 'NASA/JPL toolkit used by mission navigators to compute where planets, moons and spacecraft are. '
      'This app uses SPICE with the DE440 ephemeris and the Moon\'s precise orientation.',
  'Good day': 'A UTC day on which the Sun and Earth are both up together for at least half of the day.',
  'Longest night': 'The longest unbroken stretch in your chosen dates with no sunlight at the spot. Batteries and '
      'heaters have to last at least this long.',
};

/// A tappable/hoverable jargon word with a dotted underline (a link, so it
/// takes the interaction colour, not a meaning colour).
class Term extends StatelessWidget {
  final String term;
  final String? label;
  const Term(this.term, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final def = glossary[term] ?? '';
    final name = label ?? term;
    void open() => showExplain(context, term);
    return Tooltip(
      message: def,
      preferBelow: false,
      showDuration: const Duration(seconds: 8),
      // the wrapper replaces the InkWell's semantics, so it carries the tap too
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: '$name: show definition',
        onTap: open,
        child: FocusRingInkWell(
          borderRadius: BorderRadius.circular(PH.radius),
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                widthFactor: 1,
                child: Text(name,
                    style: const TextStyle(
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: PH.ice,
                        color: PH.ice,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Short explanation card shown above a view in Explain mode. Depth from tone
/// only (a lighter inset with one uniform radius): no hairlines or coloured
/// edge bars, which also keeps debug painting free of the "borderRadius can
/// only be given on borders with uniform colors" assertion.
class ExplainCard extends StatelessWidget {
  final String title;
  final String body;
  final List<String> terms;
  const ExplainCard({super.key, required this.title, required this.body, this.terms = const []});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: PH.panelHi, borderRadius: BorderRadius.circular(PH.radiusInner)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.school_outlined, size: 18, color: PH.muted, semanticLabel: 'Explanation'),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: PHText.body.copyWith(fontWeight: FontWeight.w600, height: 1.35))),
              ]),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 13, height: 1.5, color: PH.text)),
              if (terms.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 2, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Glossary', style: TextStyle(fontSize: 13, color: PH.muted, fontWeight: FontWeight.w600)),
                  for (final t in terms) Term(t),
                ]),
              ],
            ]),
          ),
        ),
      );
}

const explainSky = ExplainCard(
  title: 'Sky plot: where the Sun and Earth are, as seen from the site',
  body:
      'Imagine lying on your back at the landing site. North (away from the pole) is at the top, the centre is overhead, and '
      'the grey band is the real mountain skyline. A filled marker means the body counts as up under your rules; a hollow '
      'one means it does not count: it is hidden behind terrain, or only part of it is above the skyline and your rule '
      'needs more (or, with the DSN rule on, no DSN station can see the Moon). The radial scale is stretched near the '
      'horizon because polar Sun and Earth stay within a few degrees of it.',
  terms: ['Azimuth', 'Elevation', 'Terrain horizon', 'Libration'],
);

const explainTimeline = ExplainCard(
  title: 'Timeline: when you have power, contact with Earth, or both',
  body: 'Solid lines show how high the Sun and Earth are; dotted lines show the terrain skyline in their direction. When a solid '
      'line is above its dotted line, that body is visible. The bars underneath summarise it: amber = sunlight (power), '
      'blue = Earth in view (communications), hatched teal = both at once, the best time to operate. Tap to jump there.',
  terms: ['Upper limb', 'DTE', 'Power proxy'],
);

const explainLight = ExplainCard(
  title: 'Light & shadow map: the real terrain, lit for the selected moment',
  body: 'The terrain comes from NASA\'s LOLA laser-altimeter elevations of the south pole. For the moment on the time slider, '
      'the app traces sunlight, and the line of sight to Earth, across that terrain and paints what is lit and what is in '
      'shadow. Warm white means full sunlight (brighter on slopes facing the Sun), amber stripes mean only part of the Sun '
      'peeks over a ridge, and dark means shadow; ground in shadow is drawn faintly with artificial shaded relief so you can '
      'still see its shape. The arrows at the selected site point toward the Sun and Earth. Near the pole the Sun skims the '
      'horizon, so even modest hills cast shadows tens of kilometres long.',
  terms: ['Terrain horizon', 'Upper limb', 'PSR'],
);

const explainExplore = ExplainCard(
  title: 'Explore: the best spot, and how the others compare',
  body: 'The top card names the site with the best score over your chosen dates. The score weighs sunlight, Earth in view, '
      'both together and how long the nights and outages last, by the goal you pick under "What matters most?". Below it, '
      'each site has bars for sunlight, Earth in view and both together, and its longest night. Switch to the map to see '
      'where the sites are, or hold anywhere on it to test a spot of your own.',
  terms: ['Terrain horizon', 'Longest night'],
);

const explainOverview = ExplainCard(
  title: 'Site overview: one spot at a glance',
  body: 'The picture is the computed light and shadow around the site at the start of its best stretch. The three big '
      'numbers say how often it has sunlight, Earth in view, and both. "Which days work?" marks every good day, and "Plan for '
      'the dark" gives the longest night its batteries must survive. "At a glance" says what the place is, why it is on '
      'the list, what to watch out for and how it ranks: catalogue sites are described from published sources, your own '
      'spots by the app from its numbers.',
  terms: ['Good day', 'Longest night'],
);

const explainCompare = ExplainCard(
  title: 'Compare: which site is best for your mission?',
  body: 'Each site gets a score from 0 to 100. Pick what matters most (Balanced, Power first, Earth contact first or Both at '
      'once), or open Fine-tune to set the weights yourself. The winner card shows the exact sum behind its score, and "Good '
      'days by month" counts the days each site has the Sun and Earth up together for at least half the day.',
  terms: ['Power proxy', 'DTE', 'DSN'],
);
