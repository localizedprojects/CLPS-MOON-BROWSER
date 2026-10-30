/// Light & shadow map: the NASA LOLA shaded relief lit for the selected moment.
///
/// Shadows are computed on the device from the LOLA DEM (core/shadow.dart):
/// a 128 km close-up around the selected site on the 400 m grid, or the whole
/// 80-90 S region on the 800 m grid, for an observer at the chosen height
/// above the ground. Arrows at the site point toward the Sun and Earth (exact
/// SPICE-derived azimuths).
///
/// The overlay pixels ([lightOverlayPixels], state/light_engine.dart) are
/// built by the light engine (a background isolate on Android and desktop;
/// short slices on the web's main thread), kept per layer by
/// [LightImageKeeper] and drawn by [LightFramePainter]; the LightSnapshot
/// close-ups share all three.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/dem.dart';
import '../core/eclipse.dart';
import '../core/geo.dart' show Observer;
import '../core/lander_view.dart' show LanderMesh, landerNearAlpha;
import '../state/lander_light.dart' show landerNotComputedArgb;
import '../core/relief.dart';
import '../core/shadow.dart';
import '../core/visibility.dart' show EarthCriterion, SunCriterion, earthVisible;
import '../core/wording.dart';
import '../state/app_state.dart';
import '../state/light_engine.dart';
import '../theme.dart';
import 'chart_bridge.dart' show nowAt, utcLabel;
import 'glyphs.dart';
import 'time_bar.dart' show utcTwoLines;
import 'feature_guide.dart';
import 'lander_view.dart';

export '../state/light_engine.dart' show LightClass, LightLayer, classify, lightOverlayPixels, lightPixel;
export '../core/wording.dart' show eclipseSharePct;

Future<ui.Image> _decode(Uint8List rgba, int w) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, w, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// The two overlay images of one frame, ready for [LightFramePainter].
typedef LightImages = ({ui.Image mul, ui.Image scr, LightFrame frame, LightLayer layer, int w});

/// A square map window: top-left corner (x0, y0) and side, polar-stereographic metres.
typedef LightView = ({double x0, double y0, double ext});

/// The view of a computed frame.
LightView frameView(LightFrame f) => (x0: f.x0M, y0: f.y0M, ext: f.extentM);

/// What the light map's note adds for a close-up that reaches past the base
/// map's edge ([beyondBaseMap]); the snapshot says it too
/// ([lightSnapshotFidelityFor]). The scale figure: a close-up of a spot
/// south of -80.01° reaches about 77-78°S, where polar stereographic
/// distances are 2 / (1 + sin 77.8°) = 1.011 times true ones (1.013 at
/// worst, a frame corner at 77.1°S).
const lightPastMapNote = 'This close-up reaches past the base map\'s edge (about 80°S): there the terrain is LOLA\'s '
    '120 m map (LDEM_75S_120M) averaged to 400 m, the relief under the colours is shaded on this device from that '
    '400 m grid with the same artificial light as the map (a little smoother than the map\'s 320 m relief), and map '
    'distances run up to about 1% longer than true ones, so shadows cast from there are a little less exact.';

/// Earth against the Sun at [f]'s moment, seen from the frame's site: its
/// request's latitude and longitude at [terrainHeightM] + the request's
/// observer height (as `AppState.observer`), so the share is the one `nowAt`
/// gives the status line at that moment.
SunEclipse lightFrameEclipse(LightFrame f, {double terrainHeightM = 0}) {
  final q = f.request;
  return sunEclipseAt(Observer(q.lat, q.lon, terrainHeightM + q.observerHeightM), q.sun, q.earth);
}

/// [f] as drawn during a lunar eclipse ([ecl], from [lightFrameEclipse]):
/// while Earth hides the whole Sun no ground gets direct sunlight, so every
/// pixel loses its Sun bits (the Sun and Both layers draw it as in shadow and
/// the legend's Sun shares are 0); while Earth covers part of it the terrain
/// shadows stay, but no ground sees the whole disk (the fullDisk rule needs
/// no overlap, formula.md §6.5), so every pixel loses its full-Sun bit and
/// sunlit ground is drawn as seeing part of the Sun (the note gives Earth's
/// share); without an eclipse [f] itself. A copy of the flags only: no shadow
/// is recomputed. One eclipse for the whole frame, the site's
/// ([lightEclipseFidelity]).
LightFrame lightFrameEclipsed(LightFrame f, SunEclipse ecl) {
  if (ecl.fraction <= 0) return f;
  final flags = Uint8List.fromList(f.flags);
  final keep = (ecl.fraction >= 1 ? ~(lightSunAny | lightSunFull) : ~lightSunFull) & 0xFF;
  for (var i = 0; i < flags.length; i++) {
    flags[i] &= keep;
  }
  return LightFrame(f.request, f.size, f.pxM, f.x0M, f.y0M, flags, f.shade, f.computeMs);
}

/// The light map's note on a lunar eclipse at a frame's moment: null without
/// one; for a total one, that no ground gets direct sunlight; for a partial
/// one, Earth's share of the Sun ([SunEclipse.fraction], [eclipseSharePct]).
/// [lines] go on the map, [sentence] in the legend and the accessible name.
({List<String> lines, String sentence})? lightEclipseNote(SunEclipse? ecl) {
  final f = ecl?.fraction ?? 0;
  if (f <= 0) return null;
  if (f >= 1) {
    return (
      lines: const ['Earth hides the Sun (lunar eclipse)', 'No direct sunlight on the map'],
      sentence: 'Earth hides the Sun (lunar eclipse): no direct sunlight on the map',
    );
  }
  final t = 'Earth covers ${eclipseSharePct(f)}% of the Sun (lunar eclipse)';
  return (lines: [t], sentence: t);
}

/// The eclipse's approximation, added to the badges while one is shown. The
/// figures: across the region (sites up to about 600 km apart) Earth, 384 000
/// km away, shifts by up to 600 / 384 000 rad = 0.09° against the Sun, which
/// it crosses at about 0.5° an hour; a close-up spans 64 km (0.01°).
const lightEclipseFidelity = 'During a lunar eclipse, Earth\'s cover of the Sun is worked out at the site and used '
    'for the whole picture: across the region Earth\'s place against the Sun shifts by up to about 0.1° (0.01° '
    'across a close-up), so there the start and end of totality can be off by up to about 10 minutes (1 minute in '
    'a close-up). Earth is a sharp-edged disk: the dim red light its atmosphere bends onto the Moon is not shown.';

/// The Sun's status line on the light map and the snapshot, from a `nowAt`
/// body: when Earth's disk, not the terrain, is why the Sun does not count
/// ('eclipseHides'), it says so (as the Now status does); during the rest of
/// a lunar eclipse it adds Earth's share of the Sun ('eclipse').
String lightSunStatus(Map<String, dynamic> sun, SunCriterion rule) {
  double n(String k) => (sun[k] as num).toDouble();
  final e = (sun['eclipse'] as num?)?.toDouble() ?? 0;
  if (sun['eclipseHides'] == true) return eclipseHidesText(e);
  final text = sunStatusText(visible: sun['visible'] == true, elDeg: n('el'), rhoDeg: n('rho'), frac: n('frac'), sunRule: rule);
  if (e <= 0) return text;
  return '$text; ${e >= 1 ? 'Earth hides the whole Sun' : 'Earth covers ${eclipseSharePct(e)}% of the Sun'} (lunar eclipse)';
}

/// The close-up view the light engine will compute around ([lat], [lon]) on
/// a terrain grid of half-width [demHalfWidthM] (map.json dem; about 75°S):
/// ShadowGrid.windowAround on the 800 m grid while [playing], 400 m
/// otherwise, so on whole pixels of that grid and kept inside it (a site at
/// 80°S, IM-1 Odysseus, is centred too). The map shows it before the first
/// frame arrives, so that frame does not shift the map at all.
LightView closeUpTargetView(double lat, double lon, double demHalfWidthM, {required bool playing}) {
  final (x, y) = latLonToXY(lat, lon);
  final pxM = playing ? 800.0 : 400.0;
  final n = (2 * demHalfWidthM / pxM).round(), side = math.min(n, (closeUpPx * 400.0 / pxM).round());
  int place(double centre) => (centre - side / 2 + 0.5).round().clamp(0, n - side);
  final r0 = place(n / 2 - 0.5 - y / pxM), c0 = place(x / pxM + n / 2 - 0.5);
  return (x0: (c0 - n / 2) * pxM, y0: (n / 2 - r0) * pxM, ext: side * pxM);
}

/// Arrow-label suffix for a light the user's rule does not count, saying
/// why: Earth hidden only by the "DSN station in view" rule is "no DSN"
/// (pass [earthRule] for Earth); part of the disk above the skyline but not
/// counted under a stricter rule is "partly up" / "mostly up"; none of it is
/// "hidden". [b] is a body of `nowAt` (frac, el, hz, visible).
String lightArrowNote(Map<String, dynamic> b, {EarthCriterion? earthRule, bool requireDsn = false}) {
  if (b['visible'] == true) return '';
  if (b['eclipseHides'] == true) return ' · behind Earth'; // a lunar eclipse (nowAt)
  double n(String k) => (b[k] as num).toDouble();
  final frac = n('frac');
  if (earthRule != null && requireDsn && earthVisible(earthRule, frac, n('el'), n('hz'))) return ' · no DSN';
  if (frac > 0) return frac >= 0.5 ? ' · mostly up' : ' · partly up';
  return ' · hidden';
}

/// Arrow-label elevation: "2°" / "−6°", or to 0.1° with [exact] ("2.0°").
String arrowElevationText(double el, {bool exact = false}) {
  final digits = exact ? 1 : 0;
  final r = double.parse(el.toStringAsFixed(digits));
  return '${r < 0 ? '−' : ''}${r.abs().toStringAsFixed(digits)}°';
}

/// The whole arrow label for body [name] ("Sun", "Earth"): the angle of the
/// disc centre above or below the terrain skyline (el − hz, the same
/// clearance as the Sky & time caption), never the raw elevation above the
/// flat horizon, which is negative on a high peak that is still sunlit.
/// "Sun 3° above the hills", "Earth 2° below the hills", "Earth 0° at the
/// skyline · partly up". A counted body whose centre is below the skyline
/// (upper-limb rule) reads "Sun partly up", never a negative clearance next
/// to "up". "· hidden" is dropped when "below the hills" already says it.
/// [b] is a body of `nowAt` (az, el, hz, frac, visible).
String arrowLabelText(String name, Map<String, dynamic> b, {EarthCriterion? earthRule, bool requireDsn = false, bool exact = false}) {
  final c = (b['el'] as num).toDouble() - (b['hz'] as num).toDouble();
  final visible = b['visible'] == true;
  final digits = exact ? 1 : 0;
  final r = double.parse(c.toStringAsFixed(digits));
  if (visible && c < 0) return '$name partly up';
  var note = lightArrowNote(b, earthRule: earthRule, requireDsn: requireDsn);
  final String where;
  if (r == 0) {
    where = 'at the skyline';
  } else if (r > 0) {
    where = '${arrowElevationText(r, exact: exact)} above the hills';
  } else {
    where = '${arrowElevationText(-r, exact: exact)} below the hills';
    if (note == ' · hidden') note = '';
  }
  return '$name $where$note';
}

/// The centre x of a label [w] wide near [x], moved inside a frame [frameW]
/// wide (2 px margin); a label wider than the frame stays centred on [x].
double clampLabelX(double x, double w, double frameW) {
  final lo = w / 2 + 2, hi = frameW - w / 2 - 2;
  return lo > hi ? x : x.clamp(lo, hi);
}

