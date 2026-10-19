// A chart page that never reports ready (Android 7's stock web view, Chrome
// 69, cannot parse the chart bundle) says why in its card instead of
// staying blank; a later ready takes the message away.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';
import 'package:polar_horizon/widgets/chart_view.dart';

void main() {
  final problem = find.byKey(const ValueKey('chart-problem'));

  Future<void> pumpChart(WidgetTester tester, ChartController c) => tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
            body: SizedBox(width: 360, height: 300, child: ChartView(controller: c, semanticsLabel: 'Sky chart'))),
      ));

  testWidgets('no ready in time: the card says to update the web view; a later ready clears it', (tester) async {
    final c = ChartController('sky');
    c.attach((_) {}, 'page');
    await pumpChart(tester, c);
    c.pageLoaded();
    await tester.pump(ChartController.readyTimeout - const Duration(seconds: 1));
    expect(problem, findsNothing, reason: 'a slow page still has time');
    await tester.pump(const Duration(seconds: 2));
    expect(problem, findsOneWidget);
    expect(find.textContaining('newer Android System WebView'), findsOneWidget);
    expect(find.textContaining('Play Store'), findsOneWidget);
    c.handleRaw('{"type":"ready","view":"sky"}');
    await tester.pump();
    expect(problem, findsNothing, reason: 'the chart drew after all');
    expect(c.problem, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a syntax error before ready says it at once; errors after ready change nothing', (tester) async {
    final c = ChartController('timeline');
    c.attach((_) {}, 'page');
    await pumpChart(tester, c);
    c.pageLoaded();
    c.pageError('Uncaught ReferenceError: x is not defined'); // not a parse failure: the timer decides
    await tester.pump();
    expect(problem, findsNothing);
    c.pageError('Uncaught SyntaxError: Unexpected token ?');
    await tester.pump();
    expect(problem, findsOneWidget, reason: 'the bundle cannot run on this web view');
    c.handleRaw('{"type":"ready","view":"timeline"}');
    await tester.pump();
    expect(problem, findsNothing);
    c.pageError('Uncaught SyntaxError: in a later script');
    await tester.pump(ChartController.readyTimeout * 2);
    expect(problem, findsNothing, reason: 'a ready chart is drawn');
  });

  testWidgets('a ready page never gets the message, and a new page gets its own time', (tester) async {
    final c = ChartController('compare');
    c.attach((_) {}, 'page 1');
    await pumpChart(tester, c);
    c.pageLoaded();
    c.handleRaw('{"type":"ready","view":"compare"}');
    await tester.pump(ChartController.readyTimeout * 2);
    expect(problem, findsNothing);
    // a new web view (render process gone): its page loads and is ready in time
    c.attach((_) {}, 'page 2');
    c.pageLoaded();
    await tester.pump(const Duration(seconds: 3));
    c.handleRaw('{"type":"ready","view":"compare"}');
    await tester.pump(ChartController.readyTimeout * 2);
    expect(problem, findsNothing);
    c.detach('page 2');
  });
}
