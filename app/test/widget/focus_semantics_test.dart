// Keyboard focus reaches the screen reader (1.13.4 review, a11y): many custom
// controls wrap their child in Semantics(..., excludeSemantics: true), which
// drops the InkWell's own focus semantics. Tab then moved Flutter's focus and
// its ice ring, but the control's one semantics node was not focusable (on
// the web: no DOM tabindex) and never said it was focused, so the browser's
// focus, and the screen reader, stayed on an earlier control and Enter could
// activate a different one from the one announced.
//
// On Explore and on each Site view: every enabled button, link, switch and
// checkbox node is focusable, and after every Tab the semantics node that
// holds the focused control says it is focused.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderObject, SemanticsNode;
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsFlag;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/explore.dart';
import 'package:polar_horizon/screens/site/site_screen.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: deprecated_member_use
bool _flag(SemanticsNode n, SemanticsFlag f) => n.getSemanticsData().hasFlag(f);

void _walk(SemanticsNode n, void Function(SemanticsNode) f) {
  f(n);
  n.visitChildren((c) {
    _walk(c, f);
    return true;
  });
}

SemanticsNode _root(SemanticsNode n) {
  var r = n;
  while (r.parent != null) {
    r = r.parent!;
  }
  return r;
}

String _describe(SemanticsNode n) {
  final d = n.getSemanticsData();
  final l = d.label.isNotEmpty ? d.label : d.tooltip;
  return '"${l.length > 60 ? l.substring(0, 60) : l}"';
}

/// Enabled controls (a tap action plus a button, link, switch or checkbox
/// role) that are not focusable. The map's site markers are left out: they
/// are screen-reader buttons drawn by the map painter, not keyboard stops
/// (the map's hint sends keyboard users to the site cards, which are).
List<String> unfocusableControls(SemanticsNode root) {
  final out = <String>[];
  _walk(root, (n) {
    final k = n.key;
    if (k is ValueKey<String> && k.value.startsWith('map-site-')) return;
    final d = n.getSemanticsData();
    if (!d.hasAction(SemanticsAction.tap)) return;
    final control = _flag(n, SemanticsFlag.isButton) ||
        _flag(n, SemanticsFlag.isLink) ||
        _flag(n, SemanticsFlag.hasToggledState) ||
        _flag(n, SemanticsFlag.hasCheckedState);
    if (!control) return;
    if (_flag(n, SemanticsFlag.hasEnabledState) && !_flag(n, SemanticsFlag.isEnabled)) return;
    if (!_flag(n, SemanticsFlag.isFocusable)) out.add(_describe(n));
  });
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState();
    await state.init();
    await state.lightEngine();
  });
  tearDownAll(() => state.dispose());

  Future<void> pump(WidgetTester tester, Size window, Widget body) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hub = ChartHub(onEvent: (_) {});
    addTearDown(hub.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Provider<ChartHub>.value(
        value: hub,
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(body: body),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    state.goTo(Dest.explore);
  }

  /// Tab [presses] times; after each, the semantics node that holds the
  /// focused widget must say it is focused (on the web, that node is where the
  /// browser's focus and the screen reader go).
  Future<List<String>> tabWalk(WidgetTester tester, int presses) async {
    final bad = <String>[];
    for (var i = 1; i <= presses; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final f = FocusManager.instance.primaryFocus;
      final ctx = f?.context;
      if (f == null || ctx == null || ctx.findRenderObject() == null) continue;
      final node = tester.getSemantics(find.byElementPredicate((e) => identical(e, ctx)).first);
      // the node that holds the focused widget, or (a slider) its own node inside it
      var focused = _flag(node, SemanticsFlag.isFocused);
      void inside(RenderObject r) {
        final n = r.debugSemantics;
        if (n != null && _flag(n, SemanticsFlag.isFocused)) focused = true;
        if (!focused) r.visitChildren(inside);
      }

      if (!focused) inside(ctx.findRenderObject()!);
      if (!focused) bad.add('Tab $i: ${ctx.widget.runtimeType} in ${_describe(node)}');
    }
    return bad;
  }

  for (final w in [const Size(1440, 900), const Size(360, 800)]) {
    final size = '${w.width.toInt()}x${w.height.toInt()}';

    testWidgets('Explore $size: every control node is focusable and says when it has focus', (tester) async {
      final handle = tester.ensureSemantics();
      state.goTo(Dest.explore);
      await pump(tester, w, const ExploreScreen());
      final root = _root(tester.getSemantics(find.byType(ExploreScreen)));
      expect(unfocusableControls(root), isEmpty);
      expect(await tabWalk(tester, 14), isEmpty);
      handle.dispose();
      await done(tester);
    });

    for (final tab in SiteTab.values) {
      testWidgets('Site ${tab.name} $size: every control node is focusable and says when it has focus',
          (tester) async {
        final handle = tester.ensureSemantics();
        state.goTo(Dest.site, siteTab: tab);
        await pump(tester, w, const SiteScreen());
        await tester.pump(const Duration(milliseconds: 300));
        final root = _root(tester.getSemantics(find.byType(SiteScreen)));
        expect(unfocusableControls(root), isEmpty);
        expect(await tabWalk(tester, 14), isEmpty);
        handle.dispose();
        await done(tester);
      });
    }
  }
}