/// The overlay images of the latest light frame for one widget. The light
/// engine builds them at the size the map is drawn ([LightEngine.overlaySide]),
/// one layer at a time, and each is kept while its frame is the latest, so
/// switching back to a layer is instant. Replaced images are disposed after
/// the next frame is painted. Nothing is built while inactive (off screen),
/// and size changes under 8 device pixels do not rebuild.
class LightImageKeeper {
  LightImageKeeper({required this.onChange});

  /// Called whenever [shown] or [error] changes (never during a build).
  final VoidCallback onChange;

  LightEngine? _engine;
  LightFrame? _frame;
  LightLayer _layer = LightLayer.sun;
  double _side = 0;
  int _deviceSide = 0;
  bool _active = true, _building = false, _scheduled = false, _disposed = false;
  int _gen = 0;

  // overlays of _cacheFrame at _cacheW output pixels, per layer
  final _cache = <LightLayer, LightImages>{};
  LightFrame? _cacheFrame;
  int _cacheW = 0;

  /// The newest overlay built (what the painter draws). It lags the latest
  /// frame or layer while the next one is built.
  LightImages? get shown => _shown;
  LightImages? _shown;

  /// Why the last overlay could not be built (null after a success).
  Object? get error => _error;
  Object? _error;

  /// Whether an overlay of the latest frame in the chosen layer is still to come.
  bool get pending {
    final f = _frame, s = _shown;
    return f != null && _error == null && (s == null || !identical(s.frame, f) || s.layer != _layer);
  }

  /// Whether [pending] work will actually run: the keeper is active and has
  /// an engine and a size (a map never laid out builds nothing, so Play must
  /// not wait on it).
  bool get catchingUp => pending && _active && !_disposed && _engine != null && _deviceSide > 0;

  /// Number of overlays built so far (for tests).
  int builds = 0;

  /// Set any of the inputs; work (if any) starts in a microtask.
  void update({LightEngine? engine, LightFrame? frame, LightLayer? layer, double? side, double? dpr, bool? active}) {
    var changed = false;
    if (engine != null && !identical(engine, _engine)) {
      _engine = engine;
      changed = true;
    }
    if (frame != null && !identical(frame, _frame)) {
      _frame = frame;
      changed = true;
    }
    if (layer != null && layer != _layer) {
      _layer = layer;
      changed = true;
    }
    if (side != null && side.isFinite && side > 0) {
      final ds = (side * (dpr ?? 1).clamp(1.0, 2.0)).round();
      if ((ds - _deviceSide).abs() >= 8) {
        _deviceSide = ds;
        _side = side;
        changed = true;
      }
    }
    if (active != null && active != _active) {
      _active = active;
      changed = true;
    }
    if (!changed || _disposed) return;
    _gen++;
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_run);
    }
  }

  Future<void> _run() async {
    _scheduled = false;
    if (_building || _disposed || !_active) return;
    final f = _frame, e = _engine;
    if (f == null || e == null || _deviceSide == 0) return;
    final w = e.overlaySide(_deviceSide, f);
    if (!identical(_cacheFrame, f) || _cacheW != w) {
      for (final img in _cache.values) {
        if (!identical(img, _shown)) _free(img);
      }
      _cache.clear();
      _cacheFrame = f;
      _cacheW = w;
    }
    final lay = _layer;
    final hit = _cache[lay];
    if (hit != null) {
      if (!identical(hit, _shown)) _show(hit);
      return;
    }
    final gen = _gen;
    _building = true;
    LightImages? img;
    try {
      // patterns at >= 1 output px per step, so a capped overlay stays regular
      final px = await e.overlay(f, lay, w, math.max(1.0, w / _side));
      final mul = await _decode(px.mul, w);
      try {
        img = (mul: mul, scr: await _decode(px.scr, w), frame: f, layer: lay, w: w);
      } catch (_) {
        mul.dispose();
        rethrow;
      }
      builds++;
      _error = null;
    } catch (err) {
      _error = err;
    } finally {
      _building = false;
    }
    if (_disposed) {
      if (img != null) _free(img, now: true);
      return;
    }
    if (img != null) {
      final latest = identical(_cacheFrame, f) && _cacheW == w;
      if (latest) _cache[lay] = img;
      if (lay == _layer || _shown == null) {
        _show(img);
      } else if (!latest) {
        _free(img, now: true);
      }
    } else {
      onChange();
    }
    // catch up with what changed meanwhile (a failure is retried only then)
    if (img != null || gen != _gen) _run();
  }

  void _show(LightImages img) {
    final old = _shown;
    _shown = img;
    onChange();
    if (old != null && !identical(old, img) && !_cache.values.any((c) => identical(c, old))) _free(old);
  }

  void _free(LightImages img, {bool now = false}) {
    void go() {
      img.mul.dispose();
      img.scr.dispose();
    }

    if (now) {
      go();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    }
  }

  void dispose() {
    _disposed = true;
    final all = LinkedHashSet<LightImages>.identity()..addAll(_cache.values);
    if (_shown != null) all.add(_shown!);
    for (final img in all) {
      _free(img, now: true);
    }
    _cache.clear();
    _shown = null;
  }
}

/// A [reliefGrey] picture placed on the map: top-left corner and size (m).
typedef ReliefImage = ({ui.Image image, double x0M, double y0M, double widthM, double heightM});

/// The shaded relief of the 400 m terrain grid under a close-up that reaches
/// past the base map's edge (about 80°S), where hillshade.webp has no pixels:
/// the base map's recipe ([ReliefRecipe], from map.json) worked out on the
/// device, so the ground's tones carry on across the edge. Built once per
/// window ([want]); kept while the view stays there (e.g. while playing).
/// Each picture is drawn at its own place on the map, so one still being
/// replaced is never in the wrong spot.
class ReliefKeeper {
  ReliefKeeper({required this.onChange});

  /// Called when [shown] changes (never during a build).
  final VoidCallback onChange;

  ReliefImage? get shown => _shown;
  ReliefImage? _shown;
  ReliefWindow? _shownWin;

  /// How many pictures have been built (tests).
  int builds = 0;

  LightView? _view, _asked;
  Future<PolarGrid> Function()? _dem;
  ReliefRecipe? _recipe;
  bool _building = false, _scheduled = false, _disposed = false;

  /// Ask for the relief under [view] (a close-up's square) from the terrain
  /// grid [dem] returns; a null [view] or [recipe] asks for nothing.
  void want(LightView? view, Future<PolarGrid> Function() dem, ReliefRecipe? recipe) {
    if (view == null || recipe == null || _disposed) return;
    _view = view;
    _dem = dem;
    _recipe = recipe;
    if (view != _asked && !_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_run);
    }
  }

  Future<void> _run() async {
    _scheduled = false;
    final v = _view, dem = _dem, recipe = _recipe;
    if (_building || _disposed || v == null || dem == null || recipe == null || v == _asked) return;
    _asked = v;
    _building = true;
    var failed = false;
    try {
      final grid = await dem();
      final win = reliefWindow(v.x0, v.y0, v.ext, grid.size, grid.scaleM);
      if (win != null && win != _shownWin && !_disposed) {
        final grey = reliefGrey(grid.heights, grid.size, grid.scaleM, win, recipe);
        final rgba = Uint8List(grey.length * 4);
        for (var i = 0, j = 0; i < grey.length; i++, j += 4) {
          rgba[j] = rgba[j + 1] = rgba[j + 2] = grey[i];
          rgba[j + 3] = 255;
        }
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(rgba, win.cols, win.rows, ui.PixelFormat.rgba8888, c.complete);
        final image = await c.future;
        if (_disposed) {
          image.dispose();
        } else {
          final r = reliefRect(win, grid.size, grid.scaleM), old = _shown;
          _shown = (image: image, x0M: r.x0M, y0M: r.y0M, widthM: r.widthM, heightM: r.heightM);
          _shownWin = win;
          builds++;
          onChange();
          if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.image.dispose());
        }
      }
    } catch (e) {
      // the neutral ground stays (the shadows themselves need the same grid)
      debugPrint('relief unavailable: $e');
      // the next want() of this view tries again (AppState.dem retries a failed
      // load); not at once, so an offline fetch does not loop
      if (_asked == v) _asked = null;
      failed = true;
    } finally {
      _building = false;
    }
    // catch up with a view asked for meanwhile
    if (!_disposed && !failed && _view != _asked) _run();
  }

  void dispose() {
    _disposed = true;
    _shown?.image.dispose();
    _shown = null;
  }
}

class LightMap extends StatefulWidget {
  final AppState state;

  /// false while the map is off screen (e.g. another tab): no computing.
  final bool active;
  final ValueChanged<String> onSelect;

  /// An extra card (the inline explanation), shown with the controls after
  /// the legend in every layout, so it never takes height from the map.
  final Widget? sideNote;

  /// Pinned above the scrolling side column of the short side-by-side layout
  /// (a phone in landscape): the parent's time bar, which has no room above
  /// or below a full-height map there. The other layouts ignore it.
  final Widget? sideTop;
  const LightMap(
      {super.key, required this.state, required this.active, required this.onSelect, this.sideNote, this.sideTop});

  /// The card's margin plus its padding around the content.
  static const _inset = EdgeInsets.all(6 + 16);

  /// The stacked (phone) layout never draws the map smaller than this (or
  /// the width) to fit a short slot; the map then scrolls with the controls.
  static const minStackedSide = 240.0;

  /// The side column's least width beside the lander's view in phone
  /// landscape (the view takes the rest, §5).
  static const landerSideMin = 300.0;

  /// The stacked layout pins the switches above the map when a whole map at
  /// least this big (or the width) fits under them; a smaller slot scrolls
  /// the switches, a [minStackedSide] map and the rest together instead.
  static const minPinnedSide = 200.0;

  /// The view and layer switch labels: full words where both switches fit on
  /// one row, otherwise (phones) these short ones, so that both share one
  /// 48 dp row above the map and leave it as much height as possible.
  static const switchLabels = (view: ['Around site', 'Whole region', 'Lander'], layer: ['Sunlight', 'Earth view', 'Both']);
  static const shortSwitchLabels = (view: ['Site', 'Region', 'Lander'], layer: ['Sun', 'Earth', 'Both']);

  /// Side padding of a text-only segment with the full labels.
  static const segmentPad = 10.0;

  /// Side padding of a short-label segment: 6 dp, so the three view and
  /// three layer segments still share one 48 dp row on a 393 dp phone (a
  /// 360 dp one gives each switch its own row). Every segment stays at least
  /// [segmentMin] wide.
  static const shortSegmentPad = 6.0;

  /// The smallest segment: a full 48 dp tap target.
  static const segmentMin = 48.0;

  /// How the view / layer switches fit a pane [width] wide at [scaler]: with
  /// icons, full labels and short labels are tried in turn on one row; if
  /// even the short ones do not fit, the two switches take one row each.
  static ({bool icons, bool short, int rows}) switchFit(double width, TextScaler scaler) {
    // a segmented button gives every segment the width of its widest one
    double seg(List<String> labels, bool icons, double pad) {
      var widest = 0.0;
      for (final l in labels) {
        final tp = TextPainter(
            text: TextSpan(text: l, style: const TextStyle(fontFamily: PH.sans, fontSize: 14, fontWeight: FontWeight.w600)),
            textDirection: TextDirection.ltr,
            textScaler: scaler)
          ..layout();
        // an icon segment: 18 dp icon, 8 dp gap, 12 + 16 dp padding
        widest = math.max(widest, math.max(segmentMin, tp.width + (icons ? 18 + 8 + 28 : 2 * pad)));
        tp.dispose();
      }
      return labels.length * widest + 2 + 2; // the outline, a little slack
    }

    bool fits(({List<String> view, List<String> layer}) l, bool icons, {double pad = segmentPad}) =>
        seg(l.view, icons, pad) + 12 + seg(l.layer, icons, pad) <= width;
    if (fits(switchLabels, true)) return (icons: true, short: false, rows: 1);
    if (fits(switchLabels, false)) return (icons: false, short: false, rows: 1);
    if (fits(shortSwitchLabels, false, pad: shortSegmentPad)) return (icons: false, short: true, rows: 1);
    return (icons: false, short: true, rows: 2);
  }

