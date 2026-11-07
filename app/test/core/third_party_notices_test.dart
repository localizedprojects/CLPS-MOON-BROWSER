// THIRD_PARTY_NOTICES.md: the `archive` row names every part that the archive
// package's own LICENSE-other.md lists as code from another project.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The folder of a resolved package, read from the config that `flutter pub get` writes.
Directory packageRoot(String name) {
  final config = File('.dart_tool/package_config.json').absolute;
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final entry = (json['packages'] as List).cast<Map<String, dynamic>>().singleWhere((p) => p['name'] == name);
  return Directory.fromUri(config.uri.resolve(entry['rootUri'] as String));
}

void main() {
  test('the archive row names each part that LICENSE-other.md lists', () {
    final other = File('${packageRoot('archive').path}/LICENSE-other.md').readAsLinesSync();
    // Each part starts on a line of its own, such as "zlib/inflate:" or "bzip2:".
    final heading = RegExp(r'^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?:$');
    final parts = {
      for (final line in other.map((l) => l.trim()))
        if (heading.hasMatch(line)) line.split(RegExp('[/:]')).first.toLowerCase(),
    };
    expect(parts, containsAll(['zlib', 'bzip2']));

    final row = File('../THIRD_PARTY_NOTICES.md').readAsLinesSync().singleWhere((l) => l.startsWith('| `archive` '));
    final licence = row.split('|')[2].toLowerCase();
    for (final part in parts) {
      expect(licence, contains(part), reason: 'LICENSE-other.md of archive lists "$part"');
    }
  });
}
