// A preferences store that cannot open (site data blocked in a browser, no
// plugin): every read the app makes at start gives up at once, together,
// and nothing leaks out as an uncaught error. Its own file: the store's
// platform must be the real (here failing) channel, not a mock store.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a store that cannot open: the start reads all give up at once, nothing hangs or leaks', () async {
    SharedPreferences.resetStatic();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'blocked'));
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final s = AppState()..askGoalOnStart = true;
    // as main() starts them: one after another, all while the first open is under way
    await Future.wait([s.loadSavedGoal(), s.loadTourSeen(), s.loadTimeControlsHidden()])
        .timeout(const Duration(seconds: 1), onTimeout: () => fail('a read waited on a failed open forever'));
    expect(s.savedGoal, isNull);
    expect(s.tourPending, isFalse);
    expect(s.timeControlsHidden, isFalse);
    s.finishIntro();
    expect(s.startStage, StartStage.goal, reason: 'no wait at the end of the logo');
  });
}
