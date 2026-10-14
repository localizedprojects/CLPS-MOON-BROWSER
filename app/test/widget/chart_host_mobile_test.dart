// Android chart host: one render-process death must rebuild each chart's
// web view once, however many web views report it (android-1).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show ChartController;
import 'package:polar_horizon/widgets/chart_host_mobile.dart'
    show ChartPage, Coalescer, MobileChartHost, chartRenderGone;

/// Replies that never come, held from a root as the engine holds the reply
/// callback of a platform message that is never answered.
final _unanswered = <Completer<void>>[];

/// A page on a dead render process: runJavaScript never completes.
class _StuckPage implements ChartPage {
  final runs = <String>[];

  @override
  Future<void> run(String js) {
    runs.add(js);
    final reply = Completer<void>();
    _unanswered.add(reply);
    return reply.future;
  }

  @override
  Widget view(Key key) => SizedBox(key: key);
}

/// Allocates until [ref] is cleared by a garbage collection (or gives up).
bool collected(WeakReference<Object> ref) {
  final keep = <List<int>>[];
  for (var i = 0; i < 3000 && ref.target != null; i++) {
    keep.add(List<int>.filled(1 << 17, i)); // 1 MB each, straight to old space
    if (keep.length > 16) keep.removeAt(0);
  }
  return ref.target == null;
}

void main() {
  group('Coalescer (render-process-gone bursts, android-1)', () {
    test('a burst of reports fires once', () async {
      var fired = 0;
      final c = Coalescer(const Duration(milliseconds: 30), () => fired++);
      // the sky plot and timeline share one renderer: two reports, plus a late one
      c.trigger();
      c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.trigger();
      expect(c.pending, isTrue);
      expect(fired, 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(fired, 1);
      expect(c.pending, isFalse);
    });

    test('a later death (after the burst) fires again', () async {
      var fired = 0;
      final c = Coalescer(const Duration(milliseconds: 20), () => fired++);
      c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.trigger();
      c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fired, 2);
    });
  });

  // android-webviews: the host must not keep a replaced (or disposed) page
  // alive while a runJavaScript on the dead web view never completes; on
  // Android that page holds the WebViewController and, through the plugin,
  // native objects that lead back to the dead WebView.
  group('MobileChartHost releases dead pages (android-webviews)', () {
    const ready = '{"type":"ready","view":"sky"}';

    testWidgets('a render-process death replaces the page, replays to the new one, and frees the old', (tester) async {
      final c = ChartController('sky');
      final pages = <WeakReference<_StuckPage>>[];
      _StuckPage? current;
      await tester.pumpWidget(MobileChartHost(
        controller: c,
        newPage: (_) {
          final p = _StuckPage();
          pages.add(WeakReference(p));
          current = p;
          return p;
        },
      ));
      c.handleRaw(ready);
      c.send({'type': 'cursor', 'tMs': 1});
      await tester.pump();
      expect(current!.runs.single, contains('cursor')); // and it never completes

      chartRenderGone.value++;
      await tester.pump(); // post-frame: the host builds a new page
      await tester.pump();
      expect(pages, hasLength(2));
      expect(identical(current, pages[1].target), isTrue);

      c.handleRaw(ready); // the new page loads: the latest payloads are replayed to it
      await tester.pump();
      expect(current!.runs.single, contains('cursor'));
      c.send({'type': 'cursor', 'tMs': 2}); // the pump is not stuck behind the dead page
      await tester.pump();
      expect(current!.runs, hasLength(1)); // one in flight at a time; the next is queued, not lost

      expect(collected(pages[0]), isTrue, reason: 'the dead page is still referenced');
      expect(pages[1].target, isNotNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('disposing the host with a stuck runJavaScript frees its page', (tester) async {
      final c = ChartController('sky');
      final pages = <WeakReference<_StuckPage>>[];
      await tester.pumpWidget(MobileChartHost(
        controller: c,
        newPage: (_) {
          final p = _StuckPage();
          pages.add(WeakReference(p));
          return p;
        },
      ));
      c.handleRaw(ready);
      c.send({'type': 'cursor', 'tMs': 1});
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(c.ready, isFalse);
      expect(collected(pages.single), isTrue, reason: 'the disposed page is still referenced');
    });
  });
}
