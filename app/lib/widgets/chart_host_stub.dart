import 'package:flutter/material.dart';

import 'chart_bridge.dart';

/// Fallback for platforms without a web view (unit tests, desktop).
Widget buildChartHost(ChartController c) => Container(
      color: const Color(0xFF121826),
      alignment: Alignment.center,
      child: Text('Chart "${c.view}" needs Android or web', style: const TextStyle(color: Color(0xFF9AA7B8))),
    );
