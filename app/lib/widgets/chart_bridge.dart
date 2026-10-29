/// Flutter side of the chart bridge (keep in sync with charts/src/bridge.ts).
///
/// [ChartController] buffers the latest message of each type until the
/// embedded React page reports `ready`, then forwards everything. The
/// payload builders turn Dart-core results into chart-ready JSON (the React
/// side never computes science).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, State, StatefulWidget, TickerMode, TickerModeData;
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

  /// Why this chart has not drawn, or null. [ChartIssue.tooOld] only on real
  /// evidence that this web view cannot run the chart bundle: a JavaScript
  /// syntax error before `ready`, or a Chrome (Android System WebView) older
  /// than [chartMinChromeMajor] (the bundle is built for Chrome 69, Android
  /// 7's stock web view, where the cards used to stay blank). A page that has
  /// loaded but not reported `ready` within [readyTimeout] is only
  /// [ChartIssue.slow]: a cold start on a slow
  /// but up-to-date phone can take longer (every chart web view shares one
  /// renderer, and the ranking and light map run at the same time). The card
  /// and the full-screen view say it; a later `ready` clears it.
  final ValueNotifier<ChartIssue?> _issue = ValueNotifier(null);
  Timer? _readyTimer;

  /// How long a loaded page may take to report `ready` before the card says
  /// it is still loading.
  static const readyTimeout = Duration(seconds: 15);

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

  /// See [_issue].
  ChartIssue? get issue => _issue.value;
  ValueListenable<ChartIssue?> get issueListenable => _issue;

  /// What the card says for [issue], or null.
  String? get problem => _issue.value?.text;

  /// The host's page has loaded: after [readyTimeout] without `ready` the
  /// card says it is still loading (never that the web view is too old).
  void pageLoaded() {
    if (_ready.value) return;
    _readyTimer?.cancel();
    _readyTimer = Timer(readyTimeout, () {
      _readyTimer = null;
      if (!_ready.value && _issue.value == null) _issue.value = ChartIssue.slow;
    });
  }

  /// A JavaScript error from the page's console. A syntax error before
  /// `ready` means this web view cannot parse the chart bundle at all.
  void pageError(String message) {
    if (_ready.value || !message.contains('SyntaxError')) return;
    _tooOld();
  }

  /// The loaded page's `navigator.userAgent`: a Chrome older than
  /// [chartMinChromeMajor] cannot run the bundle. Not Chrome (iOS): no verdict.
  void pageUserAgent(String userAgent) {
    final major = chromeMajor(userAgent);
    if (_ready.value || major == null || major >= chartMinChromeMajor) return;
    _tooOld();
  }

  void _tooOld() {
    _readyTimer?.cancel();
    _readyTimer = null;
    _issue.value = ChartIssue.tooOld;
  }

  /// Called by the platform host [owner] once it can deliver messages to its
  /// page. A newer host replaces the current one; its page must report
  /// `ready` before anything is delivered (the buffered messages then are).
  void attach(void Function(String json) sink, Object owner, {bool Function()? busy}) {
    _sink = sink;
    _owner = owner;
    _busy = busy;
    _ready.value = false;
    _readyTimer?.cancel(); // the new page gets its own time to report ready
    _readyTimer = null;
  }

  bool Function()? _busy;

  /// True while a ready page has not yet run everything sent to it (the
  /// host's queue is not empty or a message is still in flight). Play waits
  /// on it so the chart never falls steps behind the time bar.
  bool get behind => _ready.value && (_busy?.call() ?? false);

  /// Called by [owner] when it goes away. Ignored if another host has
  /// attached since: when a chart is rebuilt elsewhere in the tree, Flutter
  /// creates the new host before it disposes the old one.
  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _sink = null;
    _owner = null;
    _busy = null;
    _ready.value = false;
    _readyTimer?.cancel();
    _readyTimer = null;
  }

  /// Raw JSON event from the page.
  void handleRaw(String raw) {
    final ev = jsonDecode(raw) as Map<String, dynamic>;
    // the web host's own bookkeeping ([ChartAcks] takes acks before they get
    // here); the Android host waits on runJavaScript and sends no numbers,
    // so an ack that reaches a controller anyway means nothing
    if (ev['type'] == 'ack') return;
    if (ev['type'] == 'detail') {
      // a tap inside the chart: replay that mode after a reload of this page
      // only (the app's expert mode is not changed)
      _pending.remove('detail');
      _pending['detail'] = jsonEncode({'type': 'detail', 'exact': ev['exact'] == true});
    }
    if (ev['type'] == 'ready') {
      final firstReady = !_ready.value;
      _ready.value = true;
      _readyTimer?.cancel();
      _readyTimer = null;
      _issue.value = null;
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

/// The web host's view of what its page has drawn (charts/src/bridge.ts,
/// "Acks"). Every message the host posts gets the next sequence number
/// ([next]); the page answers `{type: 'ack', n}` once it has run and drawn
/// everything up to n. [busy], the controller's busy test on the web, is
/// true while a message is not acked yet, so Play waits for a slow page
/// there as it waits on runJavaScript on Android.
///
/// A page that was loaded again (a new `ready`) or went away ([reset], on
/// detach) owes nothing: what the old page was sent no longer holds Play.
/// A page that stops answering holds Play for [staleMs] at most: [busy]
/// turns false once nothing was acked for that long, until an ack shows the
/// page is drawing again.
///
/// A hidden chart never holds Play. One kept alive off stage (Sky & time
/// behind Site > Overview on a narrow screen, a destination behind another;
/// [followTickerMode]) or whose frame is not in the document ([attach]'s
/// `reachable`) may get no animation frames or no messages at all, so it
/// would never ack. The page also acks without a frame once none came for a
/// moment (ACK_FALLBACK_MS in bridge.ts), for what the host cannot see.
/// Tested on the VM.
class ChartAcks {
  ChartAcks({int Function()? clockMs, this.staleMs = 3000}) : _clock = clockMs ?? _wallMs;

  static int _wallMs() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _clock;

  /// After this long without an ack the page counts as not drawing (ms).
  final int staleMs;

  int _sent = 0, _acked = 0, _since = 0;

  /// The newest number sent and the newest the page acked. Never reset to 0:
  /// a late ack from a page that was replaced can then never clear a newer
  /// page's messages.
  int get sent => _sent;
  int get acked => _acked;

  /// The sequence number of the next message to the page.
  int next() {
    if (_acked >= _sent) _since = _clock(); // the wait starts now
    return ++_sent;
  }

  /// Nothing sent so far is waited for any more.
  void reset() => _acked = _sent;

  bool _onStage = true;

  /// Whether the chart is on screen. Off stage it never holds Play, and going
  /// off stage forgets what it owed. What it is sent meanwhile is still
  /// numbered (the page acks it once it draws, or on its fallback), so back
  /// on stage Play waits only for what is not drawn yet.
  bool get onStage => _onStage;
  set onStage(bool v) {
    if (!v) reset();
    _onStage = v;
  }

  bool get busy => _onStage && _acked < _sent && _clock() - _since < staleMs;

  ValueListenable<TickerModeData>? _tickers;

  /// Keep [onStage] in step with the TickerMode at [context], the host's
  /// (call it from didChangeDependencies and activate, as
  /// TickerProviderStateMixin does: a host moved by its GlobalKey gets the
  /// new place's). Every tab, destination or page kept alive off stage mutes
  /// its tickers (_LazyTabs, _SwipeTabs, the shell), so no layout rule (the
  /// 1100 px two-pane Overview) has to be repeated here.
  void followTickerMode(BuildContext context) {
    final t = TickerMode.getValuesNotifier(context);
    if (!identical(t, _tickers)) {
      _tickers?.removeListener(_followStage);
      _tickers = t..addListener(_followStage);
    }
    _followStage();
  }

  void _followStage() => onStage = _tickers?.value.enabled ?? true;

  /// Stop following the TickerMode (the host's dispose).
  void unfollow() {
    _tickers?.removeListener(_followStage);
    _tickers = null;
  }

  /// One event from the page. An ack is taken here (true: it goes no
  /// further). A `ready` (the page was loaded or loaded again) first
  /// forgets what any earlier page owed: the controller then replays its
  /// buffer to the new page, and those messages are waited for.
  bool take(Map<dynamic, dynamic> ev) {
    switch (ev['type']) {
      case 'ack':
        final n = ev['n'];
        if (n is num && n > _acked) {
          _acked = n.toInt() < _sent ? n.toInt() : _sent;
          _since = _clock(); // the page is drawing
        }
        return true;
      case 'ready':
        reset();
    }
    return false;
  }

  /// Attach [c] to a page that acks: [post] delivers one message JSON with
  /// its sequence number, and Play waits on [busy]. While [reachable] says
  /// no (the iframe is not in the document, so it has no window to post to)
  /// a message is dropped without a number, the page owes nothing and it
  /// never holds Play: no ack can come for what it never got (the
  /// controller replays its buffer when the page reports `ready` again).
  void attach(ChartController c, void Function(String json, int n) post, Object owner, {bool Function()? reachable}) {
    bool can() {
      if (reachable?.call() ?? true) return true;
      reset();
      return false;
    }

    c.attach((json) {
      if (can()) post(json, next());
    }, owner, busy: () => can() && busy);
  }

  /// Route one event from the page: acks stop here, the rest go to [c].
  void handle(ChartController c, Map<dynamic, dynamic> ev) {
    if (!take(ev)) c.handleRaw(jsonEncode(ev));
  }
}

/// The wiring of a State that hosts a page that acks (the web chart host,
/// and the VM tests' host, so the tested wiring is the shipped one):
/// [attachAcks] attaches the controller with [pageReachable] as the page's
/// reachability, [acks] follows the TickerMode where the host sits, from
/// didChangeDependencies and activate as TickerProviderStateMixin does (a
/// host moved by its GlobalKey gets the new place's), and a host that goes
/// away stops following it and never holds Play.
mixin ChartAcksHost<T extends StatefulWidget> on State<T> {
  /// What the page has drawn of what this host posted.
  ChartAcks get acks;

  /// Whether the page can be posted to now (on the web: the iframe is in the
  /// document, so it has a window). While it cannot, what is sent takes no
  /// number and never holds Play ([ChartAcks.attach]'s `reachable`).
  bool get pageReachable;

  /// Attach [c] to this host's page: [post] delivers one message JSON with
  /// its number, while [pageReachable] says the page can get it.
  void attachAcks(ChartController c, void Function(String json, int n) post) =>
      acks.attach(c, post, this, reachable: () => pageReachable);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    acks.followTickerMode(context);
  }

  @override
  void activate() {
    super.activate();
    acks.followTickerMode(context);
  }

  @override
  void dispose() {
    acks.unfollow();
    acks.reset(); // a page that goes away never holds Play
    super.dispose();
  }
}

/// The oldest Chrome (Android System WebView) major version that can run
/// the chart bundle: charts/vite.config.ts builds it for Chrome 69 (es2018,
/// Android 7's stock web view). The one place the app reads it; it must equal
/// the bundle's build target (test/widget/chart_problem_test.dart checks).
const chartMinChromeMajor = 69;

/// The Chrome major version in a user agent string, or null (not Chrome).
/// The string may come JSON-quoted from runJavaScriptReturningResult.
int? chromeMajor(String userAgent) {
  final m = RegExp(r'Chrome/(\d+)\.').firstMatch(userAgent);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Why a chart has not drawn ([ChartController.issue]).
enum ChartIssue {
  /// Loaded, not ready after [ChartController.readyTimeout]: still loading.
  slow,

  /// This web view cannot run the chart bundle (a syntax error, or an old Chrome).
  tooOld;

  String get text => this == tooOld ? chartTooOldText() : chartSlowText;
}

/// What a chart says while its page is loaded but has not drawn yet.
const chartSlowText = 'Still loading the chart…';

/// What a chart says when its page cannot run on this device's web view.
String chartTooOldText() => defaultTargetPlatform == TargetPlatform.iOS
    ? 'This chart needs a newer version of iOS. Update iOS in Settings, then open the app again.'
    : 'This chart needs a newer Android System WebView. Update Android System WebView or Chrome '
        'from the Play Store, then open the app again.';

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
  // the Sun with Earth's disk removed during a lunar eclipse (as fillSeries)
  final ecl = SunEclipse.of(s, rs, e, re);
  final fs = visibleFraction(s.az, s.el, rs, mask, occulter: ecl.occulter), fe = visibleFraction(e.az, e.el, re, mask);
  final hs = mask.at(s.az), he = mask.at(e.az);
  // Earth under the user's Earth rule from the terrain alone, then the DSN
  // check: 'terrainVisible' lets labels say "no DSN" instead of "hidden"
  final terrainEv = earthVisible(o.earthCriterion, fe, e.el, he);
  final dsnIn = eph.dsnMask(tMs) != 0;
  final ev = terrainEv && !(o.requireDsn && !dsnIn);
  final sv = sunVisible(o.sunCriterion, fs, s.el, hs, eclipse: ecl.fraction, centreHidden: ecl.centreHidden);
  // Earth, not the terrain, is why the Sun does not count: the terrain alone would let it
  final eclipseHides = ecl.overlaps && !sv && sunVisible(o.sunCriterion, visibleFraction(s.az, s.el, rs, mask), s.el, hs);
  return {
    'sun': <String, dynamic>{
      ...bodyNow(s, rs, fs, hs, sv,
          say: eclipseHides
              ? 'Earth hides the Sun (lunar eclipse)'
              : sunStatusText(visible: sv, elDeg: s.el, rhoDeg: rs, frac: fs, sunRule: o.sunCriterion)),
      // share of the whole disk behind Earth, and the power proxy on a Sun-facing panel (W/m²)
      'eclipse': ecl.fraction,
      'eclipseHides': eclipseHides,
      'power': powerProxy(fs, s.range),
    },
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
