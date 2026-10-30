/// "About this site": what the place is, where its position comes from, the
/// terrain notes, and (for catalogue sites) the 18.6-year long-term averages
/// precomputed by the pipeline. Closed by default.
library;

import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/site_glance.dart' show skylineSentence;
import '../core/wording.dart';
import '../theme.dart';
import 'glyphs.dart';
import 'site_glance_card.dart' show numSpans;
import 'stat_bar.dart';

// longTermCustomNote moved to core/wording.dart (the At a glance engine uses it); re-exported here.
export '../core/wording.dart' show longTermCustomNote;

const aboutSiteTitle = 'About this site';

/// The exact label of the long-term averages (ux_build_contracts §1.4).
const longTermLabel = '18.6-year average (2 m above ground, any part of the Sun or Earth; lunar eclipses not included, '
    'under 0.1 percentage point)';

class AboutSite extends StatelessWidget {
  final Site site;
  const AboutSite({super.key, required this.site});

  @override
  Widget build(BuildContext context) {
    final s = site;
    final muted = PHText.small.copyWith(color: PH.muted);
    Widget para(String text, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.only(bottom: 10), child: Text.rich(numSpans(text, style ?? PHText.body))); // numbers in Mono
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Semantics(header: true, child: Text(text, style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
        );
    // the same sentence as At a glance (never '0 km away': under 1 km the
    // ground rises right next to the spot)
    final sky = skylineSentence(elevDeg: s.horizonMaxDeg, azDeg: s.horizonMaxAzDeg, distKm: s.horizonMaxDistanceKm);
    final skyline = sky.isEmpty ? null : sky;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // its own storage key: under a scroll view with a PageStorageKey
          // it would otherwise read the scroll offset as its open state
          key: PageStorageKey('about-site-${s.id}'),
          title: Text(aboutSiteTitle, style: PHText.subtitle),
          expansionAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null,
          minTileHeight: 56,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.topLeft,
          children: [
            para('${siteKindLabel(s)} · ${slopeText(s)}'),
            if (s.isArtemisRegion) para('Approximate centre of a ~15 × 15 km candidate region.', style: muted),
            if (skyline != null) para(skyline),
            heading(s.custom ? 'Long-term averages' : longTermLabel),
            if (s.custom)
              para(longTermCustomNote, style: PHText.body.copyWith(color: PH.muted))
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(children: [
                  for (final (kind, label, pct) in [
                    (GlyphKind.sun, 'Sunlit', s.longTermSunlitPct),
                    (GlyphKind.earth, 'Earth in view (any part)', s.longTermEarthPct),
                    (GlyphKind.both, 'Sun and Earth', s.longTermBothPct),
                  ])
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: StatBar(kind, pct, label: label)),
                ]),
              ),
            if (s.custom) const FidelityBadge(text: FidelityBadge.customHorizon),
            if (s.sources.isNotEmpty) ...[
              heading(s.sources.length == 1 ? 'Source' : 'Sources'),
              for (final (i, src) in s.sources.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(src.title, style: PHText.body.copyWith(fontWeight: FontWeight.w500)),
                    if (src.says.isNotEmpty) Text(src.says, style: PHText.small),
                    // own storage key: the text field's scroll offset must not
                    // share a page-storage slot with the tile or the list; a
                    // long-press target, so one node at least 48 dp tall
                    if (src.url.isNotEmpty)
                      MergeSemantics(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: KeyedSubtree(
                              key: PageStorageKey('source-url-$i'), child: SelectableText(src.url, style: muted)),
                        ),
                      ),
                  ]),
                ),
            ],
            if (s.notes.isNotEmpty) ...[
              heading('How the position was checked'),
              para(s.notes, style: muted),
            ] else if (s.custom && s.sources.isEmpty)
              para('Placed by you on the map. The horizon was worked out on this device.', style: muted),
          ],
        ),
      ),
    );
  }
}
