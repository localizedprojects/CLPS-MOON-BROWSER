/// Explain sheet: one glossary entry ("Words we use"), opened from every "?"
/// in the app. Other words are one tap away, so a reader can follow a chain
/// ("DSN" -> "DTE") without leaving the sheet.
library;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../explain.dart' show glossary;
import 'sheet_frame.dart';

/// Opens the glossary entry for [term] (a key of [glossary]).
Future<void> showExplain(BuildContext context, String term) =>
    showPhSheet<void>(context, (_) => ExplainSheet(term: term));

/// A small 48 dp "?" button that opens [showExplain] for [term].
class ExplainButton extends StatelessWidget {
  final String term;

  /// What the reader sees the term called, when it differs from the key.
  final String? label;
  const ExplainButton(this.term, {super.key, this.label});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'What does "${label ?? term}" mean?',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.help_outline, size: 20, color: PH.muted),
        onPressed: () => showExplain(context, term),
      );
}

class ExplainSheet extends StatefulWidget {
  final String term;
  const ExplainSheet({super.key, required this.term});

  @override
  State<ExplainSheet> createState() => _ExplainSheetState();
}

class _ExplainSheetState extends State<ExplainSheet> {
  late String _term = widget.term;

  @override
  Widget build(BuildContext context) {
    final def = glossary[_term];
    final others = [for (final k in glossary.keys) if (k != _term) k];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(_term),
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              def ?? 'This word is not in the glossary yet. Learn › Words we use lists every word that is.',
              style: PHText.body,
            ),
          ),
        ),
        const SheetSection('Other words we use'),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in others)
              Semantics(
                button: true,
                label: 'Explain $k',
                excludeSemantics: true,
                onTap: () => setState(() => _term = k),
                child: ActionChip(
                  label: Text(k),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: () => setState(() => _term = k),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
