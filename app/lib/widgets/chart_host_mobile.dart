import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:webview_flutter/webview_flutter.dart';

import 'chart_bridge.dart';
import 'chart_host_stub.dart' as stub;

/// Android/iOS host: the single-file React bundle loaded from Flutter assets,
/// JS -> Dart via the `PH` JavaScript channel, Dart -> JS via runJavaScript.
Widget buildChartHost(ChartController c) =>
    (Platform.isAndroid || Platform.isIOS) ? _MobileChart(controller: c) : stub.buildChartHost(c);

/// Messages waiting for the web view, at most one per type: a newer cursor
/// replaces a queued one instead of queuing behind it, so a slow web view
/// never falls behind the time slider. Order is the order of the last sends.
class MessageQueue {
  final Map<String, String> _q = {};
  int _oneShot = 0;

  bool get isEmpty => _q.isEmpty;

  void add(String json) {
    final type = RegExp(r'^\{"type":"([A-Za-z]+)"').firstMatch(json)?.group(1);
    // exports act once each: never merged
    final key = type == null || type == 'exportPng' ? '#${_oneShot++}' : type;
    _q.remove(key);
    _q[key] = json;
  }

  String take() {
    final k = _q.keys.first;
    return _q.remove(k)!;
  }

  void clear() => _q.clear();
}

/// Collapses a burst of [trigger] calls into one [fire], [window] after the
/// first (android-1): every chart web view shares one render process, so its
/// death arrives as one report per web view, and each extra report used to
/// build one more throwaway native WebView per chart host. Those were never
/// attached (so never guarded by MainActivity's RenderGuard) and made the
/// next render-process death kill the app.
class Coalescer {
  Coalescer(this.window, this.fire);
  final Duration window;
  final void Function() fire;
  Timer? _t;

  bool get pending => _t != null;

  void trigger() {
    _t ??= Timer(window, () {
      _t = null;
      fire();
    });
  }
}

/// Bumped (once per burst) when Android reports that a chart web view's
/// render process died (MainActivity's RenderGuard keeps the app alive and
/// drops that web view): every chart host then builds one fresh web view, and
/// its controller replays the latest payloads once the new page is ready
/// (new-android-4, android-1).
final ValueNotifier<int> chartRenderGone = _listenRenderGone();

ValueNotifier<int> _listenRenderGone() {
  final n = ValueNotifier(0);
  if (Platform.isAndroid) {
    final burst = Coalescer(const Duration(milliseconds: 250), () => n.value++);
    const MethodChannel('polar_horizon/webview').setMethodCallHandler((call) async {
      if (call.method == 'renderProcessGone') burst.trigger();
      return null;
    });
  }
  return n;
}

/// The web view operations the host uses: one page of the chart bundle.
/// A seam so tests can stand in a page whose runJavaScript never completes,
/// as on a web view whose render process died (android-webviews), or one
/// that reports loading, console errors and an old user agent.
abstract class ChartPage {
  Future<void> run(String js);

  /// Runs [js] and returns its result (a string may come JSON-quoted).
  Future<Object> evaluate(String js);
  Widget view(Key key);

  /// Set by the host before the page can load: the page has finished
  /// loading, and a JavaScript error reached its console.
  void Function()? onLoaded;
  void Function(String message)? onConsoleError;
}

/// The real page: a webview_flutter controller with the bundle loaded.
class _WebViewPage extends ChartPage {
  _WebViewPage(ChartController c) {
    _wc
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C1528)) // = PH.panel, the chart background
      // no browser zoom: in the full-screen view a double-tap or pinch reached
      // the web view, which magnified the whole chart page (giant clipped
      // text) and kept that zoom back in the page (QA on the phone,
      // 2026-10-13). The charts zoom themselves where it makes sense.
      ..enableZoom(false)
      ..addJavaScriptChannel('PH', onMessageReceived: (m) => c.handleRaw(m.message))
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => onLoaded?.call()))
      ..setOnConsoleMessage((m) {
        if (m.level == JavaScriptLogLevel.error) onConsoleError?.call(m.message);
      })
      ..loadFlutterAsset('assets/charts/index.html');
  }

  final WebViewController _wc = WebViewController();

  @override
  Future<void> run(String js) => _wc.runJavaScript(js);

  @override
  Future<Object> evaluate(String js) => _wc.runJavaScriptReturningResult(js);

  @override
  Widget view(Key key) => WebViewWidget(key: key, controller: _wc);
}

