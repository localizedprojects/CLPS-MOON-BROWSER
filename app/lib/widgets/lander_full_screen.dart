/// The Lander's view full screen (docs/landers_view_spec.md, "Full screen
/// and site switching", 1.10.0): the same terrain, the same computed light
/// frames and the same sky as the view inline, with its compass, callouts,
/// crosshair readout and seven buttons, the layer switch, the time bar and
/// the approximation notes, in portrait and landscape alike. The X, Esc and
/// the system or browser back close it. Its top bar switches the landing
/// site without leaving it: previous / next through the app's site list, or
/// the site picker on the name (the app's selected site follows).
///
/// The page asks for its own frames ([LightFrameLoop], the map's request
/// path with the map's keys, so the engine's cache serves both): the route
/// behind is not laid out while this opaque page covers it, so the map there
/// neither rebuilds nor asks for frames meanwhile. The camera and the mesh
/// carry over both ways: the panel sits under the host route's PageStorage
/// bucket (`lander-camera-<siteId>`) and adopts the mesh kept in
/// [AppState.landerMesh], so neither opening nor closing rebuilds it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/catalog.dart' show Site;
import '../core/lander_view.dart' show LanderMesh;
import '../core/shadow.dart' show LightShares;
import '../core/site_order.dart';
import '../state/app_state.dart';
import '../state/light_engine.dart';
import '../state/light_loop.dart';
import '../theme.dart';
import 'lander_view.dart';
import 'light_map.dart' show LightLayerSwitch, LightLegend, LightMap, lightEclipseNote;
import 'sheets/sheet_frame.dart';
import 'sheets/site_picker_sheet.dart';
import 'time_bar.dart';

/// Opens the Lander's view full screen over [context]'s route, on [layer];
/// a layer chosen there goes to [onLayer] (and to the host route's
/// PageStorage, [LightMap.layerStoreId]). Completes when it closes. No
/// orientation is forced: it works in portrait and landscape.
Future<void> openLanderFullScreen(
  BuildContext context, {
  required AppState state,
  required LightLayer layer,
  required ValueChanged<LightLayer> onLayer,
}) {
  final bucket = PageStorage.maybeOf(context);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) =>
          LanderFullScreenPage(state: state, layer: layer, onLayer: onLayer, bucket: bucket),
      transitionsBuilder: (context, a, _, child) =>
          MediaQuery.disableAnimationsOf(context) ? child : FadeTransition(opacity: a, child: child),
    ),
  );
}

class LanderFullScreenPage extends StatefulWidget {
  final AppState state;
  final LightLayer layer;
  final ValueChanged<LightLayer> onLayer;

  /// The host route's PageStorage bucket: the camera memory
  /// (`lander-camera-<siteId>`) and the layer choice live there.
  final PageStorageBucket? bucket;
  const LanderFullScreenPage({super.key, required this.state, required this.layer, required this.onLayer, this.bucket});

  /// The close button's tooltip and accessible name.
  static const closeLabel = 'Close full screen';

  /// The page's name for screen readers.
  static const routeLabel = "Lander's view full screen";

  /// A phone on its side: the view on the left, the controls in a column
  /// beside it (above or below it the view would be a thin strip).
  static bool sideBySide(BoxConstraints c) => c.maxWidth > 1.25 * c.maxHeight && c.maxHeight < 500;

  /// The side column's width in [sideBySide].
  static const sideWidth = LightMap.landerSideMin;

  /// From this width the layer switch shares the top bar's row.
  static const wideBar = 720.0;

  /// In the column layout the notes under the view (the FidelityBadges, an
  /// engine error) scroll within this share of the room between the bars.
  static const notesShare = 0.3;

  @override
  State<LanderFullScreenPage> createState() => LanderFullScreenPageState();
}

class LanderFullScreenPageState extends State<LanderFullScreenPage> {
  AppState get state => widget.state;

  /// Keeps the panel (its mesh, camera and build in flight) when turning the
  /// device moves it between the column and the row layouts.
  final _panel = GlobalKey<LanderViewPanelState>();

  /// The panel's mesh, for the FidelityBadge (eye height, DEM ends).
  final _mesh = ValueNotifier<LanderMesh?>(null);

  /// The shown frame and layer, for the legend sheet (it follows them while open).
  late final _shown = ValueNotifier<({LightFrame? near, LightLayer layer})>((near: null, layer: widget.layer));
  final _sideScroll = ScrollController(), _notesScroll = ScrollController();

  /// Used only without a host bucket (a test host).
  final _ownBucket = PageStorageBucket();

  late final _loop = LightFrameLoop(
    state,
    isActive: () => mounted,
    extent: () => LightExtent.closeUp,
    onFrame: (_, f) {
      if (!mounted) return;
      setState(() => _near = f);
      _shown.value = (near: f, layer: _layer);
    },
    onPending: _report,
    onChange: () {
      _report();
      if (mounted) setState(() {});
    },
  );

