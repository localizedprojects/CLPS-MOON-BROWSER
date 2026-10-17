import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:web/web.dart' as web;

import '../theme.dart';
import 'chart_bridge.dart';

/// Web host: the React bundle in an iframe; postMessage both ways.
Widget buildChartHost(ChartController c) => _WebChart(controller: c);

int _seq = 0;

/// The last Tab key press the app saw: when (ms since epoch) and whether
/// Shift was down. A frame takes the focus into its page only right after a
/// Tab (not on a click). Kept from the key event, not from
/// [HardwareKeyboard.logicalKeysPressed]: the Tab key is released inside the
/// frame, so the app may think Tab is still down long after.
int _lastTabMs = -1;
bool _lastTabShift = false;
bool _tabWatch = false;

bool _watchTab(KeyEvent e) {
  if ((e is KeyDownEvent || e is KeyRepeatEvent) && e.logicalKey == LogicalKeyboardKey.tab) {
    _lastTabMs = DateTime.now().millisecondsSinceEpoch;
    _lastTabShift = HardwareKeyboard.instance.isShiftPressed;
  }
  return false; // only watching
}

/// Whether the focus is moving because of a Tab just now, and backwards.
({bool tab, bool back}) _recentTab() =>
    (tab: _lastTabMs >= 0 && DateTime.now().millisecondsSinceEpoch - _lastTabMs < 500, back: _lastTabShift);

class _WebChart extends StatefulWidget {
  final ChartController controller;
  const _WebChart({required this.controller});
  @override
  State<_WebChart> createState() => _WebChartState();
}

class _WebChartState extends State<_WebChart> {
  late final String _viewType;
  late final web.HTMLIFrameElement _frame;
  JSFunction? _listener;

  /// What the page has drawn of what this host posted ([ChartAcks]).
  final _acks = ChartAcks();

  /// Has keyboard focus (Tab reached the frame): shows the ice ring and the
  /// page's first control takes the browser focus (a11y-1).
  bool _focused = false;
  final FocusNode _wrap = FocusNode(debugLabel: 'chart frame');

  @override
  void initState() {
    super.initState();
    if (!_tabWatch) {
      _tabWatch = true;
      HardwareKeyboard.instance.addHandler(_watchTab);
    }
    final c = widget.controller;
    _viewType = 'ph-chart-${c.view}-${_seq++}';
    _frame = web.HTMLIFrameElement()
      ..src = 'assets/assets/charts/index.html#view=${c.view}'
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..title = const {'sky': 'Sky plot', 'timeline': 'Visibility timeline', 'compare': 'Site comparison chart'}[c.view] ?? c.view;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => _frame);
    _listener = ((web.MessageEvent e) {
      final src = e.source;
      if (src == null || !src.strictEquals(_frame.contentWindow).toDart) return;
      final d = e.data.dartify();
      if (d is Map && d['source'] == 'ph-charts' && d['event'] != null) {
        final ev = d['event'];
        if (ev is Map && ev['type'] == 'focusExit') {
          _leave(ev['dir'] == -1 ? -1 : 1);
          return;
        }
        if (ev is Map) _acks.handle(c, ev); // acks stop there; a 'ready' clears what an old page owed
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    // each message carries a number the page acks once it has drawn it:
    // Play waits for the iframe, as it waits on runJavaScript on Android
    _acks.attach(c, (json, n) {
      final msg = {'source': 'ph-host', 'msg': jsonDecode(json), 'n': n}.jsify();
      _frame.contentWindow?.postMessage(msg, '*'.toJS);
    }, this);
  }

  @override
  void dispose() {
    if (_listener != null) web.window.removeEventListener('message', _listener);
    _acks.reset(); // a page that goes away never holds Play
    widget.controller.detach(this);
    _wrap.dispose();
    super.dispose();
  }

  /// Tab reached the frame: move the browser focus into the page, which
  /// focuses its first control, or its last one on Shift+Tab
  /// (charts/src/focusHandoff.ts). Only on Tab: when a click puts the browser
  /// focus back on the app, Flutter restores its last focus (this frame,
  /// perhaps), and that must not pull the focus into the chart again.
  ///
  /// Never from inside this callback (new-1): it runs while the focus
  /// manager notifies its changed nodes, and focusing the frame blurs the
  /// Flutter view at once, which parks the app's focus: a second focus change
  /// in the middle of the first (a ConcurrentModificationError). The hand-off
  /// runs on the next event-loop turn instead, if the frame still has focus.
  void _onFocus(bool has) {
    if (has != _focused) setState(() => _focused = has);
    final tab = _recentTab();
    if (!has || !widget.controller.ready || !tab.tab) return;
    _lastTabMs = -1; // one hand-off per Tab
    Timer.run(() {
      if (!mounted || !_wrap.hasPrimaryFocus) return;
      _frame.contentWindow?.focus();
      _frame.contentWindow
          ?.postMessage({'source': 'ph-host', 'msg': {'type': 'focusFirst', 'last': tab.back}}.jsify(), '*'.toJS);
    });
  }

  /// The page's Tab went past its last control (or Shift+Tab before its
  /// first): give the browser focus back to the app and move on from the
  /// frame, forward to the control after it (or back to the one before it),
  /// a11y-1. Focusing the Flutter view makes the app restore a focus of its
  /// own, so the move runs after that, on the next event-loop turn, and has
  /// the last word.
  void _leave(int dir) {
    if (!mounted) return;
    final view = web.document.querySelector('flutter-view');
    if (view != null) (view as web.HTMLElement).focus();
    Timer.run(() {
      if (!mounted) return;
      // the frame's node becomes its scope's focused child first, so the
      // traversal starts from it (while the page had the focus, the app's
      // focus was parked on the root scope)
      _wrap.requestFocus();
      // as if by Tab: when the next stop is another chart frame (the sky
      // plot, then the timeline), the focus goes on into its page
      _lastTabMs = DateTime.now().millisecondsSinceEpoch;
      _lastTabShift = dir < 0;
      if (dir < 0) {
        _wrap.previousFocus();
      } else {
        _wrap.nextFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _wrap,
        onFocusChange: _onFocus,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: _focused ? PH.ice : const Color(0x00000000), width: 2),
            borderRadius: BorderRadius.circular(PH.radius),
          ),
          // one Tab stop: this frame's node, not also the platform view's own
          child: ExcludeFocus(child: HtmlElementView(viewType: _viewType)),
        ),
      );
}
