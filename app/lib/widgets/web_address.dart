/// A web address shown as selectable text: the app opens no links itself (no
/// URL launcher), so a reader long-presses or selects the address to copy it.
/// Used by the lander photo links and the Learn › Credits sources.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart';

class WebAddress extends StatelessWidget {
  final String url;

  /// What a screen reader calls the address, e.g. "Web address of …".
  final String name;

  /// The key of the text field's scroll position (see below).
  final String storageKey;

  /// Whether the app runs on the web, where the address is an input that
  /// takes [name] as its label ([kIsWeb]; a parameter for the tests).
  final bool web;

  const WebAddress({super.key, required this.url, required this.name, required this.storageKey, this.web = kIsWeb});

  @override
  Widget build(BuildContext context) {
    // SelectableText is a long-press target: a text field node of its own
    // (RenderEditable is no semantics boundary, hence the container), at
    // least 48 dp tall, named by the page it opens. On the web that node is
    // an input, which takes the name as its label. On Android a text field
    // shows only its value below API 28, so there the name is a node of its
    // own around it.
    // Its own storage key: under a PageStorageKey the text field's scroller
    // would otherwise start at the page's saved scroll offset (see
    // site_glance_card.dart)
    final address = Semantics(
      container: true,
      label: web ? name : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: KeyedSubtree(
          key: PageStorageKey(storageKey),
          child: SelectableText(url, style: numStyle(size: 12, color: PH.muted)),
        ),
      ),
    );
    return web ? address : Semantics(container: true, label: name, child: address);
  }
}
