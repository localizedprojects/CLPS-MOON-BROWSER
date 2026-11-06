// web/index.html: the link-preview tags (Open Graph, Twitter/X) match the
// page description and point at files the Pages deploy serves.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://localizedprojects.github.io/CLPS-MOON-BROWSER/';
  final html = File('web/index.html').readAsStringSync();

  String meta(String attr, String key) {
    final m = RegExp('<meta $attr="${RegExp.escape(key)}" content="([^"]*)">').allMatches(html).toList();
    expect(m, hasLength(1), reason: '$attr=$key');
    return m.single.group(1)!;
  }

  test('Open Graph and Twitter tags match the description and the Pages address', () {
    final description = meta('name', 'description');
    expect(meta('property', 'og:title'), 'Lunar Horizon');
    expect(meta('property', 'og:description'), description);
    expect(meta('property', 'og:type'), 'website');
    expect(meta('property', 'og:url'), site);
    expect(meta('name', 'twitter:card'), 'summary');
    expect(meta('name', 'twitter:title'), 'Lunar Horizon');
    expect(meta('name', 'twitter:description'), description);
  });

  test('the preview image is an absolute URL to a file this folder ships, at its stated size', () {
    final image = meta('property', 'og:image');
    expect(meta('name', 'twitter:image'), image);
    expect(image, startsWith(site));
    // the deploy builds with --base-href /CLPS-MOON-BROWSER/ and serves build/web, a copy of web/
    final deploy = File('../.github/workflows/deploy-pages.yml').readAsStringSync();
    expect(deploy, contains('--base-href "/\${{ github.event.repository.name }}/"'));
    expect(deploy, contains('path: app/build/web'));
    final file = File('web/${image.substring(site.length)}');
    expect(file.existsSync(), isTrue, reason: file.path);
    final png = file.readAsBytesSync();
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    final size = ByteData.sublistView(png, 16, 24);
    expect('${size.getUint32(0)}', meta('property', 'og:image:width'));
    expect('${size.getUint32(4)}', meta('property', 'og:image:height'));
  });
}
