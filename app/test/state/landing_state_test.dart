// AppState wiring of "Find the best landing window"
// (docs/ux_landing_window_spec.md, section 7 P2): the mission length and its
// clamp, the More disclosure, searches (fresh, re-run, cancelled, next),
// staleness per option, "Use these dates" with Undo, and the validation
// numbers for the FidelityBadge. Real bundled data, one AppState.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/landing.dart';
import 'package:polar_horizon/core/ranking.dart';
import 'package:polar_horizon/core/score.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/state/app_state.dart';

const mp1 = 'derosa2012-mp1-malapert-peak';
const haworth = 'artemis3-haworth';

void expectSamePlan(LandingPlan a, LandingPlan b) {
  expect(a.status, b.status);
  expect(a.missionDays, b.missionDays);
  expect(a.candidates, b.candidates);
  expect(a.spanStartMs, b.spanStartMs);
  expect(a.spanEndMs, b.spanEndMs);
  expect(a.suggested?.startIndex, b.suggested?.startIndex);
  expect(a.suggested?.score.total, b.suggested?.score.total);
  expect(a.nextSpanStartMs, b.nextSpanStartMs);
  expect(a.longestBothRunDays, b.longestBothRunDays);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState s;
  late double nowMs;

  setUpAll(() async {
    s = AppState();
    await s.init();
    expect(s.error, isNull);
    nowMs = s.rangeStartMs + 3.3 * 3600e3; // pinned "now", a little into the period
    s.landingNowMs = () => nowMs;
    await s.openSite(mp1);
  });

  tearDownAll(() => s.dispose());

  test('defaults: 14 days, More closed, idle, validation numbers loaded', () {
    expect(s.missionDays, defaultMissionDays);
    expect(s.missionDays, 14);
    expect(s.overviewMoreOpen, isFalse);
    expect(s.landingFor(mp1), isNull);
    expect(s.landingStale(mp1), isFalse);
    expect(s.landingStaleReason(mp1), isNull);
    final v = jsonDecode(File('assets/data/validation.json').readAsStringSync()) as Map<String, dynamic>;
    final r = (v['avgvis'] as Map)['ridgePeakPoints'] as Map;
    expect(s.ridgePeakSunlitDiff, isNotNull);
    expect(s.ridgePeakSunlitDiff!.mean, (r['meanAbsDiffSunPct'] as num).toDouble());
    expect(s.ridgePeakSunlitDiff!.max, (r['maxAbsDiffSunPct'] as num).toDouble());
  });

  test('More about this site: opened by the user or shown by expert mode', () {
    var notes = 0;
    void l() => notes++;
    s.addListener(l);
    s.setOverviewMoreOpen(true);
    expect(s.overviewMoreOpen, isTrue);
    expect(s.overviewMoreShown, isTrue);
    s.setOverviewMoreOpen(false);
    expect(s.overviewMoreShown, isFalse);
    s.setExpert(true);
    expect(s.overviewMoreShown, isTrue);
    expect(s.overviewMoreOpen, isFalse);
    s.setExpert(false);
    s.removeListener(l);
    expect(notes, 4);
  });

  test('setMissionDays clamps to 1..30 (and to the dates; see "Use these dates")', () {
    s.setMissionDays(0);
    expect(s.missionDays, 1);
    s.setMissionDays(-5);
    expect(s.missionDays, 1);
    s.setMissionDays(45);
    expect(s.missionDays, maxMissionDays);
    s.setMissionDays(21);
    expect(s.missionDays, 21);
    s.setMissionDays(14);
    expect(s.missionDays, 14);
    expect(s.landingFor(mp1), isNull, reason: 'no answer yet, so nothing re-runs');
  });

  test('findLanding: busy at once, then the same plan as the core function, current and keyed', () async {
    final job = s.findLanding();
    final busy = s.landingFor(mp1)!;
    expect(busy.busy, isTrue);
    expect(busy.plan, isNull);
    expect(busy.key, s.landingKeyFor(mp1));
    await job;
    final e = s.landingFor(mp1)!;
    expect(e.busy, isFalse);
    expect(e.error, isNull);
    expect(e.windowNumber, 1);
    expect(s.landingStale(mp1), isFalse);
    final want = bestLandingWindow(s.seriesFor(mp1)!, 14, s.weights, notBeforeMs: nowMs);
    expectSamePlan(e.plan!, want);
    expect(e.plan!.status, LandingStatus.fullFit, reason: 'MP1 at 14 d and 2 m is a full fit (27 h span)');
    // landings before "now" are never offered
    expect(e.plan!.spanStartMs!, greaterThanOrEqualTo(nowMs));
    expect(e.key.missionDays, 14);
    expect(e.key.stepMs, s.options.stepMs);
    expect(e.key.weightPower, s.weights.power);
  });

  test('a stale answer under other choices: one reason per option, and it comes back current when undone', () async {
    final e = s.landingFor(mp1)!;
    expect(e.plan, isNotNull);
    Future<void> check(Future<void> Function() change, String reason, Future<void> Function() undo) async {
      final job = change();
      expect(s.landingStale(mp1), isTrue, reason: reason);
      expect(s.landingStaleReason(mp1), reason);
      expect(s.landingFor(mp1), same(e), reason: 'the old answer is kept and marked, not re-run');
      await job;
      await s.landingSettled;
      expect(s.landingFor(mp1), same(e), reason: '$reason: a change elsewhere never re-runs');
      await undo();
      expect(s.landingStale(mp1), isFalse, reason: 'back to the choices of $reason');
      expect(s.landingFor(mp1), same(e));
    }

    await check(() => s.setObserverHeight(10), 'height', () => s.setObserverHeight(2));
    await check(() => s.setSunCriterion(SunCriterion.center), 'rules', () => s.setSunCriterion(SunCriterion.upperLimb));
    await check(() => s.setEarthCriterion(EarthCriterion.anyPart), 'rules', () => s.setEarthCriterion(EarthCriterion.center));
    await check(() => s.setRequireDsn(true), 'dsn', () => s.setRequireDsn(false));
    await check(() async => s.setWeights(const ScoreWeights(power: 0.35, both: 0.1)), 'weights',
        () async => s.setGoal(Goal.balanced));
    // the dates: the ephemeris loads first, so the period changes after the await
    final t0 = s.rangeStartMs, t1 = s.rangeEndMs;
    DateTime utc(double ms) => DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
    await s.setRange(utc(t0), utc(t1 + 86400e3));
    expect(s.landingStaleReason(mp1), 'dates');
    expect(s.landingFor(mp1), same(e));
    await s.setRange(utc(t0), utc(t1));
    expect(s.rangeStartMs, t0);
    expect(s.rangeEndMs, t1);
    expect(s.landingStale(mp1), isFalse);
    expect(s.landingFor(mp1), same(e));
  });

  test('the reasons come in a fixed order (dates, height, rules, dsn, weights)', () {
    final k = s.landingKeyFor(mp1);
    LandingKey with_({double? start, double? h, SunCriterion? sun, bool? dsn, double? wp}) => LandingKey(
          siteId: k.siteId,
          rangeStartMs: start ?? k.rangeStartMs,
          rangeEndMs: k.rangeEndMs,
          observerHeightM: h ?? k.observerHeightM,
          stepMs: k.stepMs,
          sunCriterion: sun ?? k.sunCriterion,
          earthCriterion: k.earthCriterion,
          requireDsn: dsn ?? k.requireDsn,
          weightPower: wp ?? k.weightPower,
          weightBoth: k.weightBoth,
          missionDays: k.missionDays,
        );
    expect(with_(start: 0, h: 10, sun: SunCriterion.center, dsn: true, wp: 0.9).staleReason(k), 'dates');
    expect(with_(h: 10, sun: SunCriterion.center, dsn: true, wp: 0.9).staleReason(k), 'height');
    expect(with_(sun: SunCriterion.center, dsn: true, wp: 0.9).staleReason(k), 'rules');
    expect(with_(dsn: !k.requireDsn, wp: 0.9).staleReason(k), 'dsn');
    expect(with_(wp: 0.9).staleReason(k), 'weights');
    expect(with_().staleReason(k), isNull);
    expect(with_(), k);
    expect(with_().hashCode, k.hashCode);
  });

  test('in-card changes re-run at once: the goal and the mission length', () async {
    final balanced = s.landingFor(mp1)!;
    s.setGoal(Goal.power);
    expect(s.landingFor(mp1)!.busy, isTrue);
    await s.landingSettled;
    final power = s.landingFor(mp1)!;
    expect(power.key.weightPower, weightsFor(Goal.power).power);
    expect(s.landingStale(mp1), isFalse);
    expectSamePlan(power.plan!, bestLandingWindow(s.seriesFor(mp1)!, 14, weightsFor(Goal.power), notBeforeMs: nowMs));
    // back to Balanced: its answer is still kept under its key
    s.setGoal(Goal.balanced);
    expect(s.landingFor(mp1), same(balanced));

    s.setMissionDays(7);
    expect(s.landingFor(mp1)!.busy, isTrue);
    expect(s.landingFor(mp1)!.key.missionDays, 7);
    await s.landingSettled;
    final seven = s.landingFor(mp1)!;
    expect(seven.plan!.missionDays, 7);
    expectSamePlan(seven.plan!, bestLandingWindow(s.seriesFor(mp1)!, 7, s.weights, notBeforeMs: nowMs));
    s.setMissionDays(14);
    expect(s.landingFor(mp1), same(balanced));
  });

  test('a changed length with no current answer shows idle, never an answer for another length', () async {
    await s.setObserverHeight(10); // the 14-day answer is now stale
    expect(s.landingStaleReason(mp1), 'height');
    s.setMissionDays(10); // no re-run: the answer was not current
    expect(s.landingFor(mp1), isNull);
    expect(s.landingStale(mp1), isFalse);
    s.setMissionDays(14);
    expect(s.landingStaleReason(mp1), 'height');
    await s.setObserverHeight(2);
    expect(s.landingStale(mp1), isFalse);
  });

  test('"Next window that fits" moves to the next run, a new Find returns to the earliest', () async {
    final first = s.landingFor(mp1)!;
    final p = first.plan!;
    expect(p.isFullFit, isTrue);
    if (p.nextSpanStartMs == null) {
      await s.findLanding(next: true);
      expect(s.landingFor(mp1), same(first), reason: 'nothing later: the answer stays');
      return;
    }
    await s.findLanding(next: true);
    final second = s.landingFor(mp1)!;
    expect(second.windowNumber, 2);
    expect(second.plan!.spanStartMs, p.nextSpanStartMs);
    expect(second.plan!.spanStartMs!, greaterThan(p.spanEndMs!));
    expect(second.plan!.candidates, p.candidates);
    expect(s.landingStale(mp1), isFalse);
    // a third, if there is one
    if (second.plan!.nextSpanStartMs != null) {
      await s.findLanding(next: true);
      expect(s.landingFor(mp1)!.windowNumber, 3);
    }
    await s.findLanding();
    expect(s.landingFor(mp1)!.windowNumber, 1);
    expectSamePlan(s.landingFor(mp1)!.plan!, p);
  });

  test('a new search cancels the one under way (which leaves no trace)', () async {
    expect(s.landingFor(haworth), isNull);
    final a = s.findLanding(siteId: haworth);
    expect(s.landingFor(haworth)!.busy, isTrue);
    final b = s.findLanding(); // the selected site
    await Future.wait([a, b]);
    expect(s.landingFor(haworth), isNull, reason: 'the cancelled search puts back what was there (nothing)');
    expect(s.landingFor(mp1)!.plan, isNotNull);
    // a search for another site, run to the end
    await s.findLanding(siteId: haworth);
    expect(s.landingFor(haworth)!.plan!.missionDays, 14);
    expect(s.landingStale(haworth), isFalse);
  });

  test('an unknown site gives an error entry, and resetLanding goes back to idle', () async {
    await s.findLanding(siteId: 'no-such-site');
    final e = s.landingFor('no-such-site')!;
    expect(e.error, isNotNull);
    expect(e.plan, isNull);
    expect(e.busy, isFalse);
    s.resetLanding('no-such-site');
    expect(s.landingFor('no-such-site'), isNull);
    s.resetLanding(haworth);
    expect(s.landingFor(haworth), isNull);
  });

  test('"Use these dates" sets the answer\'s period at a finer step, re-runs, and Undo restores', () async {
    expect(s.canUndoLandingDates, isFalse);
    final before = s.landingFor(mp1)!;
    final p = before.plan!;
    final t0 = s.rangeStartMs, t1 = s.rangeEndMs;
    final r = landingDatesRange(p);
    final (w0, w1) = s.manifest!.clampPeriod(r.startMs, r.endMs);

    final stillFits = await s.useLandingDates();
    expect(s.rangeStartMs, w0);
    expect(s.rangeEndMs, w1);
    expect(s.options.stepMs, 600e3, reason: 'the step becomes 10 min');
    expect(s.canUndoLandingDates, isTrue);
    final now = s.landingFor(mp1)!;
    expect(now, isNot(same(before)));
    expect(now.busy, isFalse);
    expect(s.landingStale(mp1), isFalse);
    expect(now.key.stepMs, 600e3);
    expect(stillFits, now.plan!.isFullFit);
    // the new answer sits inside the new period, near the old one
    expect(now.plan!.suggested!.startMs, greaterThanOrEqualTo(w0));
    expect(now.plan!.suggested!.endMs, lessThanOrEqualTo(w1));
    // the mission length is now clamped to the short period too
    s.setMissionDays(30);
    expect(s.missionDays, missionDaysLimit(w0, w1));
    expect(s.missionDays, lessThan(30));
    s.setMissionDays(14);
    await s.landingSettled;
    expect(s.missionDays, 14);

    await s.undoLandingDates();
    expect(s.canUndoLandingDates, isFalse);
    expect(s.rangeStartMs, t0);
    expect(s.rangeEndMs, t1);
    expect(s.options.stepMs, SeriesOptions.autoStepMs(t1 - t0));
    expect(s.landingFor(mp1), same(before), reason: 'the answer for the old dates comes back');
    expect(s.landingStale(mp1), isFalse);
    // let the series and ranking for the restored period finish before dispose
    while (s.loading || !s.rankingDone) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // "Change" goes idle: the answer kept for the other period is dropped
    // too, not shown as an out-of-date answer
    s.resetLanding(mp1);
    expect(s.landingFor(mp1), isNull);
  });

  test('useLandingDates does nothing without a current answer', () async {
    await s.selectSite(haworth);
    expect(s.landingFor(haworth), isNull);
    final t0 = s.rangeStartMs;
    expect(await s.useLandingDates(), isFalse);
    expect(s.rangeStartMs, t0);
    expect(s.canUndoLandingDates, isFalse);
  });
}
