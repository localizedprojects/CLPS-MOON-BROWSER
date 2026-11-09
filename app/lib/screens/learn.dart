/// Learn: the "Explain as I go" switch, what the tool covers (the south pole
/// by default, Whole Moon beside it, their site groups, and why the pole is
/// hard), "South pole vs the rest of the Moon" once Whole Moon is open (the
/// contrast card and four facts computed from the data, 1.14.0), three
/// "Start here" cards, what each view shows, the glossary, "Can I trust these numbers?" (validation and
/// "How it's calculated"), how the score works, keyboard shortcuts and credits.
/// Phones get one column; from 840 dp two columns of about the same height,
/// at most 1040 wide.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../core/ranking.dart';
import '../core/region.dart';
import '../core/summary.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/contrast_card.dart';
import '../widgets/explain.dart';
import '../widgets/site_card.dart' show FocusRingInkWell;
import '../widgets/site_glance_card.dart' show numSpans;
import '../widgets/web_address.dart';
import 'how_calculated.dart';
import 'validation_page.dart';
import '../widgets/feature_guide.dart';
import '../widgets/focus_semantics.dart';
import '../widgets/licence_page.dart';

/// The views explained under "What each view shows", in app order.
const learnViews = [explainExplore, explainOverview, explainSky, explainTimeline, explainLight, explainLander, explainCompare,
    explainWholeMoon];

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  /// Width from which Learn uses two columns.
  static const twoColumnWidth = 840.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= twoColumnWidth;
      final side = box.maxWidth > 1040 ? (box.maxWidth - 1040) / 2 : 0.0;
      // two columns of about the same height (the keys go with the views
      // they work), so the page does not end in one column beside a blank
      // half (1.13.5 audit: Credits alone at the bottom at 1440x900)
      const left = [_StartHere(), _Views(), _Shortcuts()];
      const right = [_TrustCard(), _ScoreCard(), _Glossary(), _Credits()];
      return ListView(
        padding: EdgeInsets.fromLTRB(16 + side, 16, 16 + side, 32),
        children: [
          const _Intro(),
          const _Coverage(),
          // full width, outside the two columns, so their order and heights
          // stay as in 1.13.5 (and nothing at all until Whole Moon is open)
          const _WholeMoonContrast(),
          if (wide)
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
              SizedBox(width: 24),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
            ])
          else ...[
            // the spec's phone order: start, views, words, trust, score, keys, credits
            // (not `...left`, which holds the keys too: they showed twice)
            const _StartHere(),
            const _Views(),
            const _Glossary(),
            const _TrustCard(),
            const _ScoreCard(),
            const _Shortcuts(),
            const _Credits(),
          ],
        ],
      );
    });
  }
}

Widget _heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Semantics(header: true, child: Text(text, style: PHText.title)),
    );

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: padding, child: child),
    );

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Semantics(header: true, child: const Text('How Lunar Horizon works', style: PHText.headline)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        child: Text(
          'It checks when sunlight and a line of sight to Earth reach spots near the Moon\'s south pole, using the real '
          'mountains around each one. Start below, or turn on short explanations next to every chart and map.',
          style: PHText.body.copyWith(color: PH.muted),
        ),
      ),
      Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: GuideTarget(id: 'learn-explain', child: SwitchListTile(
          minTileHeight: 64,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: const Text('Explain as I go', style: PHText.subtitle),
          subtitle: Text('Show a short explanation next to each chart and map', style: PHText.small.copyWith(color: PH.muted)),
          value: s.explainInline,
          onChanged: s.setExplainInline,
        )),
      ),
      Card(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        child: GuideTarget(
          id: 'learn-guides',
          child: ListTile(
            key: const ValueKey('learn-guides'),
            minTileHeight: 64,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(Icons.replay_rounded, color: PH.ice),
            title: const Text('Show the guides again', style: PHText.subtitle),
            subtitle: Text('Each screen walks you through its main buttons once more, starting with Explore',
                style: PHText.small.copyWith(color: PH.muted)),
            onTap: () {
              s.replayGuides();
              s.goTo(Dest.explore);
            },
          ),
        ),
      ),
    ]);
  }
}

/// What the catalogue covers and why: the south pole only (every site and
/// custom spot lies south of 80°S, inside the loaded LOLA terrain), what each
/// site group is, and why the pole is hard. Checked against sites.json and
/// curated_sites.json; Apollo and equatorial sites are out of scope.
class _Coverage extends StatelessWidget {
  const _Coverage();

