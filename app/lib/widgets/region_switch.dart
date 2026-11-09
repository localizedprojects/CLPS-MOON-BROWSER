/// The region switch on Explore (1.14.0 "Whole Moon"): SOUTH POLE | WHOLE
/// MOON. South pole is the default; the choice is never saved (build plan
/// §2, §3): only this switch or a link (`#/moon`, `#/site/<global id>`)
/// changes it.
///
/// A segmented button, so it gets the theme's 48 dp height, neutral-navy
/// selection and the 2 px ice focus ring that follows the keyboard
/// ([FocusRings]); the selected segment also carries a check mark and a
/// heavier label, so colour is never the only cue.
///
/// The button's outline rings the whole switch for either segment, so the
/// focused segment also carries its own 2 px ice ring inside it while the
/// keyboard highlight shows (1.14.0 device check: which segment had the
/// focus was hard to see).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'focus_rings.dart';

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
    final ringed = RegionSegmentRing(key: const ValueKey('region-switch-ring'), show: FocusRings.of(context), child: seg);
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
            LayoutBuilder(builder: (context, c) => c.maxWidth < 320 ? FittedBox(child: ringed) : ringed),
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

/// Gap (dp) between a segment's edge and its own focus ring, clear of the
/// switch's 2 px outline.
const double regionSegmentRingInset = 4;

/// Paints a 2 px ice ring inside whichever of [child]'s segments has the
/// primary focus, while [show] (the keyboard highlight, [FocusRings]); it
/// follows the focus as it moves (the focus manager's notifications).
class RegionSegmentRing extends SingleChildRenderObjectWidget {
  final bool show;
  const RegionSegmentRing({super.key, required this.show, required Widget super.child});

  @override
  RenderRegionSegmentRing createRenderObject(BuildContext context) => RenderRegionSegmentRing(show);

  @override
  void updateRenderObject(BuildContext context, RenderRegionSegmentRing renderObject) => renderObject.show = show;
}

class RenderRegionSegmentRing extends RenderProxyBox {
  RenderRegionSegmentRing(this._show);

  bool _show;
  set show(bool v) {
    if (v == _show) return;
    _show = v;
    markNeedsPaint();
  }

  void _focusChanged() {
    if (attached) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void detach() {
    FocusManager.instance.removeListener(_focusChanged);
    super.detach();
  }

  /// The focused segment's box in this box's coordinates; null when the
  /// primary focus is not inside [child].
  Rect? focusedSegment() {
    final box = FocusManager.instance.primaryFocus?.context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    RenderObject? o = box;
    while (o != null && !identical(o, this)) {
      o = o.parent;
    }
    if (o == null || identical(box, this)) return null;
    return MatrixUtils.transformRect(box.getTransformTo(this), Offset.zero & box.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_show) return;
    final seg = focusedSegment();
    if (seg == null) return;
    final r = seg.deflate(regionSegmentRingInset);
    if (r.isEmpty) return;
    // the pill's round ends on the switch's outer sides, small radii between the segments
    final end = Radius.circular(r.height / 2), mid = const Radius.circular(PH.radius);
    final atLeft = seg.left <= 1, atRight = seg.right >= size.width - 1;
    context.canvas.drawRRect(
      RRect.fromRectAndCorners(r.shift(offset),
          topLeft: atLeft ? end : mid, bottomLeft: atLeft ? end : mid, topRight: atRight ? end : mid, bottomRight: atRight ? end : mid),
      Paint()
        ..color = PH.ice
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
