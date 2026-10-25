// AppState's "At a glance" (overview engine): the curated asset loads in init,
// and selectedGlance is memoised but follows the site, the dates, the height
// and DSN (design-final §4 and §10 "Memo rebuilds").
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/site_glance.dart';
import 'package:polar_horizon/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState s;

  setUpAll(() async {
    s = AppState();
    await s.init();
  });
  tearDownAll(() => s.dispose());

  DateTime dt(double ms) => DateTime.fromMillisecondsSinceEpoch(ms.toInt(), isUtc: true);

  test('the curated asset is read uncached and a failed fetch is tried once more', () async {
    final asset = File('assets/data/curated_sites.json').readAsStringSync();
    final flaky = _Bundle([null, asset]);
    final c = await AppState.loadCurated(flaky);
    expect(c.sites, isNotEmpty, reason: 'the second fetch is used');
    expect(flaky.caches, [false, false]);
    // two failed fetches, or a broken asset (not retried): the generated text, no throw
    expect((await AppState.loadCurated(_Bundle([null, null]))).isEmpty, isTrue);
    final broken = _Bundle(['{', asset]);
    expect((await AppState.loadCurated(broken)).isEmpty, isTrue);
    expect(broken.caches, hasLength(1));
  });

  test('init loads the curated asset: every curated id is a catalogue site', () {
    expect(s.curated.sites, isNotEmpty);
    final ids = {for (final x in s.catalog!.sites) x.id};
    expect(ids, containsAll(s.curated.sites.keys));
  });

  test('a curated preset: CURATED eyebrow, its headline first, the shared memo', () {
    final g = s.selectedGlance!;
    final c = s.curated.sites[s.selectedId];
    expect(c, isNotNull, reason: 'the top pick is a preset with curated text');
    expect(g.curated, isTrue);
    expect(g.eyebrow, startsWith('CURATED'));
    expect(g.rows.first.$1, GlanceRow.what);
    expect(g.rows.first.$3.first.text, c!.headline);
    expect(identical(s.selectedGlance, g), isTrue, reason: 'memoised between rebuilds');
  });

  test('the memo follows the site, DSN, the height and the dates', () async {
    final start = s.rangeStartMs, end = s.rangeEndMs, h = s.observerHeightM, dsn = s.options.requireDsn;
    final first = s.selectedId;
    var g = s.selectedGlance!;

    final other = s.catalog!.sites.firstWhere((x) => x.id != first && s.curated.sites.containsKey(x.id));
    await s.selectSite(other.id);
    expect(s.selectedGlance, isNot(same(g)));
    expect(s.selectedGlance!.rows.first.$3.first.text, s.curated.sites[other.id]!.headline);
    g = s.selectedGlance!;

    await s.setRequireDsn(!dsn);
    expect(s.selectedGlance, isNot(same(g)), reason: 'DSN');
    g = s.selectedGlance!;

    await s.setObserverHeight(h + 8);
    expect(s.selectedGlance, isNot(same(g)), reason: 'height');
    g = s.selectedGlance!;

    await s.setRange(dt(start), dt(end - 86400e3));
    expect(s.selectedGlance, isNot(same(g)), reason: 'dates');
    expect(s.selectedGlance!.pendingPeriod, isFalse, reason: 'the new numbers are in');
    expect(s.selectedGlance!.plainText, isNot(contains('NaN')));

    // back to the defaults for any later test
    await s.setRange(dt(start), dt(end));
    await s.setObserverHeight(h);
    await s.setRequireDsn(dsn);
    await s.selectSite(first);
    expect(s.selectedGlance!.rows.first.$3.first.text, s.curated.sites[first]!.headline);
  });
}

/// Answers loadString with [texts] in turn; null fails as a missing asset.
class _Bundle extends CachingAssetBundle {
  final List<String?> texts;
  final caches = <bool>[];
  _Bundle(this.texts);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    caches.add(cache);
    final t = texts[caches.length - 1];
    if (t == null) throw FlutterError('Unable to load asset: "$key".');
    return t;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}
