/// Decoding the 400 m LOLA DEM asset (custom-site horizons, the light map)
/// without freezing the UI: in a background isolate on native platforms, and
/// on the web (no isolates here) by the browser's own gunzip followed by the
/// integration in short slices on the only (UI) thread.
library;

import 'dart:typed_data';

import '../core/dem.dart';
import 'dem_load_io.dart' if (dart.library.js_interop) 'dem_load_web.dart' as impl;

/// The planar-split DEM [gz] (see [PolarGrid.decodePlanarSplit]); the same
/// grid on every platform (test/state/dem_load_test).
Future<PolarGrid> decodeDem(Uint8List gz, int size, double pxM) => impl.decodeDem(gz, size, pxM);
