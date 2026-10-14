/// The opening animations the app can play at start, in the order the
/// preview picker lists them. [defaultOpeningId] plays unless another is saved.
library;

import 'package:flutter/widgets.dart';

import '../intro.dart';
import 'line.dart';
import 'orbit.dart';
import 'skim.dart';

class Opening {
  final String id, title;
  final Widget Function(VoidCallback onDone) build;
  const Opening({required this.id, required this.title, required this.build});
}

final List<Opening> openings = [
  Opening(id: 'skim', title: 'Polar sunrise', build: (d) => SkimOpening(onDone: d)),
  Opening(id: 'line', title: 'Horizon line', build: (d) => LineOpening(onDone: d)),
  Opening(id: 'orbit', title: 'Sun and Earth circling', build: (d) => OrbitOpening(onDone: d)),
  Opening(id: 'classic', title: 'Classic', build: (d) => IntroSplash(onDone: d)),
];

const defaultOpeningId = 'skim';

/// Whether the Learn screen shows the opening picker (preview builds only:
/// `--dart-define=PH_OPENINGS_PREVIEW=true`).
const bool openingsPreview = bool.fromEnvironment('PH_OPENINGS_PREVIEW');

/// The opening with [id], or the default one for an unknown or missing id.
Opening openingById(String? id) =>
    openings.where((o) => o.id == id).firstOrNull ?? openings.firstWhere((o) => o.id == defaultOpeningId);