  /// About how tall the view / layer switches are on [rows] rows of 48 dp
  /// segmented buttons (10 dp apart) at [textScale].
  static double controlsHeightEstimate(int rows, double textScale) => (rows * 48.0 + (rows - 1) * 10) * textScale;

  /// Height kept under the map in the pinned stacked layout for the one-line
  /// approximation note, so it is on screen with the whole map.
  static const shortNoteReserve = 56.0;

  /// On a phone in portrait (a pane under 440 dp wide) the map takes the
  /// full width when at least this share of it fits the slot above the time
  /// bar (the rest scrolls); a shorter slot keeps the whole map on screen.
  static const fullWidthMinShown = 2 / 3;

  /// Whether a LightMap given [c] puts its status and legend beside the map
  /// (wide, bounded panes) instead of below it. Parents that choose between a
  /// bounded and a scrolling slot use this same test.
  static bool sideBySideFor(BoxConstraints c) => _sideBySide(c.deflate(_inset));

  /// Whether [c] gives the short side-by-side layout (phone landscape), which
  /// shows [sideNote].
  static bool shortSideBySideFor(BoxConstraints c) {
    final inner = c.deflate(_inset);
    return _sideBySide(inner) && _short(inner);
  }

  static bool _sideBySide(BoxConstraints c) =>
      c.maxHeight.isFinite && c.maxWidth > c.maxHeight * 1.25 && (c.maxWidth >= 760 || (_short(c) && c.maxWidth >= 480));

  /// A short pane (a phone in landscape): the map takes the full height and
  /// the controls scroll beside it, so the whole map is always on screen.
  static bool _short(BoxConstraints c) => c.maxHeight < 440;

  @override
  State<LightMap> createState() => _LightMapState();

  /// True while the shown map is still computing a frame, has a newer one
  /// queued, or is still building the overlay picture of its latest frame
  /// (the moment "Showing <time>" names). Play waits on it
  /// ([AppState.holdPlayForMap]), so the picture stays within one step of
  /// the time bar on a slow phone (Android 7 emulator: the overlay build
  /// after the compute was not covered, and the map fell up to 40 h behind).
  static final framePending = ValueNotifier<bool>(false);
}

class _LightMapState extends State<LightMap> {
  LightViewKind kind = LightViewKind.closeUp;
  // the lander's view uses the close-up frames (the same requests and cache entries as the map)
  bool get closeUp => kind != LightViewKind.region;
  LightLayer layer = LightLayer.sun;

  // The view and layer choices outlive this State: the site screen and the
  // Light tab build the map under a different parent in portrait, phone
  // landscape and two panes, so rotating the phone makes a new State (qa-2).
  // They are kept in the route's PageStorage bucket under fixed ids.
  static const _closeUpId = 'light-map-close-up', _viewId = 'light-map-view', _layerId = 'light-map-layer';

  void _remember(Object id, Object value) => PageStorage.maybeOf(context)?.writeState(context, value, identifier: id);

  LightEngine? _engine;
  late final _images = LightImageKeeper(onChange: () {
    if (!mounted) return;
    setState(() {});
    _reportPending(); // an overlay came in (or failed): Play may step again
  });
  late final _relief = ReliefKeeper(onChange: () {
    if (mounted) setState(() {});
  });
  LightRequest? _queued;
  bool _busy = false;
  String? _sentKey, _error;

  // the last nowAt() result and what it was computed from (see build)
  Object? _nowKey;
  Map<String, dynamic>? _now;
  List<Site>? _sites;
  Timer? _debounce;

  // legend shares of the shown frame, computed once per frame
  final _labelMemory = ArrowLabelMemory();

  /// The lander's view's mesh (its FidelityBadge reads the eye height and DEM ends).
  final _landerMesh = ValueNotifier<LanderMesh?>(null);
  LightFrame? _sharesFrame;
  LightShares? _shares;

  // each computed frame as drawn (a total lunar eclipse takes its sunlight
  // away, a partial one its full sunlight: lightFrameEclipsed) and the
  // eclipse of a drawn frame
  final _asDrawn = Expando<LightFrame>();
  final _eclipseOf = Expando<SunEclipse>();

  /// [raw] as drawn, the same object for the same frame (the image keeper
  /// compares frames by identity), its eclipse kept in [_eclipseOf].
  LightFrame _drawn(LightFrame raw) {
    final done = _asDrawn[raw];
    if (done != null) return done;
    final site = widget.state.site, q = raw.request;
    final ecl = lightFrameEclipse(raw, terrainHeightM: site.lat == q.lat && site.lon == q.lon ? site.terrainHeightM : 0);
    final f = lightFrameEclipsed(raw, ecl);
    _eclipseOf[f] = ecl;
    return _asDrawn[raw] = f;
  }

  @override
  void initState() {
    super.initState();
    final store = PageStorage.maybeOf(context);
    final c = store?.readState(context, identifier: _closeUpId), l = store?.readState(context, identifier: _layerId);
    final v = store?.readState(context, identifier: _viewId);
    if (v is String) {
      kind = LightViewKind.values.firstWhere((k) => k.name == v, orElse: () => kind);
    } else if (c is bool) {
      kind = c ? LightViewKind.closeUp : LightViewKind.region; // the old bool switch
    }
    if (l is LightLayer) layer = l;
    _images.update(active: widget.active, layer: layer);
  }

