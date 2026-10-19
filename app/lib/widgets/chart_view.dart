/// Embeds one React chart view (charts/ bundle) and wires the bridge.
/// Android/iOS: webview_flutter; web: an iframe; elsewhere: a placeholder.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
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
          child: Stack(fit: StackFit.passthrough, children: [
            KeyedSubtree(
              key: _hostKeys[controller] ??= GlobalKey(debugLabel: 'chart ${controller.view}'),
              child: host.buildChartHost(controller),
            ),
            // a page that cannot run here (an old web view) says why instead
            // of a blank card; the page stays under it, and a later `ready`
            // takes the message away
            ValueListenableBuilder<String?>(
              valueListenable: controller.problemListenable,
              builder: (context, problem, _) =>
                  problem == null ? const SizedBox.shrink() : Positioned.fill(child: ChartProblem(problem)),
            ),
          ]),
        ),
      );
}

/// The message over a chart whose page cannot run on this device.
class ChartProblem extends StatelessWidget {
  final String text;
  const ChartProblem(this.text, {super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const ValueKey('chart-problem'),
        color: PH.panel,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.system_update, color: PH.muted, size: 22),
              const SizedBox(width: 10),
              Flexible(child: Text(text, style: PHText.body.copyWith(color: PH.text))),
            ]),
          ),
        ),
      );
}
