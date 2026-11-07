import 'package:flutter/widgets.dart';

import '../theme.dart';

/// The app's 2 px ice focus ring round [child] while a widget inside it has
/// the keyboard focus (focus shown for a keyboard, as on the app's buttons;
/// not after a tap). For Material controls whose own focus cue is faint: the
/// time bar's slider shows only a translucent halo round its thumb and the
/// Simple view switch row only a lighter fill, neither 3:1 against the panel
/// (1.13.4 review, a11y).
///
/// It observes the focus inside and never takes it: no Tab stop and no
/// semantics node of its own. The ring is drawn just inside [child]'s edge,
/// over it, so focus moves nothing.
class KeyboardFocusRing extends StatefulWidget {
  final Widget child;

  /// The ring's corner radius (the control's own, so the ring follows it).
  final double radius;

  const KeyboardFocusRing({super.key, required this.child, this.radius = PH.radius});

  @override
  State<KeyboardFocusRing> createState() => _KeyboardFocusRingState();
}

class _KeyboardFocusRingState extends State<KeyboardFocusRing> {
  final _node = FocusNode(debugLabel: 'KeyboardFocusRing', canRequestFocus: false, skipTraversal: true);
  bool _ring = false;

  void _update() {
    final ring = _node.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (ring != _ring && mounted) setState(() => _ring = ring);
  }

  void _modeChanged(FocusHighlightMode _) => _update();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: (_) => _update(),
        child: DecoratedBox(
          key: const ValueKey('keyboard-focus-ring'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            border: _ring ? Border.all(color: PH.ice, width: 2) : null,
          ),
          child: widget.child,
        ),
      );
}
