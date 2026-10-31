import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/site_order.dart';

Site _site(String id, {bool custom = false}) => Site(
      id: id,
      name: 'Site $id',
      short: id,
      group: custom ? '' : 'preset',
      kind: '',
      confidence: '',
      notes: '',
      lat: -89,
      lon: 0,
      terrainHeightM: 0,
      custom: custom,
    );

void main() {
  test('siteNeighbours wraps both ways over presets then custom spots', () {
    final sites = [_site('a'), _site('b'), _site('c'), _site('mine', custom: true)];
    String pair(String id) {
      final n = siteNeighbours(sites, id)!;
      return '${n.prev.id}<$id>${n.next.id}';
    }

    expect(pair('a'), 'mine<a>b', reason: 'the first preset steps back to the last of the user\'s spots');
    expect(pair('b'), 'a<b>c');
    expect(pair('c'), 'b<c>mine', reason: 'the last preset steps on to the user\'s spots');
    expect(pair('mine'), 'c<mine>a', reason: 'the last spot wraps to the first preset');
    final two = siteNeighbours([_site('a'), _site('b')], 'a')!;
    expect((two.prev.id, two.next.id), ('b', 'b'));
  });

  test('siteNeighbours: one site or an unknown id gives null', () {
    expect(siteNeighbours(const [], 'a'), isNull);
    expect(siteNeighbours([_site('a')], 'a'), isNull);
    expect(siteNeighbours([_site('a'), _site('b')], 'zz'), isNull);
  });
}
