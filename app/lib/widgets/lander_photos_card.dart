/// "Real photos from this lander": on the site pages of the two landed
/// NASA-CLPS landers, the pages on NASA's site that show their real photos
/// (content/lander_photos.dart). Links only: no image is loaded, and the
/// addresses are selectable text like the other sources (no URL launcher).
library;

import 'package:flutter/material.dart';

import '../content/lander_photos.dart';
import '../theme.dart';
import 'site_glance_card.dart' show numSpans;

class LanderPhotosCard extends StatelessWidget {
  final LanderPhotos photos;
  const LanderPhotosCard({super.key, required this.photos});

  /// The card for [siteId], or null when the site is not a landed lander.
  static LanderPhotosCard? forSite(String siteId, {Key? key}) =>
      landerPhotos[siteId] == null ? null : LanderPhotosCard(key: key, photos: landerPhotos[siteId]!);

  @override
  Widget build(BuildContext context) {
    final muted = PHText.small.copyWith(color: PH.muted);
    var index = 0;
    List<Widget> group(String heading, List<LanderPhotoLink> links) => [
          if (links.isNotEmpty) ...[
            const SizedBox(height: 12),
            Semantics(header: true, child: MicroLabel(heading)),
            for (final l in links) _LinkRow(++index, l),
          ],
        ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(landerPhotosTitle, style: PHText.subtitle)),
          const SizedBox(height: 4),
          Text(landerPhotosNote, style: muted),
          const SizedBox(height: 10),
          Text.rich(numSpans(photos.fact, PHText.body)), // numbers in Mono
          ...group(landerPhotosSurfaceHeading, photos.surface),
          ...group(landerPhotosOrbitHeading, photos.orbit),
        ]),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final int index;
  final LanderPhotoLink link;
  const _LinkRow(this.index, this.link);

  @override
  Widget build(BuildContext context) {
    final muted = PHText.small.copyWith(color: PH.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(numSpans(link.title, PHText.body.copyWith(fontWeight: FontWeight.w500))), // numbers in Mono
        Text.rich(numSpans(link.shows, PHText.small)),
        Text.rich(numSpans('${link.date} · ${landerPhotoCredit(link)}', muted)),
        // SelectableText is a long-press target: one node at least 48 dp tall,
        // labelled with the page it opens. Its own storage key: under
        // Overview's PageStorageKey the text field's scroller would otherwise
        // start at the page's saved scroll offset (see site_glance_card.dart)
        MergeSemantics(
          child: Semantics(
            label: landerPhotoUrlSemantics(link),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: KeyedSubtree(
                key: PageStorageKey('lander-photo-url-$index'),
                child: SelectableText(link.url, style: numStyle(size: 12, color: PH.muted)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
