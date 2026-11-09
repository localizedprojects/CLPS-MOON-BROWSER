/// Loading the Whole Moon files (1.14.0; docs/global_data_contract.md):
/// `assets/data/global/{sites,horizons,validation,map}.json` through an
/// [AssetBundle] the caller hands in (tests use the synthetic fixtures), and
/// the 8 px/deg whole-Moon DEM on demand, decoded without freezing the UI: in
/// a background isolate on native platforms, in short slices on the web.
///
/// Nothing here runs before the user enters Whole Moon, opens a global link
/// or the site picker's Whole Moon section (build plan §3, guard G5).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;

import '../core/catalog.dart';
import '../core/global_dem.dart';
import '../core/region.dart';
import 'global_load_io.dart' if (dart.library.js_interop) 'global_load_web.dart' as impl;

/// The asset key prefix of every Whole Moon file.
const String kGlobalAssetPrefix = 'assets/data/global/';

/// The four JSON files [loadGlobalData] reads, under [kGlobalAssetPrefix].
const List<String> kGlobalJsonFiles = ['sites.json', 'horizons.json', 'validation.json', 'map.json'];

/// The keys of a global row that [Site] does not hold (contract §2), read
/// where the app needs them.
class GlobalSiteExtra {
  /// `"core"` or `"extended"`.
  final String tier;

  /// The flat-horizon 18.6-year Earth-visible share, %, that `side` comes from.
  final double earthFlatPct;

  /// The near-field window the mask used: `"SLDEM2015 512 px/deg"`,
  /// `"LDEM_512"`, or `"none"` (the mask is LDEM_64 only, and may read low).
  final String nearFieldSource;

  /// The mean of the 2 m mask, degrees.
  final double horizonMeanDeg;

  const GlobalSiteExtra({this.tier = '', this.earthFlatPct = double.nan, this.nearFieldSource = '', this.horizonMeanDeg = double.nan});

  /// The mask had no near-field window (LDEM_64 only).
  bool get noNearField => nearFieldSource == 'none';

  factory GlobalSiteExtra.fromJson(Map<String, dynamic> j) => GlobalSiteExtra(
        tier: (j['tier'] ?? '') as String,
        earthFlatPct: (j['earthFlatPct'] as num?)?.toDouble() ?? double.nan,
        nearFieldSource: ((j['nearField'] as Map?)?['source'] ?? '') as String,
        horizonMeanDeg: (j['horizonMeanDeg'] as num?)?.toDouble() ?? double.nan,
      );
}

/// The parsed Whole Moon files.
class GlobalData {
  /// The global presets and masks, region [Region.wholeMoon].
  final SiteCatalog catalog;

  /// Per preset id, the keys [Site] does not hold.
  final Map<String, GlobalSiteExtra> extras;

  /// `global/validation.json` as decoded (badge numbers come from here).
  final Map<String, dynamic> validation;

  /// `global/map.json` as decoded (raster sizes come from here).
  final Map<String, dynamic> map;

  /// `map.json["dem"]`: the whole-Moon DEM's file and size.
  final CylDemInfo demInfo;

  /// The files say they are synthetic test fixtures (contract §7).
  final bool synthetic;

  const GlobalData(this.catalog, this.extras, this.validation, this.map, this.demInfo, {this.synthetic = false});

  /// Parse the four files' texts (in [kGlobalJsonFiles] order).
  factory GlobalData.parse(String sites, String horizons, String validation, String map) {
    final catalog = SiteCatalog.parse(sites, horizons, region: Region.wholeMoon);
    final s = jsonDecode(sites) as Map<String, dynamic>;
    final extras = {
      for (final x in s['sites'] as List) (x as Map<String, dynamic>)['id'] as String: GlobalSiteExtra.fromJson(x),
    };
    final v = jsonDecode(validation) as Map<String, dynamic>;
    final m = jsonDecode(map) as Map<String, dynamic>;
    return GlobalData(catalog, extras, v, m, CylDemInfo.fromJson(m['dem'] as Map),
        synthetic: s['synthetic'] == true || m['synthetic'] == true);
  }
}

/// Read and parse the four JSON files from [bundle] (uncached, so a failed
/// fetch is not kept for the session).
Future<GlobalData> loadGlobalData(AssetBundle bundle) async {
  final t = await Future.wait([for (final f in kGlobalJsonFiles) bundle.loadString('$kGlobalAssetPrefix$f', cache: false)]);
  return GlobalData.parse(t[0], t[1], t[2], t[3]);
}

/// The planar-split DEM [gz] of [width] × [height] (sizes from `map.json`);
/// the same grid on every platform.
Future<CylGrid> decodeGlobalDem(Uint8List gz, int width, int height) => impl.decodeGlobalDem(gz, width, height);

/// Load and decode the whole-Moon DEM that [info] describes from [bundle].
Future<CylGrid> loadGlobalDem(AssetBundle bundle, CylDemInfo info) async {
  final bd = await bundle.load('assets/data/${info.file}');
  return decodeGlobalDem(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes), info.width, info.height);
}
