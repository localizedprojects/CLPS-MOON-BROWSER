/// Site › Overview's "now" line: how high the Sun stands and the time left
/// before sunset or Earthset at the time shown, in two short halves:
///
///   Sun 2.1° above level (1.4° above the hills) · sunset in 3 d 4 h
///   Earth 5.0° below the hills · Earthrise in 2 d 3 h
///
/// The Sun half and Earth's countdown are cut from the Sky & time status
/// line ([countdownLine], the same [Countdown]), so their words and numbers
/// are the status line's, without its clock times (the line is compact; the
/// clock times are on Sky & time). Earth's height above the skyline at its
/// azimuth is the one addition, worded as the status line words the Sun's.
library;

import 'countdown.dart';

/// The two halves of the line; [countdownParts] splits each for styling.
class NowLine {
  /// "Sun 2.1° above level (1.4° above the hills) · sunset in 3 d 4 h".
  final String sun;

  /// "Earth 5.0° below the hills · Earthrise in 2 d 3 h".
  final String earth;
  const NowLine(this.sun, this.earth);
}

String _deg(double v) => '${v.abs().toStringAsFixed(1)}°';

/// The line for countdown [c] at the time shown. [earthClearDeg] is Earth's
/// disk centre above the skyline at its azimuth (deg; negative below it);
/// [earthNoDsn]: the terrain lets Earth count but no DSN dish can reach it
/// (only with [requireDsn]).
NowLine nowLineOf(Countdown c, {required double earthClearDeg, bool earthNoDsn = false, bool requireDsn = false}) {
  // the status line's three parts: the Sun's height, its next change, Earth's next change
  final segs = <List<(String, bool)>>[[]];
  for (final p in countdownParts(countdownLine(c, dateOf: (_) => '', requireDsn: requireDsn))) {
    if (p == (' · ', true)) {
      segs.add([]);
    } else {
      segs.last.add(p);
    }
  }
  String join(Iterable<(String, bool)> ps) => [for (final (t, _) in ps) t].join();
  // the Sun's height keeps its asides (above the hills, the eclipse); the next change drops its clock time
  final sun = '${join(segs[0])} · ${join(segs[1].where((p) => !p.$2))}';
  final where = '${_deg(earthClearDeg)} ${earthClearDeg >= 0 ? 'above' : 'below'} the hills';
  final noDish = requireDsn && earthNoDsn ? ', but no DSN dish can reach it' : '';
  return NowLine(sun, 'Earth $where$noDish · ${join(segs[2])}');
}
