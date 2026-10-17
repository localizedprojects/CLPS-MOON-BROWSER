import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'save_file.dart';

Offset? _lastTap;
bool _tracking = false;

/// Remembers where the user last touched, so the iPad share popover points at the tapped button.
/// The file is shared after the chart page answers, so the button's context is gone by then.
void _trackTaps() {
  if (_tracking) return;
  _tracking = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent) _lastTap = event.position;
  });
}

/// iPad needs a source rect for the popover (share_plus throws without one): the last tap, or the screen centre.
Rect _origin() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final size = views.isEmpty ? const Size(2, 2) : views.first.physicalSize / views.first.devicePixelRatio;
  final c = _lastTap ?? size.center(Offset.zero);
  return Rect.fromCenter(center: c, width: 2, height: 2);
}

/// One share sheet for every file (ACTION_SEND_MULTIPLE for two or more).
Future<void> saveFiles(List<SaveFile> files) async {
  await SharePlus.instance.share(ShareParams(
    files: [for (final f in files) XFile.fromData(f.bytes, name: f.name, mimeType: f.mimeType)],
    fileNameOverrides: [for (final f in files) f.name],
    subject: files.length == 1 ? files.first.name : files.map((f) => f.name).join(', '),
    sharePositionOrigin: _origin(),
  ));
}

/// Start tracking taps as soon as the app runs (called from main via saveFilesInit).
void saveFilesInit() => _trackTaps();
