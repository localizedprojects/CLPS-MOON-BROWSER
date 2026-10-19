/// Application state: data loading, navigation, the selected site/range/options,
/// the computed series + metrics, the ranking of every site, and the time
/// cursor (scrub / play).
///
/// Every series is computed in short slices that hand the event loop back
/// between them ([computeSeriesSliced]), so frames and taps keep flowing while
/// a long period is worked out. A change of site, period, height or rules is
/// applied at once (the controls show it) and the selected site's series and
/// metrics follow when they are ready ([loading] meanwhile). If a computation
/// fails, the last consistent state comes back and [error] says why.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/catalog.dart';
import '../core/daily.dart';
import '../core/dem.dart';
import '../core/ephemeris.dart';
import '../core/geo.dart';
import '../core/horizon.dart';
import '../core/horizon_compute.dart';
import '../core/landing.dart';
import '../core/metrics.dart';
import '../core/ranking.dart';
import '../core/score.dart';
import '../core/summary.dart';
import '../core/timeseries.dart';
import '../core/visibility.dart';
import '../widgets/map_view.dart' show MapLayers;
import 'dem_load.dart';
import 'light_engine.dart';

Future<Uint8List> loadAsset(String path) async => (await rootBundle.load('assets/data/$path')).buffer.asUint8List();

/// The shell's four destinations.
enum Dest { explore, site, compare, learn }

/// Sub-tabs of the Site destination.
enum SiteTab { overview, skyTime, light }

/// Metrics and per-day summaries of one site under one set of options. Kept
/// for every ranked site; the full series only for a few (see [AppState._series]).
class _SiteResult {
  final SiteMetrics metrics;
  final List<DaySummary> daily;
  const _SiteResult(this.metrics, this.daily);
}

/// What a series computation needs, captured when it starts. [key] is the
/// options part of the cache key ([AppState._optionsKey]).
class _Cfg {
  final Ephemeris eph;
  final double t0, t1, h;
  final SeriesOptions o;
  final String key;
  const _Cfg(this.eph, this.t0, this.t1, this.h, this.o, this.key);
}

/// A consistent state: the choices and the selected site's results under them.
class _Snapshot {
  final Ephemeris? eph;
  final double rangeStartMs, rangeEndMs, cursorMs, observerHeightM;
  final SeriesOptions options;
  final String selectedId, key;
  final SiteSeries series;
  final SiteMetrics metrics;
  const _Snapshot(this.eph, this.rangeStartMs, this.rangeEndMs, this.cursorMs, this.observerHeightM, this.options,
      this.selectedId, this.key, this.series, this.metrics);
}

/// Everything a "best landing window" answer depends on
/// (docs/ux_landing_window_spec.md, section 7 P2). Two keys are equal when
/// every field is.
@immutable
class LandingKey {
  final String siteId;
  final double rangeStartMs, rangeEndMs, observerHeightM, stepMs;
  final SunCriterion sunCriterion;
  final EarthCriterion earthCriterion;
  final bool requireDsn;
  final double weightPower, weightBoth;
  final int missionDays;

  const LandingKey({
    required this.siteId,
    required this.rangeStartMs,
    required this.rangeEndMs,
    required this.observerHeightM,
    required this.stepMs,
    required this.sunCriterion,
    required this.earthCriterion,
    required this.requireDsn,
    required this.weightPower,
    required this.weightBoth,
    required this.missionDays,
  });

  ScoreWeights get weights => ScoreWeights(power: weightPower, both: weightBoth);

  /// Why an answer for this key is out of date under [now] (same site):
  /// 'dates' | 'height' | 'rules' | 'dsn' | 'weights', the first that applies
  /// in that order; null when none does (the mission length is not a reason:
  /// an answer for another length is never shown, see [AppState.landingFor]).
  String? staleReason(LandingKey now) {
    if (rangeStartMs != now.rangeStartMs || rangeEndMs != now.rangeEndMs || stepMs != now.stepMs) return 'dates';
    if (observerHeightM != now.observerHeightM) return 'height';
    if (sunCriterion != now.sunCriterion || earthCriterion != now.earthCriterion) return 'rules';
    if (requireDsn != now.requireDsn) return 'dsn';
    if (weightPower != now.weightPower || weightBoth != now.weightBoth) return 'weights';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is LandingKey &&
      other.siteId == siteId &&
      other.missionDays == missionDays &&
      staleReason(other) == null;

  @override
  int get hashCode => Object.hash(siteId, rangeStartMs, rangeEndMs, observerHeightM, stepMs, sunCriterion,
      earthCriterion, requireDsn, weightPower, weightBoth, missionDays);

  @override
  String toString() => 'LandingKey($siteId, $missionDays d, $rangeStartMs..$rangeEndMs, ${observerHeightM}m, '
      'step $stepMs, $sunCriterion, $earthCriterion, dsn $requireDsn, w $weightPower/$weightBoth)';
}

/// One "best landing window" search for [key]: running ([busy], with
/// [progress] 0..1), done ([plan]) or failed ([error]). [windowNumber] is 1
/// for the earliest window and 2, 3, ... after "Next window that fits".
@immutable
class LandingEntry {
  final LandingKey key;
  final LandingPlan? plan;
  final Object? error;
  final bool busy;
  final double progress;
  final int windowNumber;

  const LandingEntry(this.key, {this.plan, this.error, this.busy = false, this.progress = 0, this.windowNumber = 1});

  LandingEntry _withProgress(double p) => LandingEntry(key, busy: true, progress: p);
}

/// The start sequence ([AppState.startStage]).
enum StartStage { intro, tour, goal, loading, done }

class AppState extends ChangeNotifier {
  // ---- navigation (owned by the shell) ----

  Dest dest = Dest.explore;
  SiteTab siteTab = SiteTab.overview;

  /// Show [d] (and [siteTab] when given). Leaving Site pauses playback: the
  /// only Play/Pause control lives there.
  void goTo(Dest d, {SiteTab? siteTab}) {
    dest = d;
    if (siteTab != null) this.siteTab = siteTab;
    if (d != Dest.site) _stopPlay();
    _retryMap();
    notifyListeners();
  }

  /// Select [id] and show it in Site (on [tab]), in one notification (one
  /// web history entry).
  Future<void> openSite(String id, {SiteTab tab = SiteTab.overview}) async {
    dest = Dest.site;
    siteTab = tab;
    _retryMap();
    if (id == selectedId && series != null) {
      _userPicked = true;
      notifyListeners();
      return;
    }
    await selectSite(id);
  }

  /// "Show exact numbers (for mission planners)": readout, decimals, coordinates.
  bool expert = false;

  void setExpert(bool v) {
    expert = v;
    notifyListeners();
  }

  /// "Explain as I go": short explanation cards next to each view.
  bool explainInline = false;

  void setExplainInline(bool v) {
    explainInline = v;
    notifyListeners();
  }

  /// Explore's group filter: a [SiteGroup.id], 'custom', or null for every site.
  String? groupFilter;

  void setGroupFilter(String? g) {
    groupFilter = g;
    notifyListeners();
  }

  /// Step the cursor by [steps] samples (keyboard navigation).
  void stepCursor(int steps) => setCursor(cursorMs + steps * options.stepMs);

  final EphemerisRepository repo = EphemerisRepository(loadAsset);

  SiteCatalog? catalog;
  EphemerisManifest? manifest;

  /// Always covers [rangeStartMs, rangeEndMs) once loaded: a new period's
  /// ephemeris is loaded before the range changes (see [setRange]).
  Ephemeris? eph;
  String? error;

