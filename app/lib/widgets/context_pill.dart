/// The global assumptions in one pill: "Next 12 months · 2 m lander ▾", plus
/// "· custom rules" when the Sun/Earth/DSN rules differ from the defaults.
/// Tapping it opens Mission settings.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/wording.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'sheets/mission_settings_sheet.dart';

/// "2 m lander" / "10 m mast" for an observer height in metres.
String heightLabel(double h) {
  final metres = h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
  return '$metres m ${h <= 2 ? 'lander' : 'mast'}';
}

/// The pill's text without the ▾: "{period} · {height}[ · custom rules]".
String contextPillText({
  required double startMs,
  required double endMs,
  required double heightM,
  required bool customRules,
  required DateTime nowUtc,
}) =>
    '${periodLabel(startMs, endMs, nowUtc)} · ${heightLabel(heightM)}${customRules ? ' · custom rules' : ''}';

class ContextPill extends StatelessWidget {
  /// On its own row (phones, large text) the text wraps onto a second line
  /// instead of being cut, so the period and height always stay readable.
  final bool multiline;
  const ContextPill({super.key, this.multiline = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final text = contextPillText(
      startMs: s.rangeStartMs,
      endMs: s.rangeEndMs,
      heightM: s.observerHeightM,
      customRules: s.customRules,
      nowUtc: DateTime.now().toUtc(),
    );
    void open() => showMissionSettings(context);
    // the wrapper replaces the button's own semantics, so it carries the tap
    // action too (screen readers activate this node, not the button)
    return Semantics(
      button: true,
      label: 'Mission settings: $text',
      hint: 'Change the dates, lander or mast height and rules',
      onTap: open,
      excludeSemantics: true,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: multiline
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner))
              : const StadiumBorder(),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: multiline ? 6 : 0),
        ),
        onPressed: open,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(text,
                maxLines: multiline ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: PHText.small.copyWith(height: 1.3)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 18, color: PH.muted),
        ]),
      ),
    );
  }
}
