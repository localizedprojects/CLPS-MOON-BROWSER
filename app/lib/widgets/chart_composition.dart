import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How a chart web view is put on screen on Android (android7-timeline).
///
/// Flutter's default way to embed an Android WebView draws it into a texture
/// that Flutter composites. On Android 7 (API 24, the oldest this app runs on;
/// WebView Chrome 69) that texture is only partly repainted: during Play, when
/// a chart only moves its cursor, the classic timeline under the sky chart
/// kept just a strip of its Earth curve while its page drew every step. With
/// Hybrid Composition the WebView is a real Android view in the window, which
/// Android repaints itself.
///
/// Below this API level chart web views use Hybrid Composition. 26 (Android 8)
/// is the smallest bound that covers all of Android 7 (24 and 25 share one
/// graphics stack): the fault was seen on 24, and newer Android (the phone and
/// emulators on Android 14 and 15) repaints the default texture correctly.
/// The bound stays as low as that because before Android 10 Hybrid
/// Composition copies every Flutter frame through main memory (slower
/// scrolling); raise it if Android 8 or 9 shows the same partial charts.
const int hybridCompositionBelowSdk = 26;

/// Whether a chart web view on Android API level [sdk] uses Hybrid
/// Composition. Null (not Android, or the level is unknown) keeps the default.
bool useHybridComposition(int? sdk) => sdk != null && sdk < hybridCompositionBelowSdk;

/// The Android API level ([loadAndroidSdk] sets it before the app starts);
/// null elsewhere or when MainActivity did not answer.
int? androidSdk;

/// MainActivity answers `sdkInt` with Build.VERSION.SDK_INT (nothing leaves
/// the device).
const MethodChannel deviceChannel = MethodChannel('polar_horizon/device');

/// Reads the Android API level once, into [androidSdk].
Future<int?> loadAndroidSdk() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return androidSdk = null;
  try {
    return androidSdk = await deviceChannel.invokeMethod<int>('sdkInt');
  } on PlatformException {
    return androidSdk = null;
  } on MissingPluginException {
    return androidSdk = null;
  }
}
