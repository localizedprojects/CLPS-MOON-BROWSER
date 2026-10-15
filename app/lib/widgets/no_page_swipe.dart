/// Keeps a sideways drag on [child] from turning the page of a PageView
/// around it (the Site tabs): the drag is claimed here and does nothing, so
/// a slider, a list or a chart inside still gets it first. Vertical drags
/// and taps pass through untouched.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class NoPageSwipe extends StatelessWidget {
  final Widget child;
  const NoPageSwipe({super.key, required this.child});

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    excludeFromSemantics: true,
    // its whole box, margins too, so a drag just beside the slider is not a
    // page swipe either
    behavior: HitTestBehavior.translucent,
    gestures: {
      HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
        HorizontalDragGestureRecognizer.new,
        // a handler is needed, or the recogniser never joins in
        (r) => r..onUpdate = (_) {},
      ),
    },
    child: child,
  );
}
