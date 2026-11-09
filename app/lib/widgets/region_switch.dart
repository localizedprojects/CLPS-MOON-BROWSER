/// The region switch on Explore (1.14.0 "Whole Moon"): SOUTH POLE | WHOLE
/// MOON. South pole is the default; the choice is never saved (build plan
/// §2, §3): only this switch or a link (`#/moon`, `#/site/<global id>`)
/// changes it.
///
/// A segmented button, so it gets the theme's 48 dp height, neutral-navy
/// selection and the 2 px ice focus ring that follows the keyboard
/// ([FocusRings]); the selected segment also carries a check mark and a
/// heavier label, so colour is never the only cue.
library;

import 'package:flutter/material.dart';

import '../core/region.dart';
import '../theme.dart';

/// The two segment labels, in order.
const regionSwitchLabels = {Region.southPole: 'South pole', Region.wholeMoon: 'Whole Moon'};

/// What a screen reader says for the switch as a whole.
const regionSwitchSemantics = 'Region: the south pole, or the whole Moon';

class RegionSwitch extends StatelessWidget {
  final Region region;
  final ValueChanged<Region> onChanged;

  /// Busy while the whole-Moon sites load (the first switch only).
  final bool busy;
  const RegionSwitch({super.key, required this.region, required this.onChanged, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final seg = SegmentedButton<Region>(
      key: const ValueKey('region-switch'),
      segments: [
        for (final r in Region.values)
          ButtonSegment(
            value: r,
            label: Text(regionSwitchLabels[r]!, maxLines: 1, softWrap: false),
            tooltip: r == Region.southPole
                ? 'Detailed south-pole terrain and light map'
                : 'Landing sites across the whole Moon',
          ),
      ],
      selected: {region},
      onSelectionChanged: (v) {
        if (v.first != region) onChanged(v.first);
      },
    );
    return Semantics(
      container: true,
      label: regionSwitchSemantics,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            const ExcludeSemantics(child: MicroLabel('REGION')),
            // a wide text size: the two segments may need the whole row
            LayoutBuilder(builder: (context, c) => c.maxWidth < 320 ? FittedBox(child: seg) : seg),
            if (busy)
              Semantics(
                container: true,
                liveRegion: true,
                label: 'Loading the whole-Moon sites',
                child: const BusyIndicator(size: 16),
              ),
          ],
        ),
      ),
    );
  }
}
