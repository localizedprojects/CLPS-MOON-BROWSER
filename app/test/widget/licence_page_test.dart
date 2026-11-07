// Learn › Credits › Open-source licences (1.13.4 review, a11y): on Flutter's
// licence page a focused package row showed only a faint lighter fill, not
// the app's 2 px ice focus ring, and Escape did not close the page (it closes
// the app's sheets and dialogs). Checked on a phone (the list, then a
// package's licence texts on a page of their own) and on a desktop (the list
// beside the texts).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/learn.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(() async {
    state = AppState();
    await state.init();
    // a few packages for the list (the test has no NOTICES of its own)
    LicenseRegistry.addLicense(() => Stream.fromIterable([
          const LicenseEntryWithLineBreaks(['alpha'], 'The alpha licence.'),
          const LicenseEntryWithLineBreaks(['beta'], 'The beta licence.'),
          const LicenseEntryWithLineBreaks(['gamma'], 'The gamma licence.'),
        ]));
  });
  tearDownAll(() => state.dispose());

  // Learn, down to Credits, then its "Open-source licences" button
  Future<void> openLicences(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LearnScreen())),
    ));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('credits-licences')), 500,
        scrollable: find.byType(Scrollable).first, maxScrolls: 400);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('credits-licences')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('alpha'), findsWidgets);
  }

  // the ListTile holding the keyboard focus, if any
  Element? focusedTile() {
    final c = FocusManager.instance.primaryFocus?.context;
    Element? tile;
    c?.visitAncestorElements((e) {
      if (e.widget is ListTile) {
        tile = e;
        return false;
      }
      return true;
    });
    return tile;
  }

  // Tab until a package row has the focus
  Future<Element> tabToRow(WidgetTester tester) async {
    for (var i = 0; i < 12 && focusedTile() == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    final tile = focusedTile();
    expect(tile, isNotNull, reason: 'Tab never reached a package row');
    return tile!;
  }

  // a 2 px ice stroke drawn round [rect] (the row), on or just inside its edge
  PaintPattern ringAround(Rect rect) => paints
    ..something((method, args) {
      if (method != #drawRRect) return false;
      final r = (args[0] as RRect).outerRect;
      final p = args[1] as Paint;
      return p.style == PaintingStyle.stroke &&
          p.strokeWidth == 2 &&
          p.color.toARGB32() == PH.ice.toARGB32() &&
          (r.left - rect.left).abs() <= 2 &&
          (r.top - rect.top).abs() <= 2 &&
          (r.right - rect.right).abs() <= 2 &&
          (r.bottom - rect.bottom).abs() <= 2;
    });

  RenderObject app(WidgetTester tester) => tester.renderObject(find.byType(MaterialApp));

  for (final (name, size) in [('phone', const Size(390, 844)), ('desktop', const Size(1440, 900))]) {
    group(name, () {
      testWidgets('Escape closes the licence page, also right after it opens', (tester) async {
        await openLicences(tester, size);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsNothing);
        expect(find.byKey(const ValueKey('credits-licences')), findsOneWidget);
      });

      testWidgets('a focused package row has the 2 px ice ring; Escape from it closes the page', (tester) async {
        await openLicences(tester, size);
        final tile = await tabToRow(tester);
        final rect = tester.getRect(find.byWidget(tile.widget));
        expect(app(tester), ringAround(rect));
        // the next Tab: the ring goes with the focus
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final next = focusedTile();
        if (next != null) expect(app(tester), ringAround(tester.getRect(find.byWidget(next.widget))));
        expect(app(tester), isNot(ringAround(rect)));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsNothing);
      });
    });
  }

  testWidgets('phone: Escape on a package\'s licence texts goes back to the list, then closes the page',
      (tester) async {
    await openLicences(tester, const Size(390, 844));
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(find.text('The beta licence.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('The beta licence.'), findsNothing);
    expect(find.text('beta'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsNothing);
  });
}
