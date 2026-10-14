/// "Best time to be here": the longest stretch with the Sun and Earth up
/// together in the chosen period, with [Show me] (Sky & time at its start)
/// and [See the light at that moment] (Light & shadow at its start).
library;

import 'package:flutter/material.dart' hide Interval;

import '../core/metrics.dart' show Interval;
import '../core/summary.dart' show dateTime, duration;
import '../theme.dart';
import 'glyphs.dart';

const bestWindowTitle = 'Best time to be here';
const showMeLabel = 'Show me';
const seeLightLabel = 'See the light at that moment';

/// "from 12 Sep 2027 20:00 UTC", plus why the length may be longer in reality.
String bestWindowWhen(Interval w) => [
      'from ${dateTime(w.startMs)}',
      if (w.truncatedStart) 'already under way when your dates begin',
      if (w.truncatedEnd) 'still going when your dates end',
    ].join(', ');

/// What the best stretch is: "Sun and Earth up together", or with the DSN
/// rule "sunlight and Earth contact (DSN) together".
String bestWindowWhat({bool dsn = false}) => dsn ? 'sunlight and Earth contact (DSN) together' : 'Sun and Earth up together';

class BestWindowCard extends StatelessWidget {
  /// The longest Sun + Earth stretch (null: they are never up together).
  final Interval? window;
  final VoidCallback? onShowMe, onSeeLight;

  /// Earth counts only with a DSN station up: the stretch is sunlight plus
  /// Earth contact, and is worded so (as on the site cards).
  final bool dsn;
  const BestWindowCard({super.key, required this.window, this.onShowMe, this.onSeeLight, this.dsn = false});

  @override
  Widget build(BuildContext context) {
    final w = window;
    final what = bestWindowWhat(dsn: dsn);
    final pill = ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(48, 48)));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(bestWindowTitle, style: PHText.subtitle)),
          const SizedBox(height: 10),
          if (w == null)
            Text(dsn ? 'Sunlight and Earth contact never overlap in your chosen dates.' : 'The Sun and Earth are never up together in your chosen dates.', style: PHText.body.copyWith(color: PH.muted))
          else ...[
            Semantics(
              container: true,
              label: '${what[0].toUpperCase()}${what.substring(1)} for ${duration(w.hours)}, ${bestWindowWhen(w)}',
              excludeSemantics: true,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 6), child: MeaningGlyph(GlyphKind.both, size: 20, semantic: false)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(duration(w.hours), style: statStyle(size: 28)),
                    const SizedBox(height: 2),
                    Text('of $what, ${bestWindowWhen(w)}', style: PHText.body),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(style: pill, onPressed: onShowMe, child: const Text(showMeLabel)),
              FilledButton.tonal(style: pill, onPressed: onSeeLight, child: const Text(seeLightLabel)),
            ]),
          ],
        ]),
      ),
    );
  }
}
