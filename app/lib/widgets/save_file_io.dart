import 'package:share_plus/share_plus.dart';

import 'save_file.dart';

/// One share sheet for every file (ACTION_SEND_MULTIPLE for two or more).
Future<void> saveFiles(List<SaveFile> files) async {
  await SharePlus.instance.share(ShareParams(
    files: [for (final f in files) XFile.fromData(f.bytes, name: f.name, mimeType: f.mimeType)],
    fileNameOverrides: [for (final f in files) f.name],
    subject: files.length == 1 ? files.first.name : files.map((f) => f.name).join(', '),
  ));
}
