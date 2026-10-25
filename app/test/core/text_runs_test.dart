import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/text_runs.dart';

/// The number runs of [s], in order.
List<String> _numbers(String s) => [for (final r in numberRuns(s)) if (r.number) r.text];

void main() {
  test('runs join back to the input and alternate', () {
    for (final s in [
      '',
      'no digits here',
      '6.8 km from the pole · elevation 1,733 m · 4.5° slope',
      'Longest night over your dates: 10 d 21 h, from 12 Sep 2027 20:30 UTC.',
      'IM-2 Athena landed 570 m from SR1.',
    ]) {
      final runs = numberRuns(s);
      expect(runs.map((r) => r.text).join(), s);
      for (var i = 1; i < runs.length; i++) {
        expect(runs[i].number && runs[i - 1].number && !runs[i].text.startsWith(' '), isFalse,
            reason: 'two number runs touch in "$s"');
        expect(!runs[i].number && !runs[i - 1].number, isFalse, reason: 'text runs are merged in "$s"');
      }
    }
    expect(numberRuns(''), isEmpty);
    expect(numberRuns('Artemis III'), [const TextRun('Artemis III', false)]);
  });

  test('signed decimals, percents and units', () {
    expect(_numbers('(−89.78°, −156.45°E)'), ['−89.78°', '−156.45°E']);
    expect(_numbers('lat -89.78° here'), ['-89.78°']);
    expect(_numbers('Sun and Earth together 62% of the time'), ['62%']);
    expect(_numbers('elevation 1,733 m'), ['1,733 m']);
    expect(_numbers('elevation -176 m'), ['-176 m']);
    expect(_numbers('6.8 km from the pole'), ['6.8 km']);
    expect(_numbers('1361 W/m² or 2.5 kWh/m² at 40 K'), ['1361 W/m²', '2.5 kWh/m²', '40 K']);
    expect(_numbers('Over 18.6 years at 2 m:'), ['18.6', '2 m']);
  });

  test('durations, dates and times are single runs', () {
    expect(_numbers('Longest night: 10 d 21 h, from 12 Sep 2027 20:30 UTC.'),
        ['10 d 21 h', '12 Sep 2027 20:30 UTC']);
    expect(_numbers('for up to 3 d+ at a time'), ['3 d+']);
    expect(_numbers('5 h 30 min or 45 min'), ['5 h 30 min', '45 min']);
    expect(_numbers('on 20 October 2026 at 14:05 UTC'), ['20 October 2026', '14:05 UTC']);
    expect(_numbers('In January 2024'), ['2024']);
  });

  test('15 × 15 km and ranges', () {
    expect(_numbers('about 15 × 15 km'), ['15', '15 km']);
    expect(_numbers('1–2 sentences, 10-20 km'), ['1', '2', '10', '20 km']);
  });

  test('ordinals are numbers', () {
    expect(_numbers('2nd of 17 for Balanced'), ['2nd', '17']);
    expect(_numbers('joint 3rd of 16 catalogue sites'), ['3rd', '16']);
  });

  test('names with digits stay as text', () {
    for (final s in [
      'IM-2',
      'IM-1 Odysseus',
      'SR1',
      'Connecting ridge (CR1)',
      'de Gerlache Rim 2',
      'Nobile Rim 1.',
      'Artemis III',
      'LDEM_80S',
      'SR12',
      'Apollo 17',
    ]) {
      expect(_numbers(s), isEmpty, reason: s);
    }
    expect(numberRuns('Against SR1 (6.8 km away): Sun 62% here'), const [
      TextRun('Against SR1 (', false),
      TextRun('6.8 km', true),
      TextRun(' away): Sun ', false),
      TextRun('62%', true),
      TextRun(' here', false),
    ]);
  });

  test('a unit needs a word boundary after it', () {
    expect(_numbers('2 months and 3 days'), ['2', '3']);
    expect(_numbers('5 mm'), ['5']);
  });
}
