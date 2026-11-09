// Test support for the Whole Moon widget tests (1.14.0 WP3): an AppState
// whose region calls run on the synthetic fixtures in
// test/fixtures/global_sample (made-up values, never bundled), and an asset
// bundle that serves those fixtures as assets/data/global/*.
//
// Since the integration, setRegion and ensureGlobal are WP2's (loading the
// fixtures through the injected bundle), counted here; addGlobalCustomSpot
// only records the spot. It never changes the polar data.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/state/app_state.dart';

const globalSampleDir = 'test/fixtures/global_sample';

/// Serves `assets/data/global/<file>` from [globalSampleDir] and records
/// every key asked for; other keys come from the test asset bundle.
class GlobalSampleBundle extends CachingAssetBundle {
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    const pre = 'assets/data/global/';
    if (!key.startsWith(pre)) return rootBundle.load(key);
    final f = File('$globalSampleDir/${key.substring(pre.length)}');
    if (!f.existsSync()) throw StateError('no fixture for $key');
    return ByteData.sublistView(f.readAsBytesSync());
  }

  /// The global keys asked for so far.
  List<String> get globalRequests => [for (final k in requested) if (k.contains('assets/data/global/')) k];
}

/// The fixture catalogue as the Whole Moon catalogue.
SiteCatalog globalSampleCatalog() => SiteCatalog.parse(
      File('$globalSampleDir/sites.json').readAsStringSync(),
      File('$globalSampleDir/horizons.json').readAsStringSync(),
      region: Region.wholeMoon,
    );

class GlobalTestState extends AppState {
  /// The Whole Moon files come from the fixtures, through WP2's loader.
  GlobalTestState() {
    globalAssetBundle = GlobalSampleBundle();
  }

  /// Every setRegion call, in order.
  final List<Region> regionCalls = [];

  /// Every addGlobalCustomSpot call.
  final List<(double, double)> placed = [];

  /// How often the Whole Moon catalogue was loaded (ensureGlobal).
  int globalLoads = 0;

  /// Load the fixture catalogue once with WP2's `ensureGlobal`, then rank
  /// its sites (an update that changes nothing commits the selection and
  /// ranks both regions). The region and the selection stay as they are.
  Future<GlobalCatalogState> attachGlobal() {
    final have = global;
    if (have != null) return Future.value(have);
    return _attach ??= _attachOnce();
  }

  Future<GlobalCatalogState>? _attach;

  Future<GlobalCatalogState> _attachOnce() async {
    globalLoads++;
    final g = await super.ensureGlobal();
    await setObserverHeight(observerHeightM);
    rankGlobal();
    notifyListeners();
    return g;
  }

  /// The global sites ranked from their cached metrics (WP2's `rankedIn`).
  void rankGlobal() => rankedIn(Region.wholeMoon);

  /// WP2's load-only call, counted.
  @override
  Future<GlobalCatalogState> ensureGlobal() => attachGlobal();

  @override
  Future<void> setRegion(Region r) async {
    regionCalls.add(r);
    await super.setRegion(r);
  }

  @override
  Future<Site?> addGlobalCustomSpot(double lat, double lon) async {
    placed.add((lat, lon));
    return null;
  }
}
