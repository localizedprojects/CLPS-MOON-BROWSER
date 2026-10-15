import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/chart_hub.dart';
import 'theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final s = AppState()
          ..askGoalOnStart = true // "What matters most?" first, every time
          ..loadSavedGoal()
          ..loadSavedOpening()
          ..loadTimeControlsHidden();
        // the heavy first load (data, ranking) waits while the intro builds the
        // logo, so its frames are smooth; the question and the loading scene
        // cover the rest of the load
        Future<void>.delayed(const Duration(milliseconds: 1500), s.init);
        return s;
      },
      child: const LunarHorizonApp(),
    ),
  );
}

/// The app below an [AppState] provider: one [ChartHub] shared by every
/// screen, and [AppShell] behind a Router that keeps the web URL hash in step.
class LunarHorizonApp extends StatefulWidget {
  const LunarHorizonApp({super.key});

  @override
  State<LunarHorizonApp> createState() => _LunarHorizonAppState();
}

class _LunarHorizonAppState extends State<LunarHorizonApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _back = RootBackButtonDispatcher();
  late final ChartHub _hub = ChartHub(onEvent: _onChartEvent);
  late final ShellRouterDelegate _router;

  @override
  void initState() {
    super.initState();
    _router = ShellRouterDelegate(context.read<AppState>());
  }

  @override
  void dispose() {
    _router.dispose();
    _hub.dispose(); // cancels the cursor-coalescing and PNG-batch timers
    super.dispose();
  }

  /// Chart errors and the hub's notices go to a snackbar.
  void _onChartEvent(Map<String, dynamic> ev) {
    final msg = switch (ev['type']) {
      'error' => 'Chart: ${ev['message']}',
      'notice' => '${ev['message']}',
      _ => null,
    };
    if (msg != null) _messenger.currentState?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) => Provider<ChartHub>.value(
        value: _hub,
        child: MaterialApp.router(
          title: 'Lunar Horizon',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          scaffoldMessengerKey: _messenger,
          routerDelegate: _router,
          routeInformationParser: const ShellRouteParser(),
          backButtonDispatcher: _back,
        ),
      );
}
