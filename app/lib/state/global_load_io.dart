import 'dart:isolate';
import 'dart:typed_data';

import '../core/global_dem.dart';

/// Native: un-gzipped and integrated in a short-lived background isolate
/// ([Isolate.run]), as the polar DEM (dem_load_io.dart), so the UI keeps
/// animating while the 8 px/deg whole-Moon grid (2880 × 1440) is decoded.
Future<CylGrid> decodeGlobalDem(Uint8List gz, int width, int height) =>
    Isolate.run(() => CylGrid.decodePlanarSplit(gz, width, height), debugName: 'global-dem-decode');
