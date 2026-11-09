// Learn's line for the Lander's N key (1.14.0 device check): the key turns
// the view to the local north (yaw 0), which is away from the pole at a
// south-pole site but toward the north pole at a Whole Moon site. The line
// follows the region of the site the Lander shows; in South-pole mode it reads
// as before 1.14.0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/lander_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'global_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the N line says which way north is in each region, as the Lander\'s compass does', () {
    expect(learnNorthKeyText(Region.southPole), 'Face north (away from the pole)');
    expect(learnNorthKeyText(Region.wholeMoon), 'Face north (toward the north pole)');
    expect(landerCompassLabel, contains('away from the pole'));
    expect(landerCompassLabelGlobal, contains('toward the north pole'));
  });

  late GlobalTestState state;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpLearn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
    ));
    await tester.pump();
  }

  Future<void> expectNorthLine(WidgetTester tester, String line, String not) async {
    final lander = find.text('In the Lander\'s view (after clicking it):');
    expect(find.text(line), findsOneWidget);
    expect(find.text(not), findsNothing);
    expect(tester.getTopLeft(find.text(line)).dy, greaterThan(tester.getTopLeft(lander).dy));
    // one screen-reader node: the key, then what it does
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(tester.getSemantics(find.text(line)).label, allOf(contains('N'), contains(line)));
    semantics.dispose();
  }

  testWidgets('South pole (the default): away from the pole; Whole Moon: toward the north pole', (tester) async {
    expect(state.region, Region.southPole);
    await pumpLearn(tester);
    await expectNorthLine(tester, 'Face north (away from the pole)', 'Face north (toward the north pole)');

    await tester.runAsync(() async {
      await state.setRegion(Region.wholeMoon);
      await state.selectSite('change-4');
    });
    await tester.pump();
    expect(state.regionOf(state.selectedId), Region.wholeMoon);
    await expectNorthLine(tester, 'Face north (toward the north pole)', 'Face north (away from the pole)');

    await tester.runAsync(() => state.setRegion(Region.southPole));
    await tester.pump();
    expect(state.regionOf(state.selectedId), Region.southPole);
    await expectNorthLine(tester, 'Face north (away from the pole)', 'Face north (toward the north pole)');
  });
}
