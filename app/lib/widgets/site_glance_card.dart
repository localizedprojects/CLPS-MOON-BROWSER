/// "At a glance" (the overview engine, core/site_glance.dart): what a place
/// is, why it is on the list or what stands out, what to watch out for and how
/// it compares, with the details and sources behind a disclosure.
///
/// Render-only: every word comes from [SiteGlance]; this file only lays it
/// out. Every number is set in IBM Plex Mono with tabular figures through
/// [numSpans]. No Sun, Earth or teal colours: warnings are an icon and the
/// WATCH OUT label, in the muted text colour.
library;

import 'package:flutter/material.dart';

import '../core/catalog.dart' show SiteSource;
import '../core/site_glance.dart';
import '../core/text_runs.dart';
import '../theme.dart';
import 'site_card.dart' show FocusRingInkWell;

const glanceTitle = 'At a glance';

/// What the Details disclosure says it holds (its screen-reader hint).
const glanceDetailsHint = 'Where it is, the skyline, more watch-outs and where the text comes from';

/// [s] as spans of [base], with every number (numberRuns) in Plex Mono with
/// tabular figures at the same size, weight and colour.
TextSpan numSpans(String s, TextStyle base) => TextSpan(style: base, children: [
      for (final r in numberRuns(s))
        TextSpan(
          text: r.text,
          style: r.number
              ? numStyle(size: base.fontSize ?? 14, weight: base.fontWeight ?? FontWeight.w400, color: base.color ?? PH.text)
              : null,
        ),
    ]);

/// 'Details and sources (5)', or 'Details' when there are no sources (custom
/// spots).
String glanceDetailsLabel(int sources) => sources > 0 ? 'Details and sources ($sources)' : 'Details';

/// What a screen reader says for the Details button.
String glanceDetailsSemantics(int sources) => sources > 0 ? 'Details and sources, $sources' : 'Details';

class SiteGlanceCard extends StatefulWidget {
  final SiteGlance glance;

  /// The site the card is for: the Details open state is kept per site in
  /// [PageStorage] under 'glance-$siteId'.
  final String siteId;

  /// Show the short custom-horizon badge on a custom spot's card (false on
  /// Overview, where the full badge already sits above).
  final bool showCustomBadge;

  /// Details start open (expert mode) unless the reader has toggled them.
  final bool initiallyOpen;

  const SiteGlanceCard({
    super.key,
    required this.glance,
    required this.siteId,
    this.showCustomBadge = true,
    this.initiallyOpen = false,
  });

  @override
  State<SiteGlanceCard> createState() => _SiteGlanceCardState();
}

class _SiteGlanceCardState extends State<SiteGlanceCard> {
  String get _storageId => 'glance-${widget.siteId}';

  bool get _open =>
      (PageStorage.maybeOf(context)?.readState(context, identifier: _storageId) as bool?) ?? widget.initiallyOpen;

  void _toggle() {
    final next = !_open;
    PageStorage.maybeOf(context)?.writeState(context, next, identifier: _storageId);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.glance;
    final open = _open;
    // the engine adds 'What this cannot tell you' for custom spots only
    final custom = g.details.any((d) => d.$1 == glanceLimitsHeading);
    final n = g.sources.length;
    return Card(
      color: PH.panel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              label: g.eyebrowSpoken,
              excludeSemantics: true,
              child: MicroLabel(g.eyebrow),
            ),
            Semantics(header: true, child: Text(glanceTitle, style: PHText.subtitle)),
            if (custom && widget.showCustomBadge) const FidelityBadge(text: FidelityBadge.customHorizonShort),
            for (final (row, label, lines) in g.rows) ...[
              const SizedBox(height: 12),
              MicroLabel(label),
              for (final l in lines) _GlanceLineView(l, warning: row == GlanceRow.watch),
              if (row == GlanceRow.what && g.factsLine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(numSpans(g.factsLine!, PHText.small.copyWith(color: PH.muted))),
                ),
            ],
            const SizedBox(height: 6),
            Semantics(
              button: true,
              expanded: open,
              label: glanceDetailsSemantics(n),
              hint: glanceDetailsHint,
              excludeSemantics: true,
              onTap: _toggle,
              child: FocusRingInkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(numSpans(glanceDetailsLabel(n), PHText.body.copyWith(fontWeight: FontWeight.w600))),
                    ),
                    Icon(open ? Icons.expand_less : Icons.expand_more, color: PH.muted),
                  ]),
                ),
              ),
            ),
            if (open) _Details(g),
          ]),
        ),
      ),
    );
  }
}

/// One sentence: pending lines are a live region with a busy indicator;
/// approximate ones end with a muted '(approx.)'; watch-outs start with a
/// muted warning icon.
class _GlanceLineView extends StatelessWidget {
  final GlanceLine line;
  final bool warning;
  const _GlanceLineView(this.line, {this.warning = false});

  @override
  Widget build(BuildContext context) {
    final muted = PHText.body.copyWith(color: PH.muted);
    if (line.pending) {
      return Semantics(
        container: true,
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            const BusyIndicator(size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(line.text, style: muted)),
          ]),
        ),
      );
    }
    final text = Text.rich(TextSpan(children: [
      numSpans(line.text, PHText.body),
      if (line.approximate) TextSpan(text: ' (approx.)', style: PHText.small.copyWith(color: PH.muted)),
    ]));
    final icon = warning && line.text != glanceNothingToWatchText;
    return Semantics(
      label: line.semanticsLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: icon
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 6),
                  child: Icon(Icons.warning_amber_outlined, size: 16, color: PH.muted),
                ),
                Expanded(child: text),
              ])
            : text,
      ),
    );
  }
}

/// The groups behind the disclosure, then the numbered sources.
class _Details extends StatelessWidget {
  final SiteGlance g;
  const _Details(this.g);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (heading, lines) in g.details) ...[
            const SizedBox(height: 8),
            MicroLabel(heading),
            for (final l in lines) _GlanceLineView(l, warning: heading == glanceMoreWatchHeading),
          ],
          if (g.sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            MicroLabel(glanceSourcesHeading),
            for (var i = 0; i < g.sources.length; i++) _SourceRow(i + 1, g.sources[i]),
          ],
        ]),
      );
}

class _SourceRow extends StatelessWidget {
  final int index;
  final SiteSource source;
  const _SourceRow(this.index, this.source);

  @override
  Widget build(BuildContext context) {
    final title = source.title.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 28, child: Text('$index.', style: numStyle(size: 14, color: PH.muted))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title.isNotEmpty) Text(title, style: PHText.body),
            if (source.url.isNotEmpty) SelectableText(source.url, style: numStyle(size: 12, color: PH.muted)),
          ]),
        ),
      ]),
    );
  }
}
