/// "Plan for the dark": the longest night (no Sun) in the chosen period, the
/// time batteries and heaters must bridge, and the longest time without Earth.
library;

import 'package:flutter/material.dart' hide Interval;

import '../core/metrics.dart' show Interval, SiteMetrics;
import '../core/summary.dart' show date, duration;
import '../core/wording.dart';
import '../theme.dart';
import 'glyphs.dart';

const planForDarkTitle = 'Plan for the dark';

/// The card's main sentence (also its screen-reader label).
String planForDarkText(SiteMetrics m) {
  final night = m.longestDark;
  if (night == null) return 'The Sun is up for the whole of your chosen dates, so there is no night to plan for.';
  return 'Plan for the dark: longest night ${duration(night.hours)}. Batteries and heaters must last this long.';
}

/// "Starts 3 Jun 2027", plus why the night may be longer in reality.
String startsText(Interval i) => [
      'Starts ${date(i.startMs)}',
      if (i.truncatedStart) 'already dark when your dates begin',
      if (i.truncatedEnd) 'still dark when your dates end',
    ].join(', ');

/// The edge wording of an Earth outage ("Earth out of view already when
/// your dates begin"): an outage can happen in full sunlight, so never "dark".
String outageStartsText(Interval i, {bool requireDsn = false}) {
  final what = requireDsn ? 'no Earth contact' : 'Earth out of view';
  return [
    'Starts ${date(i.startMs)}',
    if (i.truncatedStart) '$what already when your dates begin',
    if (i.truncatedEnd) '$what still when your dates end',
  ].join(', ');
}

class PlanForDarkCard extends StatelessWidget {
  final SiteMetrics metrics;

  /// Earth counts only with a DSN station up (changes the outage label).
  final bool requireDsn;
  const PlanForDarkCard({super.key, required this.metrics, this.requireDsn = false});

  @override
  Widget build(BuildContext context) {
    final night = metrics.longestDark;
    final outage = metrics.longestEarthOutage;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(planForDarkTitle, style: PHText.subtitle)),
          const SizedBox(height: 10),
          Semantics(
            container: true,
            label: [planForDarkText(metrics), if (night != null) '${startsText(night)}.'].join(' '),
            excludeSemantics: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 6), child: MeaningGlyph(GlyphKind.dark, size: 20, semantic: false)),
              const SizedBox(width: 12),
              Expanded(
                child: night == null
                    ? Text(planForDarkText(metrics), style: PHText.body)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(duration(night.hours), style: statStyle(size: 28)),
                        const SizedBox(height: 2),
                        Text('longest night. Batteries and heaters must last this long.', style: PHText.body),
                        const SizedBox(height: 4),
                        Text('${startsText(night)}.', style: PHText.small.copyWith(color: PH.muted)),
                      ]),
              ),
            ]),
          ),
          if (outage != null) ...[
            const Divider(height: 24, thickness: 1, color: PH.line),
            Semantics(
              container: true,
              label: '${earthOutageLabel(requireDsn: requireDsn)}: ${duration(outage.hours)}. ${outageStartsText(outage, requireDsn: requireDsn)}.',
              excludeSemantics: true,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: MeaningGlyph(GlyphKind.earth, size: 20, semantic: false)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${earthOutageLabel(requireDsn: requireDsn)}: '),
                      TextSpan(text: duration(outage.hours), style: statStyle(size: 16)),
                      TextSpan(text: '. ${outageStartsText(outage, requireDsn: requireDsn)}.', style: const TextStyle(color: PH.muted)),
                    ]),
                    style: PHText.body,
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