  @override
  void didUpdateWidget(LightMap old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      // shown again: an unchanged moment is not recomputed (a change is
      // picked up by _maybeRequest); only a failed one is retried
      if (widget.active && _error != null) _sentKey = null;
      _images.update(active: widget.active);
      _reportPending();
    }
  }

  /// Tell Play whether this map is still behind the time bar. Not while the
  /// shadow engine is failing (offline, say): Play must not wait on a map
  /// that only shows an error. A replaced map (rotation) leaves the flag to
  /// its successor; [dispose] clears it when the map goes away.
  void _reportPending() {
    if (!mounted) return;
    LightMap.framePending.value = widget.active &&
        _error == null &&
        _images.error == null &&
        (_busy || _queued != null || _images.catchingUp);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _landerMesh.dispose();
    if (widget.active) LightMap.framePending.value = false;
    _images.dispose();
    _relief.dispose();
    super.dispose();
  }

  void _maybeRequest() {
    final s = widget.state, eph = s.eph;
    if (!widget.active || eph == null || !mounted) return;
    final q = lightRequestFor(s, extent: closeUp ? LightExtent.closeUp : LightExtent.region);
    if (q.key == _sentKey) return;
    _sentKey = q.key;
    _queued = q;
    _reportPending();
    _debounce?.cancel();
    // playback already paces itself; only scrubbing is debounced
    _debounce = Timer(s.playing ? Duration.zero : const Duration(milliseconds: 60), _pump);
  }

  /// While playing, when the frame just finished ([q]) is still the
  /// cursor's (no tick is waiting to be requested), start the next tick's
  /// frame, so it is ready when the cursor gets there; the engine's cache
  /// (and in-flight sharing) hands it over. Never ahead of a frame that is
  /// actually needed (the single worker runs one frame at a time).
  void _prefetch(LightEngine engine, LightRequest q) {
    final s = widget.state, eph = s.eph;
    if (!mounted || !widget.active || !s.playing || eph == null || _queued != null || !q.coarse) return;
    if (s.cursorMs != q.tMs) return; // a newer tick is on its way
    final t = q.tMs + s.playStepMs; // what _tick will set: the same sum
    // _tick stops (and sets the last time itself) once a step would reach it
    if (t < s.rangeStartMs || t >= s.lastCursorMs) return;
    engine.compute(lightRequestFor(s, extent: closeUp ? LightExtent.closeUp : LightExtent.region, tMs: t, coarse: true)).ignore();
  }

  /// Latest request wins: while a frame computes, newer requests replace
  /// each other and only the newest runs next (smooth scrubbing / playback).
  /// Overlays are built by [_images] meanwhile, always for the newest frame.
  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    _reportPending();
    if (mounted) setState(() {});
    try {
      final engine = _engine ??= await widget.state.lightEngine();
      LightRequest? last;
      while (_queued != null && mounted) {
        final q = last = _queued!;
        _queued = null;
        final f = await engine.compute(q);
        if (!mounted) return;
        _images.update(engine: engine, frame: _drawn(f));
      }
      if (last != null) _prefetch(engine, last);
      _error = null;
    } catch (e) {
      _error = '$e';
    } finally {
      _busy = false;
      _reportPending();
      if (mounted) setState(() {});
    }
  }

  LightShares _sharesOf(LightFrame f) {
    if (!identical(_sharesFrame, f)) {
      _sharesFrame = f;
      _shares = lightFrameShares(f);
    }
    return _shares!;
  }

  /// The whole region gets a margin round the map (6% a side), so sites at
  /// 80°S on its edge (IM-1 Odysseus, say) keep their markers and labels in
  /// view instead of half off the map (user report 2026-10-14).
  static LightView _withMargin(LightView v) {
    final m = v.ext * 0.06;
    return (x0: v.x0 - m, y0: v.y0 + m, ext: v.ext + 2 * m);
  }

  LightView get _targetView {
    final f = _images.shown?.frame;
    if (f != null) return f.request.closeUp ? frameView(f) : _withMargin(frameView(f));
    final layers = widget.state.mapLayers;
    final half = layers?.halfWidthM ?? 304000;
    if (!closeUp) return _withMargin((x0: -half, y0: half, ext: 2 * half));
    return closeUpTargetView(widget.state.site.lat, widget.state.site.lon, layers?.demHalfWidthM ?? half,
        playing: widget.state.playing);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRequest());
    final s = widget.state;
    final layers = s.mapLayers;
    if (layers == null || s.eph == null) {
      return Card(child: Center(child: Text('Map data unavailable', style: PHText.body.copyWith(color: PH.muted))));
    }
    final o = s.options;
    final img = _images.shown;
    final shownFrame = img?.frame;
    // While playing, the arrows, labels, status line and time on the map
    // describe the moment its picture shows (a step or two behind the
    // cursor), so the picture never contradicts the words next to it. Only
    // a playback frame of this very map counts (same view, site and height,
    // inside the chosen dates); anything else waits under "Computing".
    final fq = shownFrame?.request;
    final playFrame = s.playing &&
        fq != null &&
        fq.coarse &&
        fq.closeUp == closeUp &&
        (!closeUp || (fq.lat == s.site.lat && fq.lon == s.site.lon)) &&
        fq.observerHeightM == s.observerHeightM &&
        fq.tMs >= s.rangeStartMs &&
        fq.tMs <= s.rangeEndMs;
    final tMap = playFrame ? fq.tMs : s.cursorMs;
    // the same object while nothing it depends on changes, so the painter
    // (which compares it by identity) does not repaint on every Play tick
    // (AppState.observer is a new object on every call: key on its inputs)
    final nowKey = (s.eph, s.site, s.observerHeightM, s.mask, tMap, o);
    final now = nowKey == _nowKey ? _now! : nowAt(s.eph!, s.observer, s.mask, tMap, o);
    _nowKey = nowKey;
    _now = now;
    // AppState.allSites is a new list on every call: keep ours while equal
    final all = s.allSites;
    final sites = _sites != null && listEquals(_sites, all) ? _sites! : (_sites = all);
    final dsnUp = s.eph!.dsnMask(tMap) != 0;
    final shares = shownFrame == null ? null : _sharesOf(shownFrame);
    // a lunar eclipse at the shown frame's moment (its picture's, so while a
    // newer frame computes it may trail the status line by a step)
    final eclipse = lightEclipseNote(shownFrame == null ? null : _eclipseOf[shownFrame]);
    final failed = _error != null || _images.error != null;
    final stale = _busy || (!failed && (_images.pending || shownFrame == null || shownFrame.request.key != _sentKey));
    final fine = shownFrame?.request.closeUp ?? closeUp;
    final coarseShown = shownFrame?.request.coarse ?? false;
    final scope = fine ? 'within 64 km of ${s.site.short}' : 'of the region inside 80°S';
    // a close-up near the map's edge: part of the circle is off the map
    final onMap = shares != null && fine && shares.inside < 0.98 ? shares.inside : null;
    // narrower panes: text-only segments, then short labels (with the full
    // meaning in the accessible name), so both switches share one row and labels do
    // not wrap. The title and time only on wide panes (elsewhere the tab
    // name and the time bar say both).
    final scaler = MediaQuery.textScalerOf(context);
    // text-only segments on phones even where the icons would fit
    ({bool icons, bool short, int rows}) phoneFit(({bool icons, bool short, int rows}) f) =>
        (icons: false, short: f.short, rows: f.rows);
    Widget header(({bool icons, bool short, int rows}) fit, {bool title = false}) {
      final compact = !fit.icons;
      final l = fit.short ? LightMap.shortSwitchLabels : LightMap.switchLabels;
      // the short labels carry their full meaning in the accessible name
      // ("Both: Sun + Earth"), not in a Tooltip: on touch a tooltip shown by
      // a press could stay on screen over other screens once this tab went
      // off stage (its fade-out ticker is muted there; new-sun-earth-tooltip)
      Widget segLabel(String text, String meaning) =>
          fit.short ? Semantics(label: '$text: $meaning', excludeSemantics: true, child: Text(text)) : Text(text);
      // segments are text buttons at least 64 dp wide; a horizontal density
      // of -4 makes that 48 dp (still a full tap target, and 48 dp tall), so
      // the short labels share one row on a 393 dp phone
      final style = compact
          ? ButtonStyle(
              padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: fit.short ? LightMap.shortSegmentPad : LightMap.segmentPad)),
              visualDensity: const VisualDensity(horizontal: -4, vertical: 0))
          : null;
      return Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (title) const Text('Light & shadow', style: PHText.subtitle),
      if (title) Text(utcLabel(tMap), style: numStyle(size: 13, color: PH.muted)),
      GuideTarget(id: 'light-view', child: SegmentedButton<LightViewKind>(
        showSelectedIcon: false,
        style: style,
        segments: [
          ButtonSegment(
              value: LightViewKind.closeUp,
              label: segLabel(l.view[0], 'Around the site (64 km)'),
              icon: compact ? null : const Icon(Icons.center_focus_strong, size: 18)),
          ButtonSegment(
              value: LightViewKind.region,
              label: segLabel(l.view[1], 'Whole region (inside 80°S)'),
              icon: compact ? null : const Icon(Icons.public, size: 18)),
          // no Tooltip on touch (see segLabel); the meaning is in the accessible name
          ButtonSegment(
              value: LightViewKind.lander,
              label: GuideTarget(
                  id: 'light-lander',
                  child: segLabel(l.view[2], "From the lander (2 m up): what you would see standing on the lander, 2 m above the ground")),
              icon: compact ? null : const Icon(Icons.landscape_outlined, size: 18)),
        ],
        selected: {kind},
        onSelectionChanged: (v) => setState(() {
          kind = v.first;
          _sentKey = null;
          _remember(_viewId, kind.name);
        }),
      )),
      GuideTarget(id: 'light-layer', child: SegmentedButton<LightLayer>(
        showSelectedIcon: false,
        style: style,
        segments: [
          ButtonSegment(
              value: LightLayer.sun,
              label: segLabel(l.layer[0], 'Sunlight'),
              icon: compact ? null : const Icon(Icons.wb_sunny_outlined, size: 18)),
          ButtonSegment(
              value: LightLayer.earth,
              label: segLabel(l.layer[1], 'Earth in view'),
              icon: compact ? null : const Icon(Icons.public, size: 18)),
          ButtonSegment(
              value: LightLayer.both,
              label: segLabel(l.layer[2], 'Sun + Earth'),
              icon: compact ? null : const Icon(Icons.join_inner, size: 18)),
        ],
        selected: {layer},
        onSelectionChanged: (v) {
          setState(() => layer = v.first);
          _remember(_layerId, layer);
          _images.update(layer: v.first);
          _reportPending();
        },
      )),
    ]);
    }

    final legend = _Legend(
        layer: img?.layer ?? layer,
        shares: shares,
        scope: scope,
        onMap: onMap,
        approx: coarseShown,
        eclipse: eclipse?.sentence,
        lander: kind == LightViewKind.lander);
    final status = _StatusLine(
        site: s.site,
        now: now,
        requireDsn: o.requireDsn,
        dsnInView: dsnUp,
        sunRule: o.sunCriterion,
        earthRule: o.earthCriterion,
        exact: s.expert);
    final h = s.observerHeightM;
    final heightText = '${h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1)} m';
    // a close-up reaching past the base map's edge (about 80°S): terrain and ground there are labelled,
    // from the view mapBox shades (its relief is drawn before the first frame arrives, too)
    final pastMap = fine && viewBeyondBaseMap(_targetView, layers.halfWidthM);
    // agreement figures: test/core/shadow_test.dart (16 preset sites x 60 random moments, 2 m observer)
    final badge = kind == LightViewKind.lander
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ValueListenableBuilder<LanderMesh?>(
                valueListenable: _landerMesh,
                builder: (context, m, _) {
                  // the mesh of this site and eye height only
                  final mine = m != null && m.cam.latDeg == s.site.lat && m.cam.lonDeg == s.site.lon && m.cam.eyeHeightM == h;
                  return FidelityBadge(
                      key: const ValueKey('lander-badge'),
                      text: landerFidelityText(heightText,
                          custom: s.site.custom,
                          eyeOffsetM: mine && !s.site.custom ? m.cam.groundM - s.site.terrainHeightM : null,
                          demEnds: mine ? m.demEnds : const [],
                          eclipse: eclipse != null));
                }),
            if (s.playing) FidelityBadge(key: const ValueKey('lander-play-badge'), text: landerPlayFidelity(web: kIsWeb)),
            if (s.site.custom) const FidelityBadge(text: FidelityBadge.customHorizon),
          ])
        : FidelityBadge(
      text: 'Shadows are computed on this device from the NASA LOLA elevation map at ${fine ? '400 m' : '800 m'} '
          'per pixel, for an observer $heightText above the ground, with the Sun\'s and Earth\'s directions from '
          'SPICE (DE440). Checked against the per-site horizon calculations (2 m observer), "sunlit or not" agrees '
          '${fine ? '94%' : '91%'} of the time with 400 m horizons and ${fine ? '87%' : '82%'} with the sharper 80 m '
          'site horizons, so the map can differ from the status line near shadow edges. Edges are interpolated '
          'between grid cells. The terrain under the colours is shaded relief from the same LOLA elevations, lit '
          'by an artificial light from the upper left with heights exaggerated 2x: it is not a photo and not the '
          'real lighting, and inside shadows it is drawn faintly for orientation only.'
          '${pastMap ? ' $lightPastMapNote' : ''}'
          '${eclipse != null ? ' $lightEclipseFidelity' : ''}'
          '${coarseShown ? ' While playing, the map uses a coarser ${shownFrame!.pxM.round()} m grid so it can keep up, and the '
              'legend\'s shares are from that grid; the agreement figures above are for the paused map. Pause for full detail.' : ''}',
    );
    final error = failed ? Text(_error ?? '${_images.error}', style: PHText.small.copyWith(color: PH.warn)) : null;

    // [bottomMayHide]: the map's lower edge can sit under the pinned time bar
    // until the page is scrolled (a phone in portrait), so a note there would
    // not be seen: the note then always goes at the top.
    // [landerSize]: the lander's view in a box of its own shape (a wide strip in
    // phone landscape) instead of the [side] square
    Widget mapBox(double side, {bool bottomMayHide = false, Size? landerSize}) {
      _images.update(side: side, dpr: MediaQuery.devicePixelRatioOf(context));
      if (kind == LightViewKind.lander) {
        return GuideTarget(
            id: 'light-map',
            child: LanderViewPanel(
                state: s,
                near: shownFrame != null && shownFrame.request.closeUp ? shownFrame : null,
                layer: img?.layer ?? layer,
                width: landerSize?.width ?? side,
                meshOut: _landerMesh,
                // a phone in portrait scrolls: the view keeps its full height there
                maxHeight: bottomMayHide ? double.infinity : (landerSize?.height ?? side)));
      }
      final view = _targetView;
      // the ground past the base map's edge: shaded on the device (ReliefKeeper)
      _relief.want(fine && viewBeyondBaseMap(view, layers.halfWidthM) ? view : null, s.dem, layers.relief);
      if (!s.playing) _labelMemory.clear();
      final playNote = 'Coarser while playing, pause for full detail. Showing ${utcLabel(tMap)}';
      final semantic = '${s.site.short}, ${utcLabel(tMap)}. '
          '${shares == null ? 'Computing.' : '${coarseShown ? 'About ' : ''}${(100 * shares.sun).round()}% of the area $scope is sunlit, '
              '${(100 * shares.earth).round()}% can see Earth.'} '
          '${eclipse != null ? '${eclipse.sentence}. ' : ''}'
          '${_StatusLine.sentence(s.site, now, o.requireDsn, dsnUp, o.sunCriterion, o.earthCriterion)}'
          // the corner notes, for screen readers too
          '${playFrame ? ' $playNote.' : stale ? ' Computing shadows.' : ''}';
      // "Computing shadows…" floats over the map's corner, so nothing around
      // the map moves when it appears or goes (no layout jump)
      const busyText = 'Computing shadows…';
      // the playback note: two single lines (cut with "…" if they must be),
      // at most the canvas labels' text size, so it never covers much of the
      // map; the map's label and the badge carry the full text
      // the time first, so a cut line still shows the hour ("Showing 14:00 UTC, 12 Oct 2026")
      final (mapDay, mapTime) = utcTwoLines(tMap);
      final playLines = ['Coarser while playing · pause for full detail', 'Showing $mapTime, $mapDay'];
      final noteScaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale);
      // height of a corner note's band: 8 px inset + 12 px padding + its
      // single-line texts at [noteScaler] + 4 px air
      double noteBand(List<String> lines, double extraW, TextScaler scaler) {
        var h = 0.0;
        for (final line in lines) {
          final tp = TextPainter(
              text: TextSpan(text: line, style: PHText.small),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
              ellipsis: '…')
            ..layout(maxWidth: math.max(40.0, side - 16 - 20 - extraW));
          h += tp.height;
          tp.dispose();
        }
        return 8 + 12 + h + 4;
      }

      // Where the corner note goes: the top or the bottom (above the scale
      // bar), whichever leaves more room between the note and the reach of
      // the selected site's arrows and labels (0.24 of the side, plus about
      // 30 px of label), measured from the site's own row on this map (a
      // clamped close-up is not centred on it). Ties go to the top, so a
      // centred close-up never flips. In a close-up the note also keeps clear
      // of the pole-direction badge in the top-right corner.
      const aboveScaleBar = 44.0;
      final badgeW = fine ? 60.0 : 0.0;
      // while playing the band is the same on every frame (the playback note,
      // "Computing" or neither), so the labels it keeps out never jump in and
      // out; only a lunar eclipse adds its lines (to the playback note, or as
      // a note of its own on a paused, finished map)
      final eclLines = eclipse?.lines ?? const <String>[];
      final playH = noteBand([...playLines, ...eclLines], badgeW, noteScaler);
      final busyH = noteBand(const [busyText], 22 + badgeW, MediaQuery.textScalerOf(context));
      final noteH = s.playing
          ? math.max(playH, busyH)
          : stale
              ? busyH
              : eclLines.isEmpty
                  ? 0.0
                  : noteBand(eclLines, badgeW, noteScaler);
      final (_, sy) = latLonToXY(s.site.lat, s.site.lon);
      final siteY = (view.y0 - sy) * side / view.ext;
      final reach = 0.24 * side + 30;
      final roomTop = siteY - reach - noteH;
      final roomBottom = side - aboveScaleBar - (noteH - 8) - (siteY + reach);
      final noteTop = bottomMayHide || roomTop >= roomBottom - 0.5;
      final noteRight = 8 + (noteTop ? badgeW : 0.0);
      // the band the note (inset + padding + text + air) covers
      final noteArea = noteH <= 0
          ? null
          : (noteTop ? Rect.fromLTWH(0, 0, side, noteH) : Rect.fromLTRB(0, side - aboveScaleBar - (noteH - 8), side, side));

      // a note in the chosen corner: single lines, cut with "…" if they must be
      Widget cornerNote(Key key, List<String> lines) => Positioned(
            left: 8,
            top: noteTop ? 8 : null,
            bottom: noteTop ? null : aboveScaleBar,
            right: noteRight,
            child: IgnorePointer(
              child: Align(
                alignment: noteTop ? Alignment.topLeft : Alignment.bottomLeft,
                child: DecoratedBox(
                  key: key,
                  decoration: BoxDecoration(color: const Color(0xE6060B16), borderRadius: BorderRadius.circular(PH.radiusInner)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    // the map's label already says it to screen readers
                    child: ExcludeSemantics(
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(textScaler: noteScaler),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          for (final line in lines)
                            Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: PHText.small),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
      final busy = Positioned(
        left: 8,
        top: noteTop ? 8 : null,
        bottom: noteTop ? null : aboveScaleBar,
        right: noteRight,
        child: IgnorePointer(
          child: Align(
            alignment: noteTop ? Alignment.topLeft : Alignment.bottomLeft,
            child: Container(
              key: const ValueKey('light-busy'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xE6060B16), borderRadius: BorderRadius.circular(PH.radiusInner)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const BusyIndicator(size: 14, strokeWidth: 1.8), // a still hourglass under reduced motion
                const SizedBox(width: 8),
                Flexible(
                    child: Text(busyText,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: PHText.small.copyWith(color: PH.text))),
              ]),
            ),
          ),
        ),
      );
      return GuideTarget(id: 'light-map', child: SizedBox(
        width: side,
        height: side,
        child: Stack(children: [
          Positioned.fill(child: Semantics(
          label: 'Light and shadow map. $semantic',
          hint: 'Tap a site marker to select it.',
          child: GestureDetector(
            onTapUp: (d) => _onTap(d.localPosition, side, view),
            // its own layer: the busy note's spinner does not repaint the map
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PH.radiusInner),
                child: CustomPaint(
                  size: Size(side, side),
                  painter: LightFramePainter(
                    hillshade: layers.hillshade,
                    halfWidthM: layers.halfWidthM,
                    relief: _relief.shown,
                    images: img,
                    view: view,
                    sites: sites,
                    selected: s.site,
                    now: now,
                    closeUp: fine,
                    // the corner note covers a band; labels keep out of it
                    noteArea: noteArea,
                    // only Play keeps labels near their last spots
                    labelMemory: s.playing ? _labelMemory : null,
                    earthRule: o.earthCriterion,
                    requireDsn: o.requireDsn,
                    textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: PH.maxCanvasTextScale),
                    exact: s.expert,
                  ),
                ),
              ),
            ),
          ),
          )),
          if (playFrame)
            cornerNote(const ValueKey('light-coarse'), [...playLines, ...eclLines])
          else if (stale)
            busy
          else if (eclLines.isNotEmpty)
            cornerNote(const ValueKey('light-eclipse'), eclLines),
        ]),
      ));
    }

    final note = widget.sideNote;
    return Card(
      margin: const EdgeInsets.all(6), // part of LightMap._inset
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, c) {
          if (LightMap._sideBySide(c)) {
            if (LightMap._short(c)) {
              // phone landscape: the whole map at full height; the parent's
              // time bar is pinned beside it and the rest scrolls under that
              var side = math.max(0.0, math.min(c.maxHeight, c.maxWidth - 16 - 240));
              // the lander's view is a wide strip, not a square: it takes the
              // wide column and leaves the time bar and switches [landerSideMin]
              final lander = kind == LightViewKind.lander
                  ? Size(math.max(side, c.maxWidth - 16 - LightMap.landerSideMin), c.maxHeight)
                  : null;
              final map = mapBox(side, landerSize: lander);
              if (lander != null) side = lander.width;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                map,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ?widget.sideTop,
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (widget.sideTop != null) const SizedBox(height: 8),
                          header(phoneFit(LightMap.switchFit(c.maxWidth - 16 - side, scaler))),
                          const SizedBox(height: 12),
                          status,
                          const SizedBox(height: 10),
                          legend,
                          ?error,
                          badge,
                          if (note != null) ...[const SizedBox(height: 12), note],
                        ]),
                      ),
                    ),
                  ]),
                ),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header((icons: true, short: false, rows: 1), title: true),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(builder: (context, c2) {
                  final side = math.max(0.0, math.min(c2.maxHeight, c2.maxWidth - 300));
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    mapBox(side),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          status,
                          const SizedBox(height: 14),
                          legend,
                          ?error,
                          badge,
                          if (note != null) ...[const SizedBox(height: 12), note],
                        ]),
                      ),
                    ),
                  ]);
                }),
              ),
            ]);
          }
          // the view and layer switches always come first (on screen: the
          // demo's "Switch to Both"), on one row where short labels make that
          // possible, then the map. Where a whole map of at least
          // minPinnedSide fits under them, the switches are pinned and the
          // map fills what is left (with a one-line approximation note when
          // there is room), all above the parent's pinned time bar; the
          // status, legend and full explanation follow in the scroll. A very
          // short slot (large text on a small phone) scrolls the switches
          // and a usable map together instead of shrinking it to a thumbnail.
          final usable = math.min(c.maxWidth, LightMap.minStackedSide);
          final pinFloor = math.min(c.maxWidth, LightMap.minPinnedSide);
          final fit0 = LightMap.switchFit(c.maxWidth, scaler);
          final fit = c.maxWidth < 440 ? phoneFit(fit0) : fit0;
          final controls = header(fit);
          final shortNote = FidelityBadge(
              text: playFrame
                  ? 'Approximate: while playing, shadows from a coarser ${shownFrame!.pxM.round()} m grid; pause for the '
                      '${fine ? '400 m' : '800 m'} map. Status, legend and details below.'
                  : 'Approximate: shadows from a ${fine ? '400 m' : '800 m'} terrain grid'
                      // (kept under FidelityBadge's 110-character first-sentence summary, so it is read whole)
                      '${pastMap ? '; past about 80°S the relief is shaded on this device' : ''}. '
                      'Status, legend and details below.');
          List<Widget> below() => [
                const SizedBox(height: 12),
                status,
                const SizedBox(height: 10),
                legend,
                ?error,
                badge,
                if (note != null) ...[const SizedBox(height: 12), note],
              ];
          final textScale = (scaler.scale(14) / 14).clamp(1.0, 3.0);
          final room = c.maxHeight - LightMap.controlsHeightEstimate(fit.rows, textScale) - 12;
          if (c.maxHeight.isFinite && room >= pinFloor) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              controls,
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(builder: (context, c2) {
                  // room for the one-line note too when there is enough;
                  // otherwise the whole map, the note just under it
                  final withNote = c2.maxHeight - LightMap.shortNoteReserve;
                  // a phone in portrait: the map takes the full width
                  // (new-light-map-size) when most of it is still on screen
                  // above the time bar; its lower edge, the note and the
                  // details then scroll in the slot
                  final fullWidth = c.maxWidth < 440 && c2.maxHeight >= c2.maxWidth * LightMap.fullWidthMinShown;
                  final side = fullWidth
                      ? c2.maxWidth
                      : math.min(c2.maxWidth, withNote >= usable ? withNote : math.max(c2.maxHeight, pinFloor));
                  return SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                      Center(child: mapBox(side, bottomMayHide: fullWidth)),
                      shortNote,
                      ...below(),
                    ]),
                  );
                }),
              ),
            ]);
          }
          // a phone in portrait: the full width here too when most of the
          // map shows (new-light-map-size)
          final phoneFull = c.maxWidth < 440 && room >= c.maxWidth * LightMap.fullWidthMinShown;
          final side =
              c.maxHeight.isFinite && !phoneFull ? math.min(c.maxWidth, math.max(room, usable)) : c.maxWidth;
          final stacked = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            controls,
            const SizedBox(height: 12),
            Center(child: mapBox(side, bottomMayHide: phoneFull || !c.maxHeight.isFinite)),
            ...below(),
          ]);
          return c.maxHeight.isFinite ? SingleChildScrollView(child: stacked) : stacked;
        }),
      ),
    );
  }

  void _onTap(Offset p, double side, LightView view) {
    final k = side / view.ext;
    String? best;
    var bestD = 24.0; // 48 px finger-sized target
    for (final st in widget.state.allSites) {
      final (x, y) = latLonToXY(st.lat, st.lon);
      final d = (Offset((x - view.x0) * k, (view.y0 - y) * k) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = st.id;
      }
    }
    if (best != null) widget.onSelect(best);
  }
}

