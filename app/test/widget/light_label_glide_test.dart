// Play on Light & shadow: the Sun and Earth labels glide, they never hop
// (1.13.5, K1). On the Android 7 emulator (1.13.4, IM-1 Odysseus, Play from
// 18 Nov 2026 21:00, 360x800) the Sun label moved 34 to 43 px in 4 of 50
// steps while its head moved 6 to 12 px (from above its head to below it,
// or sideways to the map's edge), and the Earth label 21 px with a still
// head: a head or the note band arriving under a label let it side-step by
// up to its head's move plus 48 px. Here the real map's layout (its size,
// view, site names, notes and part on screen, from a playback frame of the
// real app) is painted at every Play step (ten hours; and with the frames
// lagging, two steps at a time) of the IM-1 run (19 Nov to 31 Dec 2026) and
// the Shackleton rim SR1 run (16 Nov to 31 Dec) on a phone and a desktop:
// per step a label moves at most its head's move plus 12 px (by its centre
// or either end, as its words grow or shrink: arrowLabelMove), never covers
// the site marker, its name, the notes or the other label, and stays inside
// the shown map; a repaint with no new time never moves it.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/main.dart';
import 'package:polar_horizon/state/app_state.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';
import 'package:polar_horizon/widgets/light_map.dart';
import 'package:provider/provider.dart';

import 'light_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;

  setUpAll(loadPlexFonts);
  setUp(() async {
    state = AppState();
    await state.init();
  });
  tearDown(() => state.dispose());

  final mapPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is LightFramePainter);
  LightFramePainter painter(WidgetTester tester) => tester.widget<CustomPaint>(mapPaint).painter! as LightFramePainter;

  const hour = 3600 * 1000.0;
  for (final (id, name, from, to) in [
    ('im-1-odysseus-landed', 'IM-1 Odysseus', DateTime.utc(2026, 11, 18, 21), DateTime.utc(2026, 12, 31, 23)),
    ('derosa2012-sr1-shackleton-rim', 'Shackleton rim SR1', DateTime.utc(2026, 11, 16), DateTime.utc(2026, 12, 31, 23)),
  ]) {
    for (final screen in const [Size(360, 800), Size(1440, 900)]) {
      testWidgets('$name, ${screen.width.round()}x${screen.height.round()}: per Play step a label moves at most its '
          'head\'s move plus a settle step', (tester) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(value: state, child: const LunarHorizonApp()));
        await tester.pump();
        await tester.runAsync(() => state.setRange(from, to.add(const Duration(days: 1))));
        state.openSite(id, tab: SiteTab.light);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        state.setCursor(from.millisecondsSinceEpoch.toDouble());
        state.togglePlay();
        await tester.pump();
        // up to the first playback frame: the map as Play shows it (the
        // bars hidden, the playback note's band)
        for (var i = 0; i < 400 && find.byKey(const ValueKey('light-coarse')).evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('light-coarse')), findsOneWidget, reason: 'a playback frame is shown');
        final p = painter(tester);
        final size = tester.getSize(mapPaint);
        state.togglePlay();
        expect(p.noteArea, isNotNull);
        final eph = state.eph!, obs = state.observer, mask = state.mask, o = state.options;

        final log = <String>[];
        var steps = 0, overlaps = 0, worst = 0.0, worstCentre = 0.0;
        void walk(List<double> times, String how) {
          final m = ArrowLabelMemory();
          List<Offset>? lastC, lastT;
          List<Size>? lastS;
          var over = 0;
          for (final t in times) {
            LightFramePainter at(ArrowLabelMemory mem) => LightFramePainter(
              hillshade: p.hillshade,
              halfWidthM: p.halfWidthM,
              images: null,
              view: p.view,
              sites: p.sites,
              selected: p.selected,
              now: nowAt(eph, obs, mask, t, o),
              closeUp: p.closeUp,
              noteArea: p.noteArea,
              labelMemory: mem,
              shownArea: p.shownArea,
              earthRule: p.earthRule,
              requireDsn: p.requireDsn,
              textScaler: p.textScaler,
              exact: p.exact,
            );
            final when = DateTime.fromMillisecondsSinceEpoch(t.round(), isUtc: true).toIso8601String().substring(5, 13);
            final frame = at(m);
            void paint() {
              final rec = ui.PictureRecorder();
              frame.paint(Canvas(rec), size);
              rec.endRecording().dispose();
            }

            paint();
            final c = [...m.centres], tips = [...m.tips];
            // a repaint with no new time
            paint();
            for (var k = 0; k < c.length; k++) {
              if (m.centres[k] != c[k]) log.add('$how $when: a repaint moved label $k');
            }
            final keep = [...m.kept.take(2), p.noteArea!];
            final shown = p.shownArea ?? Offset.zero & size;
            final boxes = [
              for (var k = 0; k < c.length; k++)
                Rect.fromCenter(center: c[k], width: m.sizes[k].width, height: m.sizes[k].height),
            ];
            // the Sun label (drawn over the Earth one) may slide over it as
            // it glides past, for a few steps, rather than hop round it
            if (boxes.length == 2 && boxes[0].overlaps(boxes[1])) {
              overlaps++;
              if (++over > 3) log.add('$how $when: the labels overlap for $over steps');
            } else {
              over = 0;
            }
            for (var k = 0; k < c.length; k++) {
              final b = boxes[k];
              final what = k == 0 ? 'Earth' : 'Sun';
              for (final r in keep) {
                if (b.overlaps(r)) log.add('$how $when: $what label $b covers $r');
              }
              if (!shown.inflate(0.5).contains(b.topLeft) || !shown.inflate(0.5).contains(b.bottomRight)) {
                log.add('$how $when: $what label $b outside the shown map $shown');
              }
              if (lastC != null && k < lastC.length) {
                final moved = arrowLabelMove(lastC[k], lastS![k], c[k], m.sizes[k]), head = (tips[k] - lastT![k]).distance;
                steps++;
                if (moved - head > worst) worst = moved - head;
                if (moved > head + arrowLabelSettle + 0.5) {
                  log.add('$how $when: $what label moved ${moved.toStringAsFixed(1)} px, its head '
                      '${head.toStringAsFixed(1)} px');
                }
                // (by its centre: its words grow or shrink at the map's edge)
                final centre = (c[k] - lastC[k]).distance;
                if (centre - head > worstCentre) worstCentre = centre - head;
              }
            }
            lastC = c;
            lastT = tips;
            lastS = [...m.sizes];
          }
        }

        final t0 = from.millisecondsSinceEpoch.toDouble(), t1 = to.millisecondsSinceEpoch.toDouble();
        walk([for (var t = t0; t <= t1; t += 10 * hour) t], 'every step');
        // the frames lagging (Android 7: a step skipped now and then)
        walk([for (var t = t0, i = 0; t <= t1; t += (i++ % 3 == 2 ? 20 : 10) * hour) t], 'with skips');
        debugPrint('$name ${screen.width.round()}x${screen.height.round()}: $steps label steps, worst move beyond '
            'the head ${worst.toStringAsFixed(1)} px (its centre ${worstCentre.toStringAsFixed(1)} px), $overlaps steps with the Sun label over the Earth one, ${log.length} findings');
        expect(log, isEmpty);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  }
}
