// The version shown in the app (Learn › Credits, CSV headers) is the one in
// pubspec.yaml, so a release bump cannot leave it behind.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/version.dart';

void main() {
  test('appVersion matches pubspec.yaml\'s version (before the build number)', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final v = line.substring('version:'.length).trim();
    expect(v, startsWith('$appVersion+'));
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(appVersion), isTrue, reason: 'major.minor.patch');
  });
}
