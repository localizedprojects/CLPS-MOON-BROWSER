/// Flutter side of the chart bridge (keep in sync with charts/src/bridge.ts).
///
/// [ChartController] buffers the latest message of each type until the
/// embedded React page reports `ready`, then forwards everything. The
/// payload builders turn Dart-core results into chart-ready JSON (the React
/// side never computes science).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../core/catalog.dart';
import '../core/decimate.dart';
import '../core/ephemeris.dart';
import '../core/geo.dart';
import '../core/horizon.dart';
import '../core/metrics.dart';
import '../core/timeseries.dart';
import '../core/visibility.dart';
import '../core/constants.dart';
import '../core/summary.dart' show Ranked;
import '../core/wording.dart' show bodyStateShort, earthMetricLabel, earthStatusText, sunStatusText;

typedef ChartEventHandler = void Function(Map<String, dynamic> event);

class ChartController {
  final String view;
  ChartEventHandler? onEvent;
  void Function(String json)? _sink;
  Object? _owner;
  final ValueNotifier<bool> _ready = ValueNotifier(false);

  /// Latest message per type, in the order of their last update (a replay
  /// then delivers them in the order they were sent: a cursor sent before a
  /// new payload is replayed before it, so the page knows it is older).
  final Map<String, String> _pending = {};

  /// Commands that act once (a file export; on the web `focusFirst`, which
  /// chart_host_web.dart posts itself when Tab reaches the frame): never
  /// buffered, never replayed to a page that is created later. `detail` is
  /// not one: it is replayed, as are `simple` (Sky & time's "Simple view"
  /// switch, [ChartHub.setSimpleView]) and `focus` (the chart is shown full
  /// screen; no longer sent: the full-screen view is a snapshot). The page's `focusExit` event (Tab past its last
  /// control) is handled by the web host and never reaches [handleRaw].
  static const _oneShot = {'exportPng', 'focusFirst'};

  ChartController(this.view, {this.onEvent});

  bool get ready => _ready.value;

  /// Notifies when the page becomes ready or goes away (export menus listen).
  ValueListenable<bool> get readyListenable => _ready;

  /// Called by the platform host [owner] once it can deliver messages to its
  /// page. A newer host replaces the current one; its page must report
  /// `ready` before anything is delivered (the buffered messages then are).
  void attach(void Function(String json) sink, Object owner) {
    _sink = sink;
    _owner = owner;
    _ready.value = false;
  }

  /// Called by [owner] when it goes away. Ignored if another host has
  /// attached since: when a chart is rebuilt elsewhere in the tree, Flutter
  /// creates the new host before it disposes the old one.
  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _sink = null;
    _owner = null;
    _ready.value = false;
  }

  /// Raw JSON event from the page.
  void handleRaw(String raw) {
    final ev = jsonDecode(raw) as Map<String, dynamic>;
    if (ev['type'] == 'detail') {
      // a tap inside the chart: replay that mode after a reload of this page
      // only (the app's expert mode is not changed)
      _pending.remove('detail');
      _pending['detail'] = jsonEncode({'type': 'detail', 'exact': ev['exact'] == true});
    }
    if (ev['type'] == 'ready') {
      final firstReady = !_ready.value;
      _ready.value = true;
      if (ev['view'] != view) {
        _deliver(jsonEncode({'type': 'setView', 'view': view}));
      } else if (firstReady || _pending.isNotEmpty) {
        for (final m in _pending.values) {
          _deliver(m);
        }
      }
    }
    onEvent?.call(ev);
  }

  /// Send a message (buffered until ready; only the latest per type is kept).
  /// One-shot commands reach a ready page only and are not buffered.
  void send(Map<String, dynamic> msg) {
    final json = jsonEncode(msg);
    final type = msg['type'] as String;
    if (_oneShot.contains(type)) {
      if (_ready.value) _deliver(json);
      return;
    }
    _pending.remove(type); // re-insert: replay order = order of the last sends
    _pending[type] = json;
    if (_ready.value) _deliver(json);
  }

  void _deliver(String json) => _sink?.call(json);
}

