// The loading bar under the start scene (user request 2026-10-14): it looks
// like real loading (bursts and holds) but never runs ahead of the real work,
// is full only when the app is ready, ranked and the minimum time has passed,
// and is full before the ending starts.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/screens/intro.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/theme.dart';

/// An app state whose loading progress the test sets by hand.
class _Progress extends AppState {
  bool r = false, rd = false;
  int d = 0, n = 0;
  @override
  bool get ready => r;
  @override
  bool get rankingDone => rd;
  @override
  int get rankProgress => d;
  @override
  int get rankTotal => n;
  void set({int? done, int? total, bool? ranked, bool? isReady}) {
    d = done ?? d;
    n = total ?? n;
    rd = ranked ?? rd;
    r = isReady ?? r;
    notifyListeners();
  }

  void fail(String? e) {
    error = e;
    notifyListeners();
  }

  double get work => loadingWork(ready: r, rankingDone: rd, done: d, total: n);
}

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
          builder: (c) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion), child: Scaffold(body: child))),
    );

bool _rm = false;
Widget _hostRm(Widget child) => _host(child, reduceMotion: _rm);

double _bar(WidgetTester t) => t.widget<LoadingBar>(find.byType(LoadingBar)).value.value;

void main() {
  test('the pace has holds and bursts, rises steadily and is full only at the end', () {
    var last = 0.0;
    for (var i = 0; i <= 1000; i++) {
      final p = loadingPace(i / 1000);
      expect(p, greaterThanOrEqualTo(last));
      if (i < 1000) expect(p, lessThan(1));
      last = p;
    }
    expect(loadingPace(1), 1);
    // not a straight line: a hold moves far less than a burst of the same length
    expect(loadingPace(0.18) - loadingPace(0.12), lessThan(0.05));
    expect(loadingPace(0.30) - loadingPace(0.24), greaterThan(0.05));
  });

  test('the real work: nothing before the ranking, the share ranked, full only when ready', () {
    expect(loadingWork(ready: false, rankingDone: false, done: 0, total: 0), 0);
    expect(loadingWork(ready: false, rankingDone: false, done: 0, total: 16), 0.2);
    expect(loadingWork(ready: false, rankingDone: false, done: 3, total: 16), closeTo(0.2 + 0.75 * 3 / 16, 1e-12));
    expect(loadingWork(ready: false, rankingDone: true, done: 16, total: 16), 0.95);
    expect(loadingWork(ready: true, rankingDone: true, done: 16, total: 16), 1);
  });

  testWidgets('the bar never runs ahead of the work, even after the minimum time', (tester) async {
    final s = _Progress()..set(done: 3, total: 16);
    addTearDown(s.dispose);
    var done = false;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => done = true)));
    final cap = loadingWork(ready: false, rankingDone: false, done: 3, total: 16);
    var last = 0.0;
    for (var i = 0; i < 280; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final v = _bar(tester);
      expect(v, lessThanOrEqualTo(cap + 1e-9));
      expect(v, greaterThanOrEqualTo(last), reason: 'never backwards');
      last = v;
    }
    expect(last, closeTo(cap, 1e-9), reason: 'it catches up with the work');
    expect(done, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a whole run: steady, full only when ready, ranked and the time is up, full before the end',
      (tester) async {
    final s = _Progress(); // the data is still loading: no ranking yet
    addTearDown(s.dispose);
    final semantics = tester.ensureSemantics();
    double? atDone;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => atDone = _bar(tester))));
    var last = 0.0, ms = 0, fullAt = -1;
    while (atDone == null && ms < 16000) {
      await tester.pump(const Duration(milliseconds: 50));
      ms += 50;
      final v = atDone ?? _bar(tester);
      if (atDone == null) {
        // never ahead of the work in effect, nor of the pace for the time gone
        expect(v, lessThanOrEqualTo(s.work + 1e-9), reason: 'at ${ms}ms');
        if (ms < 10000) expect(v, lessThanOrEqualTo(loadingPace(ms / 10000) + 1e-9), reason: 'at ${ms}ms');
        if (ms < 1000) expect(v, 0, reason: 'nothing before the ranking starts');
      }
      expect(v, greaterThanOrEqualTo(last), reason: 'never backwards');
      if (ms <= 10000) expect(v, lessThan(1), reason: 'not full before the minimum time');
      if (ms == 1000) s.set(done: 0, total: 16);
      if (ms == 2000) s.set(done: 8);
      if (ms == 4000) s.set(done: 16, ranked: true, isReady: true); // ready long before the minimum
      if (v >= 1 && fullAt < 0) fullAt = ms;
      last = v;
    }
    expect(atDone, 1, reason: 'full before the scene hands over');
    expect(fullAt, greaterThan(10000));
    expect(ms - fullAt, greaterThanOrEqualTo(1600), reason: 'full before the ending (1.6 s) starts');
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('percent'), findsNothing, reason: 'no numbers on screen, only for screen readers');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a slow device: ready only at 14 s, the bar waits for it', (tester) async {
    final s = _Progress()..set(done: 0, total: 16);
    addTearDown(s.dispose);
    var doneAt = -1, ms = 0;
    var last = 0.0;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => doneAt = ms)));
    while (doneAt < 0 && ms < 20000) {
      await tester.pump(const Duration(milliseconds: 50));
      ms += 50;
      final v = _bar(tester);
      expect(v, greaterThanOrEqualTo(last));
      if (doneAt < 0) expect(v, lessThanOrEqualTo(s.work + 1e-9), reason: 'at ${ms}ms');
      if (ms < 14000) expect(v, lessThanOrEqualTo(0.95 + 1e-9));
      last = v;
      if (ms == 12000) s.set(done: 16, ranked: true); // ranked, but not yet ready
      if (ms == 14000) s.set(isReady: true);
    }
    expect(doneAt, greaterThan(14000));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching reduce motion on and off mid-run keeps the bar sane and still ends', (tester) async {
    final s = _Progress()..set(done: 8, total: 16);
    addTearDown(s.dispose);
    var done = false;
    final scene = SpaceLoading(state: s, onDone: () => done = true);
    _rm = false;
    await tester.pumpWidget(_hostRm(scene));
    var last = 0.0, ms = 0;
    while (!done && ms < 20000) {
      await tester.pump(const Duration(milliseconds: 50));
      ms += 50;
      final v = _bar(tester);
      expect(v.isFinite, isTrue, reason: 'at ${ms}ms');
      expect(v, greaterThanOrEqualTo(last), reason: 'never backwards');
      last = v;
      if (ms == 3000 || ms == 4000) {
        _rm = ms == 3000;
        await tester.pumpWidget(_hostRm(scene));
      }
      if (ms == 5000) s.set(done: 16, ranked: true, isReady: true);
    }
    expect(done, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed load: the bar stops, says so, and Try again is offered', (tester) async {
    final s = _Progress()..set(done: 4, total: 16);
    addTearDown(s.dispose);
    final semantics = tester.ensureSemantics();
    var done = false;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => done = true)));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    s.fail('Could not rank the sites: boom');
    await tester.pump();
    final stuck = _bar(tester);
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_bar(tester), stuck, reason: 'it does not move');
    }
    final node = tester.getSemantics(find.byType(LoadingBar));
    expect(node.label, 'Loading stopped');
    expect(node.value, isEmpty);
    expect(find.text("Couldn't load the sites."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(48));
    expect(done, isFalse);
    // the retry clears the error and starts the work over: so does the bar
    s.fail(null);
    s.set(done: 0, total: 16);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_bar(tester), lessThanOrEqualTo(s.work + 1e-9));
    expect(find.text('Try again'), findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('screen readers hear the bar as a loading indicator with its value', (tester) async {
    final s = _Progress()..set(done: 8, total: 16);
    addTearDown(s.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () {})));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final node = tester.getSemantics(find.byType(LoadingBar));
    expect(node.label, 'Loading');
    expect(node.value, '${loadingSpoken(_bar(tester))} percent');
    expect(loadingSpoken(0.479), 40, reason: 'in 10% steps, so it is not re-announced every frame');
    expect(loadingSpoken(1), 100);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce motion: the bar simply follows the pace and the work, then on', (tester) async {
    final s = _Progress()..set(done: 16, total: 16, ranked: true, isReady: true);
    addTearDown(s.dispose);
    var done = false;
    await tester.pumpWidget(_host(SpaceLoading(state: s, onDone: () => done = true), reduceMotion: true));
    await tester.pump(const Duration(seconds: 5));
    expect(_bar(tester), closeTo(loadingPace(0.5), 1e-9), reason: 'no glide: exactly where it may be');
    expect(done, isFalse);
    s.set(done: 16); // a state change mid-way keeps it where it is
    expect(_bar(tester), closeTo(loadingPace(0.5), 1e-9));
    await tester.pump(const Duration(seconds: 5));
    expect(done, isTrue);
    expect(_bar(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });
}