/// "Shackleton rim right now: in full sunlight · Earth in view".
class _StatusLine extends StatelessWidget {
  final Site site;
  final Map<String, dynamic> now;
  final bool requireDsn;

  /// Whether a DSN station can see the Moon at this moment.
  final bool dsnInView;

  /// The user's "counts as up" rules (the status says what is physically up
  /// and, when that differs from the rule's verdict, why it is not counted).
  final SunCriterion sunRule;
  final EarthCriterion earthRule;

  /// "Show exact numbers": the azimuth, elevation and skyline angles follow
  /// each line. Off (the default), the plain-language status stands alone
  /// (rubric: decimals and jargon such as "az" / "el" only in expert mode).
  final bool exact;
  const _StatusLine(
      {required this.site,
      required this.now,
      required this.requireDsn,
      required this.dsnInView,
      required this.sunRule,
      required this.earthRule,
      this.exact = false});

  static double _n(Map<String, dynamic> b, String k) => (b[k] as num).toDouble();

  static String sunText(Map<String, dynamic> sun, SunCriterion rule) => lightSunStatus(sun, rule);

  static String earthText(Map<String, dynamic> e, bool requireDsn, bool dsnInView, EarthCriterion rule) => earthStatusText(
      visible: e['visible'] == true,
      elDeg: _n(e, 'el'),
      rhoDeg: _n(e, 'rho'),
      frac: _n(e, 'frac'),
      dsnRequired: requireDsn,
      dsnInView: dsnInView,
      earthRule: rule,
      hzDeg: _n(e, 'hz'));

  static String sentence(Site site, Map<String, dynamic> now, bool requireDsn, bool dsnInView, SunCriterion sunRule,
          EarthCriterion earthRule) =>
      '${site.short} at this moment: ${sunText(now['sun'] as Map<String, dynamic>, sunRule)}; '
      '${earthText(now['earth'] as Map<String, dynamic>, requireDsn, dsnInView, earthRule)}.';

