// Contact sheet of the current opening (IntroSplash), the baseline the
// candidates are compared with. Runs only with PH_SHEETS set.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/intro.dart';

import 'frame_sheet.dart';

void main() {
  testWidgets('contact sheet: current', (tester) async {
    await writeContactSheets(tester, 'current', (done) => IntroSplash(onDone: done));
  }, skip: sheetsDir == null);
}
