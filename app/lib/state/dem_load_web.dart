import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

import '../core/dem.dart';
import 'light_engine.dart' show runSliced;

Future<void> _yield() => Future<void>.delayed(Duration.zero);

/// Web (no isolates in this build): the browser un-gzips the bytes off the
/// main thread (DecompressionStream; the pure-Dart decoder, one blocking
/// call, only where that is missing), then the residuals are integrated on
/// the main thread in slices of about 20 ms ([runSliced]) with an event-loop
/// turn between them.
Future<PolarGrid> decodeDem(Uint8List gz, int size, double pxM) async {
  List<int> raw;
  try {
    raw = await _gunzip(gz);
  } catch (_) {
    raw = const GZipDecoder().decodeBytes(gz);
  }
  final work = PlanarSplitWork(raw, size, pxM);
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
