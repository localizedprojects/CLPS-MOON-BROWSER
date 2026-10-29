import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/visibility.dart';
import 'package:polar_horizon/core/wording.dart';

Site _site({String group = 'artemis', String kind = 'region-center-approx', double slope = 4.5, bool custom = false}) =>
    Site(
      id: 'x',
      name: 'Site X',
      short: 'X',
      group: group,
      kind: kind,
      confidence: '',
      notes: '',
      lat: -89.5,
      lon: 0,
      terrainHeightM: 0,
      slopeDeg: slope,
      custom: custom,
    );

void main() {
  test('inTen edges', () {
    final cases = {
      0.0: 'almost never',
      4.4: 'almost never',
      4.5: 'about 1 hour in 10', // shown as 5%
      5.0: 'about 1 hour in 10',
      14.4: 'about 1 hour in 10',
      14.5: 'about 2 hours in 10', // shown as 15%
      15.0: 'about 2 hours in 10',
      44.6: 'about 5 hours in 10', // shown as 45% (ux1-11: was "about 4")
      50.0: 'about 5 hours in 10',
      80.0: 'about 8 hours in 10',
      94.4: 'about 9 hours in 10',
      94.5: 'almost always', // shown as 95%
      95.0: 'almost always',
      100.0: 'almost always',
    };
    cases.forEach((pct, text) => expect(inTen(pct), text, reason: '$pct%'));
    expect(inTen(double.nan), 'not known');
    // the phrase follows the whole percent shown beside it: n hours in 10 = round(shown% / 10)
    for (var t = 0; t <= 1000; t++) {
      final pct = t / 10, shown = pct.round();
      if (shown < 5 || shown >= 95) continue;
      final n = (shown / 10).round();
      expect(inTen(pct), contains('about $n '), reason: '$pct% shown as $shown%');
    }
  });

  test('siteKindLabel per group', () {
    expect(siteKindLabel(_site(group: 'artemis')), 'Artemis III candidate region');
    expect(siteKindLabel(_site(group: 'illumination')), 'Well-lit point from research');
    expect(siteKindLabel(_site(group: 'missions')), 'Mission landing site');
    expect(siteKindLabel(_site(group: 'custom', kind: 'custom', custom: true)), 'Your custom spot');
    expect(siteKindLabel(_site(group: 'custom', kind: 'custom')), 'Your custom spot');
    expect(siteKindLabel(_site(group: 'other', kind: 'exact-point')), 'exact-point');
  });

  group('periodLabel', () {
    const day = 86400e3;
    final now = DateTime.utc(2026, 10, 10, 15, 42);
    final today = DateTime.utc(2026, 10, 10).millisecondsSinceEpoch.toDouble();

    test('the default period is "Next 12 months"', () {
      expect(periodLabel(today, today + 365 * day, now), 'Next 12 months');
      // a day of slack on the length either way
      expect(periodLabel(today, today + 364 * day, now), 'Next 12 months');
      expect(periodLabel(today, today + 366 * day, now), 'Next 12 months');
      // any start time within today's UTC day
      expect(periodLabel(today + 15 * 3600e3, today + 15 * 3600e3 + 365 * day, now), 'Next 12 months');
      // a non-UTC "now" is converted first
      expect(periodLabel(today, today + 365 * day, now.toLocal()), 'Next 12 months');
    });

    test('anything else shows the first and the last day', () {
      expect(periodLabel(today, today + 363 * day, now), '10 Oct 2026 – 7 Oct 2027');
      expect(periodLabel(today, today + 367 * day, now), '10 Oct 2026 – 11 Oct 2027');
      expect(periodLabel(today + day, today + 366 * day, now), '11 Oct 2026 – 10 Oct 2027');
      expect(periodLabel(today - 1, today + 365 * day, now), '9 Oct 2026 – 9 Oct 2027');
      expect(periodLabel(today, today + 30 * day, now), '10 Oct 2026 – 8 Nov 2026');
    });
  });

  group('periodDates', () {
    const day = 86400e3;
    final jan1 = DateTime.utc(2027).millisecondsSinceEpoch.toDouble();

    test('the end is exclusive: 1-31 Jan ends at midnight on 1 Feb', () {
      expect(periodDates(jan1, jan1 + 31 * day), '1 Jan 2027 – 31 Jan 2027');
      expect(periodDates(jan1, jan1 + day), '1 Jan 2027 – 1 Jan 2027');
    });

    test('an end inside a day shows that day', () {
      expect(periodDates(jan1, jan1 + 30 * day + 15 * 3600e3), '1 Jan 2027 – 31 Jan 2027');
    });
  });

  group('sun status', () {
    test('a lunar eclipse: only a total cover "hides" the Sun; a partial one gives Earth\'s share (1..99%)', () {
      expect(eclipseHidesText(1), 'Earth hides the Sun (lunar eclipse)');
      const tail = '% of the Sun (lunar eclipse), so it is not counted as sunlit under your Sun rule';
      expect(eclipseHidesText(0.002), 'Earth covers 1$tail');
      expect(eclipseHidesText(0.48), 'Earth covers 48$tail');
      expect(eclipseHidesText(0.998), 'Earth covers 99$tail');
      expect([eclipseSharePct(0.001), eclipseSharePct(0.404), eclipseSharePct(0.996), eclipseSharePct(1)], [1, 40, 99, 100]);
    });

    test('visible', () {
      expect(sunStatusText(visible: true, elDeg: 1.2, rhoDeg: 0.27, frac: 1), 'in full sunlight');
      expect(sunStatusText(visible: true, elDeg: 1.2, rhoDeg: 0.27, frac: 0.9995), 'in full sunlight');
      expect(sunStatusText(visible: true, elDeg: 0.4, rhoDeg: 0.27, frac: 0.62),
          'partly lit (62% of the Sun\'s disk above the skyline)');
      expect(sunStatusText(visible: true, elDeg: 0.4, rhoDeg: 0.27, frac: 0.003),
          'partly lit (1% of the Sun\'s disk above the skyline)');
      expect(sunStatusText(visible: true, elDeg: 0.4, rhoDeg: 0.27, frac: 0.997),
          'partly lit (99% of the Sun\'s disk above the skyline)');
    });
    test('not visible', () {
      expect(sunStatusText(visible: false, elDeg: 0.5, rhoDeg: 0.27, frac: 0), 'Sun hidden behind terrain');
      expect(sunStatusText(visible: false, elDeg: -0.2, rhoDeg: 0.27, frac: 0), 'Sun hidden behind terrain');
      expect(sunStatusText(visible: false, elDeg: -0.3, rhoDeg: 0.27, frac: 0), 'Sun below the horizon');
    });

    // science-1: under 'Whole disk' or 'Disk centre' a Sun that is partly up
    // but not counted must not read as hidden
    test('part of the disk up but not counted under a stricter rule', () {
      // Malapert peak (MP1), 17 Oct 2026 05:30 UTC, whole-disk rule
      expect(sunStatusText(visible: false, elDeg: 0.129, rhoDeg: 0.268, frac: 0.976, sunRule: SunCriterion.fullDisk),
          'Sun mostly above the skyline (98% of its disk), but not counted as sunlit under the whole-disk rule');
      // MP1, 17 Oct 2026 11:00 UTC, disk-centre rule (centre 0.320° vs skyline 0.330°)
      expect(sunStatusText(visible: false, elDeg: 0.320, rhoDeg: 0.268, frac: 0.478, sunRule: SunCriterion.center),
          'Sun partly above the skyline (48% of its disk), but its centre is below the skyline, '
          'so it is not counted as sunlit under the disk-centre rule');
      expect(sunStatusText(visible: false, elDeg: 0.2, rhoDeg: 0.268, frac: 0.004, sunRule: SunCriterion.fullDisk),
          'Sun partly above the skyline (1% of its disk), but not counted as sunlit under the whole-disk rule');
    });

    test('never "hidden" or "below" while part of the disk is up, under any rule', () {
      for (final rule in SunCriterion.values) {
        for (final frac in [0.001, 0.3, 0.5, 0.9, 0.998]) {
          final t = sunStatusText(visible: false, elDeg: -0.1, rhoDeg: 0.27, frac: frac, sunRule: rule);
          expect(t, isNot(anyOf(contains('hidden'), contains('below the horizon'))), reason: '$rule $frac');
          expect(t, contains('above the skyline'));
        }
        // with none of the disk up the stricter rules read as before
        expect(sunStatusText(visible: false, elDeg: 0.5, rhoDeg: 0.27, frac: 0, sunRule: rule), 'Sun hidden behind terrain');
        expect(sunStatusText(visible: false, elDeg: -0.3, rhoDeg: 0.27, frac: 0, sunRule: rule), 'Sun below the horizon');
        expect(sunStatusText(visible: true, elDeg: 1, rhoDeg: 0.27, frac: 1, sunRule: rule), 'in full sunlight');
      }
    });
  });

  group('earth status', () {
    test('every branch', () {
      expect(earthStatusText(visible: true, elDeg: 3, rhoDeg: 0.95, frac: 1, dsnRequired: true), 'Earth in view');
      expect(earthStatusText(visible: true, elDeg: 3, rhoDeg: 0.95, frac: 0.62, dsnRequired: false),
          'Earth in view (62% of its disk above the skyline)');
      // the whole disk is up, so its centre is too: the DSN is the only obstacle
      expect(earthStatusText(visible: false, elDeg: 3, rhoDeg: 0.95, frac: 1, dsnRequired: true),
          'Earth in view but no DSN station can see the Moon');
      expect(earthStatusText(visible: false, elDeg: 3, rhoDeg: 0.95, frac: 0, dsnRequired: false),
          'Earth hidden behind terrain');
      expect(earthStatusText(visible: false, elDeg: 3, rhoDeg: 0.95, frac: 0, dsnRequired: true),
          'Earth hidden behind terrain');
      expect(earthStatusText(visible: false, elDeg: -1, rhoDeg: 0.95, frac: 0, dsnRequired: true),
          'Earth below the horizon');
      expect(earthStatusText(visible: false, elDeg: -0.9, rhoDeg: 0.95, frac: 0, dsnRequired: false),
          'Earth hidden behind terrain');
    });

    // science-2 / formula.md caveat 13: the terrain comes first; the DSN is
    // blamed only when Earth would count as in view without it
    test('a partly risen Earth with its centre hidden is not "in view", even when no DSN station is up', () {
      // Haworth, 24 Jun 2027 23:30 UTC: centre 5.757° under the skyline at 5.896°, 41% of the disk up, no DSN
      expect(
          earthStatusText(
              visible: false, elDeg: 5.757, rhoDeg: 0.95, frac: 0.406, dsnRequired: true, dsnInView: false, hzDeg: 5.896),
          'Earth partly above the skyline (41% of its disk), but its centre is below the skyline, so it is not counted '
          'as in view under the Earth-centre rule (and no DSN station can see the Moon)');
      // same moment without the DSN rule
      expect(earthStatusText(visible: false, elDeg: 5.757, rhoDeg: 0.95, frac: 0.406, dsnRequired: false, hzDeg: 5.896),
          'Earth partly above the skyline (41% of its disk), but its centre is below the skyline, so it is not counted '
          'as in view under the Earth-centre rule');
      // centre above the skyline: only the DSN is missing
      expect(
          earthStatusText(
              visible: false, elDeg: 6.2, rhoDeg: 0.95, frac: 0.71, dsnRequired: true, dsnInView: false, hzDeg: 5.896),
          'Earth in view but no DSN station can see the Moon');
    });

    test('a known DSN state is used when given', () {
      // a DSN station is up, so the terrain hides the centre
      expect(earthStatusText(visible: false, elDeg: 3, rhoDeg: 0.95, frac: 0.4, dsnRequired: true, dsnInView: true),
          'Earth partly above the skyline (40% of its disk), but its centre is below the skyline, so it is not counted '
          'as in view under the Earth-centre rule');
      // without the skyline height the centre rule cannot tell: no claim that Earth is in view
      final t = earthStatusText(visible: false, elDeg: 3, rhoDeg: 0.95, frac: 0.4, dsnRequired: true, dsnInView: false);
      expect(t, 'Earth partly above the skyline (40% of its disk), but no DSN station can see the Moon');
      expect(t, isNot(contains('in view')));
    });

    test('any-part rule: part of the disk up counts, so only the DSN can be missing', () {
      expect(
          earthStatusText(
              visible: false, elDeg: -0.5, rhoDeg: 0.95, frac: 0.2, dsnRequired: true, dsnInView: false,
              earthRule: EarthCriterion.anyPart),
          'Earth in view but no DSN station can see the Moon');
      expect(
          earthStatusText(visible: false, elDeg: -1, rhoDeg: 0.95, frac: 0, dsnRequired: true, earthRule: EarthCriterion.anyPart),
          'Earth below the horizon');
    });
  });

  // science-3: with the DSN rule the Earth metric is Earth contact
  test('Earth metric labels follow the DSN rule', () {
    expect(earthMetricLabel(requireDsn: false), 'Earth in view');
    expect(earthMetricLabel(requireDsn: true), 'Earth contact (DSN)');
    expect(earthOutageLabel(requireDsn: false), 'Longest time without Earth');
    expect(earthOutageLabel(requireDsn: true), 'Longest time without Earth contact');
    expect(dsnResolutionNote, contains('±30 min'));
  });

  test('slopeText', () {
    expect(slopeText(_site(slope: 4.5)), '4.5° slope');
    expect(slopeText(_site(slope: 11.46)), '11.5° slope');
    expect(slopeText(_site(slope: double.nan, group: 'custom', kind: 'custom', custom: true)),
        'slope not computed for custom spots');
    expect(slopeText(_site(slope: double.nan)), 'slope not available');
  });

  // The same table as charts/src/format.test.ts (DURATION_TABLE): keep the two in sync.
  test('fmtDuration follows the shared duration table (charts spec 2.0)', () {
    const m = 60e3, h = 3600e3, d = 86400e3;
    final table = <(double, double?, String)>[
      (0, null, '0 min'),
      (30 * m, null, '30 min'),
      (30 * m, 30, 'about 30 min'), // exactly one sample step
      (10 * m, 10, 'about 10 min'),
      (60 * m, 30, '1 h'), // two steps: not "about"
      (59 * m + 59e3, null, '59 min'), // floored, never "1 h"
      (9 * h + 30 * m, null, '9 h 30 min'),
      (9 * h, null, '9 h'), // "0 min" dropped
      (23 * h + 59 * m, null, '23 h 59 min'),
      (d, null, '1 d'),
      (10 * d + 21 * h, null, '10 d 21 h'),
      (10 * d + 21 * h + 59 * m, null, '10 d 21 h'), // floored, never 10 d 22 h
      (10 * d, null, '10 d'), // "0 h" dropped
      (5 * d + 16 * h + 30 * m, null, '5 d 16 h'), // never rounded up to 5 d 17 h
      (102 * d + 1 * h, null, '102 d 1 h'),
    ];
    for (final (ms, step, text) in table) {
      expect(fmtDuration(ms, stepMin: step), text, reason: '$ms ms');
    }
    expect(fmtDuration(10 * d + 21 * h + 59 * m, coarse: true), '10 d');
    expect(fmtDuration(9 * h + 59 * m, coarse: true), '9 h');
    expect(fmtDuration(double.nan), '–');
  });

  test('bodyStateShort gives the six shared state words, by the status-text rules', () {
    String st({bool visible = false, double el = 1, double rho = 0.27, double frac = 0, bool? terrain}) =>
        bodyStateShort(visible: visible, elDeg: el, rhoDeg: rho, frac: frac, terrainVisible: terrain);
    expect(st(visible: true, frac: 1), 'up');
    expect(st(visible: true, frac: 0.51), 'partly');
    expect(st(frac: 0.51), 'notCounted');
    expect(st(el: -0.2, frac: 0), 'behindHills'); // el + rho >= 0, nothing clears the hills
    expect(st(el: -5.83, rho: 0.94, frac: 0, terrain: false), 'belowHorizon'); // SR1 Earth, 11 Oct 2026
    expect(st(visible: false, frac: 1, terrain: true), 'noDsn');
    // agrees with the long sentences
    expect(sunStatusText(visible: false, elDeg: -0.2, rhoDeg: 0.27, frac: 0), 'Sun hidden behind terrain');
    expect(sunStatusText(visible: false, elDeg: -1, rhoDeg: 0.27, frac: 0), 'Sun below the horizon');
    expect(st(el: -1, frac: 0), 'belowHorizon');
    expect(
        earthStatusText(visible: false, elDeg: 3, rhoDeg: 0.94, frac: 1, dsnRequired: true, dsnInView: false, hzDeg: 0),
        'Earth in view but no DSN station can see the Moon');
  });
}
