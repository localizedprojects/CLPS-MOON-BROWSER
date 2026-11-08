// web/privacy/index.html: the policy names every setting the app stores on
// the device, and nothing else (the keys written in lib/state/app_state.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final html = File('web/privacy/index.html').readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  final state = File('lib/state/app_state.dart').readAsStringSync();

  test('the policy describes each stored setting, the guides included', () {
    // Every key the app writes: set<Type>(_<name>Key, ...).
    final written = {
      for (final m in RegExp(r'\.set(?:String|Bool|Int|Double|StringList)\((_\w+Key)\b').allMatches(state)) m.group(1)!,
    };
    expect(written, {'_goalKey', '_timeControlsKey', '_guidesKey'});
    expect(html, contains('remembers three small settings'));
    expect(html, contains('the planning goal you picked'));
    expect(html, contains('whether the time controls are hidden'));
    // guidesSeen lists every guide walked through: the tutorial and the
    // feature guides, not the tutorial alone.
    expect(html, contains('which of the short tutorial and the feature guides you have already seen'));
    expect(html, isNot(contains('so it only shows on the first launch')));
  });
}