  static const scope = 'South pole (the default): every site, and every spot you add, lies south of 80°S. That is '
      'where the app has loaded the detailed NASA LOLA terrain the skylines need, and where NASA\'s CLPS landers, Artemis '
      'and other countries\' polar missions are going. Apollo and other sites near the equator are outside it; they are '
      'in Whole Moon, below.';

  /// The Whole Moon region (1.14.0), with its groups as the site list names
  /// them (contract §2). The northern limit is the code's.
  static final wholeMoon = 'Whole Moon: landing sites elsewhere on the Moon, each region ranked on its own: Apollo '
      '(crewed landings); Robotic landers 1966–76 (Surveyor, Luna); Other countries\' programmes; Commercial (CLPS). '
      'Coordinates from the LROC catalogue of objects on the Moon, skylines from coarser whole-Moon terrain (marked '
      'approximate). You can test your own spot there up to ${globalCustomMaxLatDeg.round()}°N. Learn then sets the '
      'south pole beside the rest of the Moon, worked out for your dates.';

  /// The catalogue's groups, as the site list names them, in plain words.
  static const groups = <(String, String)>[
    ('Missions', 'IM-1 Odysseus (2024) and IM-2 Athena (2025), Intuitive Machines landers flown for NASA\'s Commercial '
        'Lunar Payload Services (CLPS), with IM-2\'s intended target; the planned area of NASA\'s VIPER rover; and two '
        'international candidates, China\'s Chang\'e-7 and ISRO-JAXA\'s LUPEX / Chandrayaan-5, which are unofficial, '
        'low-confidence points, not announced landing coordinates.'),
    ('Artemis III candidate regions', 'approximate centres of NASA\'s October 2024 regions, each about 15 by 15 km; '
        'not official landing points.'),
    ('ESA Lunar Lander candidate sites', 'from De Rosa et al. (2012), chosen there for long sunlight; candidate sites '
        'for ESA\'s planned Lunar Lander.'),
  ];

  static const addYourOwn = 'To test another spot south of 80°S, tap the Explore map or use "Add a spot by '
      'coordinates…" there; your own spots are marked approximate.';

  static const whyHard = 'Near the pole the Sun skims the horizon, so hills kilometres away cast shadows tens of '
      'kilometres long, and a lunar day lasts about 29.5 Earth days, so a shaded spot can stay dark for days or weeks. '
      'So moving a few hundred metres, or landing a few days later, can turn a sunlit spot into a dark one. '
      'The Moon\'s spin axis is tilted only about 1.5° to the plane of Earth\'s orbit, so the pole also has small '
      'seasons: over a cycle of about 346.6 days the Sun\'s height at the pole drifts between about 1.6° above and '
      '1.6° below a level horizon, so the same site can do better in some months than in others. '
      'With no air there is no twilight and no refraction, and Earth stays low in roughly the same direction, only '
      'bobbing up and down with libration.';

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('What this tool covers'),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(numSpans(scope, PHText.body)),
            const SizedBox(height: 8),
            for (final (name, what) in groups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$name: ', style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
                  numSpans(what, PHText.body.copyWith(color: PH.muted)),
                ])),
              ),
            const SizedBox(height: 8),
            Text.rich(numSpans(addYourOwn, PHText.body)),
            const SizedBox(height: 8),
            Text.rich(numSpans(wholeMoon, PHText.body), key: const ValueKey('coverage-whole-moon')),
            const _OpenWholeMoon(),
            const SizedBox(height: 16),
            // its own node, so it stays a header inside the card's merged text
            Semantics(container: true, header: true, child: const Text('Why the pole is hard', style: PHText.subtitle)),
            const SizedBox(height: 4),
            Text.rich(numSpans(whyHard, PHText.body)),
          ]),
        ),
      ]);
}

/// "Open Whole Moon" in the coverage card, while the global sites are not
/// loaded: it enters Whole Moon (which loads them) and shows Explore.
class _OpenWholeMoon extends StatelessWidget {
  const _OpenWholeMoon();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.global != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('learn-open-whole-moon'),
          onPressed: () {
            // the region loads its sites itself (and reports a failure)
            s.setRegion(Region.wholeMoon);
            s.goTo(Dest.explore);
          },
          icon: const Icon(Icons.public, size: 20),
          label: const Text(
            'Open Whole Moon',
            semanticsLabel: 'Open Whole Moon: the landing sites elsewhere on the Moon, on Explore',
          ),
        ),
      ),
    );
  }
}

