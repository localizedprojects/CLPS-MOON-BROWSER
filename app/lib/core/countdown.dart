/// Time left before sunset or Earthset (or until sunrise or Earthrise) at
/// the time shown, and how high the Sun stands: the default status line.
///
/// The next change comes from the site's series (its flags already follow
/// the user's Sun and Earth rules, the DSN rule and lunar eclipses), so it is
/// the same change the timeline shows, to one sample step (10 min to 1 h).
/// A change after the last sample is "beyond your dates", never a guess.
library;

import 'timeseries.dart';
import 'wording.dart' show fmtDuration;

/// The next change of one body's state after the time shown.
class NextChange {
  /// When the new state starts (the first sample in it, Unix ms); null when
  /// the state lasts to the end of the chosen dates.
  final double? atMs;

  /// [atMs] minus the time shown (ms); 0 when [atMs] is null.
  final double inMs;

  /// Sun only: the change is Earth's disk starting or stopping to hide the
  /// Sun (a lunar eclipse seen from the Moon), not the Sun crossing the skyline.
  final bool byEclipse;

  const NextChange(this.atMs, this.inMs, {this.byEclipse = false});
  const NextChange.beyond()
      : atMs = null,
        inMs = 0,
        byEclipse = false;
  bool get beyondPeriod => atMs == null;
}

/// The next change of `s.flags & flag` after [tMs]: the first sample after
/// [tMs] whose state differs from [now] (the state at [tMs]; by default the
/// series state at the sample under [tMs], as the timeline reads it). Passing
/// the exact state keeps the countdown in step with an exact status line when
/// the time shown lies between samples.
NextChange nextChange(SiteSeries s, int flag, double tMs, {bool? now}) {
  if (s.n == 0) return const NextChange.beyond();
  final i = ((tMs - s.t0Ms) / s.stepMs).floor();
  bool on(int k) => (s.flags[k] & flag) != 0;
  final v = now ?? (i >= 0 && i < s.n && on(i));
  for (var j = i + 1 < 0 ? 0 : i + 1; j < s.n; j++) {
    if (on(j) == v) continue;
    // the eclipse is the cause when Earth covers part of the Sun on the dark side of the change
    final dark = v ? j : j - 1;
    final ecl = flag == flagSun && dark >= 0 && s.sunEclipse[dark] > 0;
    return NextChange(s.timeAt(j), s.timeAt(j) - tMs, byEclipse: ecl);
  }
  return const NextChange.beyond();
}

/// The Sun and Earth state at the time shown, as the status line knows it
/// (exact, from the ephemeris), for [countdownAt].
class CountdownNow {
  final bool sunUp, earthUp;

  /// Sun disk centre elevation above the horizontal and the skyline elevation at its azimuth (deg).
  final double sunElDeg, sunHzDeg;

  /// Share of the Sun's whole disk behind Earth (0..1).
  final double eclipse;

  /// The Sun would count from the terrain alone, but Earth hides it.
  final bool eclipseHides;

  /// Power proxy (W/m², Sun-facing panel); null when not given.
  final double? power;
  const CountdownNow({
    required this.sunUp,
    required this.earthUp,
    required this.sunElDeg,
    required this.sunHzDeg,
    this.eclipse = 0,
    this.eclipseHides = false,
    this.power,
  });
}

/// The status line's facts at the time shown.
class Countdown {
  final bool sunUp, earthUp;
  final double sunElDeg;

  /// Sun disk centre above the skyline (deg; negative below it).
  final double sunClearDeg;
  final double eclipse;
  final bool eclipseHides;
  final double? power;
  final NextChange sun, earth;
  const Countdown({
    required this.sunUp,
    required this.earthUp,
    required this.sunElDeg,
    required this.sunClearDeg,
    required this.sun,
    required this.earth,
    this.eclipse = 0,
    this.eclipseHides = false,
    this.power,
  });
}

/// The countdown at [tMs] from series [s]. With [now] (the exact state), the
/// Sun numbers and states are [now]'s; without it they come from the series:
/// elevation and skyline interpolated between the two samples around [tMs],
/// states from the sample under it, and Earth taken to hide the Sun when the
/// Sun is not counted while partly eclipsed with its centre above the skyline.
Countdown countdownAt(SiteSeries s, double tMs, {CountdownNow? now}) {
  final n = now ?? _fromSeries(s, tMs);
  return Countdown(
    sunUp: n.sunUp,
    earthUp: n.earthUp,
    sunElDeg: n.sunElDeg,
    sunClearDeg: n.sunElDeg - n.sunHzDeg,
    eclipse: n.eclipse,
    eclipseHides: n.eclipseHides,
    power: n.power,
    sun: nextChange(s, flagSun, tMs, now: n.sunUp),
    earth: nextChange(s, flagEarth, tMs, now: n.earthUp),
  );
}

