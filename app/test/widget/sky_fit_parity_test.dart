// K7 (1.13.4): the wide pane's "Where to look" frame (sky_time.dart) is sized
// for the smallest plot the chart fits to a short frame (charts/src/skyFit.ts).
// The two sides are separate languages, so this reads the chart's constants
// from its source and checks the Dart side against them: a change on either
// side that breaks the frame fails here, not only in a browser.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/site/sky_time.dart';

/// The number `export const [name] = <n>` in charts/src/skyFit.ts.
double skyFitConst(String src, String name) {
  final m = RegExp('export const $name\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)\\b').allMatches(src).toList();
  if (m.length != 1) throw StateError('${m.length} definitions of $name in charts/src/skyFit.ts, not 1');
  return double.parse(m.single.group(1)!);
}

void main() {
  // flutter test runs in app/
  final src = File('../charts/src/skyFit.ts').readAsStringSync();
  final minPx = skyFitConst(src, 'SKY_FIT_MIN_PX');
  final reservePx = skyFitConst(src, 'SKY_FIT_RESERVE_PX');

  test('the smallest fitted plot side is the same in Dart and in the chart', () {
    expect(skyFitMinSide, minPx);
  });

  test('the wide pane frame holds that plot, the rest (220 px) and the reserved caption line', () {
    for (final exact in const [false, true]) {
      expect(skyWideMinHeight(exact: exact), greaterThanOrEqualTo(skyFitMinSide + 220 + reservePx), reason: 'exact: $exact');
    }
  });

  test('the parser reads the constants it checks (and would see a change)', () {
    expect(skyFitConst('export const SKY_FIT_MIN_PX = 270\n', 'SKY_FIT_MIN_PX'), 270);
    expect(skyFitConst('export const SKY_FIT_RESERVE_PX = 17.5 // px\n', 'SKY_FIT_RESERVE_PX'), 17.5);
    expect(minPx, greaterThan(0));
    expect(reservePx, greaterThan(0));
  });
}
