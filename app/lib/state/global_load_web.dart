import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

import '../core/global_dem.dart';
import 'light_engine.dart' show runSliced;

Future<void> _yield() => Future<void>.delayed(Duration.zero);

/// Web (no isolates in this build), as the polar DEM (dem_load_web.dart): the
/// browser un-gzips the bytes off the main thread (DecompressionStream; the
/// pure-Dart decoder only where that is missing), then the residuals are
/// integrated on the main thread in slices of about 20 ms ([runSliced],
/// [CylSplitWork.step]) with an event-loop turn between them.
Future<CylGrid> decodeGlobalDem(Uint8List gz, int width, int height) async {
  List<int> raw;
  try {
    raw = await _gunzip(gz);
  } catch (_) {
    raw = const GZipDecoder().decodeBytes(gz);
  }
  final work = CylSplitWork(raw, width, height);
  await runSliced(work.step, pause: _yield);
  return work.result;
}

Future<Uint8List> _gunzip(Uint8List gz) async {
  final ds = web.DecompressionStream('gzip');
  final blob = web.Blob(<JSAny>[gz.toJS].toJS);
  final out = blob.stream().pipeThrough(web.ReadableWritablePair(readable: ds.readable, writable: ds.writable));
  final buf = await web.Response(out).arrayBuffer().toDart;
  return buf.toDart.asUint8List();
}
