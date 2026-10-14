// The chart bridge across host remounts, and charts that a layout change
// moves keeping their host (and so their web view).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';
import 'package:polar_horizon/widgets/chart_host_mobile.dart' show MessageQueue;
import 'package:polar_horizon/widgets/chart_view.dart';

void main() {
  group('ChartController', () {
    const ready = '{"type":"ready","view":"sky"}';
    Map<String, dynamic> msg(String type) => {'type': type, 'n': 1};

    test('a new host attached before the old one is disposed keeps the chart alive', () {
      final c = ChartController('sky');
      final a = <String>[], b = <String>[];
      final ownerA = Object(), ownerB = Object();
      c.attach(a.add, ownerA);
      c.handleRaw(ready);
      // remount: Flutter builds the new host, then disposes the old one
      c.attach(b.add, ownerB);
      c.detach(ownerA);
      c.send(msg('sky'));
      expect(b, isEmpty, reason: 'the new page has not reported ready yet');
      c.handleRaw(ready);
      expect(c.ready, isTrue);
      expect(b.map((j) => jsonDecode(j)['type']), ['sky']);
      c.send(msg('skyNow'));
      expect(b.length, 2);
      expect(a, isEmpty);
    });

    test('the current host detaching stops delivery', () {
      final c = ChartController('sky');
      final a = <String>[];
      final owner = Object();
      c.attach(a.add, owner);
      c.handleRaw(ready);
      c.detach(owner);
      expect(c.ready, isFalse);
      c.send(msg('sky'));
      expect(a, isEmpty);
    });

    test('an export is sent once, only to a ready page, and never replayed', () {
      final c = ChartController('sky');
      final a = <String>[], b = <String>[];
      c.attach(a.add, 1);
      c.send(msg('exportPng'));
      c.handleRaw(ready);
      expect(a, isEmpty, reason: 'not buffered while the page loads');
      c.send(msg('sky'));
      c.send(msg('exportPng'));
      expect(a.map((j) => jsonDecode(j)['type']), ['sky', 'exportPng']);
      // a re-created page gets the chart data again, not the export
      c.attach(b.add, 2);
      c.handleRaw(ready);
      expect(b.map((j) => jsonDecode(j)['type']), ['sky']);
    });

    test('a replay delivers the buffered messages in the order they were last sent', () {
      // async-1 / web-2: a cursor sent after the payload must arrive after it
      // (the page applies the newer of the two), and a cursor that predates a
      // new payload (another site) must arrive before it.
      final c = ChartController('timeline');
      final a = <String>[];
      c.attach(a.add, 1);
      c.send({'type': 'timeline', 'cursor': 0});
      c.send({'type': 'cursor', 't': 5});
      c.handleRaw('{"type":"ready","view":"timeline"}');
      expect(a.map((j) => jsonDecode(j)['type']), ['timeline', 'cursor']);

      c.send({'type': 'timeline', 'cursor': 7}); // a new site, after the cursor
      final b = <String>[];
      c.attach(b.add, 2);
      c.handleRaw('{"type":"ready","view":"timeline"}');
      expect(b.map((j) => jsonDecode(j)['type']), ['cursor', 'timeline']);
      expect(jsonDecode(b.last)['cursor'], 7);
    });

    test('ready changes are observable (export menus update when a page loads)', () {
      final c = ChartController('compare');
      var calls = 0;
      c.readyListenable.addListener(() => calls++);
      c.attach((_) {}, 1);
      c.handleRaw('{"type":"ready","view":"compare"}');
      expect(c.readyListenable.value, isTrue);
      c.detach(1);
      expect(c.readyListenable.value, isFalse);
      expect(calls, 2);
    });
  });

  group('MessageQueue (Android web view backpressure, android-1)', () {
    test('a newer message of a type replaces the queued one; order follows the last send', () {
      final q = MessageQueue()
        ..add(jsonEncode({'type': 'skyNow', 'n': 1}))
        ..add(jsonEncode({'type': 'sky', 'n': 1}))
        ..add(jsonEncode({'type': 'skyNow', 'n': 2}))
        ..add(jsonEncode({'type': 'skyNow', 'n': 3}));
      final out = <Map<String, dynamic>>[];
      while (!q.isEmpty) {
        out.add(jsonDecode(q.take()) as Map<String, dynamic>);
      }
      expect(out.map((m) => '${m['type']}${m['n']}'), ['sky1', 'skyNow3']);
    });

    test('exports are never merged', () {
      final q = MessageQueue()
        ..add(jsonEncode({'type': 'exportPng', 'id': 'a'}))
        ..add(jsonEncode({'type': 'exportPng', 'id': 'b'}));
      expect([jsonDecode(q.take())['id'], jsonDecode(q.take())['id']], ['a', 'b']);
      expect(q.isEmpty, isTrue);
    });
  });

  testWidgets('a chart moved by a layout change keeps its host', (tester) async {
    final sky = ChartController('sky');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 800);
    addTearDown(tester.view.reset);
    var explain = false;
    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, set) {
        setState = set;
        final chart = ChartView(controller: sky, semanticsLabel: 'Sky plot');
        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 1000) return Row(children: [Expanded(child: chart)]);
          // like Sky & time on a phone: cards appear on both sides of the chart
          return Column(children: [
            if (explain) const Text('About the sky plot'),
            SizedBox(height: 300, child: chart),
            if (explain) const Text('About the timeline'),
            const Text('Timeline'),
          ]);
        });
      }),
    ));
    final host = find.textContaining('needs Android or web');
    final first = tester.element(host);

    setState(() => explain = true); // a child inserted before the chart
    await tester.pump();
    expect(tester.element(host), same(first));

    tester.view.physicalSize = const Size(1200, 800); // the other layout branch
    await tester.pump();
    expect(tester.element(host), same(first));
    expect(tester.takeException(), isNull);
  });
}
