/// The first-launch tutorial (user request 2026-10-19): five swipeable cards
/// that say what Lunar Horizon works out and where to find it. The start
/// sequence shows it once, after the intro and before "What matters most?";
/// Learn's "Show the tutorial again" replays it ([FirstRunTour.replay]).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glyphs.dart';

/// One card's words.
typedef TourCard = ({String title, String body});

class FirstRunTour extends StatefulWidget {
  const FirstRunTour({super.key, required this.onDone, this.sites});

  /// Skip, Done, or back on the first card (called once).
  final VoidCallback onDone;

  /// How many sites the app ranks once the catalog is read; before that the
  /// first card says "the landing sites".
  final int? sites;

  /// The cards' words; every name matches a tab or button in the app.
  static List<TourCard> cards(int? sites) => [
        (
          title: 'Find a place to land',
          body: 'Lunar Horizon ranks ${sites == null ? 'the' : 'all $sites'} landing sites near the Moon\'s south pole '
              'for what matters most to your mission. On Explore, tap a site on the map to open it, or tap anywhere on '
              'the map to test a spot of your own; open the map full screen to place it precisely.',
        ),
        (
          title: 'Sunlight for power, Earth for radio',
          body: 'Solar panels need the Sun, and talking to home needs Earth in view. From NASA\'s map of the real '
              'mountains and where the Sun and Earth sit in the sky, the app works out when each spot gets light and a '
              'line of sight to Earth.',
        ),
        (
          title: 'Move through time',
          body: 'Open a site and pick Sky & time. Drag the time bar or press Play to move through the days, and the '
              'charts follow along.',
        ),
        (
          title: 'See light and shadow',
          body: 'The Light & shadow tab shows where sunlight falls and where the mountains cast shadows around a site, '
              'at any moment you pick on the time bar.',
        ),
        (
          title: 'Compare, then dig deeper',
          body: 'Shortlist two to four sites in Compare to weigh them side by side. Learn explains how every number is '
              'worked out, and you can replay this tutorial there any time.',
        ),
      ];

  /// Open the tutorial over the current screen (Learn's "Show the tutorial
  /// again"); Skip, Done or back on the first card closes it.
  static Future<void> replay(BuildContext context) {
    final state = context.read<AppState>();
    final d = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250);
    return Navigator.of(context).push(PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: d,
      reverseTransitionDuration: d,
      pageBuilder: (ctx, animation, secondary) => FirstRunTour(
        key: const ValueKey('tour'),
        sites: state.catalog?.sites.length,
        onDone: () {
          state.finishTour();
          Navigator.of(ctx).pop();
        },
      ),
      transitionsBuilder: (ctx, animation, secondary, child) => FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  State<FirstRunTour> createState() => _FirstRunTourState();
}

class _FirstRunTourState extends State<FirstRunTour> {
  final _pages = PageController();
  int _page = 0;
  bool _closed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() {
    if (_closed) return; // a double tap must not close two screens
    _closed = true;
    widget.onDone();
  }

