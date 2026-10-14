/// The shortlist tray at the foot of Explore (shown while 1 to 4 sites are
/// shortlisted): how many sites are picked and the way into Compare, which
/// needs at least 2.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// "Compare 3 sites →" / "Pick one more site to compare" (null when empty).
String? compareTrayText(int n) => switch (n) {
      0 => null,
      1 => 'Pick one more site to compare',
      _ => 'Compare $n sites →',
    };

class CompareTray extends StatelessWidget {
  /// Shown at the start of the tray, before the count (Explore uses none).
  final Widget? leading;
  const CompareTray({super.key, this.leading});

  @override
  Widget build(BuildContext context) {
    final ids = context.select((AppState s) => s.compareIds);
    final text = compareTrayText(ids.length);
    if (text == null) return const SizedBox.shrink();
    final s = context.read<AppState>();
    final names = [for (final id in ids) s.allSites.where((x) => x.id == id).firstOrNull?.short ?? id];
    final ready = ids.length >= 2;
    final picked = Semantics(
      liveRegion: true,
      label: '${ids.length} of 4 sites picked for comparison: ${names.join(', ')}',
      excludeSemantics: true,
      child: Text(names.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: PHText.small.copyWith(color: PH.muted)),
    );
    final action = ready
        ? Semantics(
            button: true,
            label: 'Compare ${ids.length} sites',
            excludeSemantics: true,
            onTap: () => s.goTo(Dest.compare),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => s.goTo(Dest.compare),
              child: Text(text),
            ),
          )
        : Text(text, style: PHText.body);
    return Material(
      color: PH.panelHi,
      borderRadius: BorderRadius.circular(PH.radiusSheet),
      child: Padding(
        // a short screen (a phone in landscape): slimmer, so the answer above it stays in view
        padding: MediaQuery.sizeOf(context).height < shortScreenMaxHeight ? const EdgeInsets.fromLTRB(12, 4, 8, 4) : const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: LayoutBuilder(builder: (context, c) {
          // narrow screens and large text: names above, the action under them
          final roomy = c.maxWidth >= 300 + 260 * (MediaQuery.textScalerOf(context).scale(16) / 16);
          if (roomy) {
            return Row(children: [
              ?leading,
              if (leading != null) const SizedBox(width: 8),
              Expanded(child: picked),
              const SizedBox(width: 8),
              action,
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 6), child: picked),
            Row(children: [
              ?leading,
              if (leading != null) const SizedBox(width: 8),
              Expanded(child: Align(alignment: Alignment.centerRight, child: action)),
            ]),
          ]);
        }),
      ),
    );
  }
}