/// "South pole vs the rest of the Moon" (1.14.0): the contrast card and four
/// facts, every number from the data or the core (contract §11): the highest
/// Sun and the longest night from the contrast rows, the far side from the
/// global catalogue, and how far a skyline error moves sunrise from the
/// core's `sunriseShiftMinutes`. Before Whole Moon is opened nothing global is
/// loaded (plan §3): the section is absent and the coverage card offers to
/// open it ([_OpenWholeMoon]).
class _WholeMoonContrast extends StatelessWidget {
  const _WholeMoonContrast();

  static const heading = 'South pole vs the rest of the Moon';
  static const pendingFact = 'Worked out once the sites have been computed for your dates.';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final g = s.global;
    // nothing global is loaded before Whole Moon is opened (plan §3); until
    // then the coverage card offers to open it ([_OpenWholeMoon])
    if (g == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_heading(heading), const ContrastCard(showTitle: false), _facts(contrastFactsFor(s), g.catalog.sites)],
    );
  }

  Widget _facts(ContrastFacts? f, List<Site> global) {
    final muted = PHText.body.copyWith(color: PH.muted);
    String rowFact(String key, String what) {
      final r = f?.row(key);
      if (r == null || (r.poleText.isEmpty && r.restText.isEmpty)) return pendingFact;
      String at(String v, Site? site) => v.isEmpty ? 'not known' : '$v${site == null ? '' : ' at ${site.short}'}';
      return '$what: ${at(r.poleText, r.poleSite)} at the south pole; ${at(r.restText, r.restSite)} in Whole Moon.';
    }

    final far = [
      for (final x in global)
        if (x.side == 'far') x,
    ];
    final farFact = far.isEmpty
        ? 'No far-side site is in the Whole Moon list.'
        : 'Earth never rises on the far side: ${[for (final x in far) '${x.short} sees Earth ${x.longTermEarthPct.round()}% of the time'].join(', ')} in the long-term average, so a far-side lander needs a relay satellite to talk to Earth.';

    String shiftFact() {
      final pole = f?.sunriseShift(Region.southPole), rest = f?.sunriseShift(Region.wholeMoon);
      if (pole == null && rest == null) return pendingFact;
      String at(SunriseShift? x, String where) =>
          x == null ? 'not worked out yet $where' : 'about ${duration(x.minutes / 60)} at ${x.site.short} ($where)';
      final err = contrastSkylineErrorDeg.toStringAsFixed(1);
      return 'A skyline error of $err° moves sunrise by ${at(rest, 'Whole Moon')} and by ${at(pole, 'south pole')}: '
          'away from the pole the Sun climbs steeply through the skyline, at the pole it skims along it.';
    }

    final facts = <(String, String, String)>[
      ('highest-sun', 'Highest Sun', rowFact('highestSun', 'The highest the Sun climbs')),
      ('longest-night', 'Longest night', rowFact('longestNight', 'The longest night')),
      ('far-side', 'The far side', farFact),
      ('sunrise-shift', 'A small skyline error', shiftFact()),
    ];
    final sources = <String>{for (final x in global) x.maskSource};
    final badge =
        (f == null ? null : contrastBadgeText(f)) ??
        (sources.isEmpty ? null : 'Approximate: the Whole Moon values use horizons from ${sources.join('; ')}.');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MicroLabel('FROM THE DATA'),
          const SizedBox(height: 4),
          for (final (key, title, text) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Semantics(
                container: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$title: ',
                        style: PHText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      numSpans(text, muted),
                    ],
                  ),
                  key: ValueKey('learn-fact-$key'),
                ),
              ),
            ),
          if (badge != null) ...[
            const SizedBox(height: 8),
            FidelityBadge(key: const ValueKey('learn-contrast-badge'), text: badge),
          ],
        ],
      ),
    );
  }
}

