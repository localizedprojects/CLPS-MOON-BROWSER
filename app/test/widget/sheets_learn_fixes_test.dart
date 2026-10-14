// Regression tests for the "learn" area fixes of UX step 2:
// web-2 (export sheet sample-step text) and a11y-1 (picker row ink leak).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/sheets/export_sheet.dart';
import 'package:polar_horizon/widgets/sheets/site_picker_sheet.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sampleStepWords names the CSV step (web-2)', () {
    expect(sampleStepWords(600e3), '10-minute');
    expect(sampleStepWords(1800e3), '30-minute');
    expect(sampleStepWords(3600e3), 'hourly');
    expect(sampleStepWords(7200e3), '2-hour');
    expect(sampleStepWords(5400e3), '90-minute');
  });

  group('on the real data', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    Future<void> pumpHost(WidgetTester tester, Widget child, {double w = 400, double h = 900, ChartHub? hub}) async {
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: child)));
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: state,
        child: hub == null ? app : Provider<ChartHub>.value(value: hub, child: app),
      ));
      await tester.pump();
    }

    testWidgets('export sheet states the real sample step of the series (web-2)', (tester) async {
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      await pumpHost(tester,
          Builder(builder: (context) => TextButton(onPressed: () => showExportSheet(context), child: const Text('open'))),
          hub: hub);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('${csvRowsText(state.series!.stepMs)} for ${state.site.short}'), findsOneWidget);
      // the default period (next 12 months) samples every 30 minutes, worked
      // out from the hourly data, in the same terms as Mission settings (new-2-step)
      expect(state.series!.stepMs, 1800e3);
      expect(find.textContaining('One row every 30 minutes, interpolated from the hourly data'), findsOneWidget);
      expect(find.textContaining('sample for'), findsNothing);
    });

    for (final multi in [true, false]) {
      testWidgets('picker rows paint their selection inside the list (a11y-1, multi=$multi)', (tester) async {
        await pumpHost(
            tester,
            Builder(
                builder: (context) => TextButton(
                    onPressed: () => showSitePicker(context,
                        multi: multi, initial: multi ? state.compareIds.take(2).toList() : const []),
                    child: const Text('open'))),
            w: 360,
            h: 640);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final tiles = find.byType(ListTile).evaluate().toList();
        expect(tiles, isNotEmpty);
        for (final e in tiles) {
          // the nearest Material above each row must sit inside the list's
          // scrollable, so the tile colour is clipped with the viewport
          Widget? first;
          e.visitAncestorElements((a) {
            final w = a.widget;
            if (w is Material || (w is Scrollable && w.axisDirection == AxisDirection.down)) {
              first = w;
              return false;
            }
            return true;
          });
          expect(first, isA<Material>());
        }
      });
    }
  });
}
