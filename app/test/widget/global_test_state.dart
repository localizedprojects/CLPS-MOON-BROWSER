// Test support for the Whole Moon widget tests (1.14.0 WP3): an AppState
// whose region calls run on the synthetic fixtures in
// test/fixtures/global_sample (made-up values, never bundled), and an asset
// bundle that serves those fixtures as assets/data/global/*.
//
// Until WP2's AppState lands, setRegion, ensureGlobal and
// addGlobalCustomSpot are stubs there; this subclass gives them just enough
// behaviour for the UI tests. It never changes the polar data.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/summary.dart' show rank;
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
  /// Every setRegion call, in order.
  final List<Region> regionCalls = [];

  /// Every addGlobalCustomSpot call.
  final List<(double, double)> placed = [];

  /// How often the Whole Moon catalogue was loaded (ensureGlobal).
  int globalLoads = 0;

  SiteCatalog? _cat;

  /// Load the fixture catalogue once: [global], its masks next to the polar
  /// ones (so series can be computed for its ids) and its metrics and
  /// ranking. The polar selection is kept.
  Future<GlobalCatalogState> attachGlobal() async {
    final have = global;
    if (have != null) return have;
    globalLoads++;
    final cat = _cat ??= globalSampleCatalog();
    catalog!.masks.addAll(cat.masks);
    final g = global = GlobalCatalogState(cat);
    final keep = selectedId;
    for (final x in cat.sites) {
      await selectSite(x.id);
    }
    await selectSite(keep);
    rankGlobal();
    notifyListeners();
    return g;
  }

  /// Rank the global sites from their cached metrics.
  void rankGlobal() {
    final g = global!;
    g.ranked = rank({
      for (final x in [...g.catalog.sites, ...g.customSites])
        if (metricsFor(x.id) case final m?) x.id: (x.short, m),
    }, weights);
    g.rankRunning = false;
  }

  /// WP2's load-only call (the site picker reaches it dynamically).
  Future<GlobalCatalogState> ensureGlobal() => attachGlobal();

  String? _polarId;

  @override
  Future<void> setRegion(Region r) async {
    regionCalls.add(r);
    if (r == region) return;
    if (r == Region.wholeMoon) {
      await attachGlobal();
      _polarId = selectedId;
      region = r;
      await selectSite(kGlobalDefaultSiteId);
    } else {
      region = r;
      await selectSite(_polarId ?? 'derosa2012-sr1-shackleton-rim');
    }
    notifyListeners();
  }

  @override
  Future<Site?> addGlobalCustomSpot(double lat, double lon) async {
    placed.add((lat, lon));
    return null;
  }
}
