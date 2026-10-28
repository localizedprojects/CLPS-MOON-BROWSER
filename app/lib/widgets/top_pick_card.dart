/// The answer with zero taps: the top-ranked site under the current goal,
/// pictured by its computed light at the start of its longest Sun + Earth
/// stretch, with its both-up share and that stretch. Nothing is called "best"
/// until every site has been ranked.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/metrics.dart' show SiteMetrics;
import '../core/ranking.dart';
import '../core/summary.dart' show date, duration;
import '../core/wording.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'light_snapshot.dart';
import 'stat_bar.dart';
import 'feature_guide.dart';

/// "Best spot for the next 12 months" (the default period), else
/// "Best spot for 1 Jan 2027 – 31 Jan 2027"; the goal is named when it is
/// not the balanced default.
String topPickEyebrow(String period, Goal? goal) {
  final when = period == 'Next 12 months' ? 'the next 12 months' : period;
  final why = switch (goal) {
    Goal.balanced => '',
    null => ' · your own weights',
    final g => ' · ${goalLabel(g)}',
  };
  return 'Best spot for $when$why';
}

/// "Sun and Earth both up 47% of the time" (or the DSN wording).
String bothUpText(SiteMetrics m, {required bool requireDsn}) => requireDsn
    ? 'Sunlight and Earth contact (DSN) together ${StatBar.pctText(m.pctBoth)} of the time'
    : 'Sun and Earth both up ${StatBar.pctText(m.pctBoth)} of the time';

/// "Longest stretch with both: 13.0 days from 12 Sep 2027".
String longestBothText(SiteMetrics m, {required bool requireDsn}) {
  final b = m.longestBoth;
  if (b == null) {
    return requireDsn
        ? 'Sunlight and Earth contact never overlap in this period'
        : 'Sun and Earth are never up together in this period';
  }
  return 'Longest stretch with both: ${duration(b.hours)} from ${date(b.startMs)}';
}

class TopPickCard extends StatelessWidget {
  const TopPickCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.rankingDone) return _Ranking(state: s);
    final top = s.rankedAll.firstOrNull;
    final site = top == null ? null : s.allSites.where((x) => x.id == top.id).firstOrNull;
    if (top == null || site == null) return const SizedBox.shrink();
    final m = top.metrics;
    final dsn = s.options.requireDsn;
    final period = periodLabel(s.rangeStartMs, s.rangeEndMs, DateTime.now().toUtc());
    // the picture: the start of the longest Sun + Earth stretch (else of the
    // longest sunlit stretch, else the period start); the caption gives the time
    final tMs = m.longestBoth?.startMs ?? m.longestSun?.startMs ?? s.rangeStartMs;
    final top3 = [for (final r in s.rankedAll.take(3)) r.id];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        // the answer in words comes first, so it is above the fold on a phone,
        // then its actions; the computed picture of that moment follows
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // the answer and its actions are one ring in the Explore guide
          // ("Your best spot"); the picture below is not part of it
          GuideTarget(
            id: 'top-pick',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(topPickEyebrow(period, s.activeGoal), style: PHText.small.copyWith(color: PH.muted)),
              const SizedBox(height: 4),
              Semantics(header: true, child: Text(site.short, style: PHText.title)),
              const SizedBox(height: 2),
              Text(siteKindLabel(site), style: PHText.small.copyWith(color: PH.muted)),
              if (s.expert && site.name != site.short) Text(site.name, style: PHText.small.copyWith(color: PH.muted)),
              const SizedBox(height: 12),
              Text(bothUpText(m, requireDsn: dsn), style: statStyle(size: 16, weight: FontWeight.w400)),
              Text(inTen(m.pctBoth), style: PHText.small.copyWith(color: PH.muted)),
              const SizedBox(height: 6),
              Text(longestBothText(m, requireDsn: dsn), style: statStyle(size: 16, weight: FontWeight.w400)),
            ]),
          ),
          if (dsn) const FidelityBadge(text: dsnResolutionNote),
          if (site.custom) const FidelityBadge(text: FidelityBadge.customHorizon),
          const SizedBox(height: 12),
          // the actions come straight after the answer, above the picture, so
          // they are close to the answer and never under the compare tray
          // (ux1-3)
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Semantics(
              container: true,
              button: true,
              label: 'See this site: ${site.short}',
              excludeSemantics: true,
              onTap: () => s.openSite(site.id),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => s.openSite(site.id),
                child: const Text('See this site'),
              ),
            ),
            if (top3.length >= 2)
              Semantics(
                container: true,
                button: true,
                label: 'Compare the top ${top3.length} sites',
                excludeSemantics: true,
                onTap: () => _compareTop(s, top3),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => _compareTop(s, top3),
                  child: Text('Compare top ${top3.length}'),
                ),
              ),
            Semantics(
              container: true,
              link: true,
              label: 'How is this ranked? Opens Learn',
              excludeSemantics: true,
              onTap: () => s.goTo(Dest.learn),
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => s.goTo(Dest.learn),
                child: const Text('How is this ranked?'),
              ),
            ),
          ]),
            ]),
          ),
          const SizedBox(height: 12),
          LightSnapshot(key: ValueKey('top-${site.id}'), site: site, tMs: tMs, aspect: 2.0, showFidelity: false),
          const SizedBox(height: 8),
          FidelityBadge(text: lightSnapshotFidelityFor(snapshotPastMap(s.mapLayers, site))),
        ]),
      ),
    );
  }

  static void _compareTop(AppState s, List<String> ids) {
    s.setCompare(ids);
    s.goTo(Dest.compare);
  }
}

/// After a change of period, height or rules: the progress of the re-ranking
/// (no site is named "best" from a partial ranking), and the error if it stopped.
class _Ranking extends StatelessWidget {
  final AppState state;
  const _Ranking({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const BusyIndicator(),
              const SizedBox(width: 12),
              Expanded(child: Text('Ranking the sites for your settings', style: PHText.subtitle)),
            ]),
            const SizedBox(height: 8),
            Text('${s.rankProgress} of ${s.rankTotal} sites worked out. The top pick appears when every site is in.',
                style: PHText.body.copyWith(color: PH.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            if (s.error case final err?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Problem: $err', style: PHText.small.copyWith(color: PH.warn)),
              ),
          ]),
        ),
      ),
    );
  }
}
