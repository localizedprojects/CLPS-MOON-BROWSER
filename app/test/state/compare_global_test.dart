// The shortlist with Whole Moon sites (1.14.0 integration): `setCompare`
// knows the global presets once the catalogue is loaded, and a polar-only
// state drops them as in 1.13.5. Compare's `applyShortlist` is that one call.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/compare.dart' show applyShortlist;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/global_load.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fixtures = 'test/fixtures/global_sample';

class _FixtureBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(kGlobalAssetPrefix)) throw FlutterError('not a Whole Moon key: $key');
    final f = File('$_fixtures/${key.substring(kGlobalAssetPrefix.length)}');
    if (!f.existsSync()) throw FlutterError('missing fixture for $key');
    return ByteData.sublistView(f.readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setCompare keeps global ids only once Whole Moon is loaded', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState()..globalAssetBundle = _FixtureBundle();
    await s.init();
    expect(s.error, isNull);
    final polar = [for (final x in s.allSites.take(3)) x.id];

    // polar-only: unknown (global) ids are dropped, as in 1.13.5
    s.setCompare(['apollo-11-lm', polar[0], polar[1]]);
    expect(s.compareIds, [polar[0], polar[1]]);
    expect(s.global, isNull);

    await s.ensureGlobal();
    final global = [for (final x in s.global!.catalog.sites.take(3)) x.id];
    expect(global, contains('apollo-11-lm'));

    // mixed list: order kept, duplicates and unknown ids dropped, at most 4
    s.setCompare([global[0], polar[0], global[0], 'no-such-site', global[1], polar[1], global[2]]);
    expect(s.compareIds, [global[0], polar[0], global[1], polar[1]]);

    applyShortlist(s, [polar[2], global[2]]);
    expect(s.compareIds, [polar[2], global[2]]);
    applyShortlist(s, [polar[0], polar[1]]);
    expect(s.compareIds, [polar[0], polar[1]]);
    s.dispose();
  });
}
