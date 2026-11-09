/// The Lander's 3D view entry for global presets (1.14.0 build plan WP5,
/// a stretch goal that ships only with pipeline-built 400 m tiles).
///
/// WP0 stub: [kGlobalLander] is false and [globalLanderEntry] draws nothing,
/// so the global Overview can place it from the start. WP5 owns this file.
library;

import 'package:flutter/widgets.dart';

import '../core/catalog.dart';

/// Whether the Lander's view is offered for global presets.
const bool kGlobalLander = false;

/// The Overview's entry to the Lander's view for the global preset [site];
/// nothing while [kGlobalLander] is false.
Widget globalLanderEntry(BuildContext context, Site site) => const SizedBox.shrink();
