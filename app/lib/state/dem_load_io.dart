import 'dart:typed_data';

import '../core/dem.dart';

/// Native: decoded in one go (tens of ms, once per run).
Future<PolarGrid> decodeDem(Uint8List gz, int size, double pxM) async => PolarGrid.decodePlanarSplit(gz, size, pxM);
