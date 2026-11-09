// 1.14.0 "Whole Moon": the sky payload's `northNote` (charts/src/bridge.ts
// SkyData, docs/global_data_contract.md §9). Sent for sites outside the south
// pole only; a polar payload has exactly the 1.13.5 keys.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/timeseries.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';

/// The `data` keys of a 1.13.5 sky payload, in order.
const polarSkyKeys = ['siteName', 'timeLabel', 'refMs', 'maskStepDeg', 'mask', 'maskApprox', 'now', 'trails', 'zoom'];

Site site({Region region = Region.southPole, String id = 'x', double lat = -89.5, double lon = 0}) => Site(
      id: id, name: 'Test site $id', short: 'Test $id', group: 'missions', kind: 'test', confidence: 'synthetic',
      notes: '', lat: lat, lon: lon, terrainHeightM: 0, region: region);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('skyNorthNote', () {
    test('global sites (presets and custom spots) get "N = toward the north pole"; polar ones nothing', () {
      expect(kGlobalNorthNote, 'N = toward the north pole');
      expect(kGlobalNorthNote.endsWith('.'), isFalse, reason: 'the charts add the full stop');
      expect(skyNorthNote(site(region: Region.wholeMoon, id: 'apollo-11-lm', lat: 0.67, lon: 23.47)), kGlobalNorthNote);
      expect(skyNorthNote(site(region: Region.wholeMoon, id: 'custom-global', lat: 45, lon: -170)), kGlobalNorthNote);
      expect(skyNorthNote(site()), isNull);
      expect(skyNorthNote(site(id: 'polar-custom', lat: -80.01)), isNull);
    });
  });

  group('skyPayload', () {
    final mask = HorizonMask(90, Float64List.fromList([0.5, 1, 0.25, 2]));
    final s = SiteSeries.alloc(0, 3600e3, 4);
    final now = {
      'sun': bodyNowJson(),
      'earth': bodyNowJson(),
    };

    test('without a note: exactly the 1.13.5 keys (no northNote key at all)', () {
      final p = skyPayload(site(), mask, s, now, 0, true);
      final data = p['data'] as Map<String, dynamic>;
      expect(data.keys.toList(), polarSkyKeys);
      expect(jsonEncode(p), isNot(contains('northNote')));
      expect(data.containsKey('northNote'), isFalse);
    });

    test('with a note: the same payload plus northNote, last', () {
      final polar = skyPayload(site(), mask, s, now, 0, true);
      final g = skyPayload(site(region: Region.wholeMoon), mask, s, now, 0, true, northNote: kGlobalNorthNote);
      final data = g['data'] as Map<String, dynamic>;
      expect(data.keys.toList(), [...polarSkyKeys, 'northNote']);
      expect(data['northNote'], 'N = toward the north pole');
      final rest = Map<String, dynamic>.of(data)..remove('northNote');
      expect(jsonEncode(rest), jsonEncode(polar['data']));
    });
  });

  group('ChartHub', () {
    late AppState state;
    setUpAll(() async {
      state = AppState();
      await state.init();
    });
    tearDownAll(() => state.dispose());

    test('the polar sky payload it sends carries no northNote (guard G7)', () {
      final hub = ChartHub(onEvent: (_) {});
      addTearDown(hub.dispose);
      addTearDown(() => state.goTo(Dest.explore));
      expect(state.site.region, Region.southPole);
      state.goTo(Dest.site, siteTab: SiteTab.skyTime);
      final got = <Map<String, dynamic>>[];
      hub.sky.attach((j) => got.add(jsonDecode(j) as Map<String, dynamic>), Object());
      hub.sky.handleRaw(jsonEncode({'type': 'ready', 'view': hub.sky.view}));
      hub.sync(state);
      final sky = got.where((m) => m['type'] == 'sky').toList();
      expect(sky, hasLength(1));
      final data = sky.single['data'] as Map<String, dynamic>;
      expect(data.keys.toList(), polarSkyKeys);
      expect(data['siteName'], state.site.short);
    });
  });
}

/// A body's "now" as the charts receive it (values do not matter here).
Map<String, dynamic> bodyNowJson() => {'az': 10.0, 'el': 1.0, 'rho': 0.27, 'frac': 1.0, 'hz': 0.2, 'visible': true};
