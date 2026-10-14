import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/ephemeris.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';
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

Widget _host(AppState s, double tMs) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ChangeNotifierProvider<AppState>.value(
          value: s,
          child: SizedBox(width: 360, child: LightSnapshot(site: _site, tMs: tMs)),
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
}
