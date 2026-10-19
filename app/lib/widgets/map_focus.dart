/// The Explore map, full screen (user request 2026-10-19: placing a spot on
/// the small map was hard). Its "Open the map full screen" button is the same
/// affordance as a chart's ([FocusableChart]): the open-in-full icon at the
/// top right, a short fade in (none with reduced motion), and an X, Back or
/// Esc to close. The map here is the same map, with room: the same markers,
/// zoom, pan and spot placing, starting at the page map's view.
///
/// Choosing a point here (a site marker, or "Check this spot") selects it at
/// once and says so in a small chip; [mapFocusAutoClose] later the map closes
/// by itself and the page's map is centred on that point. A new touch on the
/// map waits again; "Stay" keeps the map open until it is closed.
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

/// Open [inline]'s map full screen, at its view. A point chosen there goes to
/// [onSelect] / [onPlaceCustom] at once, and [inline] is centred on it when the
/// full-screen map closes; closed without a choice, [inline] keeps its view.
Future<void> openMapFocus(BuildContext context,
    {required MapViewController inline,
    required ValueChanged<String> onSelect,
    required void Function(double lat, double lon) onPlaceCustom}) async {
  final back = await Navigator.of(context).push(PageRouteBuilder<MapCamera>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => MapFocusPage(start: inline.camera, onSelect: onSelect, onPlaceCustom: onPlaceCustom),
    transitionsBuilder: (context, a, _, child) =>
        MediaQuery.disableAnimationsOf(context) ? child : FadeTransition(opacity: a, child: child),
  ));
  if (back == null || !context.mounted) return;
  inline.centreOn(back, animate: !MediaQuery.disableAnimationsOf(context));
}

/// The full-screen map: a title, a close button, and the map filling the rest.
/// It closes with the view to hand back: the chosen point at this map's zoom
/// (null when nothing was chosen).
class MapFocusPage extends StatefulWidget {
  final MapCamera? start;
  final ValueChanged<String> onSelect;
  final void Function(double lat, double lon) onPlaceCustom;
  const MapFocusPage({super.key, this.start, required this.onSelect, required this.onPlaceCustom});

  @override
  State<MapFocusPage> createState() => _MapFocusPageState();
}

class _MapFocusPageState extends State<MapFocusPage> {
  final _map = MapViewController();
  Timer? _timer;
  int _down = 0; // fingers (or buttons) on the map now

  /// The chosen point (as a map fraction) and its name.
  (Offset, String)? _chosen;
  bool _stay = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _choose(Offset at, String name) {
    setState(() {
      _chosen = (at, name);
      _stay = false;
    });
    _wait();
  }

  /// (Re)start the wait before closing: only after a choice, not after
  /// "Stay", and not while a finger is on the map.
  void _wait() {
    _timer?.cancel();
    if (_chosen == null || _stay || _down > 0) return;
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

  void _close() {
    _timer?.cancel();
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final chosen = _chosen;
    Navigator.of(context).pop<MapCamera>(chosen == null ? null : (zoom: _map.camera?.zoom ?? 1.0, centre: chosen.$1));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final layers = s.mapLayers;
    final chosen = _chosen;
    return PopScope<MapCamera>(
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
                            child: MapView(
                              layers: layers,
                              sites: s.allSites,
                              selectedId: s.selectedId,
                              controller: _map,
                              initialCamera: widget.start,
                              fill: true,
                              showControls: false,
                              onSelect: (id) {
                                final site = s.allSites.firstWhere((x) => x.id == id);
                                widget.onSelect(id);
                                _choose(mapFractionOf(layers, site.lat, site.lon), site.short);
                              },
                              onPlaceCustom: (lat, lon) {
                                widget.onPlaceCustom(lat, lon);
                                _choose(mapFractionOf(layers, lat, lon), 'Your spot');
                              },
                              overlay: chosen == null
                                  ? null
                                  : _ChosenChip(
                                      name: chosen.$2,
                                      leaving: !_stay,
                                      onStay: () {
                                        _timer?.cancel();
                                        setState(() => _stay = true);
                                      },
                                    ),
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

/// "Malapert selected · returning to Explore  [Stay]", or, after Stay, only
/// "Malapert selected".
class _ChosenChip extends StatelessWidget {
  final String name;
  final bool leaving;
  final VoidCallback onStay;
  const _ChosenChip({required this.name, required this.leaving, required this.onStay});

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
                  child: Text(leaving ? '$name selected · returning to Explore' : '$name selected', style: PHText.body),
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
