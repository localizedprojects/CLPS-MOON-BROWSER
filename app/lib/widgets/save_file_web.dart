import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'save_file.dart';

/// One browser download per file.
Future<void> saveFiles(List<SaveFile> files) async {
  for (final f in files) {
    final blob = web.Blob([f.bytes.toJS].toJS, web.BlobPropertyBag(type: f.mimeType));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = f.name
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    // revoke after the browser has started the download (an immediate revoke
    // can cancel the second of two downloads in some browsers)
    Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
  }
}

/// Nothing to set up on web.
void saveFilesInit() {}
