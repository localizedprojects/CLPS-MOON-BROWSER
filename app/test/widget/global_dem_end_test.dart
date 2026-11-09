// 1.14.0 device check (finding A): in a whole-Moon Lander's view the red
// dotted "terrain data ends" line ran along the whole drawn skyline, and its
// label sat on Apollo 15's Hadley Delta ridge (a few km away), so the near
// ridge read as the data edge. For a whole-Moon tile the line is drawn only
// where the tile's edge is the visible skyline, and its label only on such a
// stretch. The polar DEM keeps drawing every DEM end (LanderMesh.demEndSeen
// is null there; see the polar 'demEnds near 80°S' test).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/map_frame.dart';
import 'package:polar_horizon/state/global_tiles.dart';
import 'package:polar_horizon/widgets/lander_view.dart';

LanderMesh _apollo15(double eyeM, [String id = 'apollo-15-lm']) {
  final index = GlobalTilesIndex.parse(File('assets/data/global/tiles.json').readAsStringSync());
  final info = index.tiles[id]!;
  final grid = PolarGrid.decodePlanarSplit(
    File('assets/data/${info.file}').readAsBytesSync(),
    index.grid.size,
    index.grid.pxM,
  );
  return buildLanderMesh(
    grid.heights,
    grid.size,
    grid.scaleM,
    latDeg: info.centreLat,
    lonDeg: info.centreLon,
    observerHeightM: eyeM,
    frame: MapFrame.at(info.centreLat, info.centreLon),
  );
}

void main() {
  late LanderMesh m;
  setUpAll(() => m = _apollo15(2));

  test('Apollo 15: the tile edge (~102 km) is hidden behind Hadley Delta (az ~178°)', () {
    expect(m.demEnds, isNotEmpty);
    expect(m.demEndSeen, isNotNull, reason: 'a whole-Moon tile records where its edge is seen');
    expect(m.demEndSeen, hasLength(720));
    for (final a in [175.0, 177.5, 178.0, 178.5, 181.0]) {
      expect(m.demEndSeenAt(a), isFalse, reason: 'az $a: Hadley Delta, a few km away, is the skyline');
    }
    // the ridge stands well above the tile's edge there
    expect(skylineAt(m.skyline, 178), greaterThan(5.0));
  });

  testWidgets('Apollo 15 facing Hadley Delta: no data-end label on the ridge', (tester) async {
    const size = Size(400, 300);
    final cam = LanderCameraController()..set(yaw: 178, pitch: 0, hfov: 60);
    LanderPainter.debugRecord = true;
    addTearDown(() => LanderPainter.debugRecord = false);
    final p = LanderPainter(cam: cam, mesh: m, proj: LanderProjection(), colors: null);
    final rec = ui.PictureRecorder();
    p.paint(Canvas(rec), size);
    rec.endRecording().dispose();
    // the ridge's stretch of the skyline (148°..208° in view) carries no data-end line, so no label
    for (var a = 160.0; a <= 196.0; a += 0.5) {
      expect(m.demEndSeenAt(a), isFalse, reason: 'az $a');
    }
    expect(LanderPainter.paintedDemLabels, isEmpty);
  });

  testWidgets('from 5 km up the tile edge is the skyline over the mare: the line and its label show there', (
    tester,
  ) async {
    final hi = _apollo15(5000, 'apollo-11-lm');
    expect(hi.demEndSeen!.where((x) => x == 1).length, greaterThan(360), reason: 'past a 132 km horizon');
    const size = Size(400, 300);
    final cam = LanderCameraController()..set(yaw: 60, pitch: -4, hfov: 60);
    LanderPainter.debugRecord = true;
    addTearDown(() => LanderPainter.debugRecord = false);
    final p = LanderPainter(cam: cam, mesh: hi, proj: LanderProjection(), colors: null);
    final rec = ui.PictureRecorder();
    p.paint(Canvas(rec), size);
    rec.endRecording().dispose();
    expect(LanderPainter.paintedDemLabels, hasLength(1), reason: 'one DEM end in view, its label on a seen stretch');
  });
}
