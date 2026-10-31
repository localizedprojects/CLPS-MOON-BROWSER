/// Stepping through the sites in the app's order (the Lander's view full
/// screen's previous / next buttons, docs/landers_view_spec.md "Full screen
/// and site switching", 1.10.0).
library;

import 'catalog.dart';

/// The sites before and after [id] in [sites] (the app's order: the presets,
/// then the user's own spots, `AppState.allSites`), wrapping around at both
/// ends. Null when there is nothing to step to: fewer than two sites, or [id]
/// is not in [sites].
({Site prev, Site next})? siteNeighbours(List<Site> sites, String id) {
  if (sites.length < 2) return null;
  final i = sites.indexWhere((s) => s.id == id);
  if (i < 0) return null;
  final n = sites.length;
  return (prev: sites[(i - 1 + n) % n], next: sites[(i + 1) % n]);
}
