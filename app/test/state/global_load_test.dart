// Loading the Whole Moon files (state/global_load.dart) through an
// AssetBundle on the synthetic sample: the four JSON files, and the DEM
// decoded in a background isolate equal to the direct decode.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/global_dem.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/state/global_load.dart';

const _fixtures = 'test/fixtures/global_sample';

class _FixtureBundle extends CachingAssetBundle {
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    // the DEM key is 'assets/data/' + map.json's `file` ('global/…')
    if (!key.startsWith(kGlobalAssetPrefix)) throw FlutterError('not a Whole Moon key: $key');
    final f = File('$_fixtures/${key.substring(kGlobalAssetPrefix.length)}');
    if (!f.existsSync()) throw FlutterError('missing fixture for $key');
    return ByteData.sublistView(f.readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadGlobalData reads the four files under the global prefix', () async {
    final b = _FixtureBundle();
    final d = await loadGlobalData(b);
    expect(b.requested.toSet(), {for (final f in kGlobalJsonFiles) '$kGlobalAssetPrefix$f'});
    expect(d.catalog.region, Region.wholeMoon);
    expect(d.catalog.sites.length, 3);
    expect(d.synthetic, isTrue);
    expect((d.demInfo.width, d.demInfo.height), (144, 72));
  });

  test('a missing file fails the load (nothing half-parsed)', () async {
    final b = _FailingBundle();
    await expectLater(loadGlobalData(b), throwsA(isA<FlutterError>()));
  });

  test('decodeGlobalDem equals CylGrid.decodePlanarSplit on the sample', () async {
    final gz = File('$_fixtures/dem_8ppd.bin.gz').readAsBytesSync();
    final direct = CylGrid.decodePlanarSplit(gz, 144, 72);
    final g = await decodeGlobalDem(gz, 144, 72);
    expect((g.width, g.height), (144, 72));
    expect(g.heights, direct.heights);
    expect(g.sum, direct.sum);
  });

  test('loadGlobalDem loads map.json\'s file through the bundle', () async {
    final b = _FixtureBundle();
    final d = await loadGlobalData(b);
    final g = await loadGlobalDem(b, d.demInfo);
    expect(b.requested.last, 'assets/data/${d.demInfo.file}');
    final direct = CylGrid.decodePlanarSplit(File('$_fixtures/dem_8ppd.bin.gz').readAsBytesSync(), 144, 72);
    expect(g.heights, direct.heights);
  });
}

class _FailingBundle extends _FixtureBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('validation.json')) throw FlutterError('offline: $key');
    return super.load(key);
  }
}
