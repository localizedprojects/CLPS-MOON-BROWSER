/// Learn: the "Explain as I go" switch, what the tool covers (the south pole
/// only, its site groups, and why the pole is hard), three "Start here"
/// cards, what each view shows, the glossary, "Can I trust these numbers?" (validation and
/// "How it's calculated"), how the score works, keyboard shortcuts and credits.
/// Phones get one column; from 840 dp two columns, at most 1040 wide.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ranking.dart';
import '../core/summary.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/explain.dart';
import '../widgets/site_card.dart' show FocusRingInkWell;
import '../widgets/site_glance_card.dart' show numSpans;
import 'how_calculated.dart';
import 'validation_page.dart';
import '../widgets/feature_guide.dart';

/// The views explained under "What each view shows", in app order.
const learnViews = [explainExplore, explainOverview, explainSky, explainTimeline, explainLight, explainCompare];

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  /// Width from which Learn uses two columns.
  static const twoColumnWidth = 840.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= twoColumnWidth;
      final side = box.maxWidth > 1040 ? (box.maxWidth - 1040) / 2 : 0.0;
      const left = [_StartHere(), _Views()];
      const right = [_TrustCard(), _ScoreCard(), _Glossary(), _Shortcuts(), _Credits()];
      return ListView(
        padding: EdgeInsets.fromLTRB(16 + side, 16, 16 + side, 32),
        children: [
          const _Intro(),
          const _Coverage(),
          if (wide)
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
              SizedBox(width: 24),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
            ])
          else ...[
            // the spec's phone order: start, views, words, trust, score, keys, credits
            ...left,
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

  static const scope = 'Only the Moon\'s south pole: every site, and every spot you add, lies south of 80°S. That is '
      'where the app has loaded the NASA LOLA terrain the skylines need, and where NASA\'s CLPS landers, Artemis and '
      'other countries\' polar missions are going. Apollo and other sites near the equator are outside it.';

  /// The catalogue's groups, as the site list names them, in plain words.
  static const groups = <(String, String)>[
    ('Missions', 'IM-1 Odysseus (2024) and IM-2 Athena (2025), Intuitive Machines landers flown for NASA\'s Commercial '
        'Lunar Payload Services (CLPS), and the planned area of NASA\'s VIPER rover.'),
    ('Artemis III candidate regions', 'approximate centres of NASA\'s October 2024 regions, each about 15 by 15 km; '
        'not official landing points.'),
    ('High-illumination points', 'candidate sites for ESA\'s planned Lunar Lander, from De Rosa et al. (2012).'),
  ];

  static const addYourOwn = 'To test another spot south of 80°S, tap the Explore map or use "Add a spot by '
      'coordinates…" there; your own spots are marked approximate.';

  static const whyHard = 'Near the pole the Sun skims the horizon, so hills kilometres away cast shadows tens of '
      'kilometres long, and a lunar day lasts about 29.5 Earth days, so a shaded spot can stay dark for days or weeks. '
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
            const SizedBox(height: 16),
            // its own node, so it stays a header inside the card's merged text
            Semantics(container: true, header: true, child: const Text('Why the pole is hard', style: PHText.subtitle)),
            const SizedBox(height: 4),
            Text.rich(numSpans(whyHard, PHText.body)),
          ]),
        ),
      ]);
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
          excludeSemantics: true,
          label: '$title. $body $action',
          onTap: onTap,
          child: FocusRingInkWell(
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
          ),
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

/// The Site screen's keys (bound in the shell).
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

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('Keyboard shortcuts'),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('On the Site screen, when no button or slider has focus:', style: PHText.body.copyWith(color: PH.muted)),
            const SizedBox(height: 8),
            for (final (keys, what) in _keys)
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
          ]),
        ),
      ]);
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  static const _spoken = {'←': 'Left arrow', '→': 'Right arrow'};

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

class _Credits extends StatelessWidget {
  const _Credits();

  static const _items = <(String, String)>[
    ('NASA/JPL NAIF SPICE', 'Sun and Earth positions, with the DE440 ephemeris and the Moon\'s orientation.'),
    ('LRO LOLA', 'Terrain heights from the Lunar Orbiter Laser Altimeter on NASA\'s Lunar Reconnaissance Orbiter (PDS).'),
    ('JPL Horizons', 'Independent positions used to check the app.'),
    ('IBM Plex', 'IBM Plex Sans and IBM Plex Mono typefaces, SIL Open Font License 1.1.'),
  ];

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('Credits'),
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (who, what) in _items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$who  ', style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(text: what, style: PHText.body.copyWith(color: PH.muted)),
                ])),
              ),
            const SizedBox(height: 8),
            Text('Made for the NASA Space Apps Challenge. Not an official NASA product.',
                style: PHText.small.copyWith(color: PH.muted)),
          ]),
        ),
      ]);
}
