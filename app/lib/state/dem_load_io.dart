import 'dart:isolate';
import 'dart:typed_data';

import '../core/dem.dart';

/// Native: un-gzipped and integrated in a short-lived background isolate
/// ([Isolate.run]), so the UI keeps animating. On the shipped DEM (2280 px,
/// 4.7 MB of gzip to 10.4 MB of heights) that work takes about 120-150 ms in
/// a debug build on a desktop and longer on a phone, all of it a frozen UI if
/// it ran here. The UI isolate only copies [gz] into the message (a few ms);
/// the decoded grid comes back through [Isolate.exit] without a copy, and a
/// decode error (a size mismatch, a bad gzip) is rethrown here as itself.
/// The closure captures only this function's arguments.
Future<PolarGrid> decodeDem(Uint8List gz, int size, double pxM) =>
    Isolate.run(() => PolarGrid.decodePlanarSplit(gz, size, pxM), debugName: 'dem-decode');
