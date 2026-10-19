/// The start page: "What matters most?" (user decision 2026-10-13). A first
/// launch asks it after the tutorial; later launches rank for the saved goal
/// and open on Explore (user request 2026-10-19), where the goal chips change
/// it. The ranking goals are big cards, the last choice is marked, and one
/// tap ranks the sites for that goal and opens the loading scene. The sites
/// are ranked in the background meanwhile, so the page also covers the first
/// load (its progress shows under the cards).
library;

import 'package:flutter/material.dart';

import '../core/ranking.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';
import '../widgets/goal_chips.dart';

class GoalPage extends StatelessWidget {
  final AppState state;
  const GoalPage({super.key, required this.state});

  static const title = 'What matters most for your mission?';

  static Widget _iconFor(Goal g) => switch (g) {
        Goal.balanced => const Icon(Icons.balance_rounded, size: 28, color: PH.text),
        Goal.power => const MeaningGlyph(GlyphKind.sun, size: 28, semantic: false),
        Goal.earth => const MeaningGlyph(GlyphKind.earth, size: 28, semantic: false),
      };

  @override
  Widget build(BuildContext context) {
    final s = state;
    final n = s.catalog?.sites.length;
    final progress = s.error != null
        ? null
        : s.rankTotal > 0 && !s.rankingDone
            ? 'Ranking the sites in the background: ${s.rankProgress} of ${s.rankTotal}'
            : s.ready
                ? null
                : 'Loading the sites in the background…';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                const Row(children: [
                  BrandMark(size: 36),
                  SizedBox(width: 12),
                  Text('Lunar Horizon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 28),
                Semantics(header: true, child: const Text(title, style: PHText.headline)),
                const SizedBox(height: 8),
                Text(
                  'We rank ${n ?? 'the'} south-pole landing sites for it. You can change it any time on Explore.',
                  style: PHText.body.copyWith(color: PH.muted),
                ),
                const SizedBox(height: 20),
                for (final g in Goal.values) ...[
                  _GoalCard(
                    goal: g,
                    icon: _iconFor(g),
                    last: g == s.savedGoal,
                    onTap: () => s.answerGoal(g),
                  ),
                  const SizedBox(height: 10),
                ],
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(progress, style: PHText.small.copyWith(color: PH.muted)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final Widget icon;

  /// The goal chosen last time (marked; one tap continues with it); none on a first run.
  final bool last;
  final VoidCallback onTap;
  const _GoalCard({required this.goal, required this.icon, required this.last, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = goalLabel(goal);
    return Semantics(
      button: true,
      selected: last,
      label: '$label. ${GoalChips.hintFor(goal)}${last ? '. Your last choice' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: last ? PH.panelHi : PH.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PH.radiusInner),
          side: BorderSide(color: last ? PH.ice : PH.line, width: last ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('goal-${goal.name}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(children: [
                SizedBox(width: 36, child: Center(child: icon)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: PHText.subtitle),
                    const SizedBox(height: 2),
                    Text(GoalChips.hintFor(goal), style: PHText.small.copyWith(color: PH.muted)),
                  ]),
                ),
                if (last) ...[
                  const SizedBox(width: 8),
                  Text('Last time', style: PHText.small.copyWith(color: PH.ice)),
                ],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: PH.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
