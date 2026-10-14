/// Share & export: the four exports in one sheet, open to everyone. An export
/// that cannot run yet stays visible, greyed out, with the reason in place of
/// its description (never a silent no-op).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/wording.dart' show everyStep;
import '../../state/app_state.dart';
import '../../state/chart_hub.dart';
import '../../theme.dart';
import 'sheet_frame.dart';

Future<void> showExportSheet(BuildContext context) => showPhSheet<void>(context, (_) => const ExportSheet());

const _busyText = 'Still working out your new choices; try again in a moment';

/// Why the time-series CSV cannot be exported yet (null = it can). While new
/// choices are being worked out, [AppState.series] still holds the previous
/// choices' series but [AppState.options] already holds the new rules, so the
/// file would describe one and contain the other.
String? seriesExportBlocker(AppState s) {
  if (s.series == null) return 'The selected site is still being worked out';
  if (s.loading) return _busyText;
  return null;
}

/// Why the sky + timeline PNGs cannot be exported yet (null = they can).
String? skyExportBlocker(AppState s, {required bool chartsReady}) {
  if (s.series == null) return 'The selected site is still being worked out';
  // the charts still show the previous choices until the new series is in
  if (s.loading) return _busyText;
  if (chartsReady) return null;
  return s.dest == Dest.site && s.siteTab == SiteTab.skyTime
      ? 'The charts are still loading; try again in a moment'
      : 'Open Site › Sky & time once to draw them';
}

/// Why the comparison PNG cannot be exported yet (null = it can).
String? compareExportBlocker(AppState s, {required bool chartReady}) {
  if (s.compareIds.length < 2) return 'Shortlist two or more sites first';
  if (!s.compareReady) return 'Still ranking the shortlisted sites; try again in a moment';
  if (chartReady) return null;
  return s.dest == Dest.compare ? 'The comparison chart is still loading; try again in a moment' : 'Open Compare once to draw the chart';
}

/// Why the scorecard CSV cannot be exported yet (null = it can).
String? scorecardExportBlocker(AppState s) {
  if (s.compareIds.isEmpty) return 'Shortlist at least one site first';
  if (!s.compareReady) return 'Still ranking the shortlisted sites; try again in a moment';
  return null;
}

/// How often the time-series CSV samples, in words ('hourly', '30-minute'),
/// from the series step in milliseconds. The CSV writes every sample of the
/// series, so its step is the app's sample step, which depends on the period.
String sampleStepWords(double stepMs) {
  final mins = (stepMs / 60000).round();
  if (mins >= 60 && mins % 60 == 0) {
    final h = mins ~/ 60;
    return h == 1 ? 'hourly' : '$h-hour';
  }
  return '$mins-minute';
}

/// What the time-series CSV holds, in the same terms as Mission settings
/// (sampleStepText): one row per step of the series, worked out from the
/// hourly data ("One row every 30 minutes, interpolated from the hourly data").
String csvRowsText(double stepMs) => stepMs < 3600e3
    ? 'One row ${everyStep(stepMs)}, interpolated from the hourly data'
    : 'One row ${everyStep(stepMs)}, from the hourly data';

class ExportSheet extends StatelessWidget {
  const ExportSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final hub = context.read<ChartHub>();
    void run(VoidCallback f) {
      Navigator.of(context).pop();
      f();
    }

    // the chart pages report ready on their own schedule: rebuild when they do
    return ListenableBuilder(
      listenable: Listenable.merge([hub.sky.readyListenable, hub.timeline.readyListenable, hub.compare.readyListenable]),
      builder: (context, _) {
        final name = s.catalog == null || s.series == null ? null : s.site.short;
        final n = s.compareIds.length;
        final tiles = [
          _ExportTile(
            icon: Icons.table_chart_outlined,
            title: 'Time series (CSV)',
            ready: '${csvRowsText(s.series?.stepMs ?? s.options.stepMs)} for $name. The header records the ephemeris, frame and rules.',
            blocker: seriesExportBlocker(s),
            onTap: () => run(() => hub.exportSeriesCsv(s)),
          ),
          _ExportTile(
            icon: Icons.image_outlined,
            title: 'Sky and timeline charts (PNG)',
            ready: 'Two images for $name, saved together.',
            blocker: skyExportBlocker(s, chartsReady: hub.sky.ready && hub.timeline.ready),
            onTap: () => run(() => hub.exportSkyTimelinePng(s)),
          ),
          _ExportTile(
            icon: Icons.bar_chart,
            title: 'Comparison chart (PNG)',
            ready: 'The $n shortlisted sites side by side.',
            blocker: compareExportBlocker(s, chartReady: hub.compare.ready),
            onTap: () => run(() => hub.exportComparePng(s)),
          ),
          _ExportTile(
            icon: Icons.leaderboard_outlined,
            title: 'Scorecard (CSV)',
            ready: 'Score and metrics of the $n shortlisted ${n == 1 ? 'site' : 'sites'}.',
            blocker: scorecardExportBlocker(s),
            onTap: () => run(() => hub.exportScorecard(s)),
          ),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SheetHeader('Share & export',
                  subtitle: 'Files use UTC times and say which rules and period they were made with.'),
            ),
            if (s.loading || !s.rankingDone)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(children: [
                    const BusyIndicator(size: 18, strokeWidth: 2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.rankTotal > 0
                            ? 'Working out your choices: ${s.rankProgress} of ${s.rankTotal} sites done'
                            : 'Working out your choices…',
                        style: PHText.small.copyWith(color: PH.muted),
                      ),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            ...tiles,
          ]),
        );
      },
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final String title, ready;
  final String? blocker;
  final VoidCallback onTap;
  const _ExportTile({required this.icon, required this.title, required this.ready, required this.blocker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = blocker == null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? '$title. $ready' : '$title. Not available yet: $blocker',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: ListTile(
        minTileHeight: 64,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PH.radiusInner)),
        leading: Icon(icon),
        title: Text(title, style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(enabled ? ready : blocker!, style: PHText.small.copyWith(color: PH.muted)),
        trailing: enabled ? const Icon(Icons.download_outlined, size: 20) : const Icon(Icons.block, size: 18, color: PH.muted),
        enabled: enabled,
        onTap: onTap,
      ),
    );
  }
}
