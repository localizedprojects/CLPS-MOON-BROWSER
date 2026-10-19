// Web Play waits for the chart iframe: the host numbers every message it
// posts and the page acks the newest one it has drawn (charts/src/bridge.ts,
// "Acks"). ChartAcks is that bookkeeping, wired as chart_host_web.dart
// wires it; it runs on the VM.
import 'dart:convert';

import 'package:flutter/widgets.dart';
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

  testWidgets('a chart kept alive off stage never holds Play (its tab mutes its tickers)', (tester) async {
    ready();
    cursor(1);
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: shown,
      builder: (_, on, _) => TickerMode(enabled: on, child: _Host(acks)),
    ));
    expect(acks.onStage, isTrue);
    expect(c.behind, isTrue, reason: 'on screen: Play waits for it');
    // Site > Overview on a narrow screen: Sky & time stays alive off stage,
    // where its iframe gets no animation frames, so no ack would come
    shown.value = false;
    await tester.pump();
    expect(acks.onStage, isFalse);
    expect(c.behind, isFalse, reason: 'going off stage forgets what it owed');
    cursor(2);
    cursor(3);
    expect(posted.map((p) => p.n), [1, 2, 3], reason: 'still delivered: the page draws them when it shows');
    expect(c.behind, isFalse, reason: 'off stage it never holds Play');
    now = 1000;
    shown.value = true;
    await tester.pump();
    expect(acks.onStage, isTrue);
    expect(c.behind, isTrue, reason: 'back on stage: the newest cursor is not drawn yet');
    ack(3);
    expect(c.behind, isFalse);
  });

  testWidgets('a host moved by its GlobalKey follows the TickerMode of its new place', (tester) async {
    ready();
    final key = GlobalKey();
    Widget at({required bool hidden}) => Row(textDirection: TextDirection.ltr, children: [
          TickerMode(enabled: false, child: hidden ? _Host(acks, key: key) : const SizedBox()),
          TickerMode(enabled: true, child: hidden ? const SizedBox() : _Host(acks, key: key)),
        ]);
    await tester.pumpWidget(at(hidden: true));
    cursor(1);
    expect(c.behind, isFalse);
    await tester.pumpWidget(at(hidden: false));
    cursor(2);
    expect(acks.onStage, isTrue);
    expect(c.behind, isTrue);
    await tester.pumpWidget(at(hidden: true));
    expect(c.behind, isFalse);
  });

  testWidgets('a host that goes away never holds Play and stops following the TickerMode it left', (tester) async {
    ready();
    final on = ValueNotifier(true), shown = ValueNotifier(true);
    addTearDown(on.dispose);
    addTearDown(shown.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: on,
      builder: (_, e, _) => TickerMode(
        enabled: e,
        child: ValueListenableBuilder<bool>(valueListenable: shown, builder: (_, s, _) => s ? _Host(acks) : const SizedBox()),
      ),
    ));
    cursor(1);
    expect(acks.busy, isTrue);
    shown.value = false; // the host goes, its TickerMode stays
    await tester.pump();
    expect(acks.busy, isFalse, reason: 'a page that goes away never holds Play');
    on.value = false;
    await tester.pump();
    expect(acks.onStage, isTrue, reason: 'no longer following the TickerMode it left');
  });

  test('an iframe out of the document (no window) gets no numbers and never holds Play', () {
    var inDocument = true;
    acks.attach(c, (json, n) => posted.add((msg: jsonDecode(json) as Map<String, dynamic>, n: n)), host,
        reachable: () => inDocument);
    ready();
    cursor(1);
    expect(c.behind, isTrue);
    inDocument = false; // the platform view is not painted: its iframe left the document
    expect(c.behind, isFalse, reason: 'its page is gone, and what it was sent with it');
    cursor(2);
    expect(posted.map((p) => p.n), [1], reason: 'a message it cannot get takes no number');
    inDocument = true; // painted again: the iframe loads its page again
    expect(c.behind, isFalse, reason: 'nothing it never got is waited for');
    ready(); // the reloaded page: the buffer is replayed, numbered and waited for
    expect(posted.map((p) => p.n), [1, 2]);
    expect(posted.last.msg, {'type': 'cursor', 't': 2});
    expect(c.behind, isTrue);
    ack(2);
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

/// A chart host on the VM, wired as chart_host_web.dart's (which does not
/// run on the VM) by the same [ChartAcksHost], so the tested wiring is the
/// shipped one.
class _Host extends StatefulWidget {
  const _Host(this.acks, {super.key});
  final ChartAcks acks;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with ChartAcksHost<_Host> {
  @override
  ChartAcks get acks => widget.acks;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