/// Three ways in, each one tap to the screen that answers it.
class _StartHere extends StatelessWidget {
  const _StartHere();

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('Start here'),
      _StartCard(
        step: 1,
        title: 'Find the best spot',
        body: 'Explore scores every site on sunlight, Earth in view and the longest night, weighted by what matters most to you, '
            'names the top one, then lists the rest.',
        action: 'Go to Explore',
        onTap: () => s.goTo(Dest.explore),
      ),
      _StartCard(
        step: 2,
        title: 'Get to know one site',
        body: 'See when it has power and contact with Earth, which days work, and the light and shadow around it.',
        action: 'Open the site',
        onTap: () => s.goTo(Dest.site, siteTab: SiteTab.overview),
      ),
      _StartCard(
        step: 3,
        title: 'Choose between a few',
        body: 'Shortlist two to four sites and say what matters most. The scores update as you change it.',
        action: 'Go to Compare',
        onTap: () => s.goTo(Dest.compare),
      ),
    ]);
  }
}

class _StartCard extends StatelessWidget {
  final int step;
  final String title, body, action;
  final VoidCallback onTap;
  const _StartCard({required this.step, required this.title, required this.body, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: '$title. $body $action',
          onTap: onTap,
          child: FocusSemantics(child: FocusRingInkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PH.radiusCard),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: PH.tonal, shape: BoxShape.circle),
                    child: Text('$step', style: statStyle(size: 15)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: PHText.subtitle),
                      const SizedBox(height: 2),
                      Text(body, style: PHText.body.copyWith(color: PH.muted)),
                      const SizedBox(height: 6),
                      Text(action, style: PHText.body.copyWith(color: PH.ice, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.chevron_right, color: PH.muted),
                  ),
                ]),
              ),
            ),
          )),
        ),
      );
}

/// The ExplainCards' text at Learn's reading size.
class _Views extends StatelessWidget {
  const _Views();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('What each view shows'),
        for (final c in learnViews)
          _card(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title, style: PHText.subtitle),
              const SizedBox(height: 6),
              Text(c.body, style: PHText.body),
              if (c.terms.isNotEmpty)
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Words:', style: PHText.small.copyWith(color: PH.muted)),
                  for (final t in c.terms) Term(t),
                ]),
            ]),
          ),
      ]);
}

class _Glossary extends StatelessWidget {
  const _Glossary();

  @override
  Widget build(BuildContext context) {
    final entries = glossary.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('Words we use'),
      _card(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const Divider(height: 1, color: PH.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.key, style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(e.value, style: PHText.body.copyWith(color: PH.muted)),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// "Can I trust these numbers?": the checks (ValidationPage) and the maths
/// ("How it's calculated").
class _TrustCard extends StatelessWidget {
  const _TrustCard();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('Can I trust these numbers?'),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'The Sun and Earth positions are checked against NASA JPL Horizons, the skylines against an exact formula '
              'and an independent ray tracer, and the long-term sunlight against the NASA LOLA team\'s own maps. '
              'Spots you add yourself use a coarser map and are marked as approximate.',
              style: PHText.body,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                onPressed: () => _push(context, const ValidationPage()),
                child: const Text('See the checks'),
              ),
              FilledButton.tonal(
                onPressed: () => _push(context, const HowCalculatedPage()),
                child: const Text('How it\'s calculated'),
              ),
            ]),
          ]),
        ),
      ]);
}

/// The score in plain words, the current weights, and (once ranked) the
/// arithmetic for the top site.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = s.weights;
    final goal = s.activeGoal;
    final top = s.rankingDone && s.rankedAll.isNotEmpty ? s.rankedAll.first : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('How the score works'),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Each site gets a score from 0 to 100 built from three parts. Power: time in sunlight, and how short the '
            'longest night is. Earth: time with Earth in view, and how short the longest gap is. Both: time with the Sun '
            'and Earth up together. "What matters most?" sets how much each part counts.',
            style: PHText.body,
          ),
          const SizedBox(height: 12),
          Text(goal == null ? 'Your own weights' : 'Now: ${goalLabel(goal)}', style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
          Text('${_cap(weightingText(w))}.', style: PHText.body.copyWith(color: PH.muted)),
          const SizedBox(height: 12),
          if (top != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: PH.sunken, borderRadius: BorderRadius.circular(PH.radiusInner)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Worked example: ${top.name}', style: PHText.small.copyWith(color: PH.muted)),
                const SizedBox(height: 2),
                Text(scoreWhy(top, w), style: PHText.body.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            )
          else
            Text('A worked example appears here once every site is ranked.', style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => s.goTo(Dest.compare),
            child: const Text('Change what matters in Compare'),
          ),
        ]),
      ),
    ]);
  }

  static String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// The Site screen's keys (bound in the shell), then the Lander's view's own
