// The bundled IBM Plex fonts for the light & shadow layout tests, so text
// measures (and the view / layer switches fit or wrap) as in the app.
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled IBM Plex fonts, so text measures as in the app.
Future<void> loadPlexFonts() async {
  for (final (family, files) in const [
    ('IBM Plex Sans', ['Regular', 'Medium', 'SemiBold', 'Bold']),
    ('IBM Plex Mono', ['Regular', 'Medium', 'SemiBold']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/${family.replaceAll(' ', '')}-$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}
