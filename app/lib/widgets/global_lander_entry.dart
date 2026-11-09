/// The Lander's 3D view entry for global presets (1.14.0 build plan WP5,
/// a stretch goal that ships only with pipeline-built 400 m tiles).
///
/// The global Overview places [globalLanderEntry] under its site notes. It
/// draws nothing while [kGlobalLander] is false (the WP5 gate), nor for a
/// site without a Lander terrain tile (custom spots, presets the pipeline
/// built no tile for). Otherwise it is one button that opens the Lander's
/// view full screen ([openLanderFullScreen]): the terrain from the site's
/// LOLA tile in its map frame, the Sun and Earth at their exact positions,
/// grey ground (no light map outside the south pole in this version).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalog.dart';
import '../state/app_state.dart';
import '../state/global_tiles.dart';
import '../state/light_engine.dart' show LightLayer;
import '../theme.dart';
import 'focus_semantics.dart';
import 'lander_full_screen.dart';

/// Whether the Lander's view is offered for global presets.
const bool kGlobalLander = false;

/// The Overview's entry to the Lander's view for the global preset [site];
/// nothing while [kGlobalLander] is false.
Widget globalLanderEntry(BuildContext context, Site site) =>
    kGlobalLander ? GlobalLanderEntry(key: ValueKey('global-lander-entry-${site.id}'), site: site) : const SizedBox.shrink();

/// The entry itself (shown only when [site] has a tile).
class GlobalLanderEntry extends StatefulWidget {
  final Site site;

  /// The app state (tests); else the one the widget tree provides.
  final AppState? state;
  const GlobalLanderEntry({super.key, required this.site, this.state});

  /// The button's words.
  static const buttonText = "Lander's view";

  /// The button's accessible name for [site].
  static String semanticLabel(Site site) => "Lander's view: the horizon around ${site.short} in 3D, full screen";

  /// The line under the button.
  static const note = 'Seen from the lander\'s height above the ground, with LOLA terrain around the site. The ground '
      'is drawn grey: the Light & shadow map covers south-pole sites only in this version.';

  @override
  State<GlobalLanderEntry> createState() => _GlobalLanderEntryState();
}

class _GlobalLanderEntryState extends State<GlobalLanderEntry> {
  late Future<bool> _has = globalTiles.hasTile(widget.site);

  @override
  void didUpdateWidget(GlobalLanderEntry old) {
    super.didUpdateWidget(old);
    if (old.site.id != widget.site.id || old.site.lat != widget.site.lat || old.site.lon != widget.site.lon) {
      _has = globalTiles.hasTile(widget.site);
    }
  }

  Future<void> _open() {
    final s = widget.state ?? context.read<AppState>();
    // no light layers at a whole-Moon site: the page shows none
    return openLanderFullScreen(context, state: s, layer: LightLayer.sun, onLayer: (_) {});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _has,
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: GlobalLanderEntry.semanticLabel(widget.site),
              onTap: _open,
              child: FocusSemantics(
                child: OutlinedButton.icon(
                  key: const ValueKey('global-lander-open'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _open,
                  icon: const Icon(Icons.landscape_outlined, size: 20),
                  label: const Text(GlobalLanderEntry.buttonText),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(GlobalLanderEntry.note, style: PHText.small.copyWith(color: PH.muted)),
          ],
        ),
      );
    },
  );
}
