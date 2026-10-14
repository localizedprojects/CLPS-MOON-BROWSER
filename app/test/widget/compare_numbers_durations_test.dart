// charts-2: the Compare "All numbers" table printed durations rounded up
// ("7.0 days", "21.0 days") and without the edge "+", disagreeing with the
// chart above it ("6 d 23 h", "20 d 23 h"). It now uses the chart's format.
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/metrics.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';

Interval _h(double hours, {bool start = false, bool end = false}) =>
    Interval(0, hours * 3600e3, truncatedStart: start, truncatedEnd: end);

void main() {
  test('floored like the chart, never rounded up', () {
    expect(CompareNumbers.spellText(_h(167.5)), '6 d 23 h'); // MP1 longest night
    expect(CompareNumbers.spellText(_h(260.5)), '10 d 20 h'); // SR1
    expect(CompareNumbers.spellText(_h(503.5)), '20 d 23 h'); // Haworth, was "21.0 days"
    expect(CompareNumbers.spellText(_h(168)), '7 d');
    expect(CompareNumbers.spellText(_h(9.5)), '9 h 30 min');
  });

  test('a spell at the edge of the period gets the chart\'s "+"', () {
    expect(CompareNumbers.spellText(_h(167.5, end: true)), '6 d 23 h+');
    expect(CompareNumbers.spellText(_h(167.5, start: true)), '6 d 23 h+');
  });

  test('no spell reads "none"', () {
    expect(CompareNumbers.spellText(null), 'none');
    expect(CompareNumbers.spellText(_h(0)), 'none');
  });
}
