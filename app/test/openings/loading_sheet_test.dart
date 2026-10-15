// Contact sheets of the loading scene on a phone, upright and on its side,
// so its framing can be checked without a device (only when PH_SHEETS is set).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/intro.dart';
import 'package:polar_horizon/state/app_state.dart';

import 'frame_sheet.dart';

/// Mid-ranking, so the longest words and a moving bar show.
class _Ranking extends AppState {
  @override
  bool get loading => false;
  @override
  int get rankTotal => 120;
  @override
  int get rankProgress => 57;
}

void main() {
  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets('contact sheet: loading ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      final s = _Ranking();
      addTearDown(s.dispose);
      await writeContactSheets(tester, 'loading-${size.width.toInt()}x${size.height.toInt()}',
          (_) => SpaceLoading(state: s, onDone: () {}),
          total: const Duration(seconds: 18), frames: 16, phone: size, crop: Size(size.width * 0.6, size.height * 0.6));
      await tester.pump(const Duration(seconds: 1));
    }, skip: sheetsDir == null);
  }
}
