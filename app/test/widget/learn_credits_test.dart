// Learn › Credits: the licence texts that must go with the app (L2), the
// card read as text with its own headings, not as one big heading (A5), and
// the open-source credit naming the libraries the pipeline imports (X4).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/licenses.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/version.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
  });
  tearDownAll(() => state.dispose());

  Future<void> pumpLearn(WidgetTester tester, {double w = 390, double h = 844}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
    ));
    await tester.pump();
    // down to the end of the page, where Credits is
    await tester.scrollUntilVisible(find.byKey(const ValueKey('learn-version')), 500,
        scrollable: find.byType(Scrollable).first, maxScrolls: 400);
    await tester.pump();
  }

  group('open-source licences (L2)', () {
    testWidgets('Credits has a 48 dp "Open-source licences" button that opens the licence page', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpLearn(tester);
      final button = find.byKey(const ValueKey('credits-licences'));
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(button).label, startsWith('Open-source licences'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LicensePage), findsOneWidget);
      final page = tester.widget<LicensePage>(find.byType(LicensePage));
      expect(page.applicationName, 'Lunar Horizon');
      expect(page.applicationVersion, appVersion);
      semantics.dispose();
    });

    test('the app adds the IBM Plex OFL texts and the chart bundle\'s MIT notices', () async {
      final entries = await appLicenses().toList();
      String textOf(String package) => entries
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');
      for (final font in ['IBM Plex Sans', 'IBM Plex Mono']) {
        expect(textOf(font), contains('SIL Open Font License'), reason: font);
        expect(textOf(font), contains('IBM Corp.'), reason: font);
      }
      for (final (package, holder) in [
        ('react', 'Meta Platforms'),
        ('react-dom', 'Meta Platforms'),
        ('scheduler', 'Meta Platforms'),
        ('plotly.js', 'Plotly'),
      ]) {
        expect(textOf(package), contains(holder), reason: package);
        expect(textOf(package), contains('Permission is hereby granted'), reason: package);
      }
    });

    // 1.13.4 review: the chart bundle also compiles in Plotly's d3 modules
    // (BSD-3-Clause, not MIT), and the app ships the Material Icons font
    // (CC BY 4.0) and, on the web, the engine's Roboto (Apache 2.0)
    test('the page also holds the d3 modules\' BSD notices, Material Icons and (web) Roboto', () async {
      final entries = await appLicenses(web: true).toList();
      String textOf(String package) => entries
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');
      expect(textOf('@plotly/d3'), contains('Copyright (c) 2010-2016, Michael Bostock'));
      expect(textOf('@plotly/d3'), contains('Redistributions in binary form must reproduce'));
      expect(textOf('@plotly/d3'), contains('3.8.2'));
      for (final (package, version, line) in [
        ('d3-format', '1.4.5', 'Copyright 2010-2015 Mike Bostock'),
        ('d3-time', '1.1.0', 'Copyright 2010-2016 Mike Bostock'),
        ('d3-time-format', '2.3.0', 'Copyright 2010-2017 Mike Bostock'),
      ]) {
        expect(textOf(package), contains(line), reason: package);
        expect(textOf(package), contains('$package $version'), reason: package);
        expect(textOf(package), contains('Redistributions in binary form must reproduce'), reason: package);
      }
      expect(textOf('Material Icons'), contains('Google'));
      expect(textOf('Material Icons'), contains('Attribution 4.0 International'));
      expect(textOf('Roboto'), contains('Apache License'));
      // Android draws with its own Roboto: the entry is the web build's only
      final android = await appLicenses(web: false).toList();
      expect(android.any((e) => e.packages.contains('Roboto')), isFalse);
      expect(android.any((e) => e.packages.contains('Material Icons')), isTrue);
    });

    // the chart-bundle list of THIRD_PARTY_NOTICES.md (verified against the
    // unminified plotly.js-basic-dist 4.1.2 build): d3-interpolate and
    // d3-color are not in the bundle; the maplibre-gl stylesheet (BSD
    // 3-Clause), gl-mat4 (zlib) and 13 small MIT packages are
    test('the chart-bundle entries match THIRD_PARTY_NOTICES.md', () async {
      final entries = await appLicenses(web: true).toList();
      final packages = {for (final e in entries) ...e.packages};
      String textOf(String package) => entries
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');
      expect(packages, isNot(contains('d3-interpolate')));
      expect(packages, isNot(contains('d3-color')));
      expect(entries.expand((e) => e.paragraphs).any((p) => p.text.contains('ISC License')), isFalse,
          reason: 'no ISC code is left in the bundle');

      final maplibre = textOf('maplibre-gl');
      expect(maplibre, contains('maplibre-gl 6.11.2'));
      expect(maplibre, contains('stylesheet'));
      expect(maplibre, contains('Copyright (c) 2023, MapLibre contributors'));
      expect(maplibre, contains('Neither the name of MapLibre GL JS nor the names of its contributors'));
      expect(maplibre, contains('Contains code from mapbox-gl-js v1.13 and earlier'));
      expect(maplibre, contains('Copyright (c) 2020, Mapbox'));
      expect(maplibre, contains('Neither the name of Mapbox GL JS nor the names of its contributors'));
      expect('Redistributions in binary form must reproduce'.allMatches(maplibre), hasLength(2),
          reason: 'both BSD texts of its LICENSE.txt');

      final glMat4 = textOf('gl-mat4');
      expect(glMat4, contains('zlib License'));
      expect(glMat4, contains('gl-mat4 1.2.0'));
      expect(glMat4, contains('Copyright (c) 2013 Brandon Jones, Colin MacKenzie IV'));
      expect(glMat4, contains("This software is provided 'as-is', without any express or implied warranty."));
      expect(glMat4, contains('This notice may not be removed or altered from any source distribution.'));

      for (final (package, version, holder) in const [
        ('culori', '4.0.2', 'Dan Burzo'),
        ('world-calendars', '1.0.4', 'alexcjohnson'),
        ('is-mobile', '5.0.0', 'Julian Gruber'),
        ('fast-isnumeric', '1.1.4', 'Alex Johnson'),
        ('is-string-blank', '1.0.1', 'Alex Johnson'),
        ('base64-arraybuffer', '1.0.2', 'Niklas von Hertzen'),
        ('events', '3.3.0', 'Joyent, Inc. and other Node contributors'),
        ('is-browser', '2.1.0', 'Forbes Lindesay'),
        ('has-hover', '1.0.1', 'Dima Yv'),
        ('has-passive-events', '1.0.0', 'Dmitry Ivanov'),
        ('mouse-event-offset', '3.0.2', 'Matt DesLauriers'),
        ('parse-svg-path', '0.2.0', 'Jake Rosoman'),
        ('point-in-polygon', '1.1.0', 'James Halliday'),
      ]) {
        final text = textOf(package);
        expect(text, contains('MIT License'), reason: package);
        expect(text, contains('$package $version'), reason: package);
        expect(text, contains(holder), reason: package);
        expect(text, contains('Permission is hereby granted'), reason: package);
      }
      expect(textOf('world-calendars'), contains('Calendars for jQuery 2.0.2, written by Keith Wood'));
    });

    test('registerAppLicenses puts them in Flutter\'s LicenseRegistry', () async {
      registerAppLicenses();
      final packages = <String>{};
      await for (final e in LicenseRegistry.licenses) {
        packages.addAll(e.packages);
      }
      expect(packages, containsAll(['IBM Plex Sans', 'IBM Plex Mono', 'react', 'plotly.js']));
    });
  });

  group('Credits semantics (A5)', () {
    testWidgets('the card is not one heading: its title and "Use of AI" are, each credit is its own node', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpLearn(tester);
      expect(tester.getSemantics(find.text('Credits')), isSemantics(isHeader: true, label: 'Credits'));
      expect(tester.getSemantics(find.text('Use of AI')), isSemantics(isHeader: true, label: 'Use of AI'));
      final rows = ['NASA/JPL NAIF SPICE', 'LRO LOLA', 'JPL Horizons', 'IBM Plex', 'Source code'];
      for (final who in rows) {
        final node = tester.getSemantics(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().startsWith('$who  ')));
        expect(node.flagsCollection.isHeader, isFalse, reason: '"$who" is read as text, not as a heading');
        expect(node.label, contains(who));
        for (final other in rows.where((o) => o != who)) {
          expect(node.label, isNot(contains('$other  ')), reason: '"$who" is its own node, without "$other"');
        }
      }
      final ai = tester.getSemantics(find.byKey(const ValueKey('learn-use-of-ai')));
      expect(ai.flagsCollection.isHeader, isFalse, reason: 'the Use of AI paragraph is not a heading');
      semantics.dispose();
    });
  });

  group('open-source credit (X4)', () {
    testWidgets('it names the libraries the pipeline imports and no SciPy, which nothing imports', (tester) async {
      await pumpLearn(tester);
      final credit = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().startsWith('Open-source software  '));
      expect(credit, findsOneWidget);
      final text = tester.widget<RichText>(credit).text.toPlainText();
      for (final lib in ['SpiceyPy', 'NumPy', 'Pillow', 'Requests']) {
        expect(text, contains(lib), reason: '$lib is imported by pipeline/');
      }
      expect(text, isNot(contains('SciPy')), reason: 'no pipeline module imports SciPy');
    });
  });
}
