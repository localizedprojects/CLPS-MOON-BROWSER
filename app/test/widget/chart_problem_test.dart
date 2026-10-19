// A chart page that has not drawn says why in its card instead of staying
// blank: that this web view is too old only on evidence (a syntax error, or
// a Chrome older than the bundle needs; Android 7's stock web view, Chrome
// 69, cannot parse it), otherwise that it is still loading. A later ready
// takes the message away.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';
import 'package:polar_horizon/widgets/chart_view.dart';

void main() {
  final problem = find.byKey(const ValueKey('chart-problem'));
  final slow = find.byKey(const ValueKey('chart-slow'));

  Future<void> pumpChart(WidgetTester tester, ChartController c) => tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
            body: SizedBox(width: 360, height: 300, child: ChartView(controller: c, semanticsLabel: 'Sky chart'))),
      ));

  testWidgets('no ready in time: the card says it is still loading, not to update the web view; ready clears it',
      (tester) async {
    final c = ChartController('sky');
    c.attach((_) {}, 'page');
    await pumpChart(tester, c);
    c.pageLoaded();
    await tester.pump(ChartController.readyTimeout - const Duration(seconds: 1));
    expect(slow, findsNothing, reason: 'a slow page still has time');
    await tester.pump(const Duration(seconds: 2));
    // a cold start on a slow but up-to-date phone can take this long: no false alarm
    expect(slow, findsOneWidget);
    expect(find.text(chartSlowText), findsOneWidget);
    expect(problem, findsNothing);
    expect(find.textContaining('newer Android System WebView'), findsNothing);
    expect(c.issue, ChartIssue.slow);
    c.handleRaw('{"type":"ready","view":"sky"}');
    await tester.pump();
    expect(slow, findsNothing, reason: 'the chart drew after all');
    expect(c.problem, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old Chrome says to update the web view (the minimum is one constant); a new one does not',
      (tester) async {
    String ua(String chrome) => 'Mozilla/5.0 (Linux; Android 7.0) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Version/4.0 Chrome/$chrome Mobile Safari/537.36';
    expect(chromeMajor('"${ua('69.0.3497.100')}"'), 69);
    expect(chromeMajor('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) AppleWebKit/605.1.15 Version/17.0 Safari/604.1'), isNull);
    final c = ChartController('sky');
    c.attach((_) {}, 'page');
    await pumpChart(tester, c);
    c.pageLoaded();
    c.pageUserAgent(ua('$chartMinChromeMajor.0.4183.81'));
    c.pageUserAgent('Mozilla/5.0 (iPhone) AppleWebKit/605.1.15 Version/17.0 Mobile Safari/604.1');
    await tester.pump();
    expect(c.issue, isNull, reason: 'new enough, or not Chrome: no verdict');
    c.pageUserAgent(ua('${chartMinChromeMajor - 1}.0.4103.120'));
    await tester.pump();
    expect(problem, findsOneWidget);
    expect(find.textContaining('newer Android System WebView'), findsOneWidget);
    await tester.pump(ChartController.readyTimeout * 2);
    expect(problem, findsOneWidget, reason: 'the timeout never turns the evidence into "still loading"');
    expect(slow, findsNothing);
    c.handleRaw('{"type":"ready","view":"sky"}');
    c.pageUserAgent(ua('60.0.1'));
    await tester.pump();
    expect(problem, findsNothing, reason: 'a ready chart is drawn');
  });

  testWidgets('a syntax error before ready says it at once; errors after ready change nothing', (tester) async {
    final c = ChartController('timeline');
    c.attach((_) {}, 'page');
    await pumpChart(tester, c);
    c.pageLoaded();
    c.pageError('Uncaught ReferenceError: x is not defined'); // not a parse failure: no verdict
    await tester.pump(ChartController.readyTimeout + const Duration(seconds: 1));
    expect(problem, findsNothing);
    expect(slow, findsOneWidget);
    c.pageError('Uncaught SyntaxError: Unexpected token ?');
    await tester.pump();
    expect(problem, findsOneWidget, reason: 'the bundle cannot run on this web view');
    expect(slow, findsNothing);
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
    expect(slow, findsNothing);
    c.detach('page 2');
  });
}
