/// "What matters most?": the three ranking goals as chips, shared by Explore
/// and Compare. The selected chip is [AppState.activeGoal] (the goal the
/// current weights match); hand-tuned weights select no chip and say so.
/// Changing the goal only re-sorts the cached results (no recompute).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ranking.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'feature_guide.dart';

class GoalChips extends StatelessWidget {
  /// Show the "What matters most?" heading above the chips.
  final bool showTitle;
  const GoalChips({super.key, this.showTitle = true});

  /// One plain sentence per goal (the chip's screen-reader hint).
  static String hintFor(Goal g) => switch (g) {
        Goal.balanced => 'Solar power and Earth contact count equally',
        Goal.power => 'Sunlight for solar power counts most',
        Goal.earth => 'Earth in view for radio contact counts most',
      };

  @override
  Widget build(BuildContext context) {
    final active = context.select((AppState s) => s.activeGoal);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (showTitle) ...[
        Semantics(header: true, child: const Text('What matters most?', style: PHText.subtitle)),
        const SizedBox(height: 8),
      ],
      GuideTarget(id: 'goal-chips', child: Wrap(spacing: 8, runSpacing: 4, children: [
        for (final g in Goal.values)
          Semantics(
            label: 'Rank sites by ${goalLabel(g)}',
            hint: hintFor(g),
            selected: active == g,
            inMutuallyExclusiveGroup: true,
            excludeSemantics: true,
            button: true,
            onTap: () => context.read<AppState>().setGoal(g),
            child: ChoiceChip(
              label: Text(goalLabel(g)),
              selected: active == g,
              showCheckmark: true,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => context.read<AppState>().setGoal(g),
            ),
          ),
      ])),
      if (active == null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Your own weights are in use (set in Compare › Fine-tune). Pick a goal to go back to a preset.',
              style: PHText.small.copyWith(color: PH.muted)),
        ),
    ]);
  }
}
