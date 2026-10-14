/// Decoding the 400 m LOLA DEM asset (custom-site horizons, the light map):
/// at once on native platforms, and in short slices on the web, where it
/// would otherwise block the only (UI) thread for hundreds of ms.
library;

import 'dart:typed_data';

import '../core/dem.dart';
import 'dem_load_io.dart' if (dart.library.js_interop) 'dem_load_web.dart' as impl;

/// The planar-split DEM [gz] (see [PolarGrid.decodePlanarSplit]); the same
/// grid on every platform.
Future<PolarGrid> decodeDem(Uint8List gz, int size, double pxM) => impl.decodeDem(gz, size, pxM);
