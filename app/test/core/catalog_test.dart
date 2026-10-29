import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';

void main() {
  final catalog = SiteCatalog.parse(
    File('assets/data/sites.json').readAsStringSync(),
    File('assets/data/horizons.json').readAsStringSync(),
  );

  test('isArtemisRegion: the 8 Artemis presets, not VIPER', () {
    final artemis = [for (final s in catalog.sites) if (s.isArtemisRegion) s.id];
    expect(artemis, hasLength(8));
    expect(artemis.every((id) => id.startsWith('artemis3-')), isTrue);
    expect(catalog.byId('viper-mission-area-center').isArtemisRegion, isFalse);
  });

  test('isRegionCentre is unchanged: VIPER is still a region centre', () {
    final centres = [for (final s in catalog.sites) if (s.isRegionCentre) s.id];
    // 8 Artemis regions + VIPER + the 3 mission points added on 2026-10-29 (IM-2 target, Chang'e-7, LUPEX)
    expect(centres, hasLength(12));
    expect(centres, contains('viper-mission-area-center'));
    expect(centres, containsAll(['im-2-intended-target', 'change-7-planned-landing', 'lupex-chandrayaan-5-candidate']));
    for (final s in catalog.sites) {
      expect(s.isRegionCentre, s.kind == 'region-center-approx', reason: s.id);
      if (s.isArtemisRegion) expect(s.isRegionCentre, isTrue, reason: s.id);
    }
  });
}
