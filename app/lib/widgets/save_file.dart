/// Save/share generated files: browser downloads on web, one share sheet on
/// Android/iOS (lets the user save to Files/Drive or send them).
library;

import 'dart:typed_data';

import 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart' as impl;

/// One generated file.
class SaveFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  const SaveFile(this.name, this.bytes, this.mimeType);
}

/// Save or share [files] together: a single share sheet on Android/iOS
/// (share_plus clears its cache folder before every share, so a second sheet
/// opened right after a first one would delete the first one's file), one
/// download per file on web.
Future<void> saveFiles(List<SaveFile> files) => files.isEmpty ? Future.value() : impl.saveFiles(files);

Future<void> saveBytes(String fileName, Uint8List bytes, String mimeType) => saveFiles([SaveFile(fileName, bytes, mimeType)]);
