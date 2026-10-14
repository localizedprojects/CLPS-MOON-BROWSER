/// A sideways-scrolling row of compact site cards under the map, in the
/// list's order. Its height follows the tallest card, so it grows with the
/// text size instead of clipping.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../core/catalog.dart';
import '../core/metrics.dart' show SiteMetrics;
import 'site_card.dart';

class SiteCarousel extends StatefulWidget {
  /// (rank or null, site, metrics), in display order.
  final List<(int?, Site, SiteMetrics)> items;

  /// Scrolled into view when it changes (the site just picked on the map).
  final String? focusId;
  final double cardWidth;
  const SiteCarousel({super.key, required this.items, this.focusId, this.cardWidth = 288});

  @override
  State<SiteCarousel> createState() => _SiteCarouselState();
}

class _SiteCarouselState extends State<SiteCarousel> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'carousel $id'));

  @override
  void didUpdateWidget(SiteCarousel old) {
    super.didUpdateWidget(old);
    final id = widget.focusId;
    if (id == null) return;
    // a new spot is selected before it is ranked: turn to it when its card
    // joins the row, not only when the focus changes
    final had = old.items.any((x) => x.$2.id == id);
    final has = widget.items.any((x) => x.$2.id == id);
    if (has && (id != old.focusId || !had)) _turnTo(id);
  }

  /// Scroll the row (sideways only: the page itself stays where the user is,
  /// e.g. on the map and the spot's peek card) so the card for [id] starts
  /// at its left edge.
  void _turnTo(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ro = _keys[id]?.currentContext?.findRenderObject();
      if (ro == null || !ro.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) return;
      final p = _scroll.position;
      final target = viewport.getOffsetToReveal(ro, 0).offset.clamp(p.minScrollExtent, p.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      // on a 320 px phone the card leaves a sliver of the next one in view
      final w = c.maxWidth.isFinite ? (c.maxWidth - 40).clamp(220.0, widget.cardWidth) : widget.cardWidth;
      return Semantics(
        label: 'Sites, ${widget.items.length} cards; scroll sideways for more',
        container: true,
        explicitChildNodes: true,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (rank, site, m) in widget.items)
              Padding(
                key: _keyFor(site.id),
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(width: w, child: SiteCard(
                    site: site, metrics: m, rank: rank, compact: true, allBars: true, showRemove: site.custom)),
              ),
          ]),
        ),
      );
    });
  }
}
