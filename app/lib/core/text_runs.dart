/// Splits a sentence into number and text runs, so the UI can set every
/// number in IBM Plex Mono with tabular figures and the words in Plex Sans.
library;

/// One run of a sentence: a number (with its unit) or plain text.
class TextRun {
  final String text;
  final bool number;
  const TextRun(this.text, this.number);

  @override
  bool operator ==(Object other) => other is TextRun && other.text == text && other.number == number;

  @override
  int get hashCode => Object.hash(text, number);

  @override
  String toString() => number ? '#[$text]' : '"$text"';
}

const _monthAlt = 'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec';

/// What counts as a number, in priority order, each followed by a check that
/// no letter comes next:
/// - a date with optional time: '12 Sep 2027', '12 Sep 2027 20:30 UTC',
///   '20 October 2026';
/// - a time: '20:30', '20:30 UTC';
/// - a duration in the app's format: '10 d 21 h', '5 h 30 min', '45 min',
///   with an optional '+' (the spell runs past the period);
/// - an ordinal: '2nd', '17th';
/// - a signed decimal (hyphen-minus, U+2212 minus or plus) with an optional
///   thousands separator and unit: '−89.78°', '-156.45°E', '62%', '1,733 m',
///   '6.8 km', '1361 W/m²'.
///
/// The lookbehinds keep digits that are part of a name in sans: no letter,
/// digit or underscore may come before the number (SR1, CR1, LDEM_80S), and
/// no letter or underscore followed by a hyphen (IM-2). A range such as
/// '10-20 km' still reads as two numbers.
final _numberRe = RegExp(
  r'(?<![A-Za-z0-9_])(?<![A-Za-z_]-)'
  '(?:'
  '\\d{1,2} (?:$_monthAlt)[a-z]* \\d{4}(?: \\d{1,2}:\\d{2})?(?: UTC)?'
  r'|\d{1,2}:\d{2}(?: UTC)?'
  r'|\d+ d(?: \d+ h)?\+?|\d+ h(?: \d+ min)?\+?|\d+ min\+?'
  r'|\d+(?:st|nd|rd|th)'
  r'|[+\-−]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?'
  r'(?:\s?(?:kWh/m²|W/m²|km²|km|m²|m|h|d|K)|%|°[EWNS]?)?'
  ')'
  r'(?![A-Za-z])',
);

/// A capitalised word and one space right before a bare integer: the integer
/// is part of a name ('Rim 2', 'Apollo 17'), unless the word is a month
/// ('January 2024').
final _nameWordBefore = RegExp(r'(?:^|[^A-Za-z])([A-Z][A-Za-z]*) $');
final _month = RegExp('^(?:$_monthAlt)[a-z]*\$');
final _bareInt = RegExp(r'^\d+$');

/// Splits [s] into alternating text and number runs (adjacent text is
/// merged; empty runs are dropped). Joining the runs gives back [s].
List<TextRun> numberRuns(String s) {
  final out = <TextRun>[];
  void add(String text, bool number) {
    if (text.isEmpty) return;
    if (!number && out.isNotEmpty && !out.last.number) {
      out[out.length - 1] = TextRun(out.last.text + text, false);
    } else {
      out.add(TextRun(text, number));
    }
  }

  var at = 0;
  for (final m in _numberRe.allMatches(s)) {
    final text = m[0]!;
    var number = true;
    if (_bareInt.hasMatch(text)) {
      final w = _nameWordBefore.firstMatch(s.substring(0, m.start));
      if (w != null && !_month.hasMatch(w[1]!)) number = false;
    }
    add(s.substring(at, m.start), false);
    add(text, number);
    at = m.end;
  }
  add(s.substring(at), false);
  return out;
}
