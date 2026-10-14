/// One controller per React chart, shared by every screen (provided above the
/// shell with `Provider<ChartHub>`), plus everything that talks to them:
/// pushing [AppState] to the charts, chart events and the file exports.
///
/// Each chart is shown in exactly one place (sky + timeline in Site › Sky &
/// time, compare in Compare), so a controller never has two hosts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../core/export_csv.dart';
import '../core/metrics.dart';
import '../core/score.dart';
import '../core/summary.dart' show date;
import '../core/catalog.dart' show Site;
import '../core/geo.dart' show Observer;
import '../core/horizon.dart' show HorizonMask;
import '../core/timeseries.dart' show SeriesOptions, SiteSeries;
import '../widgets/chart_bridge.dart';
import '../widgets/compare_panel.dart' show comparePayload, rankedFor;
import '../widgets/save_file.dart';
import 'app_state.dart';

class ChartHub {
  /// [onEvent] receives every chart event after the hub has handled it (seek
  /// moves the cursor, png saves the file); the app shows 'error' events
  /// ("Chart: …") and the hub's own 'notice' events in a snackbar.
  ///
  /// Cursor and "now" messages go out at most once per [cursorInterval]
  /// (the first at once, the newest at the end of the interval), so
  /// scrubbing and Play never queue more messages than a chart can draw.
  ///
  /// [save] saves or shares generated files (tests pass a recorder).
  ChartHub({
    required this.onEvent,
    this.cursorInterval = const Duration(milliseconds: 60),
    Future<void> Function(List<SaveFile> files) save = saveFiles,
  })  : _saveFiles = save,
        sky = ChartController('sky'),
        timeline = ChartController('timeline'),
        compare = ChartController('compare') {
    sky.onEvent = (ev) => _handle(sky, ev);
    timeline.onEvent = (ev) => _handle(timeline, ev);
    compare.onEvent = (ev) => _handle(compare, ev);
  }

  final void Function(Map<String, dynamic>) onEvent;
  final ChartController sky, timeline, compare;
  final Duration cursorInterval;
  final Future<void> Function(List<SaveFile> files) _saveFiles;

  /// The state last pushed by [sync] (chart seeks move its cursor).
  AppState? _state;

  // What each chart was last sent (each chart has its own inputs, so a
  // sky-only option or a site change does not re-send unrelated payloads).
  _Shown? _shown;
  SiteSeries? _skySeries, _timelineSeries;
  bool? _skyZoom;
  String _compareKey = '';
  List<SiteMetrics?> _compareMetrics = const [];
  double _sentCursor = double.nan;
  Timer? _cursorTimer;
  bool? _sentExpert;

  /// Sky & time's "Simple view" switch: off by default (the classic sky plot
  /// and timeline); on, the charts show their simple views ("Where to look",
  /// "When"). Sent to both as `{type:'simple', on}` (kept for replay), only
  /// when it changes. The comparison chart does not take it.
  final ValueNotifier<bool> simpleView = ValueNotifier(false);

  /// The full-screen picture was closed: the charts behind it were hidden,
  /// and turned with the device for a wide one, so each ready chart redraws
  /// at its size once it shows again (`{type:'focus', on:false}` makes the
  /// page settle its layout 150, 500 and 1000 ms later).
  void settleCharts() {
    for (final c in [sky, timeline, compare]) {
      if (c.ready) c.send({'type': 'focus', 'on': false});
    }
  }

  /// Pictures asked for by [snapshot], by export id.
  final Map<String, Completer<Uint8List?>> _snaps = {};
  final Map<String, String> _snapView = {};
  int _snapSeq = 0;

