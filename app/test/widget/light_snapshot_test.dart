import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/light_map.dart' show LightFramePainter, frameView, viewBeyondBaseMap;
import 'package:polar_horizon/widgets/light_snapshot.dart';
import 'package:provider/provider.dart';

const _hour = 3600e3, _day = 86400e3;
final _t0 = DateTime.utc(2027, 9, 10).millisecondsSinceEpoch.toDouble();

const _site = Site(
    id: 'test-site', name: 'Test site', short: 'Test', group: 'artemis', kind: 'k', confidence: 'c', notes: '',
    lat: -89.4, lon: 130, terrainHeightM: 1200);

/// An AppState whose loaded ephemeris spans 3 days from [_t0] (the vectors are
/// zeros: these tests never reach the shadow engine) and whose chosen period
/// is the first 2 of those days.
AppState _state() {
  final s = AppState();
  s.eph = Ephemeris(_t0, _hour, Float32List(6 * 73), Uint8List(73));
  s.rangeStartMs = _t0;
  s.rangeEndMs = _t0 + 2 * _day;
  s.cursorMs = _t0;
  return s;
}

Widget _host(AppState s, double tMs, {Site site = _site}) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ChangeNotifierProvider<AppState>.value(
          value: s,
          child: SizedBox(width: 360, child: LightSnapshot(site: site, tMs: tMs)),
        ),
      ),
    );

void main() {
  test('coverage: light needs the loaded ephemeris, arrows need the chosen period', () {
    final c1 = snapshotCoverage(_t0 + 12 * _hour, _t0, _t0 + 3 * _day, _t0, _t0 + 2 * _day);
    expect((c1.computable, c1.inPeriod), (true, true));
    final c2 = snapshotCoverage(_t0 + 2.5 * _day, _t0, _t0 + 3 * _day, _t0, _t0 + 2 * _day);
    expect((c2.computable, c2.inPeriod), (true, false));
    final c3 = snapshotCoverage(_t0 - _day, _t0, _t0 + 3 * _day, _t0, _t0 + 2 * _day);
    expect((c3.computable, c3.inPeriod), (false, false));
  });

  test('caption time label is UTC, d MMM yyyy, HH:mm', () {
    expect(snapshotTimeLabel(DateTime.utc(2027, 9, 17, 20).millisecondsSinceEpoch.toDouble()), '17 Sep 2027, 20:00');
    expect(snapshotTimeLabel(DateTime.utc(2028, 1, 3, 4, 5).millisecondsSinceEpoch.toDouble()), '3 Jan 2028, 04:05');
  });

  testWidgets('a moment outside the chosen dates says so and shows no computed light', (tester) async {
    final s = _state();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(s, _t0 - 10 * _day));
    await tester.pump();
    expect(find.text(outsideDatesText), findsOneWidget);
    expect(find.textContaining('Computed light'), findsNothing);
    expect(find.bySemanticsLabel(outsideDatesText), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('before the ephemeris loads it is a plain skeleton, no message, no caption', (tester) async {
    final s = AppState();
    await tester.pumpWidget(_host(s, _t0));
    await tester.pump();
    expect(find.text(outsideDatesText), findsNothing);
    expect(find.textContaining('Computed light'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  // the real catalogue, map and engine: IM-1 Odysseus (80.13 S) has a
  // close-up past the base map's edge (about 80 S), SR1 (Shackleton rim) not
  // (a fresh state and light engine per test: a frame still in flight from an
  // earlier test's fake clock would never finish in the next one)
  group('past the base map\'s edge (real data)', () {
    late AppState state;
    setUp(() async {
      state = AppState();
      await state.init();
    });
    tearDown(() => state.dispose());

    final paint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
    for (final (id, past) in [('im-1-odysseus-landed', true), ('derosa2012-sr1-shackleton-rim', false)]) {
      testWidgets('$id: the note ${past ? 'says' : 'does not say'} so, and the frame is drawn '
          '${past ? 'on the device-shaded relief' : 'on the base map alone'}', (tester) async {
        final site = state.catalog!.byId(id);
        final t = state.rangeStartMs + 12 * _hour;
        await tester.pumpWidget(_host(state, t, site: site));
        await tester.pump();
        // before the frame: the view the engine will compute already decides the note
        String note() => tester.widget<FidelityBadge>(find.byType(FidelityBadge)).text;
        expect(note(), lightSnapshotFidelityFor(past), reason: id);
        expect(note().contains('Past the base map\'s edge'), past, reason: id);
        // the frame, then (past the edge) its relief picture, both take real time
        for (var i = 0; i < 400 && paint.evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(paint, findsOneWidget, reason: '$id: the frame is computed');
        LightFramePainter painter() => tester.widget<CustomPaint>(paint).painter! as LightFramePainter;
        for (var i = 0; i < 100 && past && painter().relief == null; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        final p = painter(), f = p.images!.frame;
        expect(viewBeyondBaseMap(frameView(f), p.halfWidthM), past, reason: id);
        expect(note(), lightSnapshotFidelityFor(past), reason: '$id, with the frame');
        if (past) {
          final rl = p.relief!;
          expect((rl.x0M, rl.y0M, rl.widthM, rl.heightM), (f.x0M, f.y0M, f.extentM, f.extentM), reason: id);
        } else {
          expect(p.relief, isNull, reason: id);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  });
}
