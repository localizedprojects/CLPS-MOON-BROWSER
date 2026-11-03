// Android chart host: one render-process death must rebuild each chart's
// web view once, however many web views report it (android-1). iOS: a page
// whose web content process died is rebuilt the same way, without a loop
// (ios-chart-recovery).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart' show ChartController, ChartIssue, chartMinChromeMajor;
import 'package:polar_horizon/widgets/chart_host_mobile.dart'
    show ChartPage, Coalescer, MobileChartHost, chartGoneRetries, chartGoneStable, chartRenderGone;
import 'package:webview_flutter/webview_flutter.dart' show WebResourceError, WebResourceErrorType;

/// Replies that never come, held from a root as the engine holds the reply
/// callback of a platform message that is never answered.
final _unanswered = <Completer<void>>[];

/// A page on a dead render process: runJavaScript never completes.
class _StuckPage extends ChartPage {
  final runs = <String>[];

  @override
  Future<Object> evaluate(String js) => Completer<Object>().future;

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

/// A page that loads, writes to its console and reports [userAgent] (as
/// runJavaScriptReturningResult gives it on Android: JSON-quoted), as the real
/// web view page does through its NavigationDelegate and console callbacks.
class _LoadingPage extends ChartPage {
  _LoadingPage(this.userAgent);
  final String userAgent;
  final evaluated = <String>[];

  void load() => onLoaded!();
  void console(String message) => onConsoleError!(message);

  @override
  Future<void> run(String js) async {}

  @override
  Future<Object> evaluate(String js) async {
    evaluated.add(js);
    return '"$userAgent"';
  }

  @override
  Widget view(Key key) => SizedBox(key: key);
}

String _android(int chrome) =>
    'Mozilla/5.0 (Linux; Android 7.0; sdk_gphone) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/$chrome.0.3497.100 Mobile Safari/537.36';

/// What webview_flutter_wkwebview reports when WKNavigationDelegate's
/// webViewWebContentProcessDidTerminate fires (WKErrorCode 2, main frame).
const _terminated = WebResourceError(
  errorCode: 2,
  description: '',
  errorType: WebResourceErrorType.webContentProcessTerminated,
  isForMainFrame: true,
);

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

