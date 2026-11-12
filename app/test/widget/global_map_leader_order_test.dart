// 1.14.0 (commit 4bb4f00): on the Whole Moon map a name set away from its
// marker gets a thin leader line, and the leaders are drawn before the NEAR
// SIDE / FAR SIDE chips and the markers, so that no leader crosses over a
// chip's words or a marker. This test paints the map onto a recording canvas
// and checks that order: every leader comes before the first side chip and
// before the first marker (and the side chips before the markers).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/global_map_view.dart';

import 'global_test_state.dart';
import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlexFonts);

  // the real catalogue, so that the names are placed as in the app
  final real = SiteCatalog.parse(
    File('assets/data/global/sites.json').readAsStringSync(),
    File('assets/data/global/horizons.json').readAsStringSync(),
    region: Region.wholeMoon,
  ).sites;

  // a phone: 360 x 640 dp at 2x, the map 328 x 164 dp
  Future<void> pumpMap(WidgetTester tester, String? selectedId) async {
    final layers = (await tester.runAsync(() => loadGlobalMapLayers(GlobalSampleBundle())))!;
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => FocusRings(child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GlobalMapView(
                layers: layers,
                sites: real,
                selectedId: selectedId,
                onSelect: (_) {},
                onSouthPole: () {},
                onPlaceCustom: (lat, lon) async {},
                polarSiteCount: 19,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // the map's own painter, painted onto a canvas that records every call
  List<RecordedInvocation> record(WidgetTester tester) {
    final paint = find
        .descendant(of: find.byKey(const ValueKey('global-map')), matching: find.byType(CustomPaint))
        .first;
    final painter = tester.widget<CustomPaint>(paint).painter!;
    expect(painter.runtimeType.toString(), '_GlobalPainter');
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, tester.getSize(paint));
    return canvas.invocations;
  }

  // a Paint keeps its colour in 32-bit floats: compare as 8-bit ARGB
  int argb(Color c) => c.toARGB32();
  final leaderColour = argb(PH.text.withValues(alpha: 0.6));
  Paint? paintOf(RecordedInvocation c) => c.invocation.positionalArguments.whereType<Paint>().firstOrNull;
  int? colourOf(RecordedInvocation c) => switch (paintOf(c)) {
    final p? => argb(p.color),
    null => null,
  };
  bool isCall(RecordedInvocation c, Symbol m) => c.invocation.isMethod && c.invocation.memberName == m;
  // the leaders: thin lines in the names' colour (the graticule and the
  // cap's hatching are ice)
  bool isLeader(RecordedInvocation c) => isCall(c, #drawLine) && colourOf(c) == leaderColour;
  bool isChip(RecordedInvocation c) => isCall(c, #drawRRect) && colourOf(c) == argb(globalMapChip);
  // a marker's filled shape (its dark outline follows it)
  bool isMarker(RecordedInvocation c) =>
      isCall(c, #drawPath) &&
      paintOf(c)?.style == PaintingStyle.fill &&
      (colourOf(c) == argb(PH.text) || colourOf(c) == argb(PH.both));

  testWidgets('the leaders are drawn under the side chips and the markers (phone map)', (tester) async {
    expect(real, hasLength(20));
    var withLeaders = 0;
    // no selection, and each site selected in turn: the names (and so the
    // leaders) move with the selection
    for (final id in <String?>[null, for (final st in real) st.id]) {
      await pumpMap(tester, id);
      final calls = record(tester);
      final leaders = [
        for (final (i, c) in calls.indexed)
          if (isLeader(c)) i,
      ];
      final chips = [
        for (final (i, c) in calls.indexed)
          if (isChip(c)) i,
      ];
      final markers = [
        for (final (i, c) in calls.indexed)
          if (isMarker(c)) i,
      ];
      final where = 'selected $id';
      expect(markers, hasLength(real.length), reason: '$where: one marker each');
      // NEAR SIDE, FAR SIDE (and the side label's own chip), then the markers
      final sideChips = chips.where((i) => i < markers.first).toList();
      expect(sideChips, isNotEmpty, reason: '$where: the side chips come before the markers');
      if (leaders.isEmpty) continue;
      withLeaders++;
      expect(leaders.last, lessThan(sideChips.first), reason: '$where: every leader goes under the side chips');
      expect(leaders.last, lessThan(markers.first), reason: '$where: every leader goes under the markers');
    }
    // the check above must have had leaders to look at
    expect(withLeaders, greaterThan(0));
  });
}
