/// Learn › "How it's calculated": renders lib/content/how_calculated.dart
/// (the scope first, then what is not modelled, then one card per section).
/// Nothing is copied into this file; the words live in the content file.
/// Phones get one column; from 840 dp two columns, at most 1040 wide.
library;

import 'package:flutter/material.dart';

import '../content/how_calculated.dart';
import '../theme.dart';

class HowCalculatedPage extends StatelessWidget {
  const HowCalculatedPage({super.key});

  static const twoColumnWidth = 840.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('How it\'s calculated')),
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= twoColumnWidth;
        final side = box.maxWidth > 1040 ? (box.maxWidth - 1040) / 2 : 0.0;
        final cards = [for (final (i, c) in calcSections.indexed) CalcCard(section: c, number: i + 1)];
        const scope = _ScopeCard();
        const notModelled = _NotModelledCard();
        return ListView(
          padding: EdgeInsets.fromLTRB(16 + side, 16, 16 + side, 32),
          children: [
            if (wide) ...[
              const IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: scope),
                  SizedBox(width: 16),
                  Expanded(child: notModelled),
                ]),
              ),
              // numbered so the reading order survives the two columns
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [for (var i = 0; i < cards.length; i += 2) cards[i]])),
                const SizedBox(width: 16),
                Expanded(child: Column(children: [for (var i = 1; i < cards.length; i += 2) cards[i]])),
              ]),
            ] else ...[
              scope,
              notModelled,
              ...cards,
            ],
          ],
        );
      }),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard();

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: const Text('What the app works out', style: PHText.title)),
            const SizedBox(height: 8),
            const Text(calcScope, style: PHText.body),
          ]),
        ),
      );
}

class _NotModelledCard extends StatelessWidget {
  const _NotModelledCard();

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: const Text('What it does not model', style: PHText.title)),
            const SizedBox(height: 4),
            for (final t in calcNotModelled)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 9, right: 12, left: 2),
                    child: SizedBox(
                        width: 5, height: 5, child: DecoratedBox(decoration: BoxDecoration(color: PH.muted, shape: BoxShape.circle))),
                  ),
                  Expanded(child: Text(t, style: PHText.body)),
                ]),
              ),
          ]),
        ),
      );
}

/// One [CalcSection]: plain words, the maths in a monospace block, how
/// accurate it is, and where formula.md derives it.
class CalcCard extends StatelessWidget {
  final CalcSection section;
  final int number;
  const CalcCard({super.key, required this.section, required this.number});

  @override
  Widget build(BuildContext context) {
    final c = section;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            header: true,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$number  ', style: statStyle(size: 17, color: PH.muted)),
              TextSpan(text: c.title, style: PHText.subtitle),
            ])),
          ),
          const SizedBox(height: 8),
          Text(c.plain, style: PHText.body),
          const SizedBox(height: 12),
          Semantics(
            label: 'The maths',
            container: true,
            child: Container(
              key: ValueKey('maths-$number'),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(color: PH.sunken, borderRadius: BorderRadius.circular(PH.radiusInner)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final m in c.maths)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(m, style: numStyle(size: 14).copyWith(height: 1.45)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'How accurate: ', style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
            TextSpan(text: c.accuracy, style: PHText.body),
          ])),
          const SizedBox(height: 8),
          Text('Full derivation: ${c.ref}, in the project repository', style: PHText.small.copyWith(color: PH.muted)),
        ]),
      ),
    );
  }
}
