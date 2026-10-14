// Contact sheets for the opening animations: frames across a run, drawn into
// one PNG with the time under each, so an opening can be reviewed without a
// device. Sheet tests run only when PH_SHEETS names an output folder:
//   PH_SHEETS=C:/some/dir flutter test test/openings/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/theme.dart';

/// The folder for contact sheets, or null (sheet tests skip).
String? get sheetsDir => Platform.environment['PH_SHEETS'];

/// Loads the bundled IBM Plex fonts so text in the frames is real text.
Future<void> loadAppFonts() async {
  for (final (family, file, weights) in [
    ('IBM Plex Sans', 'IBMPlexSans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
    ('IBM Plex Mono', 'IBMPlexMono', ['Regular']),
  ]) {
    final loader = FontLoader(family);
    for (final w in weights) {
      loader.addFont(rootBundle.load('assets/fonts/$file-$w.ttf'));
    }
    await loader.load();
  }
}

/// Plays [build] in a phone-sized view ([phone] logical px) and writes
/// `<name>.png` (whole screen, [frames] frames over [total]) and
/// `<name>-logo.png` (the middle [crop] at full size, same moments) to
/// [sheetsDir]. Frames after the opening calls done show its last picture.
Future<void> writeContactSheets(
  WidgetTester tester,
  String name,
  Widget Function(VoidCallback onDone) build, {
  Duration total = const Duration(milliseconds: 3600),
  int frames = 16,
  Size phone = const Size(390, 844),
  Size crop = const Size(300, 340),
}) async {
  final dir = sheetsDir!;
  await loadAppFonts();
  tester.view.physicalSize = phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  var doneAt = -1;
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(key: key, child: Scaffold(backgroundColor: PH.bg, body: Builder(builder: (_) => build(() => doneAt = doneAt < 0 ? 1 : doneAt)))),
  ));
  final step = total ~/ (frames - 1);
  final shots = <(ui.Image, int, bool)>[];
  var ms = 0;
  for (var i = 0; i < frames; i++) {
    if (i > 0) {
      await tester.pump(step);
      ms += step.inMilliseconds;
    }
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
    shots.add((img!, ms, doneAt > 0));
  }
  final whole = Rect.fromLTWH(0, 0, phone.width, phone.height);
  final mid = Rect.fromCenter(center: whole.center, width: crop.width, height: crop.height);
  await _sheet(tester, '$dir/$name.png', shots, whole, scale: 0.5, cols: 8);
  await _sheet(tester, '$dir/$name-logo.png', shots, mid, scale: 1, cols: 8);
  await tester.pumpWidget(const SizedBox()); // disposes the opening (no timers left)
}

Future<void> _sheet(WidgetTester tester, String path, List<(ui.Image, int, bool)> shots, Rect src,
    {required double scale, required int cols}) async {
  const gap = 6.0, label = 22.0;
  final cw = src.width * scale, ch = src.height * scale;
  final rows = (shots.length / cols).ceil();
  final w = gap + cols * (cw + gap), h = gap + rows * (ch + label + gap);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF000000));
  for (var i = 0; i < shots.length; i++) {
    final (img, ms, done) = shots[i];
    final x = gap + (i % cols) * (cw + gap), y = gap + (i ~/ cols) * (ch + label + gap);
    c.drawImageRect(img, src, Rect.fromLTWH(x, y, cw, ch), Paint()..filterQuality = FilterQuality.medium);
    final tp = TextPainter(
      text: TextSpan(
          text: '$ms ms${done ? '  done' : ''}',
          style: const TextStyle(color: Color(0xFFDDE6F3), fontSize: 13, fontFamily: 'IBM Plex Mono')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(x + 3, y + ch + 3));
  }
  final png = await tester.runAsync(() async {
    final img = await rec.endRecording().toImage(w.ceil(), h.ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!);
}