CountdownNow _fromSeries(SiteSeries s, double tMs) {
  final x = ((tMs - s.t0Ms) / s.stepMs).clamp(0.0, (s.n - 1).toDouble());
  final a = x.floor(), b = a + 1 < s.n ? a + 1 : a, w = x - a;
  double lerp(List<double> v) => v[a] + (v[b] - v[a]) * w;
  final el = lerp(s.sunEl), hz = lerp(s.sunHz);
  final sunUp = (s.flags[a] & flagSun) != 0, ecl = s.sunEclipse[a];
  return CountdownNow(
    sunUp: sunUp,
    earthUp: (s.flags[a] & flagEarth) != 0,
    sunElDeg: el,
    sunHzDeg: hz,
    eclipse: ecl,
    eclipseHides: !sunUp && ecl > 0 && el > hz,
    power: s.power[a],
  );
}

String _deg(double v) => '${v.abs().toStringAsFixed(1)}°';

/// The status line: "Sun 1.2° up (0.6° above the hills) · sunset in 3 d 4 h
/// (21 Oct 18:00 UTC) · Earthset in 11 h". [dateOf] writes a time (the
/// status line's own date format). With [requireDsn] Earth's half is about
/// Earth contact. [power] adds the power proxy ("Show exact numbers").
String countdownLine(Countdown c, {required String Function(double ms) dateOf, bool requireDsn = false, bool power = false}) {
  String inT(NextChange n) => 'in ${fmtDuration(n.inMs)} (${dateOf(n.atMs!)})';
  final String head, sunNext;
  if (c.eclipseHides) {
    head = 'Earth hides the Sun (lunar eclipse)';
    sunNext = c.sun.beyondPeriod ? 'until after your dates' : 'ends ${inT(c.sun)}';
  } else {
    final where = c.sunElDeg >= 0 ? '${_deg(c.sunElDeg)} up' : '${_deg(c.sunElDeg)} below the horizon';
    final hills = '${_deg(c.sunClearDeg)} ${c.sunClearDeg >= 0 ? 'above' : 'below'} the hills';
    final pct = (100 * c.eclipse).round().clamp(1, 99);
    final covered = c.eclipse > 0 ? ', Earth covers $pct% of it (lunar eclipse)' : '';
    head = 'Sun $where ($hills)$covered';
    if (c.sunUp) {
      sunNext = c.sun.beyondPeriod
          ? 'no sunset in your dates'
          : c.sun.byEclipse
              ? 'Earth hides the Sun ${inT(c.sun)}'
              : 'sunset ${inT(c.sun)}';
    } else {
      sunNext = c.sun.beyondPeriod ? 'no sunrise in your dates' : 'sunrise ${inT(c.sun)}';
    }
  }
  final e = c.earth;
  final String earthNext;
  if (requireDsn) {
    earthNext = c.earthUp
        ? (e.beyondPeriod ? 'Earth contact lasts past your dates' : 'Earth contact ends in ${fmtDuration(e.inMs)}')
        : (e.beyondPeriod ? 'no Earth contact in your dates' : 'Earth contact in ${fmtDuration(e.inMs)}');
  } else {
    earthNext = c.earthUp
        ? (e.beyondPeriod ? 'no Earthset in your dates' : 'Earthset in ${fmtDuration(e.inMs)}')
        : (e.beyondPeriod ? 'no Earthrise in your dates' : 'Earthrise in ${fmtDuration(e.inMs)}');
  }
  final p = power && c.power != null ? ' · ${c.power!.round()} W/m² on a Sun-facing panel (proxy)' : '';
  return '$head · $sunNext · $earthNext$p';
}

const _months = {
  'Jan': 'January', 'Feb': 'February', 'Mar': 'March', 'Apr': 'April', 'May': 'May', 'Jun': 'June',
  'Jul': 'July', 'Aug': 'August', 'Sep': 'September', 'Oct': 'October', 'Nov': 'November', 'Dec': 'December',
};
const _units = {'°': 'degree', 'd': 'day', 'h': 'hour', 'min': 'minute'};

/// A status line for a screen reader, without abbreviations: "3 d 4 h" is
/// "3 days 4 hours", "1.2°" is "1.2 degrees", "Oct" is "October",
/// "W/m²" is "watts per square metre" and " · " a comma.
String spokenCountdown(String line) => line
    .replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)[ \u00A0]?(°|d|h|min)(?![A-Za-z])'), (m) {
      final v = m[1]!, u = _units[m[2]]!;
      return '$v $u${v == '1' ? '' : 's'}';
    })
    .replaceAll('W/m²', 'watts per square metre')
    .replaceAllMapped(RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b'), (m) => _months[m[1]]!)
    .replaceAll(' · ', ', ');
