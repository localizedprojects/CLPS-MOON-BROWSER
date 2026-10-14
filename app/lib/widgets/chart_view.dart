/// Embeds one React chart view (charts/ bundle) and wires the bridge.
/// Android/iOS: webview_flutter; web: an iframe; elsewhere: a placeholder.
library;

import 'package:flutter/material.dart';

import 'chart_bridge.dart';
import 'chart_host_stub.dart'
    if (dart.library.js_interop) 'chart_host_web.dart'
    if (dart.library.io) 'chart_host_mobile.dart' as host;

/// One key per controller: when a layout change rebuilds the chart somewhere
/// else in the tree, Flutter moves the existing host (and its web view) there
/// instead of loading a new page. A chart is shown in one place at a time.
final _hostKeys = Expando<GlobalKey>('chart host');

class ChartView extends StatelessWidget {
  final ChartController controller;
  final String semanticsLabel;
  const ChartView({super.key, required this.controller, required this.semanticsLabel});

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticsLabel,
        container: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: KeyedSubtree(
            key: _hostKeys[controller] ??= GlobalKey(debugLabel: 'chart ${controller.view}'),
            child: host.buildChartHost(controller),
          ),
        ),
      );
}
