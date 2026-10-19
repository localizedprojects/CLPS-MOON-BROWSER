import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/shell.dart';
import 'state/app_state.dart';
import 'state/chart_hub.dart';
import 'theme.dart';
import 'widgets/light_map.dart';
import 'widgets/save_file.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initSaveFiles(); // iPad share popover anchors at the last tap
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final s = AppState()
          ..askGoalOnStart = true // "What matters most?" first, every time
          ..loadSavedGoal()
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
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _router = ShellRouterDelegate(s);
    // Play steps only as fast as the charts and the light map draw them
    s.holdPlay = () => _hub.chartsBehind;
    s.holdPlayForMap = () => LightMap.framePending.value;
    _life = AppLifecycleListener(
      // HOME, another app or a hidden browser tab: Play pauses, so nothing advances unseen
      onHide: s.pausePlay,
      // back on screen: the charts get the time bar's time again
      onShow: _hub.resync,
      // inactive alone (iOS Control Center or a call banner, Android split
      // screen or the share sheet) deliberately does not pause: the app is
      // still on screen
    );
  }

  @override
  void dispose() {
    _life.dispose();
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
