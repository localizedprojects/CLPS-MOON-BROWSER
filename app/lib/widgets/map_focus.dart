/// The Explore map, full screen (user request 2026-10-19: placing a spot on
/// the small map was hard). Its "Open the map full screen" button is the same
/// affordance as a chart's ([FocusableChart]): the open-in-full icon at the
/// top right, a short fade in (none with reduced motion), and an X, Back or
/// Esc to close. The map here is the same map, with room: the same markers,
/// zoom, pan and spot placing, starting at the page map's view.
///
/// Choosing a point here (a site marker, or "Check this spot" once the spot is
/// added) selects it and says so in a small chip; [mapFocusAutoClose] later the map closes
/// by itself and the page's map is centred on that point. A new touch on the
/// map waits again, and so does a dropped pin until it is checked; "Stay"
/// keeps the map open until it is closed. The layers go both ways.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'map_view.dart';

/// How long the full-screen map stays after a point is chosen.
const mapFocusAutoClose = Duration(seconds: 2);

/// What the full-screen map hands back as it closes: the view to centre the
/// page's map on (the chosen point at the full-screen zoom; null when nothing
/// was chosen) and the layers shown there.
typedef MapFocusResult = ({MapCamera? camera, MapOverlay overlay, bool labels});

/// Open [inline]'s map full screen, at its view and layers. A point chosen
/// there goes to [onSelect] / [onPlaceCustom] at once (a spot of the user's
/// own counts once [onPlaceCustom] says it was added), and [inline] is centred
/// on it when the full-screen map closes; closed without a choice, [inline]
/// keeps its view. The layers chosen full screen stay on [inline].
Future<void> openMapFocus(BuildContext context,
    {required MapViewController inline,
    required ValueChanged<String> onSelect,
    required Future<bool> Function(double lat, double lon) onPlaceCustom}) async {
  final reduce = MediaQuery.disableAnimationsOf(context);
  final back = await Navigator.of(context).push(PageRouteBuilder<MapFocusResult>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => MapFocusPage(
        start: inline.camera, overlay: inline.overlay, labels: inline.labels, onSelect: onSelect, onPlaceCustom: onPlaceCustom),
    transitionsBuilder: (context, a, _, child) =>
        MediaQuery.disableAnimationsOf(context) ? child : FadeTransition(opacity: a, child: child),
  ));
  if (back == null) return;
  inline.setLayers(back.overlay, back.labels);
  // the page's map was offstage meanwhile (maybe rotated, or rebuilt for a new
  // layout): the controller centres it at its next layout if need be
  if (back.camera case final c?) {
    inline.centreOn(c, animate: !(context.mounted ? MediaQuery.disableAnimationsOf(context) : reduce));
  }
}

/// The full-screen map: a title, compact Layers / coordinates buttons, a close
/// button, and the map filling the rest. It closes with a [MapFocusResult].
class MapFocusPage extends StatefulWidget {
  final MapCamera? start;
  final MapOverlay overlay;
  final bool labels;
  final ValueChanged<String> onSelect;

  /// Adds the user's spot; true once it is added and selected.
  final Future<bool> Function(double lat, double lon) onPlaceCustom;
  const MapFocusPage(
      {super.key,
      this.start,
      this.overlay = MapOverlay.none,
      this.labels = false,
      required this.onSelect,
      required this.onPlaceCustom});

  @override
  State<MapFocusPage> createState() => _MapFocusPageState();
}

class _MapFocusPageState extends State<MapFocusPage> {
  late final _map = MapViewController()..setLayers(widget.overlay, widget.labels);
  Timer? _timer;
  int _down = 0; // fingers (or buttons) on the map now

  /// The chosen point (as a map fraction) and its name.
  (Offset, String)? _chosen;
  bool _stay = false;

  /// A dropped pin waits for "Check this spot": no closing meanwhile.
  bool _pinPending = false;

  /// Spots being added (their horizons computed): no closing meanwhile.
  int _placing = 0;

  /// Why the last spot was not added (shown over the map).
  String? _refused;

  /// Bumped by each new choice, so a late refusal of an older one is not shown.
  int _seq = 0;

  /// A screen reader or switch access is on: 2 s is too short to reach Stay
  /// (WCAG 2.2.1), so a choice never closes the map by itself, as if Stay were
  /// chosen; the chip says how to go back.
  bool _held = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final held = MediaQuery.accessibleNavigationOf(context);
    if (held == _held) return;
    _held = held;
    _wait();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _choose(Offset at, String name) {
    _seq++;
    setState(() {
      _chosen = (at, name);
      _stay = false;
      _refused = null;
    });
    _wait();
  }

  /// (Re)start the wait before closing: only after a choice, not after
  /// "Stay", and not while a finger is on the map, a pin waits to be checked
  /// or a spot is being added.
  void _wait() {
    _timer?.cancel();
    if (_chosen == null || _stay || _held || _down > 0 || _pinPending || _placing > 0) return;
    _timer = Timer(mapFocusAutoClose, _close);
  }

  void _touch(bool down) {
    _down = down ? _down + 1 : math.max(0, _down - 1);
    if (down) {
      _timer?.cancel();
    } else {
      _wait();
    }
  }

  /// A new pin replaces the earlier choice (and its chip).
  void _pinChanged(bool pending) {
    setState(() {
      _pinPending = pending;
      if (pending) {
        _seq++;
        _chosen = null;
        _refused = null;
      }
    });
    _wait();
  }

