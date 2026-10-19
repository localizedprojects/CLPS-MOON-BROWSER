// A preferences store that cannot open (site data blocked in a browser, no
// plugin): every read the app makes at start gives up at once, together, so
// the end of the logo does not wait for them. Its own file: the store's
// platform must be the real (here failing) channel, not a mock store.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a store that cannot open: the start reads all give up at once, nothing hangs', () async {
    SharedPreferences.resetStatic();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'blocked'));
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final s = AppState()..askGoalOnStart = true;
    // SharedPreferences.getInstance also leaves a failed future of its own
    // that nothing listens to; only that one may surface here
    final stray = <Object>[];
    await runZonedGuarded(() async {
      // as main() starts them: one after another, all while the first open is under way
      await Future.wait([s.loadSavedGoal(), s.loadTourSeen(), s.loadTimeControlsHidden()])
          .timeout(const Duration(seconds: 1), onTimeout: () => fail('a read waited on a failed open forever'));
    }, (e, _) => stray.add(e));
    expect(stray, everyElement(isA<PlatformException>()));
    expect(s.savedGoal, isNull);
    expect(s.tourPending, isFalse);
    expect(s.timeControlsHidden, isFalse);
    s.finishIntro();
    expect(s.startStage, StartStage.goal, reason: 'no wait at the end of the logo');
  });
}