  /// One status line's spans: the body's name in bold, then its status. A
  /// status that already starts with the name ("Earth below the horizon")
  /// bolds that word instead of repeating it ("Earth: Earth below…"); any
  /// other gets a "Sun: " prefix. [angles] (expert mode only) follows, muted.
  static List<InlineSpan> statusSpans(String label, String text, String? angles) {
    const bold = TextStyle(fontWeight: FontWeight.w600);
    final named = text.startsWith('$label ');
    return [
      TextSpan(text: named ? label : '$label: ', style: bold),
      TextSpan(text: named ? text.substring(label.length) : text),
      if (angles != null) TextSpan(text: '  $angles', style: numStyle(size: 13, color: PH.muted)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sun = now['sun'] as Map<String, dynamic>, earth = now['earth'] as Map<String, dynamic>;
    Widget line(GlyphKind glyph, String label, String text, String angles) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 3), child: MeaningGlyph(glyph, size: 18, semantic: false)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(children: statusSpans(label, text, exact ? angles : null)), style: PHText.body),
            ),
          ]),
        );
    String angles(Map<String, dynamic> b) =>
        'az ${(b['az'] as num).toStringAsFixed(0)}° · el ${(b['el'] as num).toStringAsFixed(1)}° · skyline ${(b['hz'] as num).toStringAsFixed(1)}°';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(site.short, style: PHText.subtitle),
      const SizedBox(height: 8),
      line(GlyphKind.sun, 'Sun', sunText(sun, sunRule), angles(sun)),
      line(GlyphKind.earth, 'Earth', earthText(earth, requireDsn, dsnInView, earthRule), angles(earth)),
    ]);
  }
}

class _Legend extends StatelessWidget {
  final LightLayer layer;
  final LightShares? shares;
  final String scope;

  /// Share of the close-up's circle that lies on the map, when part of it
  /// does not (a site near the map's edge); null otherwise.
  final double? onMap;

  /// The shares come from a coarse playback frame: shown as "≈ N%".
  final bool approx;

  /// A lunar eclipse at the frame's moment ([lightEclipseNote]'s sentence).
  final String? eclipse;

  /// The lander's view: three more keys (light not computed, the
  /// see-through near ground and the dashed horizon, §4.4).
  final bool lander;
  const _Legend(
      {required this.layer,
      required this.shares,
      required this.scope,
      this.onMap,
      this.approx = false,
      this.eclipse,
      this.lander = false});

  @override
  Widget build(BuildContext context) {
    final sh = shares;
    String pct(double Function(LightShares) f) => sh == null ? '–' : '${approx ? '≈ ' : ''}${(100 * f(sh)).round()}%';
    final items = switch (layer) {
      LightLayer.sun => [
          (LightClass.fullSun, 'Full sunlight', pct((s) => s.sunFull)),
          (LightClass.partSun, eclipse != null ? 'Part of the Sun (ridge or Earth)' : 'Sun partly over a ridge', pct((s) => s.sun - s.sunFull)),
          (LightClass.shadow, 'In shadow', pct((s) => 1 - s.sun)),
        ],
      LightLayer.earth => [
          (LightClass.earthSeen, 'Earth in view', pct((s) => s.earth)),
          (LightClass.earthHidden, 'Earth hidden', pct((s) => 1 - s.earth)),
        ],
      LightLayer.both => [
          (LightClass.both, 'Sun + Earth', pct((s) => s.both)),
          (LightClass.sunOnly, 'Sun only', pct((s) => s.sun - s.both)),
          (LightClass.earthOnly, 'Earth only', pct((s) => s.earth - s.both)),
          (LightClass.neither, 'Neither', pct((s) => 1 - s.sun - s.earth + s.both)),
        ],
    };
    final part = onMap;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (eclipse != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$eclipse.', key: const ValueKey('light-eclipse-legend'), style: PHText.small),
        ),
      Text('Share of the area $scope', style: PHText.small.copyWith(color: PH.muted)),
      if (part != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Only ${(100 * part).round()}% of that circle lies on the map (it reaches past the map\'s edge); '
              'the shares are of that part.', style: PHText.small.copyWith(color: PH.muted)),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 8, children: [
        for (final (k, label, p) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            CustomPaint(size: const Size(22, 16), painter: _Swatch(k)),
            const SizedBox(width: 8),
            // wraps instead of overflowing on narrow cards / large text
            Flexible(child: Text(label, style: PHText.small)),
            const SizedBox(width: 6),
            Text(p, style: statStyle(size: 14)),
          ]),
        if (lander)
          for (final (k, label) in const [
            (_LanderKey.notComputed, 'Light not computed'),
            (_LanderKey.seeThrough, 'Near ground, see-through'),
            (_LanderKey.horizon, 'Horizon (dashed)'),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              CustomPaint(size: const Size(22, 16), painter: _LanderSwatch(k)),
              const SizedBox(width: 8),
              Flexible(child: Text(label, style: PHText.small)),
            ]),
      ]),
    ]);
  }
}

enum _LanderKey { notComputed, seeThrough, horizon }

/// The lander's view's extra legend keys: its grey, the near ground at its
/// see-through alpha over the sky, and the dashed reference horizon.
class _LanderSwatch extends CustomPainter {
  final _LanderKey k;
  _LanderSwatch(this.k);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = PH.bg);
    switch (k) {
      case _LanderKey.notComputed:
        canvas.drawRect(r, Paint()..color = const Color(landerNotComputedArgb));
      case _LanderKey.seeThrough:
        canvas.drawRect(Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2), Paint()..color = PH.sun);
        canvas.drawRect(r, Paint()..color = const Color(landerNotComputedArgb).withValues(alpha: landerNearAlpha));
      case _LanderKey.horizon:
        final p = Paint()
          ..color = PH.text.withValues(alpha: 0.7)
          ..strokeWidth = 1.2;
        for (var x = 1.0; x < size.width; x += 7) {
          canvas.drawLine(Offset(x, size.height / 2), Offset(math.min(size.width - 1, x + 4), size.height / 2), p);
        }
    }
    canvas.drawRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..color = PH.lineStrong);
  }

  @override
  bool shouldRepaint(_LanderSwatch old) => old.k != k;
}

/// Legend swatch: the map's own pixel rule applied to mid-grey terrain.
class _Swatch extends CustomPainter {
  final LightClass k;
  _Swatch(this.k);
  @override
  void paint(Canvas canvas, Size size) {
    const g = 0.55;
    final paint = Paint();
    for (var y = 0; y < size.height; y++) {
      for (var x = 0; x < size.width; x++) {
        final p = lightPixel(k, 0.12, x, y, 1);
        double ch(double m, double s) => 1 - (1 - g * m) * (1 - s);
        paint.color = Color.from(alpha: 1, red: ch(p.mr, p.sr), green: ch(p.mg, p.sg), blue: ch(p.mb, p.sb));
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint);
      }
    }
    // outline, so the dark (shadow) swatch stays visible on the card
    canvas.drawRect(Offset.zero & size, Paint()
      ..style = PaintingStyle.stroke
      ..color = PH.lineStrong);
  }

  @override
  bool shouldRepaint(covariant _Swatch old) => old.k != k;
}

/// One direction arrow for [layoutArrowLabels]: its shaft runs from [from] to
/// the head at [tip]; [size] is its label's box.
typedef ArrowLabel = ({Offset from, Offset tip, Size size});

/// Centres for the arrows' labels, in order. Each label goes just past its
/// arrow head when that spot is free; otherwise it steps sideways or further
/// out, or stacks beside an earlier label. A spot is free when the label is
/// inside [canvas] and clear of every arrow head and shaft, of [keepClear]
/// and of the labels placed before it. When no spot is free (a tiny canvas),
/// the labels still never cover each other or a head where that is possible.
///
/// With [memory], a label takes the free spot nearest to where it was on the
/// last layout, so Play (the arrows turning a little and the label
/// words changing on every step) never makes a label jump between spots.
List<Offset> layoutArrowLabels(
    {required List<ArrowLabel> arrows, required Size canvas, List<Rect> keepClear = const [], ArrowLabelMemory? memory}) {
  Offset inside(Size s, Offset c) => Offset(
      c.dx.clamp(s.width / 2 + 2, math.max(s.width / 2 + 2, canvas.width - s.width / 2 - 2)),
      c.dy.clamp(s.height / 2 + 2, math.max(s.height / 2 + 2, canvas.height - s.height / 2 - 2)));
  final heads = [for (final a in arrows) Rect.fromCircle(center: a.tip, radius: 9)];
  final shafts = <Offset>[
    for (final a in arrows)
      for (var t = 0.0, n = math.max(1, (a.tip - a.from).distance ~/ 4); t <= 1.0001; t += 1 / n) Offset.lerp(a.from, a.tip, t)!,
  ];
  final placed = <Rect>[];
  final out = <Offset>[];
  for (final a in arrows) {
    final w = a.size.width, h = a.size.height;
    final v = a.tip - a.from;
    final dir = v.distance < 1e-6 ? const Offset(0, -1) : v / v.distance;
    final perp = Offset(-dir.dy, dir.dx);
    // distance from the label's centre to its edge facing the head
    final support = dir.dx.abs() * w / 2 + dir.dy.abs() * h / 2;
    final a0 = 11 + support, along = h + 4;
    final across = perp.dx.abs() * w + perp.dy.abs() * h + 4;
    final candidates = <Offset>[
      for (final (k, s) in const [(0, 0), (0, 1), (0, -1), (1, 0), (1, 1), (1, -1), (0, 2), (0, -2), (2, 0), (2, 1), (2, -1)])
        a.tip + dir * (a0 + k * along) + perp * (s * across),
      // last resort: beside the shaft, short of the head (a head just under
      // a corner note at the map's edge leaves nothing free past it)
      for (final (k, s) in const [(-1, 1), (-1, -1), (-2, 1), (-2, -1), (-3, 1), (-3, -1), (-4, 1), (-4, -1)])
        a.tip + dir * (a0 + k * along) + perp * (s * across),
      // stacked above or below an earlier label (the Sun and Earth together)
      for (final r in placed) ...[Offset(r.center.dx, r.top - h / 2 - 3), Offset(r.center.dx, r.bottom + h / 2 + 3)],
    ].map((c) => inside(a.size, c)).toList();
    // and just above or below the site, its name or a note band, in line
    // with the first spot (a head off the map's edge, under the corner note,
    // leaves nothing else free)
    final c0 = candidates.first;
    candidates.addAll([
      for (final r in keepClear) ...[Offset(c0.dx, r.top - h / 2 - 3), Offset(c0.dx, r.bottom + h / 2 + 3)],
    ].map((c) => inside(a.size, c)));
    Rect box(Offset c) => Rect.fromCenter(center: c, width: w, height: h);
    bool clearOf(Rect r, Iterable<Rect> others) => !others.any(r.overlaps);
    bool strict(Offset c) {
      final r = box(c);
      return clearOf(r, [...placed, ...heads, ...keepClear]) && !shafts.any(r.inflate(1).contains);
    }

    bool relaxed(Offset c) => clearOf(box(c), [...placed, ...heads]);
    // clear of notes and labels but touching a shaft beats covering a note
    bool clearOfNotes(Offset c) => clearOf(box(c), [...placed, ...heads, ...keepClear]);
    final prev = memory?.centres.elementAtOrNull(out.length);
    Offset at;
    if (prev == null) {
      at = candidates.where(strict).firstOrNull ??
          candidates.where(clearOfNotes).firstOrNull ??
          candidates.where(relaxed).firstOrNull ??
          candidates.where((c) => clearOf(box(c), placed)).firstOrNull ??
          candidates.first;
    } else {
      // near where the label was: it moves on only as far as it must. It
      // never covers its own head or a label; covering the other arrow's
      // head as it sweeps past, a note band or a shaft only weighs against
      // distance, so a turning arrow never flips a label between far-apart
      // spots
      final i = out.length;
      final prevTip = memory!.tips.elementAtOrNull(i);
      // where it was, moved with its head, and short steps round that (to
      // let a head or a label pass without a hop across the map)
      final moved = prevTip == null ? prev : prev + (a.tip - prevTip);
      final options = [
        for (final (dx, dy) in const [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1), (2, 0), (-2, 0), (0, 2), (0, -2)])
          inside(a.size, moved + Offset(dx * 24.0, dy * 20.0)),
        ...candidates,
      ];
      // (a head at or past the map's edge, which a label pinned to that edge
      // cannot get out of the way of, only weighs too)
      final ownHead = heads[i];
      final ownSeen = (Offset.zero & canvas).deflate(1).contains(ownHead.topLeft) &&
          (Offset.zero & canvas).deflate(1).contains(ownHead.bottomRight);
      bool ok(Offset c) => clearOf(box(c), placed) && !(ownSeen && box(c).overlaps(ownHead));
      double cost(Offset c) {
        final r = box(c);
        return (c - prev).distance +
            (clearOf(r, heads) ? 0 : 60) +
            (clearOf(r, keepClear) ? 0 : 24) +
            (shafts.any(r.inflate(1).contains) ? 8 : 0);
      }

      // first the nearest spot clear of the notes, the site and every head;
      // only when there is none does covering one weigh against distance
      bool clear(Offset c) => ok(c) && clearOf(box(c), [...heads, ...keepClear]);
      final near = options.where(clear).toList();
      final free = near.isNotEmpty ? near : options.where(ok).toList();
      at = free.isEmpty
          ? candidates.first
          : near.isNotEmpty
              ? near.reduce((a, b) => (b - moved).distance < (a - moved).distance ? b : a)
              : free.reduce((a, b) => cost(b) < cost(a) ? b : a);
    }
    placed.add(box(at));
    out.add(at);
  }
  memory?.centres = out;
  memory?.tips = [for (final a in arrows) a.tip];
  memory?.sizes = [for (final a in arrows) a.size];
  memory?.kept = keepClear;
  return out;
}

