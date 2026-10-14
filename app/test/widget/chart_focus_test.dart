// The full-screen chart (user decisions 2026-10-13/14): touching a chart shows
// a still picture of it, full screen, where only the X (Back, Esc) responds.
// The live chart never leaves its page (moving it left charts tiny or blank).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_focus.dart';
import 'package:polar_horizon/widgets/chart_view.dart';
import 'package:provider/provider.dart';

// a 1 x 1 PNG, as a chart's export would send it
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  late ChartHub hub;
  late List<Map<String, dynamic>> sent;
  setUp(() {
    hub = ChartHub(onEvent: (_) {});
    sent = [];
    // a ready chart page that answers exports with a picture
    hub.timeline.attach((json) {
      final m = jsonDecode(json) as Map<String, dynamic>;
      sent.add(m);
      if (m['type'] == 'exportPng') {
        Future<void>.microtask(() => hub.timeline.handleRaw(
            jsonEncode({'type': 'png', 'id': m['id'], 'dataUrl': 'data:image/png;base64,$_png'})));
      }
    }, 'test');
    hub.timeline.handleRaw('{"type":"ready","view":"timeline"}');
  });
  tearDown(() => hub.dispose());

  Future<void> pumpPage(WidgetTester tester, {bool landscape = false, Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider<ChartHub>.value(
      value: hub,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListView(children: [
            const SizedBox(height: 40),
            SizedBox(
              height: 300,
              child: FocusableChart(
                  controller: hub.timeline, semanticsLabel: 'Timeline chart', title: 'Timeline', landscape: landscape),
            ),
          ]),
        ),
      ),
    ));
  }

  Finder picture() => find.byKey(const ValueKey('chart-focus-picture'));

  testWidgets('a tap shows a still picture full screen; the live chart stays in its page; the X closes it',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(ChartView));
    await tester.pumpAndSettle();
    expect(find.byType(ChartFocusPage), findsOneWidget);
    expect(find.descendant(of: find.byType(ChartFocusPage), matching: find.byType(ChartView)), findsNothing,
        reason: 'the full-screen page shows a picture, not the live chart');
    expect(find.byType(ChartView, skipOffstage: false), findsOneWidget, reason: 'the live chart never leaves its page');
    final ask = sent.lastWhere((m) => m['type'] == 'exportPng');
    expect(ask['width'], greaterThan(300));
    expect(ask['height'], greaterThan(600), reason: 'the picture is made at the full-screen size');
    expect(picture(), findsOneWidget);
    expect(tester.getSize(picture()).height, greaterThan(600));
    expect(sent.where((m) => m['type'] == 'focus'), isEmpty, reason: 'the chart page is not moved or told anything else');
    await tester.tap(find.byKey(const ValueKey('chart-focus-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ChartFocusPage), findsNothing);
    expect(find.byType(ChartView), findsOneWidget);
    await tester.pump();
    expect(sent.last, {'type': 'focus', 'on': false}, reason: 'the page charts are told to redraw at their size');
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the X responds: touches on the picture do nothing; Back and Esc also close', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('chart-focus-timeline')));
    await tester.pumpAndSettle();
    expect(picture(), findsOneWidget);
    final before = sent.length;
    await tester.tap(picture(), warnIfMissed: false);
    await tester.drag(picture(), const Offset(-100, 0), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(ChartFocusPage), findsOneWidget, reason: 'a touch on the picture does not close or change it');
    expect(sent.length, before, reason: 'nothing reaches the chart');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChartFocusPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chart-focus-timeline')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ChartFocusPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide chart turns the device sideways while full screen, and back after', (tester) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') calls.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpPage(tester, landscape: true);
    await tester.tap(find.byType(ChartView));
    await tester.pump();
    expect(calls.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);
    // the test screen does not turn: the picture still comes after the wait
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(picture(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chart-focus-close')));
    await tester.pumpAndSettle();
    expect(calls.last, isEmpty, reason: 'the device and app orientations apply again');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chart that is not ready says so instead of a picture', (tester) async {
    hub.timeline.detach('test');
    await pumpPage(tester);
    await tester.tap(find.byType(ChartView));
    await tester.pumpAndSettle();
    expect(picture(), findsNothing);
    expect(find.textContaining('could not be made'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
