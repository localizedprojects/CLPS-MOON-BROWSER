/// Plain-language summaries generated from metrics (no hand-written claims).
library;

import 'package:intl/intl.dart';

import 'metrics.dart';
import 'score.dart';
import 'wording.dart' show fmtDuration;

final _d = DateFormat('d MMM yyyy');
final _dt = DateFormat('d MMM yyyy HH:mm');

String date(double ms) => _d.format(DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true));
String dateTime(double ms) => '${_dt.format(DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true))} UTC';

/// A length of time in the app's one duration format ([fmtDuration], the
/// charts' `fmtDur`): floored, never rounded up, so a 503.5 h night reads
/// "20 d 23 h" here and in the timeline chart, never "21.0 days".
String duration(double hours) => fmtDuration(hours * 3600e3);

/// [duration] of a spell, with "+" when it runs past the start or end of the
/// period (it may be longer in reality), as the charts and Compare print it.
String spellDuration(Interval i) => '${duration(i.hours)}${i.truncatedStart || i.truncatedEnd ? '+' : ''}';

String _qualifiers(Interval i) =>
    '${i.truncatedStart ? ' (already under way at the start of the period)' : ''}'
    '${i.truncatedEnd ? ' (still continuing at the end of the period)' : ''}';

/// "13 d starting 12 Sep 2027 20:30 UTC" (+ truncation qualifiers).
String _window(Interval i) => '${duration(i.hours)} starting ${dateTime(i.startMs)}${_qualifiers(i)}';

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Sentences describing one site over the analysed period.
///
/// With [dsn] (the "Require a DSN station in view" setting) the Earth flags
/// mean Earth contact: Earth in view AND a DSN station able to see the Moon,
/// so the Earth sentence talks about contact, not about Earth being in view.
List<String> siteSummary(String name, SiteMetrics m, {bool dsn = false}) {
  final out = <String>[];
  final sun = m.longestSun, both = m.longestBoth, dark = m.longestDark, outage = m.longestEarthOutage;
  out.add(sun == null
      ? '$name never sees the Sun in this period.'
      : '$name has ${duration(sun.hours)} of continuous sunlight starting ${dateTime(sun.startMs)}${_qualifiers(sun)}, '
          'and is sunlit ${m.pctSunlit.toStringAsFixed(0)}% of the time overall.');
  out.add(both == null
      ? 'The Sun and Earth are never above the horizon together, so there is no window with both power and direct-to-Earth contact.'
      : 'The best window with both power and direct-to-Earth contact lasts ${_window(both)}; '
          'Sun and Earth overlap ${m.pctBoth.toStringAsFixed(0)}% of the time in ${_plural(m.bothWindowCount, 'window', 'separate windows')}.');
  if (dark != null) {
    out.add('The longest stretch without sunlight lasts ${spellDuration(dark)}, from ${dateTime(dark.startMs)}.');
  }
  final pctEarth = m.pctEarth.toStringAsFixed(0);
  if (dsn) {
    out.add(outage != null
        ? 'Earth contact (Earth in view and a DSN station able to see the Moon) is unavailable for up to '
            '${spellDuration(outage)} at a time (available $pctEarth% of the time).'
        : 'Earth contact (Earth in view and a DSN station able to see the Moon) is available for the whole period.');
  } else if (outage != null) {
    out.add('Earth is out of view for up to ${spellDuration(outage)} at a time (it is visible $pctEarth% of the time).');
  } else {
    out.add('Earth stays in view for the whole period.');
  }
  return out;
}

class Ranked {
  final String id, name;
  final SiteMetrics metrics;
  final ScoreBreakdown score;
  const Ranked(this.id, this.name, this.metrics, this.score);
}

List<Ranked> rank(Map<String, (String, SiteMetrics)> sites, ScoreWeights w) {
  final r = [for (final e in sites.entries) Ranked(e.key, e.value.$1, e.value.$2, score(e.value.$2, w))];
  r.sort((a, b) => b.score.total.compareTo(a.score.total));
  return r;
}

/// "power 50% / comms 50% for 75% of the score, Sun + Earth together for
/// 25%": all three weights of [score], in the same terms as [formulaText].
String weightingText(ScoreWeights w) =>
    'power ${(100 * w.power).round()}% / comms ${(100 * w.comms).round()}% for ${(100 * (1 - w.both)).round()}% '
    'of the score, Sun + Earth together for ${(100 * w.both).round()}%';

/// One-paragraph verdict for a comparison. With [dsn] the Earth metric is
/// Earth contact (Earth in view and a DSN station up), see [siteSummary].
String comparisonVerdict(List<Ranked> r, ScoreWeights w, {bool dsn = false}) {
  if (r.isEmpty) return 'Pick at least two sites to compare.';
  final best = r.first;
  final head = 'Best overall: ${best.name} (score ${best.score.total.toStringAsFixed(0)}/100; weighting ${weightingText(w)}).';
  final more = comparisonHighlights(r, dsn: dsn);
  return more.isEmpty ? head : '$head $more';
}

/// [comparisonVerdict] without its first "Best overall ..." sentence: which
/// site leads on sunlight, on Earth, and the longest Sun + Earth window.
String comparisonHighlights(List<Ranked> r, {bool dsn = false}) {
  if (r.isEmpty) return '';
  final best = r.first;
  final parts = <String>[];
  Ranked top(double Function(Ranked) f) => r.reduce((a, b) => f(a) >= f(b) ? a : b);
  final mostSun = top((x) => x.metrics.pctSunlit);
  final mostEarth = top((x) => x.metrics.pctEarth);
  final mostBoth = top((x) => x.metrics.longestBothHours);
  if (mostSun.id != best.id) {
    parts.add('${mostSun.name} gets the most sunlight (${mostSun.metrics.pctSunlit.toStringAsFixed(0)}%).');
  }
  if (mostEarth.id != best.id) {
    parts.add('${mostEarth.name} has ${dsn ? 'Earth contact' : 'Earth in view'} the largest share of the time '
        '(${mostEarth.metrics.pctEarth.toStringAsFixed(0)}%).');
  }
  if (mostBoth.metrics.longestBoth != null) {
    parts.add('Longest Sun + Earth window: ${mostBoth.name}, ${_window(mostBoth.metrics.longestBoth!)}.');
  }
  return parts.join(' ');
}
