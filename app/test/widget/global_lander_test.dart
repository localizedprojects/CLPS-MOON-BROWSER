// The Lander's view at whole-Moon presets (1.14.0 build plan §7 WP5): the
// Overview entry (48 dp, Semantics, only for presets with a terrain tile,
// nothing while the WP5 gate is closed), the full screen built from the
// site's own tile in its map frame (state/global_tiles.dart), no light
// frames asked for, grey ground, the global wording and badges, previous /
// next and the name's list stepping through the presets with a tile only,
// and a keyboard focus ring on that list.
//
// The catalogue is built here: three presets at the exact coordinates of
// their tiles in assets/data/global/tiles.json, one preset with no tile and
// one custom spot, all with made-up flat horizon masks (test values, never
// shown as real). The tiles are the committed ones, read from disk.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/core/catalog.dart';
import 'package:polar_horizon/core/horizon.dart';
import 'package:polar_horizon/core/region.dart';
import 'package:polar_horizon/core/shadow.dart' show lightEarth, lightSunAny, lightSunFull;
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/state/global_tiles.dart';
import 'package:polar_horizon/state/light_engine.dart';
import 'package:polar_horizon/theme.dart';
import 'package:polar_horizon/widgets/focus_rings.dart';
import 'package:polar_horizon/widgets/focus_semantics.dart';
import 'package:polar_horizon/widgets/global_lander_entry.dart';
import 'package:polar_horizon/widgets/lander_full_screen.dart';
import 'package:polar_horizon/widgets/lander_view.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

/// Records every light request (a whole-Moon preset must ask for none).
class _FakeEngine extends LightEngine {
  final requests = <LightRequest>[];

  @override
  Future<LightFrame> compute(LightRequest q) async {
    requests.add(q);
    final n = q.far ? 128 : 256, px = q.far ? 800.0 : 400.0;
    return LightFrame(q, n, px, -n * px / 2, n * px / 2,
        Uint8List(n * n)..fillRange(0, n * n, lightSunAny | lightSunFull | lightEarth),
        Uint8List(n * n)..fillRange(0, n * n, 200), 0);
  }

  @override
  Future<LightOverlay> overlay(LightFrame f, LightLayer layer, int w, double scale) => throw UnimplementedError();

  @override
  bool get onUiThread => false;

  @override
  void dispose() {}
}

const _maskSource = 'made-up flat test mask';
const _name = ValueKey('lander-full-site');
const _prev = ValueKey('lander-full-prev'), _next = ValueKey('lander-full-next');
const _open = ValueKey('global-lander-open');

/// The committed tile index (the presets' coordinates come from it).
final Map<String, dynamic> _tiles =
    (jsonDecode(File('assets/data/global/tiles.json').readAsStringSync()) as Map<String, dynamic>)['tiles']
        as Map<String, dynamic>;

Site _preset(String id, String short, {double? lat, double? lon, bool custom = false}) {
  final t = _tiles[id] as Map<String, dynamic>?;
  return Site(
    id: id,
    name: '$short (test)',
    short: short,
    group: 'test',
    kind: custom ? 'custom' : 'landed',
    confidence: 'made-up',
    notes: 'Made-up test site.',
    lat: lat ?? (t!['centreLat'] as num).toDouble(),
    lon: lon ?? (t!['centreLon'] as num).toDouble(),
    terrainHeightM: 0,
    custom: custom,
    region: Region.wholeMoon,
    maskSource: _maskSource,
    place: 'Test',
    side: 'near',
  );
}

