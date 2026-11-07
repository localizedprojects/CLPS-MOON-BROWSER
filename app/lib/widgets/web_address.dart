/// A web address shown as selectable text: the app opens no links itself (no
/// URL launcher), so a reader long-presses or selects the address to copy it.
/// Used by the lander photo links and the Learn › Credits sources.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus_semantics.dart';

class WebAddress extends StatefulWidget {
  final String url;

  /// What a screen reader calls the address, e.g. "Web address of …".
  final String name;

  /// The key of the text field's scroll position (see below).
  final String storageKey;

  /// Whether the app runs on the web, where the address is one focusable
  /// node named by [name] and the address ([kIsWeb]; a parameter for the
  /// tests).
  final bool web;

  const WebAddress({super.key, required this.url, required this.name, required this.storageKey, this.web = kIsWeb});

  @override
  State<WebAddress> createState() => _WebAddressState();
}

class _WebAddressState extends State<WebAddress> {
  // its own focus node: SelectableText's default one skips Tab, so a keyboard
  // never reached the address (Shift+Tab went from the top bar straight past
  // both Learn › Credits addresses); focused, Ctrl+A and Ctrl+C copy it
  late final FocusNode _focus = FocusNode(debugLabel: 'WebAddress')..addListener(_update);

  /// Whether the 2 px ice focus ring shows: keyboard focus, as on buttons
  /// (not a long-press or a tap to select).
  bool _ring = false;

  void _update() {
    final ring = _focus.hasFocus && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
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
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SelectableText is a long-press target, at least 48 dp tall, the address
    // centred in it. Its own storage key: under a PageStorageKey the text
    // field's scroller would otherwise start at the page's saved scroll
    // offset (see site_glance_card.dart)
    final box = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      // the focus ring drawn just outside, so focus moves nothing
      child: DecoratedBox(
        key: const ValueKey('web-address-ring'),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PH.radius),
          border: _ring
              ? Border.all(color: PH.ice, width: 2, strokeAlign: BorderSide.strokeAlignOutside)
              : null,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: KeyedSubtree(
            key: PageStorageKey(widget.storageKey),
            child: SelectableText(widget.url, focusNode: _focus, style: numStyle(size: 12, color: PH.muted)),
          ),
        ),
      ),
    );
    if (widget.web) {
      // On the web the engine renders a read-only text field as a disabled
      // textarea, which takes no DOM focus: Tab moved the ring, while the
      // browser's focus, and so the screen reader, stayed on the control
      // before (1.13.4 review). So there the address is one focusable node
      // of text instead (no text field), named by [name] with the address
      // after it, and it says when it has the focus. Selecting and copying
      // (a drag or long-press, Ctrl+A, Ctrl+C) are the app's own and work
      // as before.
      return Semantics(
        container: true,
        label: webAddressWebLabel(widget.name, widget.url),
        child: FocusSemantics(child: box),
      );
    }
    // A text field node of its own (RenderEditable is no semantics boundary,
    // hence the container). On Android a text field shows only its value
    // below API 28, so the name is a node of its own around it.
    return Semantics(container: true, label: widget.name, child: Semantics(container: true, child: box));
  }
}

/// The address's name on the web: [name], then the address itself.
String webAddressWebLabel(String name, String url) => '$name: $url';