/// (LanderViewPanel, while it has focus).
class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  static const _keys = <(List<String>, String)>[
    (['Space'], 'Play or pause'),
    (['←', '→'], 'Step back or forward'),
    (['Shift', '←', '→'], 'One day back or forward'),
    (['Home', 'End'], 'Start or end of your dates'),
    (['B'], 'Jump to the best time window'),
    (['Esc'], 'Give the keys back to the page after using a button or slider'),
  ];

  /// The keys LanderViewPanel handles once it has focus (a click or tap on
  /// it); Esc then goes to the shell, which gives the keys back to the page.
  static const _landerKeys = <(List<String>, String)>[
    (['←', '→'], 'Turn left or right'),
    (['Shift', '←', '→'], 'Turn left or right in small steps'),
    (['↑', '↓'], 'Look up or down'),
    (['+', '−'], 'Zoom in or out'),
    (['S'], 'Face the Sun'),
    (['E'], 'Face Earth'),
    (['N'], 'Face north (away from the pole)'),
    (['Home'], 'Level the view'),
    (['F'], 'Open the view full screen (Esc closes it)'),
    (['Esc'], 'Give the keys back to the page'),
  ];

  static Widget _group(String title, List<(List<String>, String)> rows) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: PHText.body.copyWith(color: PH.muted)),
        const SizedBox(height: 8),
        for (final (keys, what) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: MergeSemantics(
              child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final k in keys) _KeyCap(k),
                const SizedBox(width: 4),
                Text(what, style: PHText.body),
              ]),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('Keyboard shortcuts'),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _group('On the Site screen, when no button or slider has focus:', _keys),
            const SizedBox(height: 12),
            _group('In the Lander\'s view (after clicking it):', _landerKeys),
          ]),
        ),
      ]);
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  static const _spoken = {
    '←': 'Left arrow',
    '→': 'Right arrow',
    '↑': 'Up arrow',
    '↓': 'Down arrow',
    '+': 'Plus',
    '−': 'Minus',
  };

  @override
  Widget build(BuildContext context) => Semantics(
        label: _spoken[label] ?? label,
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minWidth: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: PH.panelHi, borderRadius: BorderRadius.circular(PH.radius)),
          child: Text(label, textAlign: TextAlign.center, style: numStyle(size: 14, weight: FontWeight.w600)),
        ),
      );
}

/// Learn › Credits: the "Use of AI" paragraph, a short form of the
/// disclosure in docs/submission.md and the README.
const learnUseOfAi = 'Lunar Horizon was built with Claude Code, Anthropic\'s AI coding agent. Under the team\'s '
    'direction it wrote the code, the tests and the documentation, including the text in this app; it found the '
    'preset sites\' published coordinates and sources and drafted their descriptions (fact-checked by separate AI '
    'agents); and it made the demo videos and their music. The results are not AI output: every number, chart and '
    'map here is computed by that code from NASA SPICE and LOLA data, and checked against JPL Horizons and the LOLA '
    'team\'s maps. No AI model produces the numbers.';

/// The source code's address, shown under Credits.
const learnSourceUrl = 'https://github.com/localizedprojects/CLPS-MOON-BROWSER';

class _Credits extends StatelessWidget {
  const _Credits();

  static const _artemisUrl = 'https://www.nasa.gov/news-release/nasa-provides-update-on-artemis-iii-moon-landing-regions/';

  /// The LROC "Anthropogenic Features on the Moon" shapefile's landing page
  /// (contract §8).
  static const lrocObjectsUrl = 'https://data.lroc.im-ldi.com/lroc/view_rdr/SHAPEFILE_ANTHROPOGENIC_OBJECTS';

