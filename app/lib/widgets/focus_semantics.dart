import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// Keeps a custom control's keyboard focus in its one semantics node.
///
/// Many controls describe themselves with one node, `Semantics(button: true,
/// label: ..., onTap: ...)` over a button or ink well, and exclude what is
/// inside. Excluding also dropped the inner widget's focus semantics, so the
/// node was not focusable (on the web: no DOM tabindex) and never said it had
/// focus: Tab moved Flutter's focus and the ice ring, while the browser's
/// focus, and so the screen reader, stayed on an earlier control (1.13.4
/// review, a11y).
///
/// Use it as the child of that [Semantics], in place of its
/// `excludeSemantics: true`: it excludes [child]'s semantics itself and adds
/// `focusable`, `focused` and the focus action to the same node. Focused means
/// a focusable widget inside [child] has the keyboard focus; the focus action
/// (a screen reader, or the web's DOM focus) gives that widget the focus.
/// [enabled] false (a disabled control) leaves the node unfocusable.
class FocusSemantics extends StatefulWidget {
  final bool enabled;
  final Widget child;
  const FocusSemantics({super.key, this.enabled = true, required this.child});

  @override
  State<FocusSemantics> createState() => _FocusSemanticsState();
}

class _FocusSemanticsState extends State<FocusSemantics> {
  // observes the focus inside; never takes it, never a Tab stop
  final _node = FocusNode(debugLabel: 'FocusSemantics', canRequestFocus: false, skipTraversal: true);
  bool _focused = false;

  void _changed(bool f) {
    if (f != _focused && mounted) setState(() => _focused = f);
  }

  void _focus() {
    if (_node.hasFocus) return; // already on this control (or a part of it)
    for (final n in _node.descendants) {
      if (n.canRequestFocus && !n.skipTraversal) {
        n.requestFocus();
        return;
      }
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: _changed,
        child: Semantics(
          focusable: widget.enabled,
          focused: widget.enabled && _focused,
          // as Focus does: not on iOS (flutter/flutter#150030)
          onFocus: widget.enabled && defaultTargetPlatform != TargetPlatform.iOS ? _focus : null,
          excludeSemantics: true,
          child: widget.child,
        ),
      );
}
