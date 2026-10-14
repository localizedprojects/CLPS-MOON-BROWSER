/// Per-site Sun/Earth visibility time series over a date range.
///
/// For every sample: topocentric az/el of Sun and Earth (SPICE-derived
/// ephemeris + site parallax), the terrain horizon at those azimuths, the
/// visible disk fractions, the power proxy, the DSN mask and the resulting
/// availability flags under the chosen criteria.
library;

import 'dart:typed_data';

import 'constants.dart';
import 'ephemeris.dart';
import 'geo.dart';
import 'horizon.dart';
import 'visibility.dart';

/// Visibility flags per sample.
const int flagSun = 1; // power available
const int flagEarth = 2; // direct-to-Earth comms available
const int flagBoth = 4; // both at once

class SeriesOptions {
  final double stepMs;
  final SunCriterion sunCriterion;
  final EarthCriterion earthCriterion;

  /// Also require a DSN complex to see the Moon (>= 10 deg) for comms. The DSN
  /// state is precomputed hourly and held at the nearest hourly sample (see
  /// [Ephemeris.dsnMask]), so at 10 and 30 min steps station rise and set times
  /// are accurate to about ±30 min ([dsnResolutionNote] labels this).
  final bool requireDsn;

  const SeriesOptions({
    this.stepMs = 3600e3,
    this.sunCriterion = SunCriterion.upperLimb,
    this.earthCriterion = EarthCriterion.center,
    this.requireDsn = false,
  });

  /// Step used for a range: 10 min up to 60 days, 30 min up to 1 year, else 1 h.
  static double autoStepMs(double rangeMs) {
    const day = 86400e3;
    if (rangeMs <= 60 * day) return 600e3;
    if (rangeMs <= 366 * day) return 1800e3;
    return 3600e3;
  }

  SeriesOptions copyWith({double? stepMs, SunCriterion? sunCriterion, EarthCriterion? earthCriterion, bool? requireDsn}) =>
      SeriesOptions(
        stepMs: stepMs ?? this.stepMs,
        sunCriterion: sunCriterion ?? this.sunCriterion,
        earthCriterion: earthCriterion ?? this.earthCriterion,
        requireDsn: requireDsn ?? this.requireDsn,
      );
}

class SiteSeries {
  final double t0Ms, stepMs;
  final int n;
  final Float64List sunAz, sunEl, sunHz, sunFrac, earthAz, earthEl, earthHz, earthFrac, power;
  final Uint8List dsn, flags;

  /// Allocate an all-zero series of [n] samples (also used by tests).
  SiteSeries.alloc(this.t0Ms, this.stepMs, this.n)
      : sunAz = Float64List(n),
        sunEl = Float64List(n),
        sunHz = Float64List(n),
        sunFrac = Float64List(n),
        earthAz = Float64List(n),
        earthEl = Float64List(n),
        earthHz = Float64List(n),
        earthFrac = Float64List(n),
        power = Float64List(n),
        dsn = Uint8List(n),
        flags = Uint8List(n);

  double timeAt(int i) => t0Ms + i * stepMs;

  /// Index of the sample nearest to [tMs] (clamped).
  int indexAt(double tMs) => ((tMs - t0Ms) / stepMs).round().clamp(0, n - 1);
}

/// Number of samples of a series over [t0Ms, t1Ms) at [stepMs] (at least 1).
int seriesLength(double t0Ms, double t1Ms, double stepMs) => ((t1Ms - t0Ms) / stepMs).floor().clamp(1, 1 << 24);

/// Compute the series for [obs] with horizon [mask] over [t0Ms, t1Ms).
SiteSeries computeSeries(Ephemeris eph, Observer obs, HorizonMask mask, double t0Ms, double t1Ms, SeriesOptions o) {
  final s = SiteSeries.alloc(t0Ms, o.stepMs, seriesLength(t0Ms, t1Ms, o.stepMs));
  fillSeries(s, eph, obs, mask, o, 0, s.n);
  return s;
}

/// [computeSeries] in slices, yielding to the event loop between them so a
/// long series (an 11-year hourly series is ~96k samples) never blocks frames
/// or taps for more than about [budget] plus one slice of [chunk] samples.
///
/// Every sample is computed by the same code as [computeSeries], so the
/// result is bit-identical. [cancelled] is checked after every yield; when it
/// returns true the computation stops and the future completes with null.
/// [yieldNow] defaults to a zero-length timer (a macrotask, so a frame can
/// render in between). A series that takes less than [budget] completes
/// without yielding.
Future<SiteSeries?> computeSeriesSliced(
  Ephemeris eph,
  Observer obs,
  HorizonMask mask,
  double t0Ms,
  double t1Ms,
  SeriesOptions o, {
  Duration budget = const Duration(milliseconds: 20),
  int chunk = 256,
  bool Function()? cancelled,
  Future<void> Function()? yieldNow,
}) async {
  final s = SiteSeries.alloc(t0Ms, o.stepMs, seriesLength(t0Ms, t1Ms, o.stepMs));
  final pause = yieldNow ?? () => Future<void>.delayed(Duration.zero);
  final sw = Stopwatch()..start();
  for (var i = 0; i < s.n;) {
    final end = i + chunk < s.n ? i + chunk : s.n;
    fillSeries(s, eph, obs, mask, o, i, end);
    i = end;
    if (i < s.n && sw.elapsed >= budget) {
      await pause();
      if (cancelled?.call() ?? false) return null;
      sw.reset();
    }
  }
  return s;
}

/// Compute samples [from, to) of [s] (its t0 and step) in place.
void fillSeries(SiteSeries s, Ephemeris eph, Observer obs, HorizonMask mask, SeriesOptions o, int from, int to) {
  final t0Ms = s.t0Ms;
  for (var i = from; i < to; i++) {
    final t = t0Ms + i * o.stepMs;
    final sun = obs.look(eph.sun(t));
    final earth = obs.look(eph.earth(t));
    final rs = angularRadiusDeg(sunRadiusKm, sun.range);
    final re = angularRadiusDeg(earthRadiusKm, earth.range);
    final sHz = mask.at(sun.az), eHz = mask.at(earth.az);
    final fs = visibleFraction(sun.az, sun.el, rs, mask);
    final fe = visibleFraction(earth.az, earth.el, re, mask);
    final dsn = eph.dsnMask(t);
    s.sunAz[i] = sun.az;
    s.sunEl[i] = sun.el;
    s.sunHz[i] = sHz;
    s.sunFrac[i] = fs;
    s.earthAz[i] = earth.az;
    s.earthEl[i] = earth.el;
    s.earthHz[i] = eHz;
    s.earthFrac[i] = fe;
    s.power[i] = powerProxy(fs, sun.range);
    s.dsn[i] = dsn;
    final sv = sunVisible(o.sunCriterion, fs, sun.el, sHz);
    var ev = earthVisible(o.earthCriterion, fe, earth.el, eHz);
    if (o.requireDsn && dsn == 0) ev = false;
    s.flags[i] = (sv ? flagSun : 0) | (ev ? flagEarth : 0) | (sv && ev ? flagBoth : 0);
  }
}