  /// A PNG of [c]'s chart at [width] x [height] logical px, rendered at
  /// [scale] device pixels per px: the full-screen picture (chart_focus.dart).
  /// Null when the chart is not ready, fails, or does not answer in 8 s.
  Future<Uint8List?> snapshot(ChartController c, int width, int height, {double scale = 1}) {
    if (!c.ready) return Future.value(null);
    final id = 'focus-${++_snapSeq}';
    final done = Completer<Uint8List?>();
    _snaps[id] = done;
    _snapView[id] = c.view;
    c.send({'type': 'exportPng', 'id': id, 'width': width, 'height': height, 'scale': scale});
    return done.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _snaps.remove(id);
      _snapView.remove(id);
      return null;
    });
  }

  /// Turn the "Simple view" switch [on] or off.
  void setSimpleView(bool on) {
    if (simpleView.value == on) return;
    simpleView.value = on;
    final msg = {'type': 'simple', 'on': on};
    sky.send(msg);
    timeline.send(msg);
  }

  /// How many full payloads have been sent per chart (tests check that
  /// unrelated changes do not re-send them).
  final Map<String, int> sentPayloads = {'sky': 0, 'timeline': 0, 'compare': 0};

  /// Push the latest state to the charts. Cheap enough to call on every
  /// AppState notification: full payloads only when their inputs changed,
  /// cursor/now updates coalesced to [cursorInterval], and nothing is ever
  /// computed here (the comparison waits for the ranking's cached metrics).
  ///
  /// The sky plot and timeline follow [AppState.series]: while a new series
  /// is being worked out (another site, height or rule) they keep showing the
  /// previous one, labelled and positioned with the choices it was computed
  /// for, and switch when the new series arrives.
  ///
  /// Building and encoding those two payloads takes tens of ms (logic-6,
  /// async-4), so while the charts are hidden (Explore, Compare, Learn,
  /// Light & shadow) they wait: they go out when the charts show, or right
  /// before a PNG export.
  void sync(AppState s) {
    _state = s;
    _syncDetail(s);
    if (s.series == null || s.eph == null) return;
    if (chartsVisible(s)) _syncSeriesCharts(s);
    _syncCompare(s);
  }

  /// The app's expert mode is the charts' "Exact numbers" mode: sent to all
  /// three when it changes (`{type:'detail', exact}`, kept for replay). A
  /// chart's own toggle changes only that chart's replay copy
  /// ([ChartController.handleRaw]), never [AppState.expert].
  void _syncDetail(AppState s) {
    if (s.expert == _sentExpert) return;
    _sentExpert = s.expert;
    final msg = {'type': 'detail', 'exact': s.expert};
    for (final c in [sky, timeline, compare]) {
      c.send(msg);
    }
  }

  /// The sky plot and timeline payloads, if their inputs changed, then the cursor.
  void _syncSeriesCharts(AppState s) {
    final series = s.series;
    if (series == null || s.eph == null) return;
    // The site, horizon and rules of the series on screen, taken when it
    // appears. They are read from the selection, so only when the selection is
    // what [series] was computed for: while [AppState.loading] the selection is
    // already the new choice and [series] the last committed one (another site
    // or height). A series that changed while the charts were hidden (or that
    // they have never shown) then waits for the result, and the charts keep
    // the series they show, under its own name (state-1).
    if (!identical(series, _shown?.series)) {
      if (!s.loading && s.committedSiteId == s.selectedId) {
        _shown = _Shown(series, s.site, s.mask, s.observer, s.resultOptions, s.metrics);
      } else if (_shown == null) {
        return;
      }
    }
    final shown = _shown!, cur = shown.series; // [series], or the previous one while it waits

    if (!identical(cur, _skySeries) || s.skyZoom != _skyZoom) {
      _skySeries = cur;
      _skyZoom = s.skyZoom;
      sky.send(skyPayload(shown.site, shown.mask, cur, _now(s, shown), s.cursorMs, s.skyZoom));
      sentPayloads['sky'] = sentPayloads['sky']! + 1;
      // a fresh skyNow follows every new sky payload, even at the same
      // cursor: the page's (and the replay buffer's) newest skyNow must never
      // be the previous site's (charts spec 4.6)
      _sentCursor = double.nan;
    }
    if (!identical(cur, _timelineSeries)) {
      _timelineSeries = cur;
      timeline.send(timelinePayload(shown.site, cur, s.cursorMs,
          requireDsn: shown.options.requireDsn, metrics: shown.metrics));
      sentPayloads['timeline'] = sentPayloads['timeline']! + 1;
    }
    if (s.cursorMs != _sentCursor && _cursorTimer == null) _flushCursor();
  }

  /// The sky plot and timeline are on screen only in Site, outside Light &
  /// shadow (from 1100 px the Overview tab shows them beside it). Hidden
  /// charts get no cursor messages (new-android-2: Light playback kept the
  /// off-screen WebViews busy); the newest cursor goes out when they show.
  static bool chartsVisible(AppState s) => s.dest == Dest.site && s.siteTab != SiteTab.light;

  Map<String, dynamic> _now(AppState s, _Shown v) => nowAt(s.eph!, v.observer, v.mask, s.cursorMs, v.options);

  /// Send the newest cursor now, then at most once per [cursorInterval].
  void _flushCursor() {
    final s = _state, shown = _shown;
    if (s == null || shown == null || s.eph == null || s.cursorMs == _sentCursor || !chartsVisible(s)) return;
    _sentCursor = s.cursorMs;
    sky.send(skyNowPayload(_now(s, shown), s.cursorMs));
    timeline.send({'type': 'cursor', 't': s.cursorMs});
    _cursorTimer = Timer(cursorInterval, () {
      _cursorTimer = null;
      _flushCursor(); // the newest cursor, if it moved meanwhile
    });
  }

  /// The comparison chart: sent once every shortlisted site has cached
  /// metrics, and again only when those metrics, the shortlist, the weights
  /// or the Earth rule change.
  void _syncCompare(AppState s) {
    if (s.compareIds.length < 2) return; // fewer than two sites is not a comparison
    final ms = [for (final id in s.compareIds) s.metricsFor(id)];
    if (ms.any((m) => m == null)) return; // the ranking has not reached them yet
    final key = '${s.compareIds.join(',')}|${s.weights.power}|${s.weights.both}|${s.options.requireDsn}|'
        '${[for (final id in s.compareIds) s.allSites.where((x) => x.id == id).firstOrNull?.short].join(',')}';
    var same = key == _compareKey && ms.length == _compareMetrics.length;
    for (var i = 0; same && i < ms.length; i++) {
      same = identical(ms[i], _compareMetrics[i]);
    }
    if (same) return;
    _compareKey = key;
    _compareMetrics = ms;
    final ranked = rankedFor(s);
    compare.send(withCompareExtras(comparePayload(ranked, s.weights, requireDsn: s.options.requireDsn), ranked));
    sentPayloads['compare'] = sentPayloads['compare']! + 1;
  }

  /// Cancel the pending cursor update (the app is going away).
  void dispose() {
    for (final s in _snaps.values) {
      if (!s.isCompleted) s.complete(null);
    }
    _snaps.clear();
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _batchTimer?.cancel();
  }

  // ---- events and exports ----

  /// PNGs requested together (sky + timeline), shared in one go when all
  /// have arrived: one share sheet on Android (two sheets in a row made the
  /// second clear the first one's file).
  final Map<String, Uint8List?> _batch = {};
  final Map<String, String> _batchView = {};
  Timer? _batchTimer;

  void _handle(ChartController c, Map<String, dynamic> ev) {
    if (ev['type'] == 'seek' && identical(c, timeline)) _state?.setCursor((ev['t'] as num).toDouble());
    if (ev['type'] == 'png' && _snaps.containsKey('${ev['id']}')) {
      final id = '${ev['id']}';
      _snapView.remove(id);
      _snaps.remove(id)!.complete(base64Decode((ev['dataUrl'] as String).split(',').last));
      return; // a full-screen picture, not a file to share
    }
    if (ev['type'] == 'error') {
      // that chart's full-screen pictures will not come
      for (final id in [for (final e in _snapView.entries) if (e.value == c.view) e.key]) {
        _snapView.remove(id);
        _snaps.remove(id)?.complete(null);
      }
    }
    if (ev['type'] == 'png') {
      final id = '${ev['id']}';
      final bytes = base64Decode((ev['dataUrl'] as String).split(',').last);
      if (_batch.containsKey(id)) {
        _batch[id] = bytes;
        if (_batch.values.every((b) => b != null)) _flushBatch();
      } else {
        _save([SaveFile('$id.png', bytes, 'image/png')]);
      }
    }
    if (ev['type'] == 'error' && _batch.isNotEmpty) {
      // that chart's image will not come: share what the others sent
      _batch.removeWhere((id, b) => b == null && _batchView[id] == c.view);
      if (_batch.values.every((b) => b != null)) _flushBatch();
    }
    onEvent(ev);
  }

  void _flushBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;
    final files = [for (final e in _batch.entries) if (e.value != null) SaveFile('${e.key}.png', e.value!, 'image/png')];
    _batch.clear();
    _batchView.clear();
    if (files.isNotEmpty) _save(files);
  }

  Future<void> _save(List<SaveFile> files) => _saveFiles(files).catchError((Object e) {
        onEvent({'type': 'notice', 'message': 'Could not save ${files.length == 1 ? files.first.name : 'the files'}: $e'});
      });

  /// "Shackleton_rim_10Oct2026": site and period start, for file names.
  String fileSlug(AppState s) => _slug(s.site.short, s.rangeStartMs);

  String _slug(String short, double t0Ms) => '${short.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${date(t0Ms).replaceAll(' ', '')}';

  String _start(AppState s) => date(s.rangeStartMs).replaceAll(' ', '');

  /// Ask a chart for a PNG; the file is saved when the page sends it back.
  /// A chart that has not been opened yet cannot draw one, so say so instead.
  void exportPng(ChartController c, String name) {
    if (!c.ready) {
      onEvent({'type': 'notice', 'message': 'Open that chart once, then export it.'});
      return;
    }
    c.send({'type': 'exportPng', 'id': name, 'width': 1600, 'height': 1000});
  }

  /// Sky plot + timeline of the selected site: two PNG files, saved or
  /// shared together once both have arrived.
  void exportSkyTimelinePng(AppState s) {
    if (!sky.ready || !timeline.ready) {
      onEvent({'type': 'notice', 'message': 'Open Site › Sky & time once, then export the charts.'});
      return;
    }
    // payloads held back while the charts were hidden go first (the page draws messages in order)
    _syncSeriesCharts(s);
    // named after what the charts draw (while a new choice is worked out, the previous one: state-1)
    final shown = _shown, slug = shown == null ? fileSlug(s) : _slug(shown.site.short, shown.series.t0Ms);
    final skyId = 'sky_$slug', tlId = 'timeline_$slug';
    _batch
      ..clear()
      ..[skyId] = null
      ..[tlId] = null;
    _batchView
      ..clear()
      ..[skyId] = sky.view
      ..[tlId] = timeline.view;
    _batchTimer?.cancel();
    // a chart that never answers must not hold the other image back forever
    _batchTimer = Timer(const Duration(seconds: 20), _flushBatch);
    exportPng(sky, skyId);
    exportPng(timeline, tlId);
  }

  /// The comparison bar chart.
  void exportComparePng(AppState s) => exportPng(compare, 'comparison_${_start(s)}');

  /// Every sample of the selected site's series, with the rules in the header.
  /// Refused (with a notice) while new choices are being worked out: the
  /// series on hand is then the previous choices' one.
  Future<void> exportSeriesCsv(AppState s) async {
    if (s.series == null || s.loading) {
      onEvent({'type': 'notice', 'message': 'The time series is still being worked out; try again in a moment.'});
      return;
    }
    await _save([
        SaveFile(
            'polar_horizon_${fileSlug(s)}.csv',
            utf8.encode(seriesCsv(s.site, s.series!,
                observerHeightM: s.observerHeightM, options: s.options, ephemeris: 'DE440 (NAIF SPICE), DSN via ITRF93')),
            'text/csv'),
      ]);
  }

  /// Score and metrics of the shortlisted sites (those with metrics so far).
  Future<void> exportScorecard(AppState s) => _save([
        SaveFile(
            'polar_horizon_comparison_${_start(s)}.csv',
            // the period's last day (the range end is exclusive), as the app shows it
            utf8.encode(scorecardCsv(rankedFor(s), '${date(s.rangeStartMs)} - ${date(s.rangeEndMs - 1)}', formulaText(s.weights),
                requireDsn: s.options.requireDsn)),
            'text/csv'),
      ]);
}

/// The site, horizon, observer and rules a series was computed for.
class _Shown {
  final SiteSeries series;
  final Site site;
  final HorizonMask mask;
  final Observer observer;
  final SeriesOptions options;

  /// The metrics of [series] (AppState sets them together); null only in
  /// tests that build a state by hand (the payload then computes them).
  final SiteMetrics? metrics;
  const _Shown(this.series, this.site, this.mask, this.observer, this.options, this.metrics);
}