  /// True while the selected site's series for the current choices is being
  /// computed; [series] and [metrics] still hold the previous ones meanwhile.
  bool loading = true;

  String selectedId = 'derosa2012-sr1-shackleton-rim';
  double observerHeightM = 2.0;
  SeriesOptions options = const SeriesOptions();
  bool skyZoom = true;

  double rangeStartMs = 0, rangeEndMs = 0, cursorMs = 0;
  SiteSeries? series;
  SiteMetrics? metrics;

  bool playing = false;
  Timer? _timer;

  /// True while the charts have not drawn the last step yet ([ChartHub.chartsBehind]);
  /// set by the app. Play then skips its step, up to [_maxHeldTicks] in a row.
  bool Function()? holdPlay;
  int _heldTicks = 0;

  /// At most 3 s of waiting per step (a slow emulator's web view can take
  /// that long), so a stuck web view never stops Play.
  static const _maxHeldTicks = 30;

  /// True while the Light & shadow map has not shown the last step yet
  /// ([LightMap.framePending]: its frame or its overlay picture is still
  /// being made); set by the app. Play then skips its step, up to
  /// [_maxMapHeldTicks] in a row. The map is made on the device, so unlike a
  /// web view it cannot hang for good: it finishes or fails, and a failing
  /// engine stops holding at once. The cap only guards against a flag left
  /// set by mistake.
  bool Function()? holdPlayForMap;

  /// At most 30 s of waiting per step for the light map. An Android 7
  /// emulator takes several seconds per frame; the charts' 3 s let its map
  /// fall up to four steps (40 h) behind the time bar.
  static const _maxMapHeldTicks = 300;

  /// Map layers (LOLA hillshade + overlays); null until loaded, and while a
  /// failed load waits for its retry ([ensureMap]).
  MapLayers? mapLayers;

  /// Makes the next [n] loads of the map layers fail (tests of the retry).
  @visibleForTesting
  int debugFailMapLoads = 0;

  // ---- comparison shortlist and score weights ----

  /// The shortlist: 0..4 sites over the same period/options (Compare needs >= 2).
  /// Empty until the user shortlists something ("Compare top 3", a card's
  /// compare toggle), so Explore opens on its answer with no pre-filled tray
  /// (ux1-1).
  List<String> compareIds = [];

  /// A fixed trio of known sites, for tests that need a shortlist from the start.
  @visibleForTesting
  static const exampleShortlist = ['derosa2012-sr1-shackleton-rim', 'artemis3-malapert-massif', 'artemis3-haworth'];
  ScoreWeights weights = const ScoreWeights();

  /// "What matters most?" ([weights] are [weightsFor] this goal unless tuned by hand).
  Goal goal = Goal.balanced;

  // ---- the start question (user decision 2026-10-13) ----

  /// Ask "What matters most?" when the app opens (main.dart sets this; tests
  /// and other hosts leave it off and start on Explore).
  bool askGoalOnStart = false;

  /// The start question was answered in this run of the app.
  bool goalAnswered = false;

  /// Where the start sequence is (with [askGoalOnStart]): the intro
  /// animation, the question, the loading scene, then the app.
  StartStage startStage = StartStage.intro;

  /// The end of the intro (its animation, a tap on it, or reduced motion's
  /// short timer): the tutorial on a first launch, else the start question.
  /// While [loadTourSeen] is still reading (a tap right away, a slow cold
  /// start) it waits for the answer, up to [tourFlagWait], so a first launch
  /// never skips the tutorial; a store that never answers goes on without it.
  void finishIntro() {
    if (startStage != StartStage.intro || _introEnding) return;
    final flag = _tourFlag;
    if (flag == null) return _endIntro();
    _introEnding = true;
    unawaited(flag.timeout(tourFlagWait, onTimeout: () {}).whenComplete(_endIntro));
  }

  void _endIntro() {
    _introEnding = false;
    if (_disposed || startStage != StartStage.intro) return;
    startStage = tourPending ? StartStage.tour : StartStage.goal;
    notifyListeners();
  }

  /// How long the end of the intro waits for the tutorial flag.
  static const tourFlagWait = Duration(seconds: 2);

  /// [loadTourSeen] while it is reading (null before and after).
  Future<void>? _tourFlag;
  bool _introEnding = false;

  // ---- the first-launch tutorial (user request 2026-10-19) ----

  /// The tutorial has not been seen on this device yet: the start sequence
  /// shows it once, between the intro and the start question. False until
  /// [loadTourSeen] reads the store, so tests and other hosts never see it.
  bool tourPending = false;

  /// The first-launch tutorial is on screen in the start sequence: links
  /// wait for its Skip or Done (the shell's router holds them). The shell
  /// shows it only over Explore, so a link opened during the intro's wait
  /// for the flag (dest Compare, say) is not held: the tutorial shows when
  /// Explore is reached, as the start question does.
  bool get inStartTour => askGoalOnStart && startStage == StartStage.tour && dest == Dest.explore;

  static const _tourKey = 'tourSeen';

  /// Opens the store the tutorial flag lives in (tests swap in a slow, hung
  /// or failing one).
  @visibleForTesting
  Future<SharedPreferences> Function() openPrefs = SharedPreferences.getInstance;

  /// Read whether the tutorial was seen. A missing or failing store does not
  /// show it: it could not be remembered, so it would come back every launch.
  Future<void> loadTourSeen() => _tourFlag ??= _readTourSeen().whenComplete(() => _tourFlag = null);

  Future<void> _readTourSeen() async {
    try {
      final seen = (await openPrefs()).getBool(_tourKey) ?? false;
      if (_disposed || tourPending == !seen) return;
      tourPending = !seen;
      notifyListeners();
    } catch (_) {}
  }

  /// Skip or Done on the tutorial: remember it, and in the start sequence go
  /// on to the start question (a link that came during it opens now).
  void finishTour() {
    tourPending = false;
    if (startStage == StartStage.tour) startStage = StartStage.goal;
    notifyListeners();
    unawaited(() async {
      try {
        await (await openPrefs()).setBool(_tourKey, true);
      } catch (_) {}
    }());
  }

  void finishStartLoading() {
    if (startStage != StartStage.loading) return;
    startStage = StartStage.done;
    notifyListeners();
  }

  /// The goal saved by the last [answerGoal] (null on a first run or when
  /// nothing could be read).
  Goal? savedGoal;

  static const _goalKey = 'goal';

  /// Retired: preview builds saved the chosen opening here. Cleared at start;
  /// never reuse this key name.
  static const _retiredOpeningKey = 'opening';

