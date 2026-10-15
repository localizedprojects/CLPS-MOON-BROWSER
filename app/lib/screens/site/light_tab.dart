/// Site › Light & shadow: the computed light & shadow map and a compact,
/// pinned time bar.
library;

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../widgets/explain.dart';
import '../../widgets/light_map.dart';
import '../../widgets/time_bar.dart';

class LightTab extends StatelessWidget {
  final AppState state;
  const LightTab({super.key, required this.state});

  static const _pad = EdgeInsets.all(6);

  /// Below this height the time bar is not pinned (it would leave no room
  /// for the map); the tab scrolls as a whole instead.
  static const minPinnedHeight = 380.0;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final note = s.explainInline ? explainLight : null;
    LightMap lightMap({Widget? sideTop}) => LightMap(
      state: s,
      active: s.dest == Dest.site && s.siteTab == SiteTab.light,
      onSelect: (id) => s.openSite(id, tab: SiteTab.light),
      sideNote: note,
      sideTop: sideTop,
    );
    // Play hides the top bars on a phone (as on Sky & time)
    return PlayHidesBars(
      state: s,
      tab: SiteTab.light,
      child: LayoutBuilder(
        builder: (context, c) {
          // a phone in landscape: the map takes the whole height and the time
          // bar is pinned in the column beside it (above or below it the map
          // would shrink to a thumbnail)
          if (LightMap.shortSideBySideFor(c.deflate(_pad))) {
            return Padding(
              padding: _pad,
              child: lightMap(sideTop: TimeBar(state: s, compact: true, alignTop: true)),
            );
          }
          // too short to pin the bar and still show a usable map (large text on a
          // small phone): the bar first, then the map, all in one scroll
          if (c.maxHeight < minPinnedHeight) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TimeBar(state: s, compact: true, alignTop: true),
                  Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 6), child: lightMap()),
                ],
              ),
            );
          }
          // elsewhere the time bar is pinned under the map's slot; LightMap pins
          // its view / layer switches above the map when a usable whole map still
          // fits under them, and scrolls the status, legend and notes below it
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: lightMap()),
              ),
              TimeBar(state: s, compact: true),
            ],
          );
        },
      ),
    );
  }
}
