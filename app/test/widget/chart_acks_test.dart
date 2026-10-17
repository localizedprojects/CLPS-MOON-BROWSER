// Web Play waits for the chart iframe: the host numbers every message it
// posts and the page acks the newest one it has drawn (charts/src/bridge.ts,
// "Acks"). ChartAcks is that bookkeeping, wired as chart_host_web.dart
// wires it; it runs on the VM.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polar_horizon/widgets/chart_bridge.dart';

void main() {
  var now = 0;
  late ChartController c;
  late ChartAcks acks;
  late List<({Map<String, dynamic> msg, int n})> posted;
  late List<Map<String, dynamic>> events;
  late Object host;

  /// A web host for [c] as chart_host_web.dart builds it, and its page's ready.
  setUp(() {
    now = 0;
    events = [];
    c = ChartController('timeline', onEvent: events.add);
    acks = ChartAcks(clockMs: () => now);
    posted = [];
    host = Object();
    acks.attach(c, (json, n) => posted.add((msg: jsonDecode(json) as Map<String, dynamic>, n: n)), host);
  });

  void ready() => acks.handle(c, {'type': 'ready', 'view': 'timeline'});
  void ack(int n) => acks.handle(c, {'type': 'ack', 'n': n});
  void cursor(num t) => c.send({'type': 'cursor', 't': t});

  test('numbers every message and holds Play until the page acks the newest', () {
    ready();
    expect(c.ready, isTrue);
    expect(c.behind, isFalse, reason: 'a page that was sent nothing owes nothing');
    cursor(1);
    cursor(2);
    expect(posted.map((p) => p.n), [1, 2]);
    expect(posted.last.msg, {'type': 'cursor', 't': 2});
    expect(c.behind, isTrue);
    ack(1);
    expect(c.behind, isTrue, reason: 'the newest cursor is not drawn yet');
    ack(2);
    expect(c.behind, isFalse);
    expect(events.map((e) => e['type']), ['ready'], reason: 'acks stop at the web host');
  });

  test('a page loaded again owes nothing of what the old page was sent; its replay is waited for', () {
    ready();
    cursor(1); // the old page never acks it: it is reloading
    expect(c.behind, isTrue);
    ready(); // the new page: the controller replays its buffer to it
    expect(posted.map((p) => p.n), [1, 2]);
    expect(posted.last.msg, {'type': 'cursor', 't': 1});
    expect(c.behind, isTrue, reason: 'the replay is waited for');
    ack(1); // a late ack from the old page
    expect(c.behind, isTrue);
    ack(2);
    expect(c.behind, isFalse);
  });

  test('a page that stops answering holds Play for 3 s at most', () {
    ready();
    cursor(1);
    now = 2999;
    expect(c.behind, isTrue);
    now = 3000;
    expect(c.behind, isFalse, reason: 'a dead iframe never stops Play');
    cursor(2);
    now = 3500;
    expect(c.behind, isFalse, reason: 'still no sign of life');
    ack(1); // drawing again, still one behind
    expect(c.behind, isTrue);
    ack(2);
    expect(c.behind, isFalse);
  });

  test('a host that goes away leaves nothing waiting', () {
    ready();
    cursor(1);
    expect(c.behind, isTrue);
    // chart_host_web.dart dispose()
    acks.reset();
    c.detach(host);
    expect(acks.busy, isFalse);
    expect(c.behind, isFalse);
  });

  test('acks past the newest number or without one change nothing', () {
    ready();
    cursor(1);
    acks.handle(c, {'type': 'ack'});
    expect(c.behind, isTrue);
    ack(99);
    expect(acks.acked, 1);
    expect(c.behind, isFalse);
    cursor(2);
    expect(c.behind, isTrue, reason: 'an ack ahead of what was sent never pre-acks the next message');
  });

  test('Android: an ack that reaches a controller is ignored', () {
    final got = <String>[];
    final ev = <Map<String, dynamic>>[];
    final a = ChartController('sky', onEvent: ev.add);
    var running = false;
    a.attach(got.add, Object(), busy: () => running);
    a.handleRaw(jsonEncode({'type': 'ready', 'view': 'sky'}));
    a.send({'type': 'cursor', 't': 1});
    running = true;
    a.handleRaw(jsonEncode({'type': 'ack', 'n': 1}));
    expect(a.behind, isTrue, reason: 'the runJavaScript test alone decides on Android');
    expect(a.ready, isTrue);
    expect(ev.map((e) => e['type']), ['ready']);
    expect(got, hasLength(1));
  });
}