  /// Read the goal saved last time and rank for it until the start question
  /// is answered. A missing or failing store keeps Balanced.
  Future<void> loadSavedGoal() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.containsKey(_retiredOpeningKey)) await p.remove(_retiredOpeningKey);
      final name = p.getString(_goalKey);
      final g = Goal.values.where((x) => x.name == name).firstOrNull;
      if (g == null) return;
      savedGoal = g;
      if (!goalAnswered) {
        goal = g;
        weights = weightsFor(g);
      }
      notifyListeners();
    } catch (_) {
      // no store (a test host, a private browser window): Balanced, nothing marked
    }
  }

  /// Whether the time bar of Sky & time and Light & shadow is folded to its
  /// slim strip (user request 2026-10-15). Both tabs share it; it is saved.
  bool timeControlsHidden = false;

  static const _timeControlsKey = 'timeControlsHidden';

  /// Read the saved [timeControlsHidden]; a missing store keeps the bar shown.
  Future<void> loadTimeControlsHidden() async {
    try {
      final v = (await SharedPreferences.getInstance()).getBool(_timeControlsKey);
      if (v == null || v == timeControlsHidden) return;
      timeControlsHidden = v;
      notifyListeners();
    } catch (_) {}
  }

  /// Fold the time bar to its strip ([hidden]) or open it, and remember it.
  void setTimeControlsHidden(bool hidden) {
    if (hidden == timeControlsHidden) return;
    timeControlsHidden = hidden;
    notifyListeners();
    unawaited(() async {
      try {
        await (await SharedPreferences.getInstance()).setBool(_timeControlsKey, hidden);
      } catch (_) {}
    }());
  }

  /// Answer the start question: rank for [g], open Explore, and remember the
  /// choice for next time.
  void answerGoal(Goal g) {
    goalAnswered = true;
    savedGoal = g;
    if (startStage != StartStage.done) startStage = StartStage.loading;
    setGoal(g); // notifies
    unawaited(() async {
      try {
        await (await SharedPreferences.getInstance()).setString(_goalKey, g.name);
      } catch (_) {}
    }());
  }

  /// The goal the current [weights] match, or null when they were tuned by
  /// hand. Goal chips show this one as selected (none for custom weights),
  /// since [goal] keeps the last preset.
  Goal? get activeGoal => goalFor(weights);

  void setGoal(Goal g) {
    final rerun = _landingLive(selectedId); // an in-card change: the answer follows (spec 7 P2)
    goal = g;
    weights = weightsFor(g);
    notifyListeners();
    if (rerun && !_landingLive(selectedId)) unawaited(findLanding());
  }

  /// Metrics of the shortlisted sites that are already computed under the
  /// current options. Never computes: the ranking works the shortlist out
  /// first after any change (see [compareReady]).
  Map<String, SiteMetrics> get compareMetrics => {for (final id in compareIds) id: ?metricsFor(id)};

  /// Every shortlisted site has metrics under the current options.
  bool get compareReady => eph != null && catalog != null && compareIds.every((id) => metricsFor(id) != null);

  Site siteById(String id) => allSites.firstWhere((x) => x.id == id);

  /// Add [id] to the shortlist (when it has fewer than 4 sites) or remove it.
  void toggleCompare(String id) {
    if (compareIds.contains(id)) {
      compareIds = [...compareIds]..remove(id);
    } else if (compareIds.length < 4) {
      compareIds = [...compareIds, id];
    } else {
      return;
    }
    notifyListeners();
  }

  /// Replace the shortlist (duplicates and unknown ids dropped, at most 4 kept).
  void setCompare(List<String> ids) {
    final known = catalog == null ? null : {for (final s in allSites) s.id};
    compareIds = [for (final id in ids.toSet()) if (known == null || known.contains(id)) id].take(4).toList();
    notifyListeners();
  }

  void setWeights(ScoreWeights w) {
    weights = w;
    goal = goalFor(w) ?? goal;
    notifyListeners();
  }

  /// User-placed sites; their horizons come from the coarse on-device DEM.
  final List<Site> customSites = [];
  final Map<String, Map<double, HorizonMask>> _customMasks = {};
  bool placingCustom = false;

  /// Shown when a custom site falls outside the 400 m terrain map's coverage.
  static const customSiteEdgeText = 'That spot is at the very edge of the terrain map, where no height can be read. '
      'Pick a point a little closer to the pole (80.01° S or further south).';

  List<Site> get allSites => [...catalog!.sites, ...customSites];
  Site get site => customSites.where((s) => s.id == selectedId).firstOrNull ?? catalog!.byId(selectedId);
  HorizonMask get mask => _maskOf(selectedId, observerHeightM);
  Observer get observer => Observer(site.lat, site.lon, site.terrainHeightM + observerHeightM);

  HorizonMask _maskOf(String id, double h) => (_customMasks[id] ?? catalog!.masks[id])![h]!;

  /// Options differ from the [SeriesOptions] defaults (Sun rule, Earth rule, DSN).
  bool get customRules {
    const d = SeriesOptions();
    return options.sunCriterion != d.sunCriterion || options.earthCriterion != d.earthCriterion || options.requireDsn != d.requireDsn;
  }

  SiteSeries? _nextFor;
  double _nextAt = double.nan;
  NextStretch? _next;

  /// Where "Next good stretch ›" goes from the cursor: the next good stretch
  /// (Sun + Earth together for at least 24 h, [goodWindows]) that starts after
  /// the cursor; when none is left in the period, the next Sun + Earth window
  /// of any length, with [NextStretch.good] false; null when there is neither.
  NextStretch? get nextStretchFromCursor {
    final s = series;
    if (s == null) return null;
    if (!identical(s, _nextFor) || cursorMs != _nextAt) {
      _nextFor = s;
      _nextAt = cursorMs;
      _next = nextStretch(s, cursorMs);
    }
    return _next;
  }

  /// The window of [nextStretchFromCursor] (a good stretch when one is left).
  Interval? get nextBothWindowFromCursor => nextStretchFromCursor?.window;

  // ---- ranking of every site (catalogue + custom) ----

  /// Per site and options (see [_cacheKey]): metrics + daily summaries.
  final Map<String, _SiteResult> _results = {};

  /// Full series, least recently stored first; trimmed to [_seriesKeep], never
  /// dropping the selected or compared sites under the current options.
  final Map<String, SiteSeries> _series = {};
  static const _seriesKeep = 6;

  /// Series computations under way, by cache key (one per key: the ranking
  /// and the selected site share it).
  final Map<String, Future<SiteSeries?>> _jobs = {};

  /// Longest stretch of work per event-loop turn in a series computation.
  static const defaultSliceBudget = Duration(milliseconds: 20);

  /// [defaultSliceBudget], except in a test that shortens it to count the
  /// slices (a structural check that CPU load cannot fail, unlike a
  /// millisecond budget on the longest turn).
  @visibleForTesting
  static Duration sliceBudget = defaultSliceBudget;

  int _rankGen = 0, _updateGen = 0, _rankProgress = 0, _rankTotal = 0, _resultsStamp = 0;
  bool _rankingDone = false, _ready = false, _userPicked = false, _disposed = false;
  String? _rankedSig;
  List<Ranked> _ranked = const [];

  /// Options key of the ranking that is running or done, null when none is.
  String? _rankingKey;

  /// During the first ranking: the best site so far, whose series is kept
  /// (it becomes the default selection).
  String? _keepBest;

  /// The selected site's results as last committed, and the last committed
  /// state whose ranking finished: what a failed computation returns to.
  _Snapshot? _committed, _good;

  /// The cursor before the first change of the ranking now running: a failed
  /// ranking puts it back with the previous settings.
  double? _cursorBeforeChange;

  /// How many series have been computed (tests check that re-sorting is free).
  @visibleForTesting
  int seriesComputeCount = 0;

  /// Makes every computation of this site's series throw (tests of the
  /// failure paths).
  @visibleForTesting
  String? debugFailSiteId;

  int get rankProgress => _rankProgress;
  int get rankTotal => _rankTotal;
  bool get rankingDone => _rankingDone;

  /// True once the first ranking has finished and the default site is chosen
  /// (the shell shows the loading screen until then).
  bool get ready => _ready;

  String get _optionsKey => '$rangeStartMs|$rangeEndMs|$observerHeightM|'
      '${options.sunCriterion}|${options.earthCriterion}|${options.requireDsn}';

  String _cacheKey(String id) => '$id|$_optionsKey';

  _Cfg get _cfg => _Cfg(eph!, rangeStartMs, rangeEndMs, observerHeightM,
      options.copyWith(stepMs: SeriesOptions.autoStepMs(rangeEndMs - rangeStartMs)), _optionsKey);

  /// Every site ranked so far under the current options, best first under
  /// [weights]. Grows while a ranking runs; re-sorting is free (no recompute).
  List<Ranked> get rankedAll {
    if (eph == null || catalog == null) return const [];
    final sig = '$_optionsKey|${weights.power}|${weights.both}|$_resultsStamp|${customSites.length}';
    if (sig != _rankedSig) {
      _rankedSig = sig;
      _ranked = List.unmodifiable(rank({
        for (final st in allSites)
          if (_results[_cacheKey(st.id)] case final r?) st.id: (st.short, r.metrics),
      }, weights));
    }
    return _ranked;
  }

  /// Metrics of [id] under the current options; null until computed.
  SiteMetrics? metricsFor(String id) => eph == null ? null : _results[_cacheKey(id)]?.metrics;

  /// The full series of [id] when it is kept (always for the selected site;
  /// for compared sites once computed), else null.
  SiteSeries? seriesFor(String id) => eph == null ? null : _series[_cacheKey(id)];

  /// One summary per UTC day for [id]; empty until its series has been computed.
  List<DaySummary> dailyFor(String id) => eph == null ? const [] : _results[_cacheKey(id)]?.daily ?? const [];

  /// Cache [s] (and its metrics + daily summaries) under [key].
  _SiteResult _store(String key, SiteSeries s) {
    final r = _results[key] ??= _SiteResult(computeMetrics(s), dailySummaries(s));
    _resultsStamp++;
    _series.remove(key);
    _series[key] = s;
    final keep = {
      _cacheKey(selectedId),
      for (final id in compareIds) _cacheKey(id),
      if (_keepBest case final b?) _cacheKey(b),
    };
    while (_series.length > _seriesKeep) {
      _series.remove(_series.keys.firstWhere((k) => !keep.contains(k), orElse: () => _series.keys.first));
    }
    return r;
  }

  /// The series of [st] under [c], in slices; stored in the cache when done.
  /// Null when the options changed meanwhile (the computation stopped early).
  Future<SiteSeries?> _seriesOf(Site st, _Cfg c) {
    final key = '${st.id}|${c.key}';
    final running = _jobs[key];
    if (running != null) return running;
    final job = _compute(key, st, c);
    _jobs[key] = job;
    void done() {
      if (identical(_jobs[key], job)) _jobs.remove(key);
    }

    job.then((_) => done(), onError: (Object _) => done());
    return job;
  }

  Future<SiteSeries?> _compute(String key, Site st, _Cfg c) async {
    seriesComputeCount++;
    if (debugFailSiteId == st.id) throw StateError('test failure for ${st.short}');
    final n = seriesLength(c.t0, c.t1, c.o.stepMs);
    final last = c.t0 + (n - 1) * c.o.stepMs;
    if (!c.eph.covers(c.t0, last)) {
      throw RangeError('the loaded ephemeris does not cover ${dateTime(c.t0)} to ${dateTime(last)}');
    }
    final s = await computeSeriesSliced(
        c.eph, Observer(st.lat, st.lon, st.terrainHeightM + c.h), _maskOf(st.id, c.h), c.t0, c.t1, c.o,
        budget: sliceBudget, cancelled: () => _disposed || c.key != _optionsKey);
    if (s == null) return null;
    // metrics and day summaries each in their own turn (tens of ms for 11 years)
    await Future<void>.delayed(Duration.zero);
    final m = computeMetrics(s);
    await Future<void>.delayed(Duration.zero);
    _results[key] ??= _SiteResult(m, dailySummaries(s));
    _store(key, s);
    return s;
  }

  void _cancelRanking() {
    _rankGen++;
    _rankingKey = null;
    _rankProgress = 0;
    _rankTotal = catalog == null ? 0 : allSites.length;
    _rankingDone = false;
  }

  /// The ranking's order: the selected site, then the shortlist (so Site and
  /// Compare are ready first), then every other site.
  List<Site> _rankOrder() {
    final all = allSites;
    final first = [selectedId, ...compareIds];
    return [
      for (final id in first.toSet()) ...all.where((x) => x.id == id),
      ...all.where((x) => !first.contains(x.id)),
    ];
  }

  /// Rank every site for the current options, in slices so frames keep
  /// flowing (the progress drives the loading screen). Any option change
  /// starts a new run, which cancels this one through [_rankGen].
  Future<void> _rankAll() async {
    final gen = ++_rankGen;
    final c = _cfg;
    _rankingKey = c.key;
    final sites = _rankOrder();
    _rankTotal = sites.length;
    _rankProgress = 0;
    _rankingDone = false;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      for (final st in sites) {
        final key = '${st.id}|${c.key}';
        if (!_results.containsKey(key)) {
          await Future<void>.delayed(Duration.zero); // let a frame render between sites
          if (gen != _rankGen) return;
          // the selected site's computation may have stored it meanwhile
          if (!_results.containsKey(key)) {
            final s = await _seriesOf(st, c);
            if (gen != _rankGen || s == null) return;
          }
          if (!_ready) _keepBest = rankedAll.firstOrNull?.id;
        }
        _rankProgress++;
        notifyListeners();
      }
    } catch (err, st) {
      if (gen != _rankGen) return;
      debugPrint('$err\n$st');
      await _rankFailed(c.key, err);
      return;
    }
    debugPrint('ranked ${sites.length} sites in ${sw.elapsedMilliseconds} ms');
    _rankingDone = true;
    _cursorBeforeChange = null;
    if (_committed case final cm? when cm.key == c.key) _good = cm;
    if (!_ready) {
      await _pickDefault(gen);
      if (gen != _rankGen) return;
      _keepBest = null;
      _ready = true;
    }
    notifyListeners();
  }

  /// After the first ranking: select the top pick, unless the user already chose a site.
  Future<void> _pickDefault(int gen) async {
    final top = rankedAll.firstOrNull;
    if (_userPicked || top == null || top.id == selectedId) return;
    final key = _cacheKey(top.id);
    SiteSeries? s = _series[key];
    if (s == null) {
      try {
        s = await _seriesOf(siteById(top.id), _cfg);
      } catch (e) {
        debugPrint('default site: $e');
        return; // keep the site that is already computed
      }
    }
    if (s == null || gen != _rankGen || _userPicked) return;
    selectedId = top.id;
    _commit(key, s);
  }

  /// A ranking under [failedKey] failed: go back to the last fully ranked
  /// state (and rank it again when it lacks a site, e.g. a new custom site).
  Future<void> _rankFailed(String failedKey, Object err) async {
    final msg = 'These settings could not be worked out for every site, so the previous settings are back. ($err)';
    final good = _good;
    if (good == null) {
      // the first ranking: the loading screen shows the error and "Try again"
      error = 'Could not rank the sites: $err';
      if (_ready) {
        _rankingDone = true;
        _rankProgress = _rankTotal;
      }
      notifyListeners();
      return;
    }
    // the cursor from before the change that started this ranking (new-logic-4)
    final cursor = _cursorBeforeChange ?? cursorMs;
    _cursorBeforeChange = null;
    _restore(good, cursor);
    error = msg;
    if (_optionsKey == failedKey) {
      // nothing older to return to: keep the sites that were ranked
      _rankingKey = _optionsKey;
      _rankingDone = true;
      _rankProgress = _rankTotal;
      notifyListeners();
      return;
    }
    notifyListeners();
    await _rankAll();
  }

  /// Put back the choices and results of [to], keeping [cursor] when it lies
  /// in that period.
  void _restore(_Snapshot to, double cursor) {
    final before = _optionsKey;
    _updateGen++; // a change still being computed no longer applies
    eph = to.eph;
    rangeStartMs = to.rangeStartMs;
    rangeEndMs = to.rangeEndMs;
    observerHeightM = to.observerHeightM;
    options = to.options;
    _resultOptions = to.options;
    selectedId = to.selectedId;
    series = to.series;
    metrics = to.metrics;
    final last = rangeEndMs - options.stepMs;
    cursorMs = cursor >= rangeStartMs && cursor <= last ? cursor : to.cursorMs.clamp(rangeStartMs, last);
    _store(_cacheKey(selectedId), to.series); // its metrics are still cached; the series is kept again
    loading = false;
    // what a later failure returns to is this state, not an abandoned one (new-logic-1)
    _committed = to;
    if (_optionsKey != before) _cancelRanking();
  }

  /// The options the shown [series] and [metrics] were computed with. While
  /// [loading] they can differ from [options] (the controls already show the
  /// new choice), so labels of the shown numbers use these (new-logic-2).
  SeriesOptions get resultOptions => _resultOptions ?? options;
  SeriesOptions? _resultOptions;

  /// The site that [series] and [metrics] belong to. While [loading] after a
  /// change of site it is the previous one, not [selectedId]: a screen that
  /// shows [site] must then use [metricsFor] ([selectedId]) or wait, never
  /// mix the new site's name with these numbers (logic-1).
  String? get committedSiteId => _committed?.selectedId;

  /// The selected site's metrics: cached under the current options when they
  /// are, else [metrics] when those belong to the selected site (while
  /// [loading] after a change of period, height or rules they are the
  /// previous choices' numbers, which the screens say), else null (another
  /// site's numbers are never returned; show a wait instead).
  SiteMetrics? get selectedMetrics => metricsFor(selectedId) ?? (committedSiteId == selectedId ? metrics : null);

  /// Make [s] the selected site's series (stored under [key]).
  void _commit(String key, SiteSeries s) {
    _resultOptions = options;
    metrics = _store(key, s).metrics;
    series = s;
    cursorMs = cursorMs.clamp(rangeStartMs, rangeEndMs - options.stepMs);
    loading = false;
    error = null;
    final snap = _Snapshot(eph, rangeStartMs, rangeEndMs, cursorMs, observerHeightM, options, selectedId, _optionsKey, s,
        metrics!);
    _committed = snap;
    if (_rankingDone && _rankingKey == snap.key) _good = snap;
  }

  /// Load the data, compute the default site, then rank every site (the
  /// returned future completes when the first ranking is done). Safe to call
  /// again after a failure ("Try again").
  Future<void> init() async {
    error = null;
    loading = true;
    _ready = false;
    // a retry after a failed ranking starts the ranking over too (the loading
    // bar must not read the old run's partial progress as work done)
    _rankGen++;
    _rankProgress = 0;
    _rankTotal = 0;
    _rankingDone = false;
    notifyListeners();
    try {
      // fetched together, not one after another (async-2); the map layers load
      // alongside the ephemeris and the first series, and are in place before
      // the first commit (they never fail init: see [_loadMap])
      final mapJob = ensureMap();
      final validationJob = _ridgePeak == null ? _loadValidation() : Future<void>.value(); // never throws
      final texts = await Future.wait([
        rootBundle.loadString('assets/data/sites.json'),
        rootBundle.loadString('assets/data/horizons.json'),
      ]);
      final manifestJob = repo.manifest();
      catalog = SiteCatalog.parse(texts[0], texts[1]);
      manifest = await manifestJob;
      if (!allSites.any((s) => s.id == selectedId)) selectedId = catalog!.sites.first.id;
      // default: the next 12 months from today (UTC midnight), within the ephemeris span
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch.toDouble();
      final m = manifest!;
      final start = today.clamp(m.startUnixMs.toDouble(), m.endUnixMs - 366 * 86400e3);
      final (t0, t1) = m.clampPeriod(start, start + 365 * 86400e3);
      eph = await repo.range(t0, t1);
      rangeStartMs = t0;
      rangeEndMs = t1;
      cursorMs = t0;
      options = options.copyWith(stepMs: SeriesOptions.autoStepMs(t1 - t0));
      final key = _cacheKey(selectedId);
      final s = _series[key] ?? await _seriesOf(site, _cfg);
      await mapJob;
      await validationJob;
      if (s == null) return; // disposed, or a newer change took over
      _commit(key, s);
    } catch (e, st) {
      error = 'Failed to load data: $e';
      debugPrint('$e\n$st');
      loading = false;
      notifyListeners();
      return;
    }
    notifyListeners();
    await _rankAll();
  }

  Future<ui.Image> _image(String path) async {
    final codec = await ui.instantiateImageCodec(await loadAsset(path));
    return (await codec.getNextFrame()).image;
  }

  /// Load the map layers unless they are in place (once, even when asked for
  /// twice meanwhile). Never throws: a failed load (a network blip on the
  /// web, one layer that does not decode) leaves [mapLayers] null and is
  /// tried again on the next call, which every navigation makes
  /// ([goTo], [openSite]) and a "Try again" control can make, instead of
  /// the map being gone for the whole session (state-2).
  Future<void> ensureMap() {
    if (mapLayers != null || _disposed) return Future<void>.value();
    return _mapJob ??= _loadMap().then((ok) {
      _mapJob = null;
      // init commits and notifies on its own; later loads tell the screens
      if (ok && _ready) notifyListeners();
    });
  }

  Future<void>? _mapJob;

  /// After loading: a navigation retries a map load that failed.
  void _retryMap() {
    if (_ready && mapLayers == null && _mapJob == null) unawaited(ensureMap());
  }

  /// True when the layers are in place; false (logged) when they failed.
  Future<bool> _loadMap() async {
    try {
      if (debugFailMapLoads > 0) {
        debugFailMapLoads--;
        throw StateError('test failure of the map layers');
      }
      final m = jsonDecode(await rootBundle.loadString('assets/data/map/map.json')) as Map<String, dynamic>;
      Future<ui.Image?> opt(String key) async {
        final f = (m[key] as Map?)?['file'] as String?;
        return f == null ? null : _image(f);
      }
      // the four layers are fetched and decoded together (async-2)
      final imgs = await Future.wait<ui.Image?>([_image('map/hillshade.webp'), opt('sunvis'), opt('earthvis'), opt('psr')]);
      if (_disposed) return false;
      mapLayers = MapLayers(imgs[0]!, imgs[1], imgs[2], imgs[3], (m['halfWidthM'] as num).toDouble());
      return true;
    } catch (e) {
      debugPrint('map layers unavailable: $e');
      return false;
    }
  }

  /// The 400 m LOLA DEM (custom-site horizons, light map), loaded on first use
  /// (once, even when asked for twice meanwhile; again after a failure). On the
  /// web it is decoded in short slices ([decodeDem]).
  Future<PolarGrid> dem() => _demJob ??= _loadDem().catchError((Object e) {
        _demJob = null;
        throw e;
      });

  Future<PolarGrid>? _demJob;

  Future<PolarGrid> _loadDem() async {
    final m = (jsonDecode(await rootBundle.loadString('assets/data/map/map.json')) as Map<String, dynamic>)['dem'] as Map;
    return decodeDem(await loadAsset(m['file'] as String), m['size'] as int, (m['pxM'] as num).toDouble());
  }

  Future<LightEngine>? _light;

  /// Tests hand in their own shadow engine (a slow fake, say).
  @visibleForTesting
  set lightEngineForTest(LightEngine e) => _light = Future.value(e);

  /// Shadow engine behind the light & shadow map (started on first use; a
  /// failed start, e.g. the DEM fetch going offline, is tried again on the
  /// next call instead of failing for good, async-7).
  Future<LightEngine> lightEngine() {
    final running = _light;
    if (running != null) return running;
    late final Future<LightEngine> job;
    job = dem().then((d) => LightEngine.start(d.heights, d.size, d.scaleM)).catchError((Object e) {
      if (identical(_light, job)) _light = null;
      throw e;
    });
    return _light = job;
  }

  /// Place a custom site: horizon from the 400 m LOLA DEM computed on the device.
  /// A spot outside the DEM's coverage (the outermost edge of the -80° circle)
  /// is refused with [customSiteEdgeText]. True once the spot is added and
  /// selected (the full-screen map hands it back only then); false when it was
  /// refused or failed ([error] says why).
  Future<bool> addCustomSite(double lat, double lon) async {
    placingCustom = true;
    notifyListeners();
    var placed = false;
    try {
      final grid = await dem();
      if (!grid.coversLatLon(lat, lon)) {
        placingCustom = false;
        error = customSiteEdgeText;
        notifyListeners();
        return false;
      }
      final h = computeCoarseHorizon(grid, lat, lon, observerHeightsM: catalog!.heightsM);
      // never reuse a removed spot's id: its cached results are keyed by it
      final n = ++_customSeq;
      final id = 'custom-$n';
      customSites.add(Site(
        id: id,
        name: 'Custom site $n (${lat.toStringAsFixed(3)}°, ${lon.toStringAsFixed(3)}°E)',
        short: 'Custom $n',
        group: 'custom',
        kind: 'custom',
        confidence: 'user-placed',
        notes: 'Horizon computed on this device from the LOLA 400 m DEM (approximate).',
        lat: lat,
        lon: lon,
        terrainHeightM: h.siteHeightM,
        custom: true,
      ));
      _customMasks[id] = h.masks;
      placingCustom = false;
      await selectSite(id);
      placed = true;
      // the new site joins the ranking (the others are cached)
      await _rankAll();
      return true;
    } catch (e) {
      placingCustom = false;
      error = 'Could not place site: $e';
      notifyListeners();
      return placed;
    }
  }

  int _customSeq = 0;

  /// Remove the user-placed site [id]: from the sites, the shortlist and the
  /// caches. When it was selected, the top-ranked remaining site is selected
  /// instead. The other sites keep their (cached) results, so nothing is
  /// re-ranked unless a ranking was still running.
  Future<void> removeCustomSite(String id) async {
    final i = customSites.indexWhere((x) => x.id == id);
    if (i < 0) return;
    customSites.removeAt(i);
    _customMasks.remove(id);
    compareIds = [...compareIds]..remove(id);
    _results.removeWhere((k, _) => k.startsWith('$id|'));
    _series.removeWhere((k, _) => k.startsWith('$id|'));
    _resultsStamp++;
    if (_keepBest == id) _keepBest = null;
    // a failure must never return to a state that shows the removed site
    if (_committed?.selectedId == id) _committed = null;
    if (_good?.selectedId == id) _good = null;
    final rankRunning = !_rankingDone;
    if (rankRunning) {
      _cancelRanking(); // its site list still has the removed site
    } else {
      _rankTotal = allSites.length;
      _rankProgress = _rankTotal;
    }
    if (selectedId == id) {
      final next = rankedAll.firstOrNull?.id ?? catalog!.sites.first.id;
      await _update(() => selectedId = next);
    } else {
      notifyListeners();
    }
    if (rankRunning && _rankingKey != _optionsKey) await _rankAll();
  }

  /// Apply [change] (the controls show it at once), compute the selected
  /// site's series in slices and, when the period, height or rules changed,
  /// re-rank every site in the background (the returned future completes when
  /// that ranking is done or superseded). On failure the last committed state
  /// comes back and [error] says why.
  Future<void> _update(void Function() change) async {
    final gen = ++_updateGen;
    final before = _optionsKey, cursorBefore = cursorMs;
    change();
    options = options.copyWith(stepMs: SeriesOptions.autoStepMs(rangeEndMs - rangeStartMs));
    if (_optionsKey != before) {
      _cancelRanking();
      _cursorBeforeChange ??= cursorBefore;
    }
    if (eph == null || catalog == null) {
      notifyListeners();
      return;
    }
    final key = _cacheKey(selectedId);
    var s = _series[key];
    if (s == null) {
      loading = true;
      notifyListeners();
      try {
        s = await _seriesOf(site, _cfg);
      } catch (e, st) {
        if (gen != _updateGen) return;
        debugPrint('$e\n$st');
        final to = _committed;
        if (to == null) {
          loading = false;
          error = '$e';
          notifyListeners();
          return;
        }
        _restore(to, cursorBefore);
        error = 'These settings could not be worked out, so the previous settings are back. ($e)';
        notifyListeners();
        if (_rankingKey != _optionsKey) await _rankAll();
        return;
      }
      // superseded: a newer change (or a return to the last good state) took over
      if (s == null || gen != _updateGen || key != _cacheKey(selectedId)) return;
    }
    _commit(key, s);
    notifyListeners();
    if (_rankingKey != _optionsKey) await _rankAll();
  }

  Future<void> selectSite(String id) async {
    _userPicked = true;
    if (id == selectedId && series != null) return;
    await _update(() => selectedId = id);
  }

  Future<void> setObserverHeight(double h) => _update(() => observerHeightM = h);

  int _rangeGen = 0;

  /// Analyse [start, end) (clamped to the data, see
  /// [EphemerisManifest.clampPeriod]: a period ending on 31 Dec 2035 ends at
  /// the last hourly sample, 23:00 UTC).
  Future<void> setRange(DateTime start, DateTime end) async {
    final m = manifest!;
    final (t0, t1) = m.clampPeriod(start.millisecondsSinceEpoch.toDouble(), end.millisecondsSinceEpoch.toDouble());
    // the latest request wins, even when an earlier one's ephemeris loads last
    final gen = ++_rangeGen;
    final Ephemeris e;
    try {
      // load first, so the range never changes without an ephemeris that covers it
      e = await repo.range(t0, t1);
    } catch (err) {
      if (gen != _rangeGen) return;
      error = '$err';
      notifyListeners();
      return;
    }
    if (gen != _rangeGen || _disposed) return;
    await _update(() {
      eph = e;
      rangeStartMs = t0;
      rangeEndMs = t1;
      cursorMs = t0;
    });
  }

  Future<void> setSunCriterion(SunCriterion c) => _update(() => options = options.copyWith(sunCriterion: c));
  Future<void> setEarthCriterion(EarthCriterion c) => _update(() => options = options.copyWith(earthCriterion: c));
  Future<void> setRequireDsn(bool v) => _update(() => options = options.copyWith(requireDsn: v));

  void setSkyZoom(bool v) {
    skyZoom = v;
    notifyListeners();
  }

  /// The last cursor position: one step before the (exclusive) period end.
  double get _lastCursorMs => rangeEndMs - options.stepMs;

  /// The last time the cursor can show (Play stops there).
  double get lastCursorMs => _lastCursorMs;

  void setCursor(double tMs) {
    cursorMs = tMs.clamp(rangeStartMs, _lastCursorMs);
    notifyListeners();
  }

  /// Move the cursor to [tMs] and show the selected site on [tab], in one
  /// notification (one web history entry).
  void openAt(double tMs, SiteTab tab) {
    dest = Dest.site;
    siteTab = tab;
    setCursor(tMs);
  }

  /// Play or pause. Play at the end of the period starts again from its
  /// beginning. Playback crosses the whole current period in about 40 s,
  /// except on the Light & shadow map, which plays ten hours per step
  /// ([playStepMs]).
  void togglePlay() {
    if (playing) {
      _stopPlay();
    } else {
      if (cursorMs >= _lastCursorMs - 1e-3) cursorMs = rangeStartMs;
      playing = true;
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    }
    notifyListeners();
  }

  /// How far one playback step (100 ms) moves the cursor: 1/400 of the
  /// period, or at most ten hours while the Light & shadow map is shown, so
  /// its shadows sweep at a readable pace (about 5 degrees of Sun azimuth per
  /// step; a lunar day in about 7 s; user decisions 2026-10-12: smooth,
  /// 2026-10-13: about 10 hours per frame).
  double get playStepMs {
    final step = (rangeEndMs - rangeStartMs) / 400;
    return dest == Dest.site && siteTab == SiteTab.light ? (step < playMapStepMs ? step : playMapStepMs) : step;
  }

  /// The Light & shadow map's playback step: ten hours.
  static const double playMapStepMs = 10 * 3600 * 1000;

  /// One playback step of 1/400 of the period as it is now (it may change
  /// while playing); stops at the end.
  void _tick() {
    final charts = _heldTicks < _maxHeldTicks && (holdPlay?.call() ?? false);
    if (charts || (_heldTicks < _maxMapHeldTicks && (holdPlayForMap?.call() ?? false))) {
      _heldTicks++;
      return; // the charts or the light map are still drawing the previous step
    }
    _heldTicks = 0;
    final last = _lastCursorMs;
    final dt = playStepMs;
    if (cursorMs + dt >= last) {
      cursorMs = last;
      _stopPlay();
      notifyListeners();
    } else {
      setCursor(cursorMs + dt);
    }
  }

  /// Pause Play if it is running (the app left the foreground: nothing
  /// advances unseen, and the time bar shows it paused on return).
  void pausePlay() {
    if (!playing) return;
    _stopPlay();
    notifyListeners();
  }

  void _stopPlay() {
    playing = false;
    _heldTicks = 0;
    _timer?.cancel();
    _timer = null;
  }

  /// Jump to the start of the longest "both available" window.
  void jumpToBestWindow() {
    if (loading) return; // the shown metrics are for the previous choices
    final b = metrics?.longestBoth;
    if (b != null) setCursor(b.startMs);
  }

  // ---- best landing window (docs/ux_landing_window_spec.md, section 7 P2) ----

  /// Surface mission length in whole days for "Find the best landing window".
  int missionDays = defaultMissionDays;

  /// Set the mission length, clamped to 1 .. min(30, whole days in the dates).
  /// An in-card change: when the selected site has a current answer (or a
  /// search under way), the search runs again at once.
  void setMissionDays(int d) {
    final c = rangeEndMs > rangeStartMs ? clampMissionDays(d, rangeStartMs, rangeEndMs) : d.clamp(minMissionDays, maxMissionDays);
    if (c == missionDays) return;
    final rerun = _landingLive(selectedId);
    missionDays = c;
    notifyListeners();
    if (rerun && !_landingLive(selectedId)) unawaited(findLanding());
  }

  /// "More about this site" on Overview, open for the session.
  bool overviewMoreOpen = false;

  void setOverviewMoreOpen(bool v) {
    overviewMoreOpen = v;
    notifyListeners();
  }

  /// More is shown open when the user opened it or expert mode is on.
  bool get overviewMoreShown => overviewMoreOpen || expert;

  /// Answers by key (least recently stored first, trimmed to [_landingKeep])
  /// and each site's latest key.
  final Map<LandingKey, LandingEntry> _landingByKey = {};
  final Map<String, LandingKey> _landingLast = {};
  static const _landingKeep = 48;
  int _landingGen = 0;
  Future<void>? _landingRun;

  /// The earliest landing offered ("now"); tests may pin it.
  @visibleForTesting
  double Function() landingNowMs = () => DateTime.now().millisecondsSinceEpoch.toDouble();

  /// The 'now' the landing search starts from (notBeforeMs).
  double get landingNow => landingNowMs();

  /// Completes when the latest [findLanding] (including one started by
  /// [setMissionDays] or [setGoal]) has finished or was superseded.
  Future<void> get landingSettled => _landingRun ?? Future<void>.value();

  /// The key an answer for [siteId] would have under the current choices.
  LandingKey landingKeyFor(String siteId) => LandingKey(
        siteId: siteId,
        rangeStartMs: rangeStartMs,
        rangeEndMs: rangeEndMs,
        observerHeightM: observerHeightM,
        stepMs: SeriesOptions.autoStepMs(rangeEndMs - rangeStartMs),
        sunCriterion: options.sunCriterion,
        earthCriterion: options.earthCriterion,
        requireDsn: options.requireDsn,
        weightPower: weights.power,
        weightBoth: weights.both,
        missionDays: missionDays,
      );

  /// What the landing card shows for [siteId]: the answer (or search) under
  /// the current choices when there is one; else the site's last current
  /// answer for the same mission length, which is then [landingStale]; else
  /// null (idle). A failed search under older choices is not kept (idle).
  LandingEntry? landingFor(String siteId) {
    final cur = _landingByKey[landingKeyFor(siteId)];
    if (cur != null) {
      _landingLast[siteId] = cur.key; // the one shown last (no notification: nothing changed)
      return cur;
    }
    bool usable(LandingEntry? e) =>
        e != null && e.key.siteId == siteId && e.key.missionDays == missionDays && (e.plan != null || e.busy);
    final last = _landingByKey[_landingLast[siteId]];
    if (usable(last)) return last;
    // the latest stored answer for this site and length
    return _landingByKey.values.toList().reversed.where(usable).firstOrNull;
  }

  /// [landingFor] holds an answer for other choices (dates, height, rules,
  /// DSN or weights changed elsewhere since it was found).
  bool landingStale(String siteId) => landingStaleReason(siteId) != null;

  /// Why [landingFor] is out of date: 'dates' | 'height' | 'rules' | 'dsn' |
  /// 'weights'; null when it is current (or there is none).
  String? landingStaleReason(String siteId) => landingFor(siteId)?.key.staleReason(landingKeyFor(siteId));

  /// The selected site has a current answer or a search under way.
  bool _landingLive(String siteId) {
    final e = _landingByKey[landingKeyFor(siteId)];
    return e != null && (e.plan != null || e.busy);
  }

  void _putLanding(LandingEntry e) {
    _landingByKey.remove(e.key);
    _landingByKey[e.key] = e;
    _landingLast[e.key.siteId] = e.key;
    final latest = _landingLast.values.toSet();
    while (_landingByKey.length > _landingKeep) {
      final old = _landingByKey.keys.where((k) => !latest.contains(k)).firstOrNull;
      if (old == null) break;
      _landingByKey.remove(old);
    }
  }

  /// Find the best landing window for [siteId] (default the selected site)
  /// under the current choices: waits for the site's series, then searches in
  /// slices ([bestLandingWindowSliced], landings from now on). A new call
  /// cancels the one under way. With [next], shows the next full-fit window
  /// after the current answer instead ([nextFullFit]); nothing changes when
  /// there is none (the plan's `nextSpanStartMs` is then null).
  Future<void> findLanding({String? siteId, bool next = false}) {
    final job = next ? _nextLanding(siteId ?? selectedId) : _findLanding(siteId ?? selectedId);
    _landingRun = job;
    return job;
  }

  Future<void> _findLanding(String id) async {
    final gen = ++_landingGen;
    final key = landingKeyFor(id);
    final w = key.weights;
    final prevForKey = _landingByKey[key], prevLast = _landingLast[id];
    var busy = LandingEntry(key, busy: true);
    _putLanding(busy);
    notifyListeners();
    bool superseded() => _disposed || gen != _landingGen;
    bool mine() => identical(_landingByKey[key], busy);
    // a cancelled search puts back what was there before it
    void dropBusy() {
      if (!mine()) return;
      _landingByKey.remove(key);
      if (prevForKey != null) _landingByKey[key] = prevForKey;
      if (prevLast != null) {
        _landingLast[id] = prevLast;
      } else if (_landingLast[id] == key && prevForKey == null) {
        _landingLast.remove(id);
      }
      notifyListeners();
    }

    try {
      if (eph == null || catalog == null) throw StateError('the Sun and Earth positions are not loaded');
      var s = seriesFor(id);
      if (s == null) {
        s = await _seriesOf(siteById(id), _cfg);
        if (superseded()) return dropBusy();
        if (s == null || landingKeyFor(id) != key) {
          // the choices changed while the series was worked out: search under the new ones
          dropBusy();
          return _findLanding(id);
        }
      }
      final clock = Stopwatch()..start();
      final plan = await bestLandingWindowSliced(s, key.missionDays, w,
          notBeforeMs: landingNowMs(), budget: sliceBudget, cancelled: superseded, onProgress: (p) {
        if (!mine() || p <= busy.progress) return;
        busy = busy._withProgress(p);
        _landingByKey[key] = busy;
        if (clock.elapsedMilliseconds >= 50) {
          clock.reset();
          notifyListeners();
        }
      });
      if (plan == null || superseded()) return dropBusy();
      if (!mine()) return;
      _putLanding(LandingEntry(key, plan: plan));
    } catch (e, st) {
      if (superseded()) return dropBusy();
      debugPrint('landing window: $e\n$st');
      if (mine()) _putLanding(LandingEntry(key, error: e));
    }
    notifyListeners();
  }

  Future<void> _nextLanding(String id) async {
    final e = landingFor(id);
    final p = e?.plan;
    if (e == null || p == null || landingStale(id) || p.nextSpanStartMs == null) return;
    final key = e.key;
    var s = seriesFor(id);
    if (s == null) {
      try {
        s = await _seriesOf(siteById(id), _cfg);
      } catch (err) {
        debugPrint('next landing window: $err');
        return;
      }
      if (s == null || _disposed || landingKeyFor(id) != key || !identical(_landingByKey[key], e)) return;
    }
    final n = nextFullFit(s, p, key.weights);
    if (n == null) return;
    _putLanding(LandingEntry(key, plan: n, windowNumber: e.windowNumber + 1));
    notifyListeners();
  }

  /// Back to idle for [siteId] (default the selected site) under the current
  /// choices: cancels a search under way and forgets the current answer.
  void resetLanding([String? siteId]) {
    final id = siteId ?? selectedId;
    final key = landingKeyFor(id);
    if (_landingByKey[key]?.busy ?? false) _landingGen++;
    _landingByKey.remove(key);
    // also drop the answers kept for this site under other choices (another
    // period after "Use these dates" and Undo, say): landingFor falls back to
    // them, so 'Change' would show an out-of-date answer instead of idle
    _landingByKey.removeWhere((k, e) => k.siteId == id && !e.busy);
    _landingLast.remove(id);
    notifyListeners();
  }

  /// The period before the last [useLandingDates], for [undoLandingDates].
  ({double startMs, double endMs})? _undoRange;

  /// [undoLandingDates] has a period to go back to.
  bool get canUndoLandingDates => _undoRange != null;

  /// "Use these dates": set the period to the selected site's answer
  /// ([landingDatesRange], clamped to the ephemeris coverage), wait for the
  /// new series (a finer step), search again and return whether the answer
  /// is still a full fit. False (and nothing changes) without a current
  /// answer, or when the new period could not be loaded.
  Future<bool> useLandingDates() async {
    final id = selectedId;
    final p = landingFor(id)?.plan;
    final m = manifest;
    if (p == null || p.suggested == null || p.spanStartMs == null || landingStale(id) || m == null) return false;
    final before = (startMs: rangeStartMs, endMs: rangeEndMs);
    final r = landingDatesRange(p);
    final (t0, t1) = m.clampPeriod(r.startMs, r.endMs);
    if (!await _applyRange(t0, t1)) return false;
    _undoRange = before;
    notifyListeners();
    await findLanding(siteId: id);
    return landingFor(id)?.plan?.isFullFit ?? false;
  }

  /// Undo [useLandingDates]: the previous period comes back, and with it the
  /// answer found for it (answers are kept per key).
  Future<void> undoLandingDates() async {
    final r = _undoRange;
    if (r == null) return;
    _undoRange = null;
    await _applyRange(r.startMs, r.endMs);
  }

  /// Load the ephemeris for [t0, t1) (already clamped) and apply the period
  /// (as [setRange] does); returns once the period has changed, without
  /// waiting for the series or the ranking that follow. False when a newer
  /// period request took over or the load failed ([error] says why).
  Future<bool> _applyRange(double t0, double t1) async {
    final gen = ++_rangeGen;
    final Ephemeris e;
    try {
      e = await repo.range(t0, t1);
    } catch (err) {
      if (gen != _rangeGen) return false;
      error = '$err';
      notifyListeners();
      return false;
    }
    if (gen != _rangeGen || _disposed) return false;
    unawaited(_update(() {
      eph = e;
      rangeStartMs = t0;
      rangeEndMs = t1;
      cursorMs = t0;
    }));
    return true;
  }

  /// LOLA AVGVISIB cross-check of the ridge and peak points (sunlit share,
  /// mean and max absolute difference in points), from validation.json; null
  /// until loaded or when it is missing.
  ({double mean, double max})? get ridgePeakSunlitDiff => _ridgePeak;
  ({double mean, double max})? _ridgePeak;

  Future<void> _loadValidation() async {
    try {
      final v = jsonDecode(await rootBundle.loadString('assets/data/validation.json')) as Map<String, dynamic>;
      final r = (v['avgvis'] as Map?)?['ridgePeakPoints'] as Map?;
      final mean = r?['meanAbsDiffSunPct'], max = r?['maxAbsDiffSunPct'];
      if (mean is num && max is num) _ridgePeak = (mean: mean.toDouble(), max: max.toDouble());
    } catch (e) {
      debugPrint('validation numbers unavailable: $e');
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rankGen++;
    _updateGen++;
    _stopPlay();
    // a failed start has nothing to dispose (and must not raise an unhandled error)
    _light?.then((e) => e.dispose(), onError: (Object _) {});
    super.dispose();
  }
}
