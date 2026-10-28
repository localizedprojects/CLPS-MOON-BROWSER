// decodeDem on native: same grid as the one-shot decoder, decoded off the
// calling (UI) isolate, errors passed through.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/dem.dart';
import 'package:polar_horizon/state/dem_load.dart';

/// The pipeline's planar-split encoding (basemap.DEM_ENCODING) of [z]:
/// r = z - (left + up - upleft), zero-padded, int16 wrap-around, all low
/// bytes then all high bytes, gzip.
Uint8List encodePlanarSplit(Int16List z, int size) {
  final n = size * size;
  final raw = Uint8List(2 * n);
  for (var i = 0; i < size; i++) {
    for (var j = 0; j < size; j++) {
      final k = i * size + j;
      final left = j > 0 ? z[k - 1] : 0;
      final up = i > 0 ? z[k - size] : 0;
      final upLeft = (i > 0 && j > 0) ? z[k - size - 1] : 0;
      final r = (z[k] - (left + up - upLeft)) & 0xFFFF;
      raw[k] = r & 0xFF;
      raw[n + k] = r >> 8;
    }
  }
  return Uint8List.fromList(const GZipEncoder().encodeBytes(raw));
}

/// Heights over the whole int16 range (so the residuals wrap) on a smooth ramp.
Int16List synthHeights(int size, int seed) {
  final rnd = math.Random(seed);
  final z = Int16List(size * size);
  for (var k = 0; k < z.length; k++) {
    z[k] = k % 7 == 0 ? rnd.nextInt(65536) - 32768 : (k ~/ size) * 3 - (k % size) * 2 + rnd.nextInt(41) - 20;
  }
  return z;
}

/// Event-loop turns (timer events) the calling isolate gets while [job] runs:
/// none when the work is done before [job] returns its future.
Future<(T, int)> turnsWhile<T>(Future<T> Function() job) async {
  var turns = 0, waiting = true;
  final f = job();
  final ticker = () async {
    while (waiting) {
      await Future<void>.delayed(Duration.zero);
      if (waiting) turns++;
    }
  }();
  final v = await f;
  waiting = false;
  await ticker;
  return (v, turns);
}

void main() {
  test('decodeDem returns the same heights as PolarGrid.decodePlanarSplit', () async {
    const size = 96;
    final z = synthHeights(size, 1);
    final gz = encodePlanarSplit(z, size);
    final ref = PolarGrid.decodePlanarSplit(gz, size, 400);
    expect(ref.heights, z, reason: 'the test encoder round-trips');

    final g = await decodeDem(gz, size, 400);
    expect(g.size, size);
    expect(g.scaleM, 400);
    expect(g.heights, ref.heights);
    expect(gz, encodePlanarSplit(z, size), reason: 'the input bytes are left as they were');
  });

  test('decodeDem decodes off the calling isolate (its event loop keeps turning)', () async {
    const size = 768;
    final gz = encodePlanarSplit(synthHeights(size, 2), size);

    // control: the old native path (all the work inside the call) gives the
    // caller no event-loop turn at all, so the probe tells the two apart
    Future<PolarGrid> blocking() async => PolarGrid.decodePlanarSplit(gz, size, 400);
    final (ref, blockedTurns) = await turnsWhile(blocking);
    expect(blockedTurns, 0);

    final (g, turns) = await turnsWhile(() => decodeDem(gz, size, 400));
    expect(turns, greaterThan(0), reason: 'the UI isolate would have been frozen for the whole decode');
    expect(g.heights, ref.heights);
  });

  test('a decode error reaches the caller as itself', () async {
    const size = 16;
    final gz = encodePlanarSplit(synthHeights(size, 3), size);
    await expectLater(decodeDem(gz, size + 1, 400), throwsFormatException);
    await expectLater(decodeDem(Uint8List.fromList([1, 2, 3]), size, 400), throwsFormatException); // bad gzip
  });
}
