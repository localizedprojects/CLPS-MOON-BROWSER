// 1.14.0 WP3b: the Validation page's Whole Moon section reads
// global/validation.json only once Whole Moon is open, and prints its values.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/screens/validation_page.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';

class _Bundle extends CachingAssetBundle {
  final asked = <String>[];
  @override
  Future<ByteData> load(String key) async {
    asked.add(key);
    final f = key == GlobalValidationSection.asset ? 'test/fixtures/global_sample/validation.json' : key;
    return ByteData.sublistView(File(f).readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, AppState? state, _Bundle bundle) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page = DefaultAssetBundle(
      bundle: bundle,
      child: const Scaffold(body: SingleChildScrollView(child: GlobalValidationSection())),
    );
    if (state != null) page = ChangeNotifierProvider<AppState>.value(value: state, child: page);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: page));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('closed: a note, and no global file read (also without a provider)', (tester) async {
    final b = _Bundle();
    await pump(tester, null, b);
    expect(find.text(GlobalValidationSection.closed), findsOneWidget);
    final s = AppState();
    addTearDown(s.dispose);
    await pump(tester, s, b);
    expect(find.text(GlobalValidationSection.closed), findsOneWidget);
    expect(b.asked, isNot(contains(GlobalValidationSection.asset)));
  });

  testWidgets('open: values, gates, historic Sun and the synthetic mark from the file', (tester) async {
    final s = AppState();
    addTearDown(s.dispose);
    s.global = GlobalCatalogState(
      SiteCatalog.parse(
        File('test/fixtures/global_sample/sites.json').readAsStringSync(),
        File('test/fixtures/global_sample/horizons.json').readAsStringSync(),
        region: Region.wholeMoon,
      ),
    );
    final b = _Bundle();
    await pump(tester, s, b);
    expect(b.asked, contains(GlobalValidationSection.asset));
    expect(find.byKey(const ValueKey('global-validation-synthetic')), findsOneWidget);
    expect(find.text('Sun 0.0020′, Earth 0.0020′'), findsNWidgets(2));
    expect(find.text('median 1.1°, worst 1.9°'), findsOneWidget);
    expect(find.text('median 0.9°, worst 1.4°'), findsOneWidget);
    expect(find.text('Earth 100%, Sun 50%'), findsOneWidget);
    expect(find.text('Earth 0%'), findsOneWidget);
    expect(find.text('not checked'), findsOneWidget);
    expect(find.text('RMS 1.5°, bias -1.2°'), findsOneWidget);
    expect(find.textContaining('pass ('), findsWidgets);
    expect(find.text('SYNTHETIC frame note.'), findsOneWidget);
  });
}