  /// The user's spot counts once it is really added and selected; refused
  /// (the map's very edge) or failed, the reason shows here and nothing is
  /// handed back.
  Future<void> _place(Offset at, double lat, double lon) async {
    final n = ++_seq;
    _placing++;
    setState(() {
      _chosen = null;
      _refused = null;
    });
    _wait();
    final ok = await widget.onPlaceCustom(lat, lon);
    if (!mounted) return;
    _placing--;
    if (ok && !_pinPending) return _choose(at, 'Your spot');
    setState(() {
      if (!ok && n == _seq) _refused = context.read<AppState>().error ?? 'That spot could not be added.';
    });
    _wait();
  }

  void _close() {
    _timer?.cancel();
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final chosen = _chosen;
    Navigator.of(context).pop<MapFocusResult>((
      camera: chosen == null ? null : (zoom: _map.camera?.zoom ?? 1.0, centre: chosen.$1),
      overlay: _map.overlay,
      labels: _map.labels,
    ));
  }

  Widget? _chip() {
    final chosen = _chosen, why = _refused;
    if (chosen != null) {
      return _ChosenChip(
        name: chosen.$2,
        leaving: !_stay && !_held,
        held: _held,
        onStay: () {
          _timer?.cancel();
          setState(() => _stay = true);
        },
      );
    }
    if (_placing > 0) {
      return const _NoteChip(key: ValueKey('map-focus-placing'), icon: Icons.hourglass_top, text: 'Checking your spot…');
    }
    if (why != null) return _NoteChip(key: const ValueKey('map-focus-refused'), icon: Icons.error_outline, text: why);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final layers = s.mapLayers;
    final layerWords = 'Map layers: ${overlayName(_map.overlay)}${_map.labels ? ', names shown' : ''}';
    return PopScope<MapFocusResult>(
      // Back hands the chosen point back too
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: PH.bg,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Semantics(header: true, child: Text('South pole map', style: PHText.subtitle))),
                    // the page map's Layers button and coordinates entry, compact
                    IconButton(
                      key: const ValueKey('map-focus-layers'),
                      tooltip: layerWords,
                      onPressed: layers == null ? null : _map.openLayers,
                      icon: const Icon(Icons.layers_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('map-focus-coordinates'),
                      tooltip: 'Add a spot by coordinates',
                      onPressed: layers == null ? null : _map.askCoordinates,
                      icon: const Icon(Icons.add_location_alt_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('map-focus-close'),
                      tooltip: 'Close full screen',
                      onPressed: _close,
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                  Expanded(
                    child: layers == null
                        ? const SizedBox.shrink()
                        : Listener(
                            onPointerDown: (_) => _touch(true),
                            onPointerUp: (_) => _touch(false),
                            onPointerCancel: (_) => _touch(false),
                            // a mouse wheel restarts the wait; a trackpad pinch or
                            // two-finger pan holds it like a finger on the map
                            onPointerSignal: (_) => _wait(),
                            onPointerPanZoomStart: (_) => _touch(true),
                            onPointerPanZoomEnd: (_) => _touch(false),
                            child: MapView(
                              layers: layers,
                              sites: s.allSites,
                              selectedId: s.selectedId,
                              controller: _map,
                              initialCamera: widget.start,
                              fill: true,
                              showControls: false,
                              onPinChanged: _pinChanged,
                              onLayersChanged: () => setState(() {}),
                              onSelect: (id) {
                                final site = s.allSites.firstWhere((x) => x.id == id);
                                widget.onSelect(id);
                                _choose(mapFractionOf(layers, site.lat, site.lon), site.short);
                              },
                              onPlaceCustom: (lat, lon) => _place(mapFractionOf(layers, lat, lon), lat, lon),
                              overlay: _chip(),
                            ),
                          ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note over the map: a spot being checked, or why it was not added.
class _NoteChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _NoteChip({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          color: PH.panel.withValues(alpha: 0.94),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner), side: const BorderSide(color: PH.line)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: PH.text),
              const SizedBox(width: 8),
              Flexible(child: Text(text, style: PHText.body)),
            ]),
          ),
        ),
      );
}

/// "Malapert selected · returning to Explore  [Stay]", or, after Stay, only
/// "Malapert selected"; with a screen reader or switch access on (no closing by
/// itself), "Malapert selected · Close full screen to return to Explore".
class _ChosenChip extends StatelessWidget {
  final String name;
  final bool leaving, held;
  final VoidCallback onStay;
  const _ChosenChip({required this.name, required this.leaving, required this.held, required this.onStay});

  String get _words => leaving
      ? '$name selected · returning to Explore'
      : held
          ? '$name selected · Close full screen to return to Explore'
          : '$name selected';

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          key: const ValueKey('map-focus-chosen'),
          color: PH.panel.withValues(alpha: 0.94),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner), side: const BorderSide(color: PH.line)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 4, leaving ? 4 : 12, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_outline, size: 18, color: PH.both),
              const SizedBox(width: 8),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_words, style: PHText.body),
                ),
              ),
              if (leaving)
                TextButton(
                  key: const ValueKey('map-focus-stay'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: onStay,
                  child: const Text('Stay'),
                ),
            ]),
          ),
        ),
      );
}
