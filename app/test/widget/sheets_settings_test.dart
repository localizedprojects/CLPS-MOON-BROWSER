// P7a: the ContextPill, the Mission settings sheet and the Explain sheet,
// on the real data (loaded and ranked once).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/summary.dart' show date;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/context_pill.dart';
import 'package:polar_horizon/widgets/explain.dart' show glossary;
import 'package:polar_horizon/widgets/sheets/explain_sheet.dart';
import 'package:polar_horizon/widgets/sheets/mission_settings_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpHost(WidgetTester tester, Widget child, {double w = 400, double h = 900, double text = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: child))),
    ));
    await tester.pump();
  }

  Future<void> openSettings(WidgetTester tester, {double w = 400, double h = 900, double text = 1}) async {
    await pumpHost(tester, const ContextPill(multiline: true), w: w, h: h, text: text);
    await tester.tap(find.byType(ContextPill));
    await tester.pumpAndSettle();
    expect(find.text('Mission settings'), findsOneWidget);
  }

  group('pill text', () {
    final now = DateTime.utc(2026, 10, 11, 15);
    final today = DateTime.utc(2026, 10, 11).millisecondsSinceEpoch.toDouble();
    const day = 86400e3;
    test('default: next 12 months on a lander', () {
      expect(contextPillText(startMs: today, endMs: today + 365 * day, heightM: 2, customRules: false, nowUtc: now),
          'Next 12 months · 2 m lander');
    });
    test('mast, picked dates (last day inclusive) and custom rules', () {
      final a = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch.toDouble();
      final b = DateTime.utc(2027, 2, 1).millisecondsSinceEpoch.toDouble();
      expect(contextPillText(startMs: a, endMs: b, heightM: 10, customRules: true, nowUtc: now),
          '${date(a)} – ${date(b - 1)} · 10 m mast · custom rules');
      expect(date(b - 1), contains('31 Jan'));
    });
    test('height labels', () {
      expect(heightLabel(2), '2 m lander');
      expect(heightLabel(10), '10 m mast');
      expect(heightLabel(2.5), '2.5 m mast');
    });
  });

  group('dates', () {
    test('a picked range ends at the midnight after its last day (exclusive end)', () {
      final (a, b) = pickedToPeriod(DateTimeRange(start: DateTime(2027, 1, 1), end: DateTime(2027, 1, 31)));
      expect(a, DateTime.utc(2027, 1, 1));
      expect(b, DateTime.utc(2027, 2, 1));
      // and the picker is seeded back with the same last day
      final r = initialPickerRange(a.millisecondsSinceEpoch.toDouble(), b.millisecondsSinceEpoch.toDouble(),
          DateTime.utc(2020), DateTime.utc(2035, 12, 31));
      expect(r.end, DateTime.utc(2027, 1, 31));
    });
  });

  testWidgets('the pill shows the period and height and opens Mission settings', (tester) async {
    await pumpHost(tester, const ContextPill());
    final pillLabel = tester.getSemantics(find.byType(ContextPill)).label;
    expect(pillLabel, startsWith('Mission settings: '));
    expect(pillLabel, contains('2 m lander'));
    expect(tester.getSize(find.byType(ContextPill)).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(ContextPill));
    await tester.pumpAndSettle();
    for (final t in ['Mission settings', 'When', 'Lander or mast', 'More options', 'Show exact numbers (for mission planners)']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('2 m lander'), findsOneWidget);
    expect(find.text('10 m mast'), findsOneWidget);
    // defaults: More options stays closed
    expect(state.customRules, isFalse);
    expect(find.text('Any part of the Sun shows'), findsNothing);
    // Back closes the sheet first
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Mission settings'), findsNothing);
  });

  testWidgets('the chosen height and period are marked for screen readers, not only by tone', (tester) async {
    final handle = tester.ensureSemantics();
    await openSettings(tester);
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^2 m lander\.'))), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^10 m mast\.'))), isSemantics(isSelected: false));
    expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'a check mark marks the choice');
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Next 12 months'))), isSemantics(isSelected: true));
    handle.dispose();
  });

  testWidgets('"Pick dates" opens the date picker, bounded by the data', (tester) async {
    final handle = tester.ensureSemantics();
    // Flutter's own full-screen range picker overflows its header with the
    // wide test font on a phone; the dialog form (800 dp) does not
    await openSettings(tester, w: 800);
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Period: ')));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    final picker = tester.widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog));
    expect(picker.lastDate.isAfter(DateTime.utc(2035, 12, 31)), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(find.text('Mission settings'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('More options opens by itself when something is not the default', (tester) async {
    state.setSkyZoom(false);
    addTearDown(() => state.setSkyZoom(true));
    expect(moreOptionsNonDefault(state), isTrue);
    await openSettings(tester);
    expect(find.text('Any part of the Sun shows'), findsOneWidget);
    expect(find.text('The centre of Earth shows'), findsOneWidget);
    expect(find.text('Require a DSN station in view'), findsOneWidget);
    expect(find.text('Back to the default rules'), findsOneWidget);
    // the sky zoom switch works without leaving the sheet
    await tester.ensureVisible(find.text('Zoom the sky plot to the horizon'));
    await tester.tap(find.text('Zoom the sky plot to the horizon'));
    await tester.pump();
    expect(state.skyZoom, isTrue);
  });

  testWidgets('the expert switch sets "Show exact numbers"', (tester) async {
    addTearDown(() => state.setExpert(false));
    await openSettings(tester);
    await tester.ensureVisible(find.text('Show exact numbers (for mission planners)'));
    await tester.tap(find.text('Show exact numbers (for mission planners)'));
    await tester.pump();
    expect(state.expert, isTrue);
  });

  testWidgets('works at 320 px with 2x text, every target at least 48 dp', (tester) async {
    state.setSkyZoom(false); // open More options too
    addTearDown(() => state.setSkyZoom(true));
    await openSettings(tester, w: 320, h: 640, text: 2);
    expect(tester.takeException(), isNull);
    for (final f in [find.byType(ChoiceChip), find.byType(SwitchListTile), find.byType(ListTile)]) {
      for (final e in f.evaluate()) {
        final size = (e.renderObject! as RenderBox).size;
        expect(size.height, greaterThanOrEqualTo(48), reason: '${e.widget.runtimeType} is ${size.height} tall');
      }
    }
    // the cards stack instead of squeezing side by side
    final a = tester.getTopLeft(find.text('2 m lander'));
    final b = tester.getTopLeft(find.text('10 m mast'));
    expect(b.dy, greaterThan(a.dy));
  });

  testWidgets('Explain sheet shows a glossary entry and moves to another word', (tester) async {
    await pumpHost(
        tester,
        Builder(
            builder: (context) =>
                TextButton(onPressed: () => showExplain(context, 'DSN'), child: const Text('open'))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('DSN'), findsOneWidget);
    expect(find.text(glossary['DSN']!), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'DTE'));
    await tester.tap(find.widgetWithText(ActionChip, 'DTE'));
    await tester.pumpAndSettle();
    expect(find.text(glossary['DTE']!), findsOneWidget);
    expect(tester.getSize(find.byType(ActionChip).first).height, greaterThanOrEqualTo(48));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ExplainSheet), findsNothing);
  });

  testWidgets('the "?" button opens the Explain sheet; an unknown word says so', (tester) async {
    await pumpHost(tester, const Column(mainAxisSize: MainAxisSize.min, children: [ExplainButton('Libration'), ExplainButton('Nope')]));
    expect(tester.getSize(find.byType(ExplainButton).first).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(ExplainButton).first);
    await tester.pumpAndSettle();
    expect(find.text(glossary['Libration']!), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExplainButton).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('not in the glossary yet'), findsOneWidget);
  });
}
