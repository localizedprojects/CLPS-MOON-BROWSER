// The scorecard CSV a user saves from Compare (1.14.1): a shortlist that
// mixes regions has no single ranking (every screen and chart says so), so
// its CSV has no rank column and says why; an all-polar shortlist writes
// exactly the 1.14.0 CSV, and an all-whole-Moon one the 1.14.0 columns with
// each row's lat, lon and horizon filled in (1.14.0 left them empty). Runs on the synthetic whole-Moon
// fixtures (test/fixtures/global_sample, made-up values).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/export_csv.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/score.dart' show formulaText;
import 'package:polar_horizon/core/summary.dart' show date;
import 'package:polar_horizon/screens/compare.dart' show applyShortlist;
import 'package:polar_horizon/state/chart_hub.dart';
import 'package:polar_horizon/widgets/compare_panel.dart';
import 'package:polar_horizon/widgets/save_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/global_test_state.dart';

const polarPair = ['derosa2012-sr1-shackleton-rim', 'artemis3-malapert-massif'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GlobalTestState state;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    state = GlobalTestState();
    await state.init();
    await state.ensureGlobal();
    expect(state.region, Region.southPole);
  });
  tearDownAll(() => state.dispose());

  /// The CSV text [ChartHub.exportScorecard] saves for the current shortlist.
  Future<String> saved() async {
    final files = <SaveFile>[];
    final hub = ChartHub(onEvent: (_) {}, save: (f) async => files.addAll(f));
    addTearDown(hub.dispose);
    await hub.exportScorecard(state);
    expect(files, hasLength(1));
    expect(files.single.mimeType, 'text/csv');
    return utf8.decode(files.single.bytes);
  }

  /// The 1.14.0 call (no `mixed` argument), for the byte-for-byte check.
  String csv114() => scorecardCsv(
      rankedFor(state), '${date(state.rangeStartMs)} - ${date(state.rangeEndMs - 1)}', formulaText(state.weights),
      sites: {for (final x in state.allSites) x.id: x}, observerHeightM: state.observerHeightM, options: state.options);

  /// [csv114] with the Whole Moon sites in the lookup too: since 1.14.1 their
  /// rows carry lat, lon and horizon (1.14.0 left those cells empty).
  String csvAll() => scorecardCsv(
      rankedFor(state), '${date(state.rangeStartMs)} - ${date(state.rangeEndMs - 1)}', formulaText(state.weights),
      sites: {for (final x in state.allSites) x.id: x, for (final x in state.global!.sites) x.id: x},
      observerHeightM: state.observerHeightM, options: state.options);

  /// The data rows of [csv] (after the column header), in score order.
  List<String> rowsOf(String csv) {
    final lines = csv.trim().split('\n');
    final header = lines.firstWhere((l) => !l.startsWith('#'));
    return lines.skipWhile((l) => l != header).skip(1).toList();
  }

  /// Each row ends with its site's lat, lon, observer height, rules and
  /// horizon: a Whole Moon row its own mask source, a polar row the 1.14.0 text.
  void expectProvenance(List<String> rows) {
    final ranked = rankedFor(state);
    expect(rows, hasLength(ranked.length));
    for (final (i, row) in rows.indexed) {
      final site = state.siteById(ranked[i].id);
      final horizon = site.region == Region.wholeMoon ? site.maskSource : 'LOLA 80 m/240 m DEM';
      expect(site.lat.isFinite && site.lon.isFinite, isTrue, reason: site.id);
      expect(row, contains(',${site.lat},${site.lon},${state.observerHeightM},'), reason: row);
      expect(row, endsWith(',"$horizon"'), reason: row);
    }
  }

  test('an all-polar shortlist saves exactly the 1.14.0 CSV, with ranks', () async {
    applyShortlist(state, [...polarPair, 'artemis3-haworth']);
    expect(compareMixed(state), isFalse);
    expect(state.compareReady, isTrue);
    final csv = await saved();
    expect(csv, csv114());
    expect(csv, isNot(contains(scorecardMixedNote)));
    expect(csvAll(), csv114(), reason: 'polar rows: the Whole Moon lookup changes nothing');
    expectProvenance(rowsOf(csv));
    final lines = csv.trim().split('\n');
    expect(lines.where((l) => l.startsWith('rank,site,')), hasLength(1));
    expect([for (final l in lines) if (RegExp(r'^\d,').hasMatch(l)) l[0]], ['1', '2', '3']);
  });

  test('an all-whole-Moon shortlist saves the 1.14.0 columns with ranks, and each row its lat, lon and horizon (1.14.1)',
      () async {
    final ids = [for (final x in state.global!.catalog.sites.take(2)) x.id];
    applyShortlist(state, ids);
    expect(compareMixed(state), isFalse);
    expect(rankedFor(state), hasLength(2), reason: 'both whole-Moon sites have metrics');
    final csv = await saved();
    expect(csv, csvAll());
    expect(csv, contains('\nrank,site,'));
    expect(csv, isNot(contains('LOLA 80 m/240 m DEM')), reason: 'no polar horizon on a Whole Moon row');
    expectProvenance(rowsOf(csv));
    // the same lines as 1.14.0 apart from the cells 1.14.0 left empty
    expect(csv.split('\n').length, csv114().split('\n').length);
  });

  test('a mixed shortlist saves no rank column and says there is no single ranking', () async {
    applyShortlist(state, [...polarPair, 'apollo-11-lm']);
    expect(compareMixed(state), isTrue);
    final ranked = rankedFor(state);
    expect(ranked, hasLength(3));
    final csv = await saved();
    final lines = csv.trim().split('\n');
    expect(lines, contains(scorecardMixedNote));
    expect(scorecardMixedNote, contains('mixed regions: no single ranking'));
    expect(lines.where((l) => l.startsWith('rank,')), isEmpty, reason: 'no rank column');
    final header = lines.firstWhere((l) => !l.startsWith('#'));
    expect(header, startsWith('site,score,'));
    final rows = lines.skipWhile((l) => l != header).skip(1).toList();
    expect(rows, hasLength(3));
    // rows stay in score order, each starting with its name, never a rank number
    for (final (i, row) in rows.indexed) {
      expect(row, startsWith('"${ranked[i].name.replaceAll('"', '""')}",'), reason: row);
      expect(row, isNot(matches(RegExp(r'^\d+,'))));
    }
    // the same numbers as the ranked CSV, without the rank field
    final withRanks = csvAll().trim().split('\n').where((l) => RegExp(r'^\d+,').hasMatch(l)).toList();
    expect(rows, [for (final l in withRanks) l.substring(l.indexOf(',') + 1)]);
    // every row, polar or Whole Moon, has its lat, lon and horizon (1.14.1)
    expectProvenance(rows);
  });
}