  /// Next, Back and the back gesture: a slide, or a jump with reduced motion.
  void _go(int page) {
    if (!_pages.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = FirstRunTour.cards(widget.sites);
    final last = _page == cards.length - 1;
    return PopScope(
      canPop: false,
      // Android back: the card before, or Skip on the first card
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_page == 0) {
          _finish();
        } else {
          _go(_page - 1);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                const BrandMark(size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Lunar Horizon',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
                TextButton(
                  key: const ValueKey('tour-skip'),
                  onPressed: _finish,
                  child: const Text('Skip', semanticsLabel: 'Skip the tutorial'),
                ),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('tour-pages'),
                controller: _pages,
                itemCount: cards.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _CardPage(index: i, count: cards.length, card: cards[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _Dots(page: _page, count: cards.length),
                const SizedBox(height: 8),
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 4,
                  children: [
                    // an empty slot on the first card keeps Next on the right
                    if (_page == 0)
                      const SizedBox.shrink()
                    else
                      TextButton(
                        key: const ValueKey('tour-back'),
                        onPressed: () => _go(_page - 1),
                        child: const Text('Back', semanticsLabel: 'Previous card'),
                      ),
                    FilledButton(
                      key: const ValueKey('tour-next'),
                      onPressed: last ? _finish : () => _go(_page + 1),
                      child: Text(last ? 'Done' : 'Next'),
                    ),
                  ],
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One card: its picture above the words, or beside them on a wide, short
/// screen (a phone in landscape, a tablet). It scrolls when text is large.
class _CardPage extends StatelessWidget {
  const _CardPage({required this.index, required this.count, required this.card});

  final int index;
  final int count;
  final TourCard card;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final side = box.maxWidth >= 600 && box.maxWidth > box.maxHeight * 1.2;
        final words = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${index + 1} of $count',
              semanticsLabel: 'Card ${index + 1} of $count', style: PHText.small.copyWith(color: PH.muted)),
          const SizedBox(height: 6),
          Semantics(header: true, child: Text(card.title, style: PHText.headline)),
          const SizedBox(height: 10),
          Text(card.body, style: PHText.body.copyWith(color: PH.muted)),
        ]);
        final art = ExcludeSemantics(child: _TourArt(index));
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0.0, box.maxHeight - 32)),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: side ? 880 : 560),
                child: side
                    ? Row(children: [art, const SizedBox(width: 32), Expanded(child: words)])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                        Center(child: art),
                        const SizedBox(height: 28),
                        words,
                      ]),
              ),
            ),
          ),
        );
      });
}

/// Where the reader is: one dot per card, the current one wider.
class _Dots extends StatelessWidget {
  const _Dots({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      // each card already says "Card 2 of 5"
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            key: ValueKey('tour-dot-$i'),
            duration: still ? Duration.zero : const Duration(milliseconds: 200),
            width: i == page ? 20 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: i == page ? PH.ice : PH.line, borderRadius: BorderRadius.circular(4)),
          ),
      ]),
    );
  }
}

/// Each card's picture, drawn from the app's own icons and colours.
class _TourArt extends StatelessWidget {
  const _TourArt(this.index);

  final int index;

  static Widget _disc({required Widget child, Gradient? gradient}) => Container(
        width: 136,
        height: 136,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient ?? const RadialGradient(colors: [PH.selected, PH.panel]),
          border: Border.all(color: PH.line, width: 2),
        ),
        child: child,
      );

  static Widget _tile(IconData icon) => Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: PH.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PH.line),
        ),
        child: Icon(icon, size: 40, color: PH.ice),
      );

  static Widget _dot(double x, double y) => Align(
        alignment: Alignment(x, y),
        child: Container(width: 9, height: 9, decoration: const BoxDecoration(color: PH.muted, shape: BoxShape.circle)),
      );

  @override
  Widget build(BuildContext context) => switch (index) {
        0 => _disc(
            child: Stack(children: [
              _dot(-0.45, -0.2),
              _dot(0.35, 0.4),
              _dot(0.5, -0.45),
              _dot(-0.25, 0.5),
              _dot(-0.05, -0.6),
              const Align(alignment: Alignment(0.05, -0.05), child: Icon(Icons.location_on_rounded, size: 46, color: PH.sun)),
            ]),
          ),
        1 => const Row(mainAxisSize: MainAxisSize.min, children: [
            MeaningGlyph(GlyphKind.sun, size: 46, semantic: false),
            SizedBox(width: 12),
            Icon(Icons.landscape_rounded, size: 76, color: PH.muted),
            SizedBox(width: 12),
            MeaningGlyph(GlyphKind.earth, size: 46, semantic: false),
          ]),
        2 => SizedBox(
            width: 210,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.show_chart_rounded, size: 56, color: PH.both),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                decoration: BoxDecoration(
                  color: PH.panel,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: PH.line),
                ),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: PH.ice, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: PH.bg),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: const LinearProgressIndicator(
                          value: 0.6, minHeight: 6, color: PH.ice, backgroundColor: PH.line),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        3 => _disc(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCCFFB000), Color(0x66FFB000), PH.sunken, PH.sunken],
              stops: [0, 0.48, 0.52, 1],
            ),
            child: const Icon(Icons.landscape_rounded, size: 68, color: PH.text),
          ),
        _ => Row(mainAxisSize: MainAxisSize.min, children: [
            _tile(Icons.leaderboard_rounded),
            const SizedBox(width: 16),
            _tile(Icons.school_rounded),
          ]),
      };
}