final _fmt = DateFormat('yyyy-MM-dd HH:mm');
String utcLabel(double ms) => '${_fmt.format(DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true))} UTC';

/// One body's state for the charts. Besides the geometry it carries what the
/// charts show as text, all from Dart (charts spec 4.1): `clear` (el - hz at
/// the disk centre, deg), `state` ([bodyStateShort]) and `say` (the full
/// sentence of [sunStatusText] / [earthStatusText]). [terrainVisible] is the
/// Earth verdict from the terrain alone (null for the Sun).
Map<String, dynamic> bodyNow(AzEl a, double rho, double frac, double hz, bool visible, {bool? terrainVisible, String? say}) => {
      'az': a.az,
      'el': a.el,
      'rho': rho,
      'frac': frac,
      'hz': hz,
      'visible': visible,
      'terrainVisible': ?terrainVisible,
      'clear': a.el - hz,
      'state': bodyStateShort(visible: visible, elDeg: a.el, rhoDeg: rho, frac: frac, terrainVisible: terrainVisible),
      'say': ?say,
    };

/// Exact Sun/Earth state at [tMs] for the sky plot markers (and the light
/// map's arrows and status line).
Map<String, dynamic> nowAt(Ephemeris eph, Observer obs, HorizonMask mask, double tMs, SeriesOptions o) {
  final s = obs.look(eph.sun(tMs)), e = obs.look(eph.earth(tMs));
  final rs = angularRadiusDeg(sunRadiusKm, s.range), re = angularRadiusDeg(earthRadiusKm, e.range);
  final fs = visibleFraction(s.az, s.el, rs, mask), fe = visibleFraction(e.az, e.el, re, mask);
  final hs = mask.at(s.az), he = mask.at(e.az);
  // Earth under the user's Earth rule from the terrain alone, then the DSN
  // check: 'terrainVisible' lets labels say "no DSN" instead of "hidden"
  final terrainEv = earthVisible(o.earthCriterion, fe, e.el, he);
  final dsnIn = eph.dsnMask(tMs) != 0;
  final ev = terrainEv && !(o.requireDsn && !dsnIn);
  final sv = sunVisible(o.sunCriterion, fs, s.el, hs);
  return {
    'sun': bodyNow(s, rs, fs, hs, sv,
        say: sunStatusText(visible: sv, elDeg: s.el, rhoDeg: rs, frac: fs, sunRule: o.sunCriterion)),
    'earth': bodyNow(e, re, fe, he, ev,
        terrainVisible: terrainEv,
        say: earthStatusText(
            visible: ev,
            elDeg: e.el,
            rhoDeg: re,
            frac: fe,
            dsnRequired: o.requireDsn,
            dsnInView: dsnIn,
            earthRule: o.earthCriterion,
            hzDeg: he)),
  };
}

/// At most this many points per chart curve (min/max decimation keeps up to
/// two per bucket) and per sky-plot trail.
const timelineCurveMaxPoints = 3000;
const skyTrailMaxPoints = 1500;

/// Chart precision: 0.001° for plotted elevations (the charts print 2
/// decimals) and whole ms for times. Display rounding only.
double _deg3(double v) => v.isFinite ? (v * 1000).round() / 1000 : v;

/// Indices of [y] kept by min/max decimation to at most [maxPoints] points:
/// every bucket keeps its lowest and highest sample, so short dips and peaks
/// (the Sun grazing the skyline) survive (formula.md §9.5).
List<int> minMaxIndices(List<double> y, int maxPoints) {
  final idx = [for (var i = 0; i < y.length; i++) i.toDouble()];
  return [for (final i in minMaxDecimate(idx, y, maxPoints ~/ 2).t) i.toInt()];
}

/// One chart curve: its own min/max-decimated time axis (Unix ms) and values.
Map<String, dynamic> curvePayload(SiteSeries s, List<double> y, {int maxPoints = timelineCurveMaxPoints}) {
  final keep = minMaxIndices(y, maxPoints);
  return {
    't': [for (final i in keep) s.timeAt(i).round()],
    'y': [for (final i in keep) _deg3(y[i])],
  };
}