/// The arrow-label spots of the last layout, kept by the map between frames
/// (see [layoutArrowLabels]); a new site, view or map size starts afresh.
class ArrowLabelMemory {
  Object? _key;

  /// The last layout's label centres and arrow heads (for tests).
  List<Offset> centres = const [], tips = const [];

  /// The last layout's label sizes and the areas it kept clear (for tests).
  List<Size> sizes = const [];
  List<Rect> kept = const [];

  /// Forgets the spots when [key] differs from the last one.
  void keyedTo(Object key) {
    if (key != _key) clear();
    _key = key;
  }

  /// Forgets the spots (Play stopped: the still map gets its ideal layout).
  void clear() {
    centres = tips = const [];
    sizes = const [];
    kept = const [];
    _key = null;
  }
}

/// Paints one light frame: the LOLA shaded relief cropped to [view], the
/// computed overlay ([images]; dimmed terrain while there is none), site
/// markers, a scale bar, and the Sun / Earth arrows from [selected] when
/// [now] is given.
///
/// The square [view] is centred in the canvas and cropped to it, so a
/// non-square canvas shows a centre crop of the frame (LightSnapshot).
/// Whether part of [f] lies outside the base map's square (±[mapHalfWidthM]).
bool beyondBaseMap(LightFrame f, double mapHalfWidthM) => viewBeyondBaseMap(frameView(f), mapHalfWidthM);

/// Whether part of the view [v] lies outside the base map's square (±[mapHalfWidthM]).
bool viewBeyondBaseMap(LightView v, double mapHalfWidthM) =>
    v.x0 < -mapHalfWidthM || v.y0 > mapHalfWidthM || v.x0 + v.ext > mapHalfWidthM || v.y0 - v.ext < -mapHalfWidthM;

/// Neutral mid-grey under a close-up's light colours beyond the base map
/// only for the moment its shaded relief ([ReliefKeeper]) is being built, or
/// when map.json has no tint levels: no meaning of its own (a grey near the
/// relief's average, so multiply / screen read the same as on it).
const beyondMapGround = Color(0xFF6E737B);

class LightFramePainter extends CustomPainter {
  final ui.Image hillshade;
  final double halfWidthM;
  final LightImages? images;
  final LightView view;
  final List<Site> sites;
  final Site selected;

  /// Shaded relief of the 400 m terrain grid ([ReliefKeeper]), drawn where it
  /// lies under a close-up that reaches past the base map; the base map's
  /// relief (hillshade.webp) is drawn over it inside ±[halfWidthM].
  final ReliefImage? relief;

  /// nowAt() state of [selected]; null draws no Sun / Earth arrows.
  final Map<String, dynamic>? now;
  final bool closeUp;

  /// Close-up only: names of the other sites (laid out around the arrows).
  final bool siteNames;

  /// Arrow length as a fraction of the canvas' shorter side.
  final double arrowFrac;

  /// The user's Earth rule and DSN setting, so the Earth arrow can say "no
  /// DSN" when only the DSN rule hides it ([lightArrowNote]).
  final EarthCriterion earthRule;
  final bool requireDsn;

  /// The user's text size for the canvas labels (callers clamp it to
  /// [PH.maxCanvasTextScale] so labels never swamp the map).
  final TextScaler textScaler;

  /// "Show exact numbers": arrow-label elevations to 0.1°; otherwise whole
  /// degrees (rubric s2: exact decimals only on request).
  final bool exact;
  LightFramePainter({required this.hillshade, required this.halfWidthM, required this.images, required this.view,
      required this.sites, required this.selected, required this.now, required this.closeUp,
      this.siteNames = true, this.arrowFrac = 0.24, this.earthRule = EarthCriterion.center, this.requireDsn = false,
      this.textScaler = TextScaler.noScaling, this.exact = false, this.noteArea, this.labelMemory, this.relief});

  /// Keeps each arrow label on its spot from frame to frame (Play).
  final ArrowLabelMemory? labelMemory;

  /// Where a note over the map ("Computing shadows…", "Coarser while
  /// playing") sits, as a full-width band; arrow labels are laid out clear of it.
  final Rect? noteArea;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final box = Offset.zero & size;
    final side = math.max(size.width, size.height);
    final dst = Rect.fromLTWH((size.width - side) / 2, (size.height - side) / 2, side, side);
    final k = side / view.ext;
    Offset px(double x, double y) => Offset(dst.left + (x - view.x0) * k, dst.top + (view.y0 - y) * k);
    Offset ll(double lat, double lon) {
      final (x, y) = latLonToXY(lat, lon);
      return px(x, y);
    }

    canvas.save();
    canvas.clipRect(box);
    final im = images;
    final fr = im?.frame;
    final frameDst = fr == null
        ? null
        : Rect.fromLTWH(dst.left + (fr.x0M - view.x0) * k, dst.top + (view.y0 - fr.y0M) * k, fr.extentM * k, fr.extentM * k);
    // a close-up reaches past the base map's edge (about 80°S) where the
    // terrain grid goes on to about 75°S: the relief shaded on the device
    // from that grid with the base map's recipe (named in the FidelityBadge),
    // over a neutral grey for the moment it is being built
    if (closeUp && viewBeyondBaseMap(view, halfWidthM)) {
      if (frameDst != null && fr!.request.closeUp) canvas.drawRect(frameDst, Paint()..color = beyondMapGround);
      final rl = relief;
      if (rl != null) {
        canvas.drawImageRect(
            rl.image,
            Rect.fromLTWH(0, 0, rl.image.width.toDouble(), rl.image.height.toDouble()),
            Rect.fromPoints(px(rl.x0M, rl.y0M), px(rl.x0M + rl.widthM, rl.y0M - rl.heightM)),
            Paint()..filterQuality = FilterQuality.medium);
      }
    }
    // NASA LOLA shaded relief (artificial light), cropped to the view
    // only the part of the view the map covers (the whole region has a margin)
    final hk = hillshade.width / (2 * halfWidthM);
    final vx0 = math.max(view.x0, -halfWidthM), vy0 = math.min(view.y0, halfWidthM);
    final vx1 = math.min(view.x0 + view.ext, halfWidthM), vy1 = math.max(view.y0 - view.ext, -halfWidthM);
    canvas.drawImageRect(
        hillshade,
        Rect.fromLTRB((vx0 + halfWidthM) * hk, (halfWidthM - vy0) * hk, (vx1 + halfWidthM) * hk, (halfWidthM - vy1) * hk),
        Rect.fromLTRB(dst.left + (vx0 - view.x0) * k, dst.top + (view.y0 - vy0) * k, dst.left + (vx1 - view.x0) * k,
            dst.top + (view.y0 - vy1) * k),
        Paint()..filterQuality = FilterQuality.medium);
    if (im != null) {
      final src = Rect.fromLTWH(0, 0, im.w.toDouble(), im.w.toDouble());
      // the frame's own square inside the view (the whole view for a close-up): frameDst
      canvas.drawImageRect(im.mul, src, frameDst!, Paint()
        ..blendMode = BlendMode.multiply
        ..filterQuality = FilterQuality.low);
      canvas.drawImageRect(im.scr, src, frameDst, Paint()
        ..blendMode = BlendMode.screen
        ..filterQuality = FilterQuality.low);
    } else {
      canvas.drawRect(box, Paint()..color = const Color(0x99060B16));
    }

