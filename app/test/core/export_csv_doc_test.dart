// 1.14.1 review: the scorecardCsv dartdoc ran straight into the
// scorecardMixedNote one, so the `///` lines about [requireDsn], [sites],
// [observerHeightM] and the power proxy documented the constant, and the
// function kept only its [mixed] paragraph, which also overstated the
// byte-for-byte claim (Whole Moon rows changed in 1.14.1). Reads the source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `///` lines directly above the line of [source] that starts with
/// [declaration], joined with spaces.
String docAbove(String source, String declaration) {
  final lines = source.split('\n');
  final at = lines.indexWhere((l) => l.startsWith(declaration));
  expect(at, greaterThan(0), reason: '$declaration not found');
  final doc = <String>[];
  for (var i = at - 1; i >= 0 && lines[i].startsWith('///'); i--) {
    doc.insert(0, lines[i].substring(3).trim());
  }
  return doc.join(' ');
}

void main() {
  final source = File('lib/core/export_csv.dart').readAsStringSync();

  test('scorecardCsv keeps its own dartdoc, apart from scorecardMixedNote', () {
    final fn = docAbove(source, 'String scorecardCsv(');
    for (final p in ['[requireDsn]', '[sites]', '[observerHeightM]', '[options]', '[mixed]', 'Sun-facing-panel proxy']) {
      expect(fn, contains(p), reason: 'scorecardCsv dartdoc lacks $p');
    }
    final note = docAbove(source, 'const scorecardMixedNote');
    expect(note, contains('mixed regions'));
    for (final p in ['[requireDsn]', '[sites]', '[observerHeightM]', 'Sun-facing-panel proxy']) {
      expect(note, isNot(contains(p)), reason: 'scorecardMixedNote dartdoc carries $p');
    }
  });

  test('the byte-for-byte claim is limited to south-pole sites (Whole Moon rows changed in 1.14.1)', () {
    final fn = docAbove(source, 'String scorecardCsv(');
    expect(fn, contains('byte-for-byte the 1.14.0 one for south-pole sites'));
  });
}
