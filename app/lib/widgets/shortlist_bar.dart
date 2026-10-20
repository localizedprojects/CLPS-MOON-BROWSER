/// The Compare shortlist: one chip per shortlisted site (tap its x to take it
/// off) and an "Add site" button that opens the site picker.
library;

import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../theme.dart';
import 'feature_guide.dart';

class ShortlistBar extends StatelessWidget {
  /// The shortlisted sites, in shortlist order.
  final List<Site> sites;

  /// Take a site off the shortlist.
  final ValueChanged<String> onRemove;

  /// Open the site picker; null hides the button.
  final VoidCallback? onAdd;

  /// The most sites a comparison can hold.
  final int max;

  const ShortlistBar({super.key, required this.sites, required this.onRemove, this.onAdd, this.max = 4});

  @override
  Widget build(BuildContext context) {
    final full = sites.length >= max;
    final status = switch (sites.length) {
      0 => 'No sites yet. Pick two to $max.',
      1 => '1 site. Pick at least one more.',
      final n => '$n of $max sites${full ? ', the most you can compare' : ''}',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Your shortlist', style: PHText.subtitle),
      const SizedBox(height: 4),
      Semantics(
        liveRegion: true,
        child: Text(status, style: PHText.small.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in sites) _SiteChip(site: s, onRemove: () => onRemove(s.id)),
        if (onAdd != null)
          GuideTarget(id: 'compare-add', child: Semantics(
            container: true,
            button: true,
            label: full ? 'Add site. The shortlist is full: remove a site first' : 'Add site to the comparison',
            excludeSemantics: true,
            enabled: !full,
            onTap: full ? null : onAdd,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.tonalIcon(
                onPressed: full ? null : onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add site'),
              ),
            ),
          )),
      ]),
    ]);
  }
}

class _SiteChip extends StatelessWidget {
  final Site site;
  final VoidCallback onRemove;
  const _SiteChip({required this.site, required this.onRemove});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            padding: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(color: PH.panelHi, borderRadius: BorderRadius.circular(24)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(site.short, maxLines: 2, overflow: TextOverflow.ellipsis, style: PHText.body),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove ${site.short} from the comparison',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close_rounded, size: 20, color: PH.muted),
              ),
            ]),
          ),
        ),
      );
}