/// A sky-plot path: az/el pairs at the samples min/max decimation keeps for
/// the elevation.
Map<String, dynamic> _trail(List<double> az, List<double> el) {
  final keep = minMaxIndices(el, skyTrailMaxPoints);
  return {
    'az': [for (final i in keep) _deg3(az[i])],
    'el': [for (final i in keep) _deg3(el[i])],
  };
}

Map<String, dynamic> skyPayload(Site site, HorizonMask mask, SiteSeries s, Map<String, dynamic> now, double tMs, bool zoom) => {
      'type': 'sky',
      'data': {
        'siteName': site.short,
        'timeLabel': utcLabel(tMs),
        // the period start: the header adds the year outside its 12 months
        'refMs': s.t0Ms,
        'maskStepDeg': mask.azStepDeg,
        'mask': [for (final v in mask.elevDeg) double.parse(v.toStringAsFixed(2))],
        'maskApprox': mask.approximate,
        'now': now,
        'trails': {'sun': _trail(s.sunAz, s.sunEl), 'earth': _trail(s.earthAz, s.earthEl)},
        'zoom': zoom,
      },
    };

Map<String, dynamic> skyNowPayload(Map<String, dynamic> now, double tMs) => {'type': 'skyNow', 'now': now, 'timeLabel': utcLabel(tMs)};

List<List<double>> _runs(SiteSeries s, int flag) => [for (final r in runs(s, flag)) [r.startMs, r.endMs]];

/// The `minHours` of [nextStretch] ("Next good stretch"): the timeline's
/// "next 1 day or more" hint uses the same value (charts spec 4.2).
const goodStretchMinHours = 24.0;

/// [metrics] are the series' [SiteMetrics] (computed here when not given):
/// the timeline's `pct` and `longestDark` are the numbers Overview and
/// Compare show (charts spec 4.2).
Map<String, dynamic> timelinePayload(Site site, SiteSeries s, double cursorMs, {required bool requireDsn, SiteMetrics? metrics}) {
  final m = metrics ?? computeMetrics(s);
  final dark = m.longestDark;
  // Each curve is min/max-decimated on its own time axis (<= 3000 points), so
  // short dips and peaks are never dropped; the availability runs are sent at
  // full resolution.
  return {
    'type': 'timeline',
    'data': {
      'siteName': site.short,
      'curves': {
        'sunEl': curvePayload(s, s.sunEl),
        'earthEl': curvePayload(s, s.earthEl),
        'sunHz': curvePayload(s, s.sunHz),
        'earthHz': curvePayload(s, s.earthHz),
      },
      'runs': {'sun': _runs(s, flagSun), 'earth': _runs(s, flagEarth), 'both': _runs(s, flagBoth)},
      'range': [s.t0Ms, s.timeAt(s.n)],
      'cursor': cursorMs,
      // with the DSN required the Earth flags mean Earth contact, not line of sight
      'earthLabel': earthMetricLabel(requireDsn: requireDsn),
      'pct': {'sun': m.pctSunlit, 'earth': m.pctEarth, 'both': m.pctBoth},
      'longestDark': dark == null ? null : [dark.startMs, dark.endMs],
      'stepMin': s.stepMs / 60000,
      'goodMinH': goodStretchMinHours,
    },
  };
}

/// True when [dark] (a site's longest dark spell) starts at the period start
/// or ends at the period end, so its real length may be longer (the charts
/// add a `+`).
bool longestDarkAtEdge(Interval? dark) => dark != null && (dark.truncatedStart || dark.truncatedEnd);

/// The compare payload [p] (from `comparePayload`, built from [ranked] in the
/// same order) with `longestDarkAtEdge` on every row (charts spec 4.3).
Map<String, dynamic> withCompareExtras(Map<String, dynamic> p, List<Ranked> ranked) {
  final rows = ((p['data'] as Map)['rows'] as List).cast<Map<String, dynamic>>();
  final byId = {for (final r in ranked) r.id: r};
  for (final row in rows) {
    row['longestDarkAtEdge'] = longestDarkAtEdge(byId[row['id']]?.metrics.longestDark);
  }
  return p;
}
