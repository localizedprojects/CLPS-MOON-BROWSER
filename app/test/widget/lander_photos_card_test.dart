// "Real photos from this lander" (user decision 2026-11-01): the content
// (links to NASA's pages, nothing bundled) and the card on its own.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/content/lander_photos.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/lander_photos_card.dart';

const _landers = ['im-1-odysseus-landed', 'im-2-athena-landed'];

/// A Text (plain or Text.rich) whose text is [s]; number runs keep their
/// spaces unbreakable (U+00A0), so compare with ordinary spaces.
Finder _text(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll(' ', ' ') == s,
    description: 'text "$s"');

Finder _url(String url) => find.byWidgetPredicate((w) => w is SelectableText && w.data == url, description: 'URL $url');

Future<void> _pump(WidgetTester tester, Widget w, {double width = 360, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 4000), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: w))),
    ),
  ));
  await tester.pump();
}

void main() {
  group('content', () {
    test('only the two landed landers, both in the catalogue', () {
      expect(landerPhotos.keys.toSet(), _landers.toSet());
      final cat = SiteCatalog.parse(
          File('assets/data/sites.json').readAsStringSync(), File('assets/data/horizons.json').readAsStringSync());
      for (final id in _landers) {
        expect(cat.sites.any((s) => s.id == id), isTrue, reason: id);
      }
      expect(cat.sites.where((s) => s.kind == 'landed-position').map((s) => s.id).toSet(), _landers.toSet());
    });

    test('every link: title, one sentence, date, credit and a NASA page (not an image file)', () {
      final datePattern = RegExp(r'^(Taken|Posted) \d{1,2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}$');
      final urls = <String>{};
      for (final MapEntry(key: id, value: p) in landerPhotos.entries) {
        expect(p.fact, endsWith('.'), reason: id);
        expect(p.surface, isNotEmpty, reason: id);
        expect(p.orbit, isNotEmpty, reason: id);
        for (final l in p.links) {
          expect(l.title.trim(), isNotEmpty, reason: l.url);
          expect(l.shows, endsWith('.'), reason: l.url);
          expect(l.shows.substring(0, l.shows.length - 1), isNot(contains('. ')), reason: 'one sentence: ${l.url}');
          expect(l.date, matches(datePattern), reason: l.url);
          // surface photos are Intuitive Machines'; orbital ones are LRO's
          expect(l.credit, l.fromOrbit ? 'NASA/Goddard/Arizona State University' : 'Intuitive Machines', reason: l.url);
          final u = Uri.parse(l.url);
          expect(u.scheme, 'https', reason: l.url);
          expect(u.host, anyOf('www.nasa.gov', 'science.nasa.gov'), reason: l.url);
          expect(u.path, isNot(matches(RegExp(r'\.(png|jpe?g|gif|webp|tiff?)$', caseSensitive: false))), reason: l.url);
          expect(urls.add(l.url), isTrue, reason: 'duplicate ${l.url}');
        }
      }
    });

    test('links only: nothing loads an image or opens the network', () {
      final banned = RegExp(r'Image\.network|NetworkImage|Image\(|HttpClient|package:http/|url_launcher|dart:io');
      for (final f in ['lib/content/lander_photos.dart', 'lib/widgets/lander_photos_card.dart']) {
        expect(File(f).readAsStringSync(), isNot(contains(banned)), reason: f);
      }
      expect(File('pubspec.yaml').readAsStringSync(), isNot(contains('url_launcher')));
    });

    test('pages without photos from the Moon stay dropped', () {
      // the 28 Feb 2024 Artemis blog post (empty image blocks) and PRIME-1 (renderings, lab photos)
      final urls = [for (final p in landerPhotos.values) for (final l in p.links) l.url];
      expect(urls, everyElement(isNot(anyOf(contains('/blogs/artemis/2024/02/28/'), contains('prime-1')))));
    });
  });

  group('LanderPhotosCard', () {
    test('only for the landers (not Malapert peak or a custom spot)', () {
      for (final id in _landers) {
        expect(LanderPhotosCard.forSite(id), isNotNull, reason: id);
      }
      for (final id in ['derosa2012-mp1-malapert-peak', 'change-7-planned-landing', 'custom-1']) {
        expect(LanderPhotosCard.forSite(id), isNull, reason: id);
      }
    });

    for (final id in _landers) {
      testWidgets('$id: the note, the fact, and every title, date, credit and selectable URL', (tester) async {
        final p = landerPhotos[id]!;
        await _pump(tester, LanderPhotosCard.forSite(id)!);
        expect(find.text(landerPhotosTitle), findsOneWidget);
        expect(find.text(landerPhotosNote), findsOneWidget);
        expect(_text(p.fact), findsOneWidget);
        expect(find.text(landerPhotosSurfaceHeading), findsOneWidget);
        expect(find.text(landerPhotosOrbitHeading), findsOneWidget);
        for (final l in p.links) {
          expect(_text(l.title), findsOneWidget, reason: l.title);
          expect(_text(l.shows), findsOneWidget, reason: l.title);
          expect(_text('${l.date} · Credit: ${l.credit}'), findsOneWidget, reason: l.title);
          expect(_url(l.url), findsOneWidget, reason: l.title);
        }
        expect(find.byType(SelectableText), findsNWidgets(p.links.length));
        // the orbital links come after the lander's own
        expect(tester.getTopLeft(find.text(landerPhotosOrbitHeading)).dy,
            greaterThan(tester.getTopLeft(_text(p.surface.last.title)).dy));
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('semantics: headers, a labelled 48 dp address for each link', (tester) async {
      final handle = tester.ensureSemantics();
      final p = landerPhotos['im-1-odysseus-landed']!;
      await _pump(tester, LanderPhotosCard(photos: p));
      expect(tester.getSemantics(find.text(landerPhotosTitle)), isSemantics(isHeader: true, label: landerPhotosTitle));
      expect(tester.getSemantics(find.text(landerPhotosOrbitHeading)),
          isSemantics(isHeader: true, label: landerPhotosOrbitHeading));
      for (final l in p.links) {
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(landerPhotoUrlSemantics(l)))), findsOneWidget, reason: l.title);
        final box = find.ancestor(of: _url(l.url), matching: find.byType(ConstrainedBox)).first;
        expect(tester.getSize(box).height, greaterThanOrEqualTo(48), reason: l.title);
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('320 dp wide, text x2: no overflow', (tester) async {
      await _pump(tester, LanderPhotosCard.forSite('im-2-athena-landed')!, width: 320, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