  LightFrame? _near;
  late LightLayer _layer = widget.layer;

  /// [f] only when it is the selected site's: right after a switch the last
  /// frame is still the previous site's until the new one is computed, and
  /// its shares or eclipse are never shown under the new site's name.
  LightFrame? _ofSite(LightFrame? f) {
    final site = state.site;
    return f != null && f.request.lat == site.lat && f.request.lon == site.lon ? f : null;
  }

  /// The shown frame, when it is the selected site's ([_ofSite]).
  LightFrame? get _siteNear => _ofSite(_near);

  /// The panel's state (tests; the site switcher keeps its camera with it).
  LanderViewPanelState? get panel => _panel.currentState;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
    LightMap.framePending.value = false;
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _loop.dispose();
    _mesh.dispose();
    _shown.dispose();
    _sideScroll.dispose();
    _notesScroll.dispose();
    LightMap.framePending.value = false;
    super.dispose();
  }

  /// The app changed (the moment, Play, the site): rebuild, never during a
  /// build (the request goes out after the frame, from [build]).
  void _onState() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Play waits on the frame shown here (not while the engine is failing).
  void _report() {
    if (!mounted) return;
    LightMap.framePending.value = _loop.error == null && (_loop.busy || _loop.queued);
  }

  void _setLayer(LightLayer l) {
    setState(() => _layer = l);
    _shown.value = (near: _near, layer: l);
    widget.bucket?.writeState(context, l, identifier: LightMap.layerStoreId);
    widget.onLayer(l);
  }

  /// Keeps the camera for the next view of this site (the inline one on
  /// closing; another site's view on a switch).
  void rememberCamera() => _panel.currentState?.rememberCamera();

  void _close() => Navigator.maybePop(context);

  void _showLegend() => showPhSheet<void>(
    context,
    (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ValueListenableBuilder(
          valueListenable: _shown,
          builder: (context, v, _) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const SheetHeader('Legend'), const SizedBox(height: 8), _legend(v.near, v.layer)],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _legend(LightFrame? frame, LightLayer layer) {
    final near = _ofSite(frame);
    return LightLegend(
    layer: layer,
    shares: near == null ? null : _sharesOf(near),
    scope: 'within 64 km of ${state.site.short}',
    approx: near?.request.coarse ?? false,
    eclipse: lightEclipseNote(near == null ? null : _loop.eclipseOf(near))?.sentence,
    lander: true,
  );
  }

  LightFrame? _sharesFrame;
  LightShares? _shares;
  LightShares _sharesOf(LightFrame f) {
    if (!identical(_sharesFrame, f)) {
      _sharesFrame = f;
      _shares = lightFrameShares(f);
    }
    return _shares!;
  }

  // ---- parts ------------------------------------------------------------

  /// Shows the site [id] here (previous / next, the picker): the app's
  /// selected site changes as with "Change site" ([AppState.openSite], same
  /// tab), so the Site screen behind follows, and this page stays open on the
  /// Lander's view. The camera as it is now is kept for the site it shows
  /// first; the new site's view then builds ('Building the view…' unless its
  /// mesh is still kept) and takes its own remembered camera, else faces the
  /// Sun, else Earth, else north.
  void _switchTo(String id) {
    if (id == state.selectedId || !state.allSites.any((x) => x.id == id)) return;
    rememberCamera();
    unawaited(state.openSite(id, tab: state.siteTab));
  }

  /// The name: the same single-select picker as "Change site".
  Future<void> _pickSite() async {
    final ids = await showSitePicker(context, multi: false, initial: [state.selectedId]);
    if (!mounted || ids == null || ids.isEmpty) return;
    _switchTo(ids.first);
  }

  /// The top bar (at least 48 dp): previous site, the site's name (a tap
  /// opens the site picker), next site, then [trailing] (the layer switch on
  /// wide screens) and the close button. Previous and next step through
  /// [AppState.allSites] (the presets, then the user's own spots) and wrap
  /// around; they are left out when there is no other site.
  Widget _topBar({Widget? trailing}) {
    final site = state.site;
    final around = siteNeighbours(state.allSites, site.id);
    Widget step(Site to, {required bool next}) => IconButton(
      key: ValueKey(next ? 'lander-full-next' : 'lander-full-prev'),
      tooltip: '${next ? 'Next' : 'Previous'} site: ${to.short}',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () => _switchTo(to.id),
      icon: Icon(next ? Icons.chevron_right : Icons.chevron_left),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          if (around != null) step(around.prev, next: false) else const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Change site. Current site: ${site.short}',
              excludeSemantics: true,
              // excludeSemantics drops the TextButton's own action: keep it here
              onTap: _pickSite,
              child: TextButton(
                key: const ValueKey('lander-full-site'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: PH.text,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _pickSite,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(site.short, maxLines: 1, overflow: TextOverflow.ellipsis, style: PHText.subtitle),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (around != null) step(around.next, next: true),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          IconButton(
            key: const ValueKey('lander-full-close'),
            tooltip: LanderFullScreenPage.closeLabel,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _close,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _layerSwitch({required bool short}) =>
      LightLayerSwitch(key: const ValueKey('lander-full-layer'), selected: _layer, onChanged: _setLayer, short: short);

  Widget _legendButton() => IconButton(
    key: const ValueKey('lander-full-legend'),
    tooltip: 'Show the legend',
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: _showLegend,
    icon: const Icon(Icons.info_outline),
  );

  Widget _badges() {
    final near = _siteNear;
    return LanderFidelityBadges(
      state: state,
      mesh: _mesh,
      eclipse: lightEclipseNote(near == null ? null : _loop.eclipseOf(near)) != null,
    );
  }

  /// The engine's error, as the map shows it under its view, with a way to
  /// ask for the same moment again ([LightFrameLoop.retry]); null while the
  /// engine works. Play does not wait on a failing engine ([_report]).
  Widget? _error() {
    final e = _loop.error;
    if (e == null) return null;
    return Row(
      key: const ValueKey('lander-full-error'),
      children: [
        Expanded(child: Text(e, style: PHText.small.copyWith(color: PH.warn))),
        Semantics(
          button: true,
          label: 'Try the light again',
          excludeSemantics: true,
          onTap: _retry,
          child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _retry,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }

  void _retry() {
    _loop.retry();
    _loop.request();
  }

  Widget _view(double width, double height) => PageStorage(
    // the host route's bucket: the camera memory and the layer live there
    bucket: widget.bucket ?? _ownBucket,
    child: LanderViewPanel(
      key: _panel,
      state: state,
      near: _near,
      layer: _layer,
      width: width,
      maxHeight: height,
      fill: true,
      meshOut: _mesh,
    ),
  );

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loop.request();
    });
    final s = state;
    final Widget body;
    if (s.eph == null) {
      body = Center(
        child: Text('Map data unavailable', style: PHText.body.copyWith(color: PH.muted)),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, c) {
          if (LanderFullScreenPage.sideBySide(c)) {
            // a phone on its side: the view on the left, the bar, the time bar and
            // the rest in a column beside it (the bar and the time bar pinned)
            final w = c.maxWidth - 16 - LanderFullScreenPage.sideWidth;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(left: 8), child: _view(w - 8, c.maxHeight - 8)),
                const SizedBox(width: 16),
                SizedBox(
                  width: LanderFullScreenPage.sideWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(),
                      TimeBar(state: s, compact: true, alignTop: true),
                      Expanded(
                        child: Scrollbar(
                          controller: _sideScroll,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _sideScroll,
                            padding: const EdgeInsets.only(right: 8, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 8),
                                Align(alignment: Alignment.centerLeft, child: _layerSwitch(short: true)),
                                const SizedBox(height: 10),
                                ?_error(),
                                _legend(_near, _layer),
                                _badges(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          // portrait phones, tablets and the web: bar, view, notes, time bar
          final wide = c.maxWidth >= LanderFullScreenPage.wideBar;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(
                trailing: wide
                    ? Row(mainAxisSize: MainAxisSize.min, children: [_layerSwitch(short: false), _legendButton()])
                    : null,
              ),
              if (!wide)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(alignment: Alignment.centerLeft, child: _layerSwitch(short: true)),
                      ),
                      _legendButton(),
                    ],
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c1) {
                    // the notes under the view (the badges, an error) scroll in at most
                    // [LanderFullScreenPage.notesShare] of the room, so opening the
                    // approximation text ('More') never squeezes the view or pushes
                    // the time bar off screen; the main badge comes first, in sight
                    final error = _error();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: LayoutBuilder(builder: (context, c2) => _view(c2.maxWidth, c2.maxHeight)),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: c1.maxHeight * LanderFullScreenPage.notesShare),
                          child: Scrollbar(
                            controller: _notesScroll,
                            child: SingleChildScrollView(
                              key: const ValueKey('lander-full-notes'),
                              controller: _notesScroll,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [?error, _badges()],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              TimeBar(state: s, compact: true),
            ],
          );
        },
      );
    }
    return PopScope(
      // the close button, Esc, Android back and the browser's back all pop
      // here: the camera as it is now goes back to the view inline
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) rememberCamera();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          autofocus: true,
          child: Semantics(
            // names the page for screen readers (there is no app bar)
            namesRoute: true,
            explicitChildNodes: true,
            label: LanderFullScreenPage.routeLabel,
            child: Scaffold(
              backgroundColor: PH.bg,
              body: SafeArea(child: body),
            ),
          ),
        ),
      ),
    );
  }
}