    TextPainter label(String s, {Color color = PH.text, double fs = 12, bool bold = false}) => TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        text: TextSpan(
            text: s,
            style: TextStyle(fontFamily: PH.sans, color: color, fontSize: fs, fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                shadows: const [Shadow(blurRadius: 3, color: Colors.black), Shadow(blurRadius: 6, color: Colors.black)])))
      ..layout();
    Rect boxAt(TextPainter t, Offset centre) => Rect.fromCenter(center: centre, width: t.width + 4, height: t.height);
    void text(String s, Offset at, {Color color = PH.text, double fs = 12, bool bold = false}) {
      final t = label(s, color: color, fs: fs, bold: bold);
      t.paint(canvas, at - Offset(t.width / 2, t.height / 2));
    }

    // the "pole" badge's box: labels and site names keep clear of it
    Rect? poleBadge;
    if (!closeUp) {
      // graticule (2 deg rings, 30 deg meridians)
      final grid = Paint()
        ..color = const Color(0x40FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      final c = px(0, 0);
      for (var lat = -88.0; lat >= -80.0; lat -= 2) {
        canvas.drawCircle(c, (ll(lat, 0) - c).distance, grid);
      }
      for (var lon = 0.0; lon < 360; lon += 30) {
        canvas.drawLine(c, ll(-80, lon), grid);
      }
      for (final (lon, s) in [(0.0, '0°'), (90.0, '90°E'), (180.0, '180°'), (-90.0, '90°W')]) {
        text(s, ll(-81.0, lon), fs: 12);
      }
    } else {
      // which way is the pole (the view is rotated with the map, 0E up)
      final (sx, sy) = latLonToXY(selected.lat, selected.lon);
      final dist = math.sqrt(sx * sx + sy * sy);
      if (dist > 2000) {
        // half size on small canvases (a phone in landscape), so it leaves room for the labels
        final s = size.shortestSide < 240 ? 0.6 : 1.0;
        final dir = Offset(-sx / dist, sy / dist);
        final at = Offset(w - 34 * s, 34 * s);
        final pen = Paint()
          ..color = PH.text
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(at, 22 * s, Paint()..color = const Color(0xAA060B16));
        canvas.drawLine(at - dir * 12 * s, at + dir * 12 * s, pen);
        final head = at + dir * 12 * s, side = Offset(-dir.dy, dir.dx);
        canvas.drawPath(Path()..addPolygon([head, head - dir * 6 + side * 4, head - dir * 6 - side * 4], true),
            Paint()..color = PH.text);
        text('pole', at + Offset(0, 30 * s), fs: s == 1 ? 10.5 : 9.5);
        final word = label('pole', fs: s == 1 ? 10.5 : 9.5);
        poleBadge = Rect.fromLTRB(at.dx - 24 * s, at.dy - 24 * s, at.dx + 24 * s, at.dy + 30 * s + word.height / 2)
            .expandToInclude(boxAt(word, at + Offset(0, 30 * s)));
        word.dispose();
      }
    }

    // scale bar (about a fifth of the visible width), on a dark under-stroke
    // so it reads on bright sunlit terrain too
    final targetM = w / k * 0.22;
    final nice = [1, 2, 5, 10, 20, 25, 50, 100, 200].map((v) => v * 1000.0).lastWhere((v) => v <= targetM, orElse: () => 1000);
    final barPx = nice * k;
    final y0 = size.height - 18.0;
    for (final bar in [
      Paint()
        ..color = const Color(0xB3000000)
        ..strokeWidth = 4.5,
      Paint()
        ..color = PH.text
        ..strokeWidth = 2,
    ]) {
      canvas.drawLine(Offset(14, y0), Offset(14 + barPx, y0), bar);
      canvas.drawLine(Offset(14, y0 - 4), Offset(14, y0 + 4), bar);
      canvas.drawLine(Offset(14 + barPx, y0 - 4), Offset(14 + barPx, y0 + 4), bar);
    }
    text('${(nice / 1000).round()} km', Offset(14 + barPx / 2, y0 - 10), fs: 12);
    // the bar and its words: the arrow labels keep clear of them (Android 7
    // run: "Sun 4° above the hills" printed over "25 km" while playing)
    final scaleWords = label('${(nice / 1000).round()} km', fs: 12);
    final scaleArea = Rect.fromLTRB(14 - 6.0, y0 - 6, 14 + barPx + 6, y0 + 6)
        .expandToInclude(boxAt(scaleWords, Offset(14 + barPx / 2, y0 - 10)));
    scaleWords.dispose();

    // Sun and Earth direction arrows from the selected site (map bearing of
    // the true azimuth: az is measured from local north = away from the pole).
    // Their labels and the site name are laid out first so other site names
    // can step aside instead of overlapping them.
    final p = ll(selected.lat, selected.lon);
    final len = size.shortestSide * arrowFrac;
    final state = now;
    final arrows = [
      if (state != null)
        for (final (key, color, name) in [('earth', PH.earth, 'Earth'), ('sun', PH.sun, 'Sun')])
          () {
            final b = state[key] as Map<String, dynamic>;
            final (dx, dy) = mapDirection(selected.lon, (b['az'] as num).toDouble());
            final dir = Offset(dx, -dy);
            final visible = b['visible'] == true;
            final t = label(
                arrowLabelText(name, b, earthRule: key == 'earth' ? earthRule : null, requireDsn: requireDsn, exact: exact),
                color: color,
                fs: 13,
                bold: true);
            return (color: color, name: name, dir: dir, visible: visible, tip: p + dir * len, label: t);
          }(),
    ];
    final siteLabel = label(selected.short, bold: true, fs: 13);
    final siteAt = p + const Offset(0, 22);
    // arrow labels sit just past their heads, inside the canvas and clear of
    // both arrows, both heads, the site and the other label, so they never
    // overprint when the Sun and Earth point almost the same way
    labelMemory?.keyedTo((selected.id, closeUp, size, view.ext));
    final ats = layoutArrowLabels(
      memory: labelMemory,
      arrows: [for (final a in arrows) (from: p + a.dir * 12, tip: a.tip, size: Size(a.label.width + 4, a.label.height))],
      canvas: size,
      keepClear: [
        Rect.fromCircle(center: p, radius: 14),
        boxAt(siteLabel, siteAt),
        ?poleBadge,
        ?noteArea,
        scaleArea,
      ],
    );
    final placed = <Rect>[
      Rect.fromCircle(center: p, radius: 14), // the selected marker and its ring
      boxAt(siteLabel, siteAt),
      ?poleBadge,
      for (var i = 0; i < arrows.length; i++) boxAt(arrows[i].label, ats[i]),
    ];

    // every marker on the canvas is kept clear of the neighbours' names
    for (final st in sites) {
      final q = ll(st.lat, st.lon);
      if (st.id != selected.id && box.inflate(10).contains(q)) placed.add(Rect.fromCircle(center: q, radius: 6));
    }
    // site markers (shape = group, as on the main map)
    for (final st in [...sites.where((x) => x.id != selected.id), selected]) {
      final q = ll(st.lat, st.lon);
      if (!box.inflate(10).contains(q)) continue;
      final sel = st.id == selected.id;
      final r = sel ? 6.5 : 4.5;
      final path = siteMarkerPath(st, q, r);
      canvas.drawPath(path, Paint()..color = siteMarkerColor(st));
      canvas.drawPath(path, Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
      if (sel) {
        canvas.drawCircle(q, r + 5, Paint()
          ..color = PH.ice
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      } else if (closeUp && siteNames) {
        // name above the marker, else below; skipped if both would collide.
        // A dark backing keeps it readable on bright sunlit terrain.
        final t = label(st.short, fs: 12);
        final own = Rect.fromCircle(center: q, radius: 6);
        for (final raw in [q + Offset(0, -(r + 9)), q + Offset(0, r + 9)]) {
          // slid sideways to stay inside the frame (never cut at its edge)
          final at = Offset(clampLabelX(raw.dx, t.width + 3, size.width), raw.dy);
          final b = boxAt(t, at);
          if (b.top < 0 || b.bottom > size.height || b.left < 0 || b.right > size.width) continue;
          if (placed.any((o) => o != own && b.overlaps(o))) continue;
          placed.add(b);
          canvas.drawRRect(RRect.fromRectAndRadius(b.inflate(1.5), const Radius.circular(4)),
              Paint()..color = const Color(0xD9060B16));
          t.paint(canvas, at - Offset(t.width / 2, t.height / 2));
          break;
        }
      }
    }

    final under = Paint()
      ..color = const Color(0xCC000000)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final (i, a) in arrows.indexed) {
      final pen = Paint()
        ..color = a.color
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final start = p + a.dir * 12;
      if (a.name == 'Earth') {
        // dashed for Earth, solid for the Sun (line style, not only colour)
        final total = (a.tip - start).distance;
        for (var t = 0.0; t < total; t += 10) {
          final s0 = start + a.dir * t, s1 = start + a.dir * math.min(t + 6, total);
          canvas.drawLine(s0, s1, under);
          canvas.drawLine(s0, s1, pen);
        }
      } else {
        canvas.drawLine(start, a.tip, under);
        canvas.drawLine(start, a.tip, pen);
      }
      // head: Sun = filled disc, Earth = ring; hollow centre when not counted
      canvas.drawCircle(a.tip, 8, Paint()..color = Colors.black);
      if (a.name == 'Sun') {
        canvas.drawCircle(a.tip, 6.5, Paint()..color = a.color);
        if (!a.visible) canvas.drawCircle(a.tip, 3, Paint()..color = Colors.black);
      } else {
        canvas.drawCircle(a.tip, 6, Paint()
          ..color = a.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6);
        if (a.visible) canvas.drawCircle(a.tip, 2.4, Paint()..color = a.color);
      }
      a.label.paint(canvas, ats[i] - Offset(a.label.width / 2, a.label.height / 2));
    }
    siteLabel.paint(canvas, siteAt - Offset(siteLabel.width / 2, siteLabel.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LightFramePainter old) =>
      old.images != images ||
      old.relief != relief ||
      old.noteArea != noteArea ||
      old.labelMemory != labelMemory ||
      old.view != view ||
      old.selected != selected ||
      old.now != now ||
      old.sites != sites ||
      old.closeUp != closeUp ||
      old.siteNames != siteNames ||
      old.arrowFrac != arrowFrac ||
      old.earthRule != earthRule ||
      old.requireDsn != requireDsn ||
      old.exact != exact ||
      old.textScaler != textScaler;
}

/// The Light tab's three views (docs/landers_view_spec.md §7.1).
enum LightViewKind { closeUp, region, lander }

/// The request for [s]'s site and moment ([tMs], default the cursor) at
/// [extent]: the map, its prefetch and the lander's view all use it, so they
/// share keys and cache entries (D2). [coarse] defaults to "playing".
LightRequest lightRequestFor(AppState s, {required LightExtent extent, double? tMs, bool? coarse}) {
  final t = tMs ?? s.cursorMs, eph = s.eph!;
  return LightRequest(
      closeUp: extent == LightExtent.closeUp,
      far: extent == LightExtent.far,
      lat: s.site.lat,
      lon: s.site.lon,
      sun: eph.sun(t),
      earth: eph.earth(t),
      tMs: t,
      observerHeightM: s.observerHeightM,
      coarse: coarse ?? s.playing);
}

/// The lander's view FidelityBadge text (§6): the main text, then (g) the
/// eye's offset from a preset's 80 m height when over 5 m ([eyeOffsetM] =
/// the 400 m surface minus the site's height), (h) where the terrain data
/// ends, and the eclipse note.
String landerFidelityText(String heightText,
    {required bool custom,
    double? eyeOffsetM,
    List<({double az0, double az1, double distM})> demEnds = const [],
    bool eclipse = false}) {
  final ends = [...demEnds]..sort((a, b) => a.az0.compareTo(b.az0));
  String deg(double a) => '${(((a % 360) + 360) % 360).round()}';
  return 'Approximate: the light map\'s own 400 m LOLA terrain and light; Sun and Earth at true size and place. '
      'Terrain is the grid the light map uses (400 m within 64 km, 800 m out to 300 km), block-averaged the same way, '
      'so rims and peaks are smoothed and the drawn skyline can differ from '
      '${custom ? '80 m horizons by 0.5–1.4° (up to about 6° on sharp rims); it matches this spot\'s 400 m horizon '
          '(dashed) within about 0.4°' : 'this site\'s 80 m horizon mask (dashed) by about 1° and up to 5°'}. '
      'Ground within 800 m is not resolved by the 400 m grid: where it would rise above the distant skyline it is '
      'drawn see-through, because the light map and the horizon masks ignore it. Light and shadow are the Light '
      'tab\'s computed frame for this moment, pixel for pixel; Earth\'s direction there is taken from the Moon\'s '
      'centre, up to 0.3° higher than seen from the ground. Shadowed ground is drawn dark: Earthshine is not '
      'computed, and the ground colour is a flat grey, not a photo. The Sun and Earth are drawn in their meaning '
      'colours at true size and position (DE440, apparent, no refraction); glyphs, labels, the 0° line, the '
      'compass and the stripe and dot patterns are visual aids.'
      '${eyeOffsetM != null && eyeOffsetM.abs() > 5 ? ' The eye is $heightText above the 400 m surface, '
          '${eyeOffsetM.abs().round()} m ${eyeOffsetM < 0 ? 'below' : 'above'} this site\'s 80 m height.' : ''}'
      '${ends.isEmpty ? '' : ' Terrain data ends ${(ends.map((e) => e.distM).reduce(math.min) / 1000).round()} km away '
          'toward azimuth ${ends.map((e) => '${deg(e.az0)}–${deg(e.az1)}°').join(', ')} (edge of the LOLA map).'}'
      '${eclipse ? ' $lightEclipseFidelity' : ''}';
}