  group('MobileChartHost reports when it is behind (Play waits on it)', () {
    const ready = '{"type":"ready","view":"sky"}';

    testWidgets('behind while a run is in flight or queued, not after it finishes', (tester) async {
      final c = ChartController('sky');
      final page = _StuckPage();
      await tester.pumpWidget(MobileChartHost(controller: c, newPage: (_) => page));
      c.handleRaw(ready);
      await tester.pump();
      for (final r in List.of(_unanswered)) {
        if (!r.isCompleted) r.complete();
      }
      _unanswered.clear();
      await tester.pump();
      expect(c.behind, isFalse);
      c.send({'type': 'cursor', 'tMs': 1});
      await tester.pump();
      expect(c.behind, isTrue, reason: 'the run has not finished');
      c.send({'type': 'cursor', 'tMs': 2});
      _unanswered.removeLast().complete(); // the first run finishes, the second starts
      await tester.pump();
      expect(c.behind, isTrue, reason: 'the queued cursor is running now');
      _unanswered.removeLast().complete();
      await tester.pump();
      expect(c.behind, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('not behind after a render-process death replaces a stuck page', (tester) async {
      final c = ChartController('sky');
      await tester.pumpWidget(MobileChartHost(controller: c, newPage: (_) => _StuckPage()));
      c.handleRaw(ready);
      c.send({'type': 'cursor', 'tMs': 1});
      await tester.pump();
      expect(c.behind, isTrue);
      chartRenderGone.value++;
      await tester.pump();
      await tester.pump();
      expect(c.behind, isFalse, reason: 'Play must not wait 3 s on every step for a dead page');
      await tester.pumpWidget(const SizedBox());
    });
  });
  // c2f45b7 review: the host, not only the controller, must report the page's
  // load, its console errors and its Chrome version (the card's message)
  group('MobileChartHost reports why a page has not drawn (Android 7)', () {
    testWidgets('a loaded page that does not report ready is "still loading", never "too old"', (tester) async {
      final c = ChartController('sky');
      final page = _LoadingPage(_android(120));
      await tester.pumpWidget(MobileChartHost(controller: c, newPage: (_) => page));
      page.load();
      await tester.pump();
      expect(page.evaluated, ['navigator.userAgent']);
      expect(c.issue, isNull, reason: 'an up-to-date web view: no verdict yet');
      await tester.pump(ChartController.readyTimeout + const Duration(seconds: 1));
      expect(c.issue, ChartIssue.slow, reason: 'the load reached the controller: its timer ran');
      c.handleRaw('{"type":"ready","view":"sky"}');
      expect(c.issue, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an old Chrome says "too old" as soon as the page loads', (tester) async {
      final c = ChartController('timeline');
      final page = _LoadingPage(_android(chartMinChromeMajor - 1));
      await tester.pumpWidget(MobileChartHost(controller: c, newPage: (_) => page));
      page.load();
      await tester.pump();
      expect(c.issue, ChartIssue.tooOld);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a syntax error on the console says "too old" at once; other errors do not', (tester) async {
      final c = ChartController('compare');
      final page = _LoadingPage(_android(120));
      await tester.pumpWidget(MobileChartHost(controller: c, newPage: (_) => page));
      page.console('Uncaught ReferenceError: x is not defined');
      expect(c.issue, isNull);
      page.console('Uncaught SyntaxError: Unexpected token ?');
      expect(c.issue, ChartIssue.tooOld);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ios-chart-recovery: iOS can kill a WKWebView's web content process
  // (memory pressure, a long time in the background), which leaves the chart
  // blank; webview_flutter_wkwebview reports it as a web resource error. The
  // host recovers that page as after an Android render-process death.
  group('MobileChartHost recovers a page whose web content process died (iOS)', () {
    const ready = '{"type":"ready","view":"sky"}';

    testWidgets('a termination replaces that page only, replays to the new one, and frees the old', (tester) async {
      final c = ChartController('sky');
      final other = ChartController('timeline');
      final pages = <WeakReference<_StuckPage>>[];
      _StuckPage? current;
      var otherPages = 0;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          MobileChartHost(
            controller: c,
            newPage: (_) {
              final p = _StuckPage();
              pages.add(WeakReference(p));
              current = p;
              return p;
            },
          ),
          MobileChartHost(
            controller: other,
            newPage: (_) {
              otherPages++;
              return _StuckPage();
            },
          ),
        ]),
      ));
      c.handleRaw(ready);
      other.handleRaw('{"type":"ready","view":"timeline"}');
      c.send({'type': 'cursor', 'tMs': 1});
      await tester.pump();
      expect(current!.runs.single, contains('cursor')); // and it never completes
      expect(c.behind, isTrue);

      current!.webResourceError(_terminated);
      current!.webResourceError(_terminated); // a repeat before the rebuild
      await tester.pump(); // post-frame: the host builds a new page
      await tester.pump();
      expect(pages, hasLength(2), reason: 'one new page, however many reports');
      expect(identical(current, pages[1].target), isTrue);
      expect(c.ready, isFalse, reason: 'nothing is sent until the new page reports ready');
      expect(c.behind, isFalse, reason: 'Play must not wait on the dead page');
      expect(otherPages, 1, reason: 'a chart whose page is alive keeps it');
      expect(other.ready, isTrue);

      c.handleRaw(ready); // the new page loads: the latest payloads are replayed to it
      await tester.pump();
      expect(current!.runs.single, contains('cursor'));
      expect(collected(pages[0]), isTrue, reason: 'the dead page is still referenced');
      expect(pages[1].target, isNotNull);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('other web resource errors and reports from a replaced page change nothing', (tester) async {
      final c = ChartController('sky');
      final pages = <_StuckPage>[];
      await tester.pumpWidget(MobileChartHost(
        controller: c,
        newPage: (_) {
          final p = _StuckPage();
          pages.add(p);
          return p;
        },
      ));
      c.handleRaw(ready);
      for (final type in [WebResourceErrorType.connect, WebResourceErrorType.unknown, null]) {
        pages.last.webResourceError(WebResourceError(errorCode: -1, description: 'x', errorType: type));
      }
      await tester.pump();
      await tester.pump();
      expect(pages, hasLength(1));
      expect(c.ready, isTrue);

      pages.first.webResourceError(_terminated);
      await tester.pump();
      await tester.pump();
      expect(pages, hasLength(2));
      pages.first.webResourceError(_terminated); // the replaced page again
      await tester.pump();
      await tester.pump();
      expect(pages, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a page that keeps dying, before or after ready, is not reloaded in a loop', (tester) async {
      final c = ChartController('sky');
      final pages = <_StuckPage>[];
      await tester.pumpWidget(MobileChartHost(
        controller: c,
        newPage: (_) {
          final p = _StuckPage();
          pages.add(p);
          return p;
        },
      ));
      Future<void> die() async {
        pages.last.webResourceError(_terminated);
        await tester.pump();
        await tester.pump();
      }

      c.send({'type': 'cursor', 'tMs': 1});
      for (var i = 1; i <= chartGoneRetries; i++) {
        // the bundle reports ready before it draws: a page that the replayed
        // payloads kill dies after ready every time (and some before it)
        if (i.isOdd) c.handleRaw(ready);
        await tester.pump();
        await die();
        expect(pages, hasLength(1 + i));
      }
      c.handleRaw(ready);
      await tester.pump();
      expect(pages.last.runs.single, contains('cursor')); // and it never completes
      expect(c.behind, isTrue);
      await die();
      await die();
      expect(pages, hasLength(1 + chartGoneRetries), reason: 'reloaded in a loop');
      expect(c.ready, isFalse, reason: 'the dead page is not ready');
      expect(c.behind, isFalse, reason: 'Play must not wait on the dead page');
      c.send({'type': 'cursor', 'tMs': 2});
      await tester.pump();
      expect(pages.last.runs, hasLength(1), reason: 'nothing more is sent to the dead page');

      // its screen rebuilt: a fresh host with a fresh count, given the latest payload
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MobileChartHost(
        controller: c,
        newPage: (_) {
          final p = _StuckPage();
          pages.add(p);
          return p;
        },
      ));
      expect(pages, hasLength(2 + chartGoneRetries));
      c.handleRaw(ready);
      await tester.pump();
      expect(pages.last.runs.single, contains('cursor'));
      expect(pages.last.runs.single, contains(r'\"tMs\":2'));
      await die();
      expect(pages, hasLength(3 + chartGoneRetries));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a reloaded page that stays alive starts the count again', (tester) async {
      final c = ChartController('sky');
      final pages = <_StuckPage>[];
      await tester.pumpWidget(MobileChartHost(
        controller: c,
        newPage: (_) {
          final p = _StuckPage();
          pages.add(p);
          return p;
        },
      ));
      Future<void> die() async {
        c.handleRaw(ready);
        await tester.pump();
        pages.last.webResourceError(_terminated);
        await tester.pump();
        await tester.pump();
      }

      await die();
      await tester.pump(chartGoneStable - const Duration(seconds: 1)); // not alive long enough
      for (var i = 1; i < chartGoneRetries; i++) {
        await die();
      }
      expect(pages, hasLength(1 + chartGoneRetries));
      await tester.pump(chartGoneStable); // the last reload lived long enough
      await die();
      expect(pages, hasLength(2 + chartGoneRetries), reason: 'a page that lived is recovered');
      for (var i = 1; i < chartGoneRetries; i++) {
        await die();
      }
      expect(pages, hasLength(1 + 2 * chartGoneRetries));
      await die();
      expect(pages, hasLength(1 + 2 * chartGoneRetries), reason: 'reloaded in a loop');
      expect(c.ready, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
