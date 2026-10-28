// The real ring beyond 80°S (map.json "outer"): AppState reads it with the
// base map but decodes its images only when asked; their sizes match
// map.json, and the ring's relief carries real pixels just inside the base
// map's edge (no hairline gap where the two meet).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final m = jsonDecode(File('assets/data/map/map.json').readAsStringSync()) as Map<String, dynamic>;
  final outer = m['outer'] as Map<String, dynamic>?;

  test('the ring is described, loaded only on request, and its images match map.json', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.ensureMap();
    final l = state.mapLayers!;
    final o = l.outer!;
    expect(o.halfWidthM, (outer!['halfWidthM'] as num).toDouble());
    expect(o.halfWidthM, greaterThan(l.halfWidthM));
    expect(o.hillshadePxM, (outer['hillshade'] as Map)['pxM']);
    expect(o.layerPxM, (outer['sunvis'] as Map)['pxM']);
    expect(o.images, isNull, reason: 'not decoded with the base map');
    expect(o.loadsStarted, 0);

    await o.request();
    final i = o.images!;
    expect(o.loadsStarted, 1);
    void size(ui.Image? im, String key) {
      final n = (2 * o.halfWidthM / ((outer[key] as Map)['pxM'] as num)).round();
      expect(im, isNotNull, reason: key);
      expect((im!.width, im.height), (n, n), reason: key);
    }

    size(i.hillshade, 'hillshade');
    size(i.sunvis, 'sunvis');
    size(i.earthvis, 'earthvis');
    size(i.psr, 'psr');

    // the base map's edge (±halfWidthM) in the ring's relief: real (opaque)
    // pixels on both sides of it, along both axes
    final px = (await i.hillshade.toByteData())!;
    final w = i.hillshade.width, k = w / (2 * o.halfWidthM);
    final edge = ((o.halfWidthM - l.halfWidthM) * k).floor(); // the first ring pixel the base map touches
    int alpha(int x, int y) => px.getUint8((y * w + x) * 4 + 3);
    final mid = w ~/ 2;
    for (final d in [-2, -1, 0, 1, 2]) {
      expect(alpha(edge + d, mid), 255, reason: 'left edge ${edge + d}');
      expect(alpha(mid, edge + d), 255, reason: 'top edge ${edge + d}');
      expect(alpha(w - 1 - edge - d, mid), 255, reason: 'right edge');
      expect(alpha(mid, w - 1 - edge - d), 255, reason: 'bottom edge');
    }
  }, skip: outer == null ? 'map.json has no "outer" yet' : false);

  test('a failed load of the ring is tried again on the next request', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.ensureMap();
    final o = state.mapLayers!.outer!;
    state.debugFailOuterLoads = 1;
    await o.request();
    expect(o.images, isNull, reason: 'the first load failed');
    expect(o.loadsStarted, 1);
    await o.request();
    expect(o.images, isNotNull, reason: 'tried again');
    expect(o.loadsStarted, 2);
    await o.request();
    expect(o.loadsStarted, 2, reason: 'kept once loaded');
  }, skip: outer == null ? 'map.json has no "outer" yet' : false);
}