class _MobileChart extends StatefulWidget {
  final ChartController controller;
  const _MobileChart({super.key, required this.controller});
  @override
  State<_MobileChart> createState() => _MobileChartState();
}

/// The Android/iOS chart host with an injectable [newPage] (tests).
@visibleForTesting
class MobileChartHost extends _MobileChart {
  const MobileChartHost({super.key, required super.controller, required this.newPage});
  final ChartPage Function(ChartController c) newPage;
}

class _MobileChartState extends State<_MobileChart> {
  late ChartPage _page;
  final _queue = MessageQueue();
  bool _busy = false, _disposed = false, _recreatePending = false;
  int _gen = 0;

  /// Completed when the current page is replaced or the host goes away: a
  /// runJavaScript stuck on a dead page then stops holding this host's pump,
  /// so nothing here keeps the old page (and its native objects) alive
  /// (android-webviews).
  Completer<void> _abandon = Completer<void>();

  @override
  void initState() {
    super.initState();
    _create();
    chartRenderGone.addListener(_recreate);
  }

  void _create() {
    final c = widget.controller;
    final w = widget;
    _page = w is MobileChartHost ? w.newPage(c) : _WebViewPage(c);
    // a page that loads but never reports ready says why in its card: an old
    // web view (Android 7's stock one cannot parse the bundle) on evidence
    // only, a syntax error or its Chrome version; otherwise "still loading".
    // A replaced page's reports are ignored (and hold no reference to it).
    final gen = _gen;
    _page.onLoaded = () => _pageLoaded(gen);
    _page.onConsoleError = (message) {
      debugPrint('chart ${c.view}: $message');
      if (!_disposed && gen == _gen) c.pageError(message);
    };
    c.attach((json) {
      _queue.add(json);
      _pump();
    }, this, busy: () => _busy || !_queue.isEmpty);
  }

  void _pageLoaded(int gen) {
    if (_disposed || gen != _gen) return;
    final c = widget.controller;
    c.pageLoaded();
    _page.evaluate('navigator.userAgent').then((ua) {
      if (!_disposed && gen == _gen) c.pageUserAgent('$ua');
    }, onError: (Object e) => debugPrint('chart ${c.view}: user agent: $e'));
  }

  void _abandonPage() {
    if (!_abandon.isCompleted) _abandon.complete();
    _abandon = Completer<void>();
  }

  /// A render process died: one new web view (new platform view) and page,
  /// built after the current frame so that however many notifications arrive
  /// in between, exactly one controller is created and it is the one the
  /// next build attaches (an unattached native WebView is never guarded).
  void _recreate() {
    if (_disposed || _recreatePending) return;
    _recreatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recreatePending = false;
      if (_disposed || !mounted) return;
      setState(() {
        _queue.clear();
        _busy = false; // a runJavaScript on the dead web view may never complete
        _gen++;
        _abandonPage();
        _create();
      });
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// One runJavaScript in flight at a time (the next starts when the web view
  /// has run the previous one). A pump bound to a replaced web view stops,
  /// without waiting for the old web view, and keeps no reference to it.
  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    final gen = _gen;
    try {
      while (!_disposed && gen == _gen && !_queue.isEmpty) {
        final json = _queue.take();
        try {
          await Future.any([_page.run('window.phRender && window.phRender(${jsonEncode(json)})'), _abandon.future]);
        } catch (e) {
          debugPrint('chart ${widget.controller.view}: $e');
        }
      }
    } finally {
      if (gen == _gen) {
        _busy = false;
      } else if (!_disposed && !_queue.isEmpty) {
        unawaited(_pump()); // messages for the new web view queued while this one was stuck
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    chartRenderGone.removeListener(_recreate);
    _queue.clear();
    _abandonPage();
    widget.controller.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _page.view(ValueKey(_gen));
}