void main() {
  late AppState state;
  late _FakeEngine engine;
  // in the catalogue's order: the no-tile preset sits between two with a tile
  final a15 = _preset('apollo-15-lm', 'Apollo 15'),
      noTile = _preset('test-no-tile', 'No tile', lat: 10, lon: 10),
      a11 = _preset('apollo-11-lm', 'Apollo 11'),
      c4 = _preset('change-4', "Chang'e 4"),
      spot = _preset('custom-global-test', 'Custom spot', lat: 20, lon: -30, custom: true);
  final tiled = [a15, a11, c4];

  setUpAll(loadPlexFonts);
  setUp(() async {
    state = AppState();
    await state.init();
    engine = _FakeEngine();
  });
  tearDown(() {
    debugGlobalTiles = null;
    state.dispose();
  });

  // the made-up catalogue as the Whole Moon one, its masks next to the polar
  // ones (as test/widget/global_test_state.dart does), the committed tiles
  // from disk, the fake engine; Apollo 15 selected
  Future<void> install(WidgetTester tester) async {
    final heights = state.catalog!.heightsM;
    HorizonMask flat() => HorizonMask(0.25, Float64List(1440), source: _maskSource, approximate: true);
    final masks = {
      for (final x in [a15, noTile, a11, c4, spot]) x.id: {for (final h in heights) h: flat()},
    };
    final cat = SiteCatalog([const SiteGroup('test', 'Test', '')], [a15, noTile, a11, c4], {}, heights, 'made-up',
        region: Region.wholeMoon);
    state.catalog!.masks.addAll(masks);
    state.global = GlobalCatalogState(cat, customSites: [spot]);
    state.lightEngineForTest = engine;
    debugGlobalTiles = GlobalTiles(
      loadString: (k) async => File(k).readAsStringSync(),
      loadBytes: (k) async => File(k).readAsBytesSync(),
    );
    // the tile index and tiles load later, in the test's own zone (a future
    // made inside runAsync completes only on the real event loop)
    await tester.runAsync(() => state.selectSite(a15.id));
  }

  void size(WidgetTester tester, Size s) {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(List<Widget> children) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => FocusRings(child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  LanderViewPanelState panel(WidgetTester tester) => tester.state(find.byType(LanderViewPanel));
  LanderPainter painter(WidgetTester tester) => tester
      .widget<CustomPaint>(
          find.descendant(of: find.byKey(const ValueKey('lander-view')), matching: find.byType(CustomPaint)))
      .painter! as LanderPainter;

  Future<void> meshReady(WidgetTester tester, Site site) async {
    var i = 0;
    bool done() {
      final m = panel(tester).mesh;
      return panel(tester).meshError != null || (m != null && m.cam.latDeg == site.lat && m.cam.lonDeg == site.lon);
    }

    for (; i < 5000 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(panel(tester).meshError, isNull);
    expect(panel(tester).mesh, isNotNull, reason: 'after $i pumps');
    await tester.pump();
  }

  // the entry for Apollo 15, tapped: the full screen, its mesh built
  Future<void> openFull(WidgetTester tester) async {
    await install(tester);
    await tester.pumpWidget(host([GlobalLanderEntry(site: a15, state: state)]));
    await settle(tester);
    await tester.tap(find.byKey(_open));
    await settle(tester);
    expect(find.byType(LanderFullScreenPage), findsOneWidget);
    await meshReady(tester, a15);
  }

  void onSite(WidgetTester tester, Site site, String why) {
    expect(state.selectedId, site.id, reason: why);
    expect(find.byType(LanderFullScreenPage), findsOneWidget, reason: '$why: still full screen');
    expect(find.descendant(of: find.byKey(_name), matching: find.text(site.short)), findsOneWidget, reason: why);
  }

  testWidgets(
      'E1 the entry: one 48 dp button with its Semantics label for a preset with a tile; nothing for a preset '
      'without one, a custom spot or a polar site; the Overview hook is empty while the gate is closed',
      (tester) async {
    size(tester, const Size(390, 844));
    final handle = tester.ensureSemantics();
    await install(tester);
    final polar = state.allSites.first;
    late BuildContext ctx;
    await tester.pumpWidget(host([
      for (final x in [a15, noTile, spot, polar])
        KeyedSubtree(key: ValueKey('e-${x.id}'), child: GlobalLanderEntry(site: x, state: state)),
      Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      }),
    ]));
    await settle(tester);
    final b = find.byKey(_open);
    expect(b, findsOneWidget);
    expect(find.descendant(of: find.byKey(ValueKey('e-${a15.id}')), matching: b), findsOneWidget);
    expect(tester.getSize(b).height, 48);
    expect(tester.getSize(b).width, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel(GlobalLanderEntry.semanticLabel(a15)), findsOneWidget);
    expect(find.text(GlobalLanderEntry.buttonText), findsOneWidget);
    expect(find.text(GlobalLanderEntry.note), findsOneWidget);
    for (final x in [noTile, spot, polar]) {
      expect(find.descendant(of: find.byKey(ValueKey('e-${x.id}')), matching: find.byType(OutlinedButton)),
          findsNothing, reason: x.id);
      expect(find.bySemanticsLabel(GlobalLanderEntry.semanticLabel(x)), findsNothing, reason: x.id);
    }
    final hook = globalLanderEntry(ctx, a15);
    if (kGlobalLander) {
      expect(hook, isA<GlobalLanderEntry>());
    } else {
      expect(hook, isA<SizedBox>());
      expect((hook as SizedBox).width, 0);
      expect(hook.height, 0);
    }
    handle.dispose();
  });

  testWidgets(
      'E2 a tap opens the full screen: the mesh from the site\'s tile at its position, no light frames, grey ground '
      'without a status, the global mask label, compass, badges and notes, no layer switch or legend', (tester) async {
    size(tester, const Size(390, 844));
    final handle = tester.ensureSemantics();
    await openFull(tester);
    final m = panel(tester).mesh!;
    expect(m.cam.latDeg, a15.lat);
    expect(m.cam.lonDeg, a15.lon);
    await settle(tester);
    expect(engine.requests, isEmpty, reason: 'no light frames at a whole-Moon preset');
    final p = painter(tester);
    expect(p.status, isNull, reason: 'no "Computing light…" at a whole-Moon preset');
    expect(p.colors, isNotNull, reason: 'the ground is drawn (grey)');
    expect(p.maskLabel, landerMaskLabelGlobal(a15.maskSource));
    expect(find.bySemanticsLabel(landerCompassLabelGlobal), findsOneWidget);
    expect(find.bySemanticsLabel(landerCompassLabel), findsNothing);
    for (final k in ['lander-full-layer', 'lander-full-legend', 'lander-full-error']) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
    final ix = globalTiles.loadedIndex!;
    expect(ix.terrainText, startsWith('Terrain LOLA 474 m resampled to 400 m'), reason: 'numbers from tiles.json');
    final badge = tester.widget<FidelityBadge>(find.byKey(const ValueKey('lander-badge')));
    expect(badge.text, contains(ix.terrainText));
    expect(badge.text, contains(_maskSource));
    final scope = tester.widget<FidelityBadge>(find.byKey(const ValueKey('lander-global-scope')));
    expect(scope.text, landerGlobalLightNote);
    // the badges scroll under the view; the notes are the panel's own
    final scroll = find.byKey(const ValueKey('lander-full-notes'));
    expect(find.descendant(of: scroll, matching: find.byKey(const ValueKey('lander-global-scope'))), findsOneWidget);
    final notes = find.byType(LanderViewPanel);
    expect(
        find.descendant(
            of: notes,
            matching: find.textContaining('Ground light and shadow are not computed at whole-Moon sites',
                findRichText: true)),
        findsWidgets);
    expect(
        find.descendant(
            of: notes, matching: find.textContaining('Terrain from LOLA around this site', findRichText: true)),
        findsOneWidget);
    expect(find.textContaining('Computing light', findRichText: true), findsNothing);
    handle.dispose();
  });

  testWidgets('E3 wide: no layer switch or legend button in the top bar either', (tester) async {
    size(tester, const Size(1280, 800));
    await openFull(tester);
    await settle(tester);
    for (final k in ['lander-full-layer', 'lander-full-legend', 'lander-full-error']) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
    expect(find.byKey(const ValueKey('lander-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('lander-global-scope')), findsOneWidget);
    expect(engine.requests, isEmpty);
  });

  testWidgets(
      'E4 previous / next step through the presets with a tile only (never the one without, nor a custom spot) '
      'and wrap around; each builds its own mesh', (tester) async {
    size(tester, const Size(390, 844));
    await openFull(tester);
    onSite(tester, a15, 'opened');
    expect(tester.widget<IconButton>(find.byKey(_next)).tooltip, 'Next site: ${a11.short}');
    expect(tester.widget<IconButton>(find.byKey(_prev)).tooltip, 'Previous site: ${c4.short}');
    for (final (key, to) in [(_next, a11), (_next, c4), (_next, a15), (_prev, c4), (_prev, a11), (_prev, a15)]) {
      await tester.tap(find.byKey(key));
      await tester.pump();
      await tester.pump();
      onSite(tester, to, '${key.value} to ${to.id}');
      await meshReady(tester, to);
      expect(panel(tester).mesh!.cam.latDeg, to.lat);
      expect(panel(tester).mesh!.cam.lonDeg, to.lon);
    }
    await settle(tester);
    expect(engine.requests, isEmpty);
  });

  testWidgets(
      'E5 the name opens the list of presets with a tile: 48 dp rows with Semantics and focus rings, the current one '
      'with a check mark and its word; a row switches the site', (tester) async {
    size(tester, const Size(390, 844));
    final handle = tester.ensureSemantics();
    await openFull(tester);
    await tester.tap(find.byKey(_name));
    await settle(tester);
    expect(find.text(LanderFullScreenPageState.globalPickerTitle), findsOneWidget);
    Finder row(Site x) => find.byKey(ValueKey('lander-global-pick-${x.id}'));
    for (final x in tiled) {
      expect(row(x), findsOneWidget, reason: x.id);
      expect(tester.getSize(row(x)).height, greaterThanOrEqualTo(48), reason: x.id);
      expect(find.ancestor(of: row(x), matching: find.byType(FocusSemantics)), findsOneWidget, reason: x.id);
      final current = x.id == a15.id;
      expect(find.descendant(of: row(x), matching: find.byIcon(Icons.check)), current ? findsOneWidget : findsNothing,
          reason: x.id);
      expect(find.descendant(of: row(x), matching: find.text('current')), current ? findsOneWidget : findsNothing,
          reason: x.id);
      expect(find.bySemanticsLabel(current ? '${x.short}, current site' : x.short), findsOneWidget, reason: x.id);
    }
    for (final x in [noTile, spot]) {
      expect(row(x), findsNothing, reason: x.id);
    }

    // keyboard focus on a row shows the 2 px ice ring; a touch hides it again
    BorderSide side() {
      final mat = tester.widget<Material>(find.descendant(of: row(a11), matching: find.byType(Material)).first);
      return (mat.shape! as OutlinedBorder).side;
    }

    Focus.of(tester.element(find.descendant(of: row(a11), matching: find.text(a11.short)))).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.traditional);
    expect(side(), const BorderSide(color: PH.ice, width: 2), reason: 'keyboard focus shows the ring');
    await tester.tapAt(tester.getTopLeft(find.text(LanderFullScreenPageState.globalPickerTitle)));
    await tester.pump();
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
    expect(side().width == 2 && side().color == PH.ice, isFalse, reason: 'no ring after a touch');
    handle.dispose();

    await tester.tap(row(c4));
    await tester.pump();
    await tester.pump();
    onSite(tester, c4, 'picked');
    await meshReady(tester, c4);
    await settle(tester);
    expect(find.text(LanderFullScreenPageState.globalPickerTitle), findsNothing, reason: 'closed by the pick');
    expect(panel(tester).mesh!.cam.latDeg, c4.lat);
    expect(panel(tester).mesh!.cam.lonDeg, c4.lon);
    expect(engine.requests, isEmpty);
  });
}
