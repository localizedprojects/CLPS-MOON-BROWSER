// Fix 4 (2026-10-29): a new period keeps the time shown when it is still
// inside it; otherwise the time goes to the nearer end, never back to the
// start by default.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/state/app_state.dart';

double _utc(int y, int m, int d, [int h = 0, int min = 0]) => DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch.toDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cursorForPeriod', () {
    final t0 = _utc(2027, 6, 1), t1 = _utc(2027, 7, 1); // 30 days: 10-min steps

    test('a time inside the new period stays where it is', () {
      final c = _utc(2027, 6, 15, 13, 37);
      expect(AppState.cursorForPeriod(c, t0, t1), c);
      expect(AppState.cursorForPeriod(t0, t0, t1), t0);
    });

    test('a time before the period goes to its start', () {
      expect(AppState.cursorForPeriod(_utc(2027, 5, 2), t0, t1), t0);
    });

    test('a time after the period goes to its last sample, not the start', () {
      expect(AppState.cursorForPeriod(_utc(2027, 9, 1), t0, t1), t1 - 600e3);
      expect(AppState.cursorForPeriod(t1, t0, t1), t1 - 600e3, reason: 'the end is exclusive');
      // a year: 30-min steps
      final y1 = _utc(2028, 6, 1);
      expect(AppState.cursorForPeriod(_utc(2029, 1, 1), t0, y1), y1 - 1800e3);
    });

    test('a period shorter than one step keeps its start', () {
      final end = t0 + 300e3;
      expect(AppState.cursorForPeriod(_utc(2027, 9, 1), t0, end), t0);
    });
  });

  group('changing the period', () {
    late AppState s;
    setUpAll(() async {
      s = AppState();
      await s.init();
    });
    tearDownAll(() => s.dispose());

    test('keeps the time shown when it is still inside, else the nearer end', () async {
      await s.setRange(DateTime.utc(2027, 1, 1), DateTime.utc(2028, 1, 1));
      final c = _utc(2027, 6, 15, 13, 30);
      s.setCursor(c);

      // a shorter period around it: the time stays
      await s.setRange(DateTime.utc(2027, 6, 1), DateTime.utc(2027, 7, 1));
      expect(s.error, isNull);
      expect((s.rangeStartMs, s.rangeEndMs), (_utc(2027, 6, 1), _utc(2027, 7, 1)));
      expect(s.cursorMs, c);

      // a later period: its start is the nearer end
      await s.setRange(DateTime.utc(2027, 7, 1), DateTime.utc(2027, 8, 1));
      expect(s.cursorMs, _utc(2027, 7, 1));

      // an earlier period: its last sample (10-min steps), not its start
      s.setCursor(_utc(2027, 7, 20));
      await s.setRange(DateTime.utc(2027, 6, 1), DateTime.utc(2027, 7, 1));
      expect(s.options.stepMs, 600e3);
      expect(s.cursorMs, _utc(2027, 6, 30, 23, 50));

      // back to a longer period that holds it: kept
      await s.setRange(DateTime.utc(2027, 1, 1), DateTime.utc(2028, 1, 1));
      expect(s.cursorMs, _utc(2027, 6, 30, 23, 50));
    });
  });
}
