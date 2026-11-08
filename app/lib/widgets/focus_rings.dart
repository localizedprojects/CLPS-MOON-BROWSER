import 'package:flutter/material.dart';

import '../theme.dart';

/// The app's 2 px ice focus rings follow the keyboard, as Flutter's own focus
/// highlights do: they show while [FocusManager.highlightMode] is
/// [FocusHighlightMode.traditional] (the last input was a key) and hide once
/// the screen is touched ([FocusHighlightMode.touch]), while the focus stays
/// where it was, so the next Tab goes on from there and shows them again.
///
/// Material marks a control [WidgetState.focused] whenever it has the focus,
/// whether or not the highlight shows, and the theme's rings follow that
/// state: after Tab and Escape the Mission settings pill kept its ring
/// through later taps and tab changes (1.13.5). On Android a key from a
/// virtual keyboard device (an IME, or `adb shell input keyevent`) leaves
/// the mode at touch, so the buttons showed a ring there while the controls
/// that follow the mode (a web address) did not.
///
/// Put one above the app's navigator (MaterialApp.builder). It gives the
/// buttons, segmented buttons and chips the theme parts whose rings match
/// the mode ([buildTheme] `focusRings`), so they rebuild when it changes,
/// and [FocusRings.of] tells the app's own controls whether to draw theirs.
class FocusRings extends StatefulWidget {
  final Widget child;
  const FocusRings({super.key, required this.child});

  /// Whether keyboard focus rings show now. True with no [FocusRings] above
  /// (a control tested on its own), as before.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FocusRingsScope>()?.show ?? true;

  @override
  State<FocusRings> createState() => _FocusRingsState();
}

class _FocusRingsState extends State<FocusRings> {
  static final _keyboard = buildTheme();
  static final _touch = buildTheme(focusRings: false);

  bool _show = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  void _modeChanged(FocusHighlightMode mode) {
    final show = mode == FocusHighlightMode.traditional;
    if (show != _show && mounted) setState(() => _show = show);
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _show ? _keyboard : _touch;
    // the parts of the theme with a focus ring; each control reads its own
    // (OutlinedButtonTheme.of and so on), so only these rebuild on a change
    return _FocusRingsScope(
      show: _show,
      child: OutlinedButtonTheme(
        data: t.outlinedButtonTheme,
        child: FilledButtonTheme(
          data: t.filledButtonTheme,
          child: TextButtonTheme(
            data: t.textButtonTheme,
            child: IconButtonTheme(
              data: t.iconButtonTheme,
              child: SegmentedButtonTheme(
                data: t.segmentedButtonTheme,
                child: ChipTheme(data: t.chipTheme, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusRingsScope extends InheritedWidget {
  final bool show;
  const _FocusRingsScope({required this.show, required super.child});

  @override
  bool updateShouldNotify(_FocusRingsScope old) => show != old.show;
}
