// Chart web views on old Android use Hybrid Composition: the default texture
// mode repainted only part of the classic timeline during Play on Android 7
// (android7-timeline).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/chart_composition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('useHybridComposition (API level threshold)', () {
    test('Android 7.0 and 7.1 (API 24, 25) use Hybrid Composition', () {
      expect(useHybridComposition(24), isTrue);
      expect(useHybridComposition(25), isTrue);
    });

    test('Android 8 and newer keep the default texture mode', () {
      expect(hybridCompositionBelowSdk, 26);
      for (final sdk in [26, 28, 29, 34, 35, 36]) {
        expect(useHybridComposition(sdk), isFalse, reason: 'API $sdk');
      }
    });

    test('an unknown level (not Android, or no answer) keeps the default', () {
      expect(useHybridComposition(null), isFalse);
    });
  });

  group('loadAndroidSdk (MainActivity sdkInt)', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(deviceChannel, null);
      androidSdk = null;
    });

    test('stores the level MainActivity answers', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(deviceChannel, (call) async {
        calls.add(call.method);
        return 24;
      });
      expect(await loadAndroidSdk(), 24);
      expect(androidSdk, 24);
      expect(calls, ['sdkInt']);
      expect(useHybridComposition(androidSdk), isTrue);
    });

    test('no handler (MissingPluginException) leaves the level unknown', () async {
      androidSdk = 24;
      expect(await loadAndroidSdk(), isNull);
      expect(androidSdk, isNull);
      expect(useHybridComposition(androidSdk), isFalse);
    });

    test('a platform error leaves the level unknown', () async {
      messenger.setMockMethodCallHandler(deviceChannel, (call) async => throw PlatformException(code: 'x'));
      expect(await loadAndroidSdk(), isNull);
    });
  });
}
