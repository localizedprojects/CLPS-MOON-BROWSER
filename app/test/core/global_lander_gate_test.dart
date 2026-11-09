// The WP5 gate (1.14.0 build plan §7): Apollo 15's Lander's view, built from
// its pipeline tile in its map frame, shows Mons Hadley and Hadley Delta at the
// azimuths of the pipeline's horizon maxima (global/horizons.json, LOLA +
// SLDEM2015 near field) within 1°. The horizon file is WP1's; until it is in
// the tree the comparison skips.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/core/lander_view.dart';
import 'package:polar_horizon/core/map_frame.dart';
import 'package:polar_horizon/state/global_tiles.dart';

/// The azimuth (°) and elevation of the highest sample of [el] (one per
/// [step]° from 0) in [lo, hi).
(double, double) _peak(List<double> el, double step, double lo, double hi) {
  var best = -1, bestEl = -90.0;
  for (var i = (lo / step).ceil(); i * step < hi; i++) {
    if (el[i] > bestEl) {
      bestEl = el[i];
      best = i;
    }
  }
  return (best * step, bestEl);
}

void main() {
  const horizonsPath = 'assets/data/global/horizons.json';
  final haveHorizons = File(horizonsPath).existsSync();

  test(
    'Apollo 15: Mons Hadley and Hadley Delta sit at the pipeline\'s horizon maxima (≤ 1°)',
    () {
      final index = GlobalTilesIndex.parse(File('assets/data/global/tiles.json').readAsStringSync());
      final info = index.tiles['apollo-15-lm']!;
      final grid = PolarGrid.decodePlanarSplit(
        File('assets/data/${info.file}').readAsBytesSync(),
        index.grid.size,
        index.grid.pxM,
      );
      final mesh = buildLanderMesh(
        grid.heights,
        grid.size,
        grid.scaleM,
        latDeg: info.centreLat,
        lonDeg: info.centreLon,
        observerHeightM: 2,
        frame: MapFrame.at(info.centreLat, info.centreLon),
      );
      final h = jsonDecode(File(horizonsPath).readAsStringSync()) as Map<String, dynamic>;
      expect(h['unit'], 'centidegrees');
      final step = (h['azStepDeg'] as num).toDouble();
      final mask = ((h['masks'] as Map)['apollo-15-lm']['2'] as List).map((v) => (v as num) / 100.0).toList();
      final sky = mesh.skyline.toList();
      // Mons Hadley rises north-east of the landing site, Hadley Delta to the south
      for (final (name, lo, hi) in [('Mons Hadley', 0.0, 90.0), ('Hadley Delta', 135.0, 225.0)]) {
        final (pAz, pEl) = _peak(mask, step, lo, hi);
        final (mAz, mEl) = _peak(sky, 0.5, lo, hi);
        // ignore: avoid_print
        print(
          '$name: pipeline ${pAz.toStringAsFixed(2)}° az, ${pEl.toStringAsFixed(2)}° el; '
          'Lander mesh ${mAz.toStringAsFixed(2)}° az, ${mEl.toStringAsFixed(2)}° el',
        );
        expect((mAz - pAz).abs(), lessThanOrEqualTo(1.0), reason: name);
        expect(mEl, greaterThan(5.0), reason: '$name stands well above the horizon');
      }
    },
    skip: haveHorizons ? false : 'needs WP1\'s $horizonsPath',
  );
}
