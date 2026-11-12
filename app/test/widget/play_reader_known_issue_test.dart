// 1.14.1 review: the known issue "Screen readers during Play on Android 7"
// was first recorded in 1.13.2 (PLAN.md's 1.13.2 entry) and is dated "1.13.2
// to 1.14.0" in README.md and docs/release_checklist.md; the header of
// play_reader_semantics_test.dart said "1.13.1 to 1.14.0". Every range given
// next to the issue's name now agrees.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The "<version> to 1.14.0" ranges within a sentence's reach of the
  /// issue's name in [text] (line breaks and `//` comment marks read as
  /// spaces).
  List<String> rangesNearIssue(String text) {
    final t = text.replaceAll(RegExp(r'\s*\n\s*(//\s*)?'), ' ');
    final out = <String>[];
    for (final m in RegExp('during Play on Android 7', caseSensitive: false).allMatches(t)) {
      final window = t.substring(math.max(0, m.start - 60), math.min(t.length, m.end + 60));
      out.addAll([for (final r in RegExp(r'(\d+\.\d+\.\d+) to 1\.14\.0').allMatches(window)) r.group(1)!]);
    }
    return out;
  }

  test('the Android 7 screen-reader known issue is dated 1.13.2 to 1.14.0 wherever a range is given', () {
    final header = File('test/widget/play_reader_semantics_test.dart')
        .readAsLinesSync()
        .takeWhile((l) => l.startsWith('//'))
        .join('\n');
    for (final (name, text) in [
      ('README.md', File('../README.md').readAsStringSync()),
      ('docs/release_checklist.md', File('../docs/release_checklist.md').readAsStringSync()),
      ('the header of play_reader_semantics_test.dart', header),
    ]) {
      final ranges = rangesNearIssue(text);
      expect(ranges, isNotEmpty, reason: '$name gives no range for the issue');
      expect(ranges.toSet(), {'1.13.2'}, reason: '$name dates the issue from ${ranges.toSet()}');
    }
  });
}
