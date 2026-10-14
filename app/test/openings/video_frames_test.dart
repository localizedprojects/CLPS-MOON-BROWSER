// Video frames of every opening: one PNG per 1/30 s on a 390 x 844 phone at
// 2x, until the opening is done plus 0.6 s of its held last picture. Runs
// only when PH_FRAMES names a folder:
//   PH_FRAMES=C:/some/dir flutter test test/openings/video_frames_test.dart
// then encode each folder, e.g.
//   ffmpeg -framerate 30 -i <dir>/skim/f%04d.png -c:v libx264 -pix_fmt yuv420p -crf 16 skim.mp4
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/openings/openings.dart';
import 'package:polar_horizon/theme.dart';

import 'frame_sheet.dart';

final _dir = Platform.environment['PH_FRAMES'];

void main() {
  for (final o in openings) {
    testWidgets('video frames: ${o.id}', (tester) async {
      await loadAppFonts();
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      var frame = 0, doneAt = -1;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(backgroundColor: PH.bg, body: o.build(() => doneAt = doneAt < 0 ? frame : doneAt)),
        ),
      ));
      final out = Directory('$_dir/${o.id}')..createSync(recursive: true);
      for (final f in out.listSync()) {
        f.deleteSync();
      }
      const step = Duration(microseconds: 1000000 ~/ 30);
      while (frame < 180 && (doneAt < 0 || frame < doneAt + 18)) {
        if (frame > 0) await tester.pump(step);
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          img.dispose();
          return data!.buffer.asUint8List();
        });
        File('${out.path}/f${frame.toString().padLeft(4, '0')}.png').writeAsBytesSync(png!);
        frame++;
      }
      await tester.pumpWidget(const SizedBox());
    }, skip: _dir == null);
  }
}