  /// Who, what, and an optional (web address, its screen-reader name).
  static const _items = <(String, String, (String, String)?)>[
    ('NASA/JPL NAIF SPICE', 'Sun and Earth positions, with the DE440 ephemeris and the Moon\'s orientation.', null),
    (
      'LRO LOLA',
      'Terrain heights from the Lunar Orbiter Laser Altimeter on NASA\'s Lunar Reconnaissance Orbiter (PDS), and the '
          'LOLA team\'s long-term average Sun and Earth visibility maps, for the map overlays and as a check.',
      null
    ),
    ('JPL Horizons', 'Independent positions used to check the app.', null),
    (
      'JPL DSN Telecommunications Link Design Handbook (810-005)',
      'Locations of the Deep Space Network antennas at Goldstone, Madrid and Canberra (module 301).',
      null
    ),
    (
      'Site coordinates',
      'NASA\'s Artemis III candidate landing regions (update of 28 Oct 2024), Henriksen et al. (2023) and LROC '
          'mosaics, De Rosa et al. (2012), LROC images of IM-1 and IM-2, and Beyer et al. (2025) for VIPER. Each '
          'site\'s page lists its own sources.',
      (_artemisUrl, 'Web address of NASA\'s Artemis III landing regions update, on NASA\'s site')
    ),
    // 1.14.0 "Whole Moon" (contract §8): NASA PDS data, public domain
    (
      'Whole Moon site coordinates',
      'The LROC "Anthropogenic Features on the Moon" shapefile (LRO-L-LROC-5-RDR-V1.0, 2026-08-14 version, NASA PDS, '
          'public domain), with coordinates measured by Wagner, Nelson, Plescia, Robinson, Speyerer and Mazarico '
          '(2017), "Coordinates of anthropogenic features on the Moon", Icarus 283, 92–103. Each site\'s page lists '
          'its own sources.',
      (lrocObjectsUrl, 'Web address of the LROC anthropogenic features catalogue, on the LROC data site'),
    ),
    (
      'Whole Moon terrain',
      'LOLA global elevation grids LDEM_16, LDEM_64 and LDEM_512 (LRO-L-LOLA-4-GDR-V1.0), and SLDEM2015, the LOLA '
          'and Kaguya Terrain Camera merge of Barker et al. (2016), Icarus 273, 346–355, both from the NASA PDS '
          'Geosciences Node (public domain), for the Whole Moon map and skylines.',
      null,
    ),
    (
      'Lander photos',
      'Linked from the IM-1 and IM-2 site pages, not bundled: surface photos © Intuitive Machines; photos from '
          'orbit NASA/Goddard/Arizona State University.',
      null
    ),
    ('IBM Plex', 'IBM Plex Sans and IBM Plex Mono typefaces, SIL Open Font License 1.1.', null),
    (
      'Open-source software',
      'Flutter and Dart packages; React and Plotly.js (MIT licence) for the charts; SpiceyPy (NAIF CSPICE), NumPy, '
          'Pillow and Requests for the data; the Roboto web font (Apache License 2.0).',
      null
    ),
    (
      'Source code',
      'On GitHub under the MIT licence. The data, fonts and libraries keep their own terms.',
      (learnSourceUrl, 'Web address of the source code, on GitHub')
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final muted = PHText.body.copyWith(color: PH.muted);
    var link = 0;
    Widget address((String, String) a) =>
        WebAddress(key: ValueKey('credits-url-${a.$1}'), url: a.$1, name: a.$2, storageKey: 'credits-url-${link++}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('Credits'),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // each credit its own node (its words, then its address), so a
          // screen reader steps through them one by one
          for (final (who, what, url) in _items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Semantics(
                container: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    // numbers in Mono, in the titles too ("810-005")
                    numSpans('$who  ', PHText.body.copyWith(fontWeight: FontWeight.w600)),
                    numSpans(what, muted),
                  ])),
                  if (url != null) address(url),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          // the licence texts that must go with the app: Flutter's NOTICES
          // (the Dart and Flutter packages) and lib/licenses.dart (the fonts,
          // the chart bundle's React and Plotly.js)
          OutlinedButton.icon(
            key: const ValueKey('credits-licences'),
            // Escape closes it and a focused row has the ice ring (licence_page.dart)
            onPressed: () => showAppLicences(context),
            icon: const Icon(Icons.description_outlined, size: 20),
            label: const Text('Open-source licences',
                semanticsLabel: 'Open-source licences: the licence texts of the software and fonts in this app'),
          ),
          const SizedBox(height: 12),
          // its own node: a header without one turned the whole card into a
          // heading (the web read all of Credits as one <header>)
          Semantics(container: true, header: true, child: const Text('Use of AI', style: PHText.subtitle)),
          const SizedBox(height: 4),
          Text(learnUseOfAi, key: const ValueKey('learn-use-of-ai'), style: muted),
          const SizedBox(height: 12),
          Text('Made for the NASA Space Apps Challenge. Not an official NASA product.',
              style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 4),
          Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Version ', style: PHText.small.copyWith(color: PH.muted)),
                TextSpan(text: appVersion, style: numStyle(size: 13, color: PH.muted)),
              ]),
              key: const ValueKey('learn-version')),
        ]),
      ),
    ]);
  }
}
