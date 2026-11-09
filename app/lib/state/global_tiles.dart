/// The Lander's view terrain for global presets (1.14.0 build plan WP5):
/// `assets/data/global/tiles.json` and one `global/tiles/<id>.bin.gz` per
/// preset, written by `python -m lunarsp.globe_tiles` (LOLA LDEM_64 area
/// mean, 512 px of 400 m laid out in the site's map frame,
/// `core/map_frame.dart`; the polar 400 m DEM's encoding and `DemInfo`
/// rules). Nothing is requested until a global site's Lander's view asks
/// (build plan §3 lazy loading); a south-pole session never loads it.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/catalog.dart' show Site;
import '../core/dem.dart';
import '../core/map_frame.dart';
import '../core/region.dart';

/// One preset's tile ([GlobalTilesIndex.tiles]).
class GlobalTileInfo {
  final String id, file, sha256;
  final double centreLat, centreLon;
  const GlobalTileInfo(this.id, this.file, this.sha256, this.centreLat, this.centreLon);
}

/// `global/tiles.json`.
class GlobalTilesIndex {
  /// The tile grid as the polar DEM's `DemInfo` (size divisible by 4,
  /// halfWidthM = size × pxM / 2, all inner block): [DemInfo.fromJson] checks it.
  final DemInfo grid;

  /// The source raster's pixel (m at the equator; LDEM_64: about 474 m).
  final double sourcePxM;
  final String source, projection;
  final Map<String, GlobalTileInfo> tiles;
  const GlobalTilesIndex(this.grid, this.sourcePxM, this.source, this.projection, this.tiles);

  /// Throws [FormatException] when the grid breaks the `DemInfo` rules or a
  /// tile is not under `global/tiles/`.
  factory GlobalTilesIndex.parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final size = m['sizePx'] as int, pxM = (m['pxM'] as num).toDouble();
    final grid = DemInfo.fromJson({'file': 'global/tiles/', 'size': size, 'pxM': pxM, 'halfWidthM': m['halfWidthM']});
    final tiles = <String, GlobalTileInfo>{};
    for (final e in (m['tiles'] as Map<String, dynamic>).entries) {
      final t = e.value as Map<String, dynamic>;
      final file = t['file'] as String;
      if (file != 'global/tiles/${e.key}.bin.gz') throw FormatException('tile ${e.key}: unexpected file $file');
      tiles[e.key] = GlobalTileInfo(e.key, file, t['sha256'] as String, (t['centreLat'] as num).toDouble(),
          (t['centreLon'] as num).toDouble());
    }
    return GlobalTilesIndex(grid, (m['sourcePxM'] as num).toDouble(), m['source'] as String,
        m['projection'] as String, tiles);
  }

  /// [site]'s tile: a global preset whose tile was built at its very
  /// coordinates (never a tile built for other ones); null otherwise
  /// (polar sites, custom spots, presets without a tile).
  GlobalTileInfo? forSite(Site site) {
    if (site.region != Region.wholeMoon || site.custom) return null;
    final t = tiles[site.id];
    return t != null && t.centreLat == site.lat && t.centreLon == site.lon ? t : null;
  }

  /// Half the tile's side, km (102.4 for 512 px of 400 m).
  double get halfWidthKm => grid.halfWidthM / 1000;

  /// The terrain part of the global Lander's FidelityBadge (build plan §2,
  /// item 5), its numbers from this file.
  String get terrainText => 'Terrain LOLA ${sourcePxM.round()} m resampled to ${grid.pxM.round()} m, '
      '±${_km(halfWidthKm)} km around the site; relief under ~1 km smoothed, terrain beyond '
      '${_km(halfWidthKm)} km not drawn.';

  static String _km(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// A decoded tile and the frame it is laid out in.
typedef GlobalTile = ({PolarGrid grid, MapFrame frame, GlobalTileInfo info});

/// Loads the index once and tiles on demand (the last two kept).
class GlobalTiles {
  final Future<String> Function(String key) _loadString;
  final Future<List<int>> Function(String key) _loadBytes;
  GlobalTiles({Future<String> Function(String key)? loadString, Future<List<int>> Function(String key)? loadBytes})
      : _loadString = loadString ?? rootBundle.loadString,
        _loadBytes = loadBytes ?? ((k) async => (await rootBundle.load(k)).buffer.asUint8List());

  static const indexKey = 'assets/data/global/tiles.json';

  Future<GlobalTilesIndex>? _index;
  GlobalTilesIndex? _loaded;
  final _tiles = <String, Future<GlobalTile>>{};

  /// The index, once it has loaded (null before, or when it failed).
  GlobalTilesIndex? get loadedIndex => _loaded;

  /// The index (loaded on first call; a failure is retried on the next).
  Future<GlobalTilesIndex> index() => _index ??= () async {
        try {
          return _loaded = GlobalTilesIndex.parse(await _loadString(indexKey));
        } catch (_) {
          _index = null;
          rethrow;
        }
      }();

  /// Whether [site] has a tile (loads the index).
  Future<bool> hasTile(Site site) async {
    if (site.region != Region.wholeMoon) return false;
    try {
      return (await index()).forSite(site) != null;
    } catch (_) {
      return false;
    }
  }

  /// [site]'s decoded tile and frame; throws [StateError] when it has none.
  /// The decode runs in slices of 64 rows (the web's single thread).
  Future<GlobalTile> tileFor(Site site) async {
    final ix = await index();
    final info = ix.forSite(site);
    if (info == null) throw StateError('no Lander terrain tile for ${site.id}');
    final key = '${info.id}|${info.sha256}';
    final hit = _tiles.remove(key);
    final f = hit ?? _decode(ix, info);
    _tiles[key] = f;
    while (_tiles.length > 2) {
      _tiles.remove(_tiles.keys.first);
    }
    try {
      return await f;
    } catch (_) {
      _tiles.remove(key);
      rethrow;
    }
  }

  Future<GlobalTile> _decode(GlobalTilesIndex ix, GlobalTileInfo info) async {
    final gz = await _loadBytes('assets/data/${info.file}');
    final raw = const GZipDecoder().decodeBytes(gz);
    final w = PlanarSplitWork(raw, ix.grid.size, ix.grid.pxM);
    while (!w.step(64)) {
      await Future<void>.delayed(Duration.zero);
    }
    return (grid: w.result, frame: MapFrame.at(info.centreLat, info.centreLon), info: info);
  }
}

/// The app's tiles (tests replace it with [debugGlobalTiles]).
GlobalTiles get globalTiles => _override ?? (_app ??= GlobalTiles());
GlobalTiles? _app, _override;

/// Replaces [globalTiles] in tests (null restores the app's).
set debugGlobalTiles(GlobalTiles? t) => _override = t;
