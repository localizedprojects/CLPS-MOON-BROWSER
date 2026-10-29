/// Exact numbers for mission planners (shown only when "Show exact numbers"
/// is on): the Sun/Earth readout at the cursor and the period's key metrics.
library;

import 'package:flutter/material.dart';

import '../core/metrics.dart' show SiteMetrics;
import '../core/visibility.dart' show EarthCriterion, SunCriterion;
import '../core/wording.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'chart_bridge.dart';

/// "5.2 h", "36 h", "13.0 days".
String fmtDuration(double hours) {
  if (hours >= 48) return '${(hours / 24).toStringAsFixed(1)} days';
  return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} h';
}

/// Share of a disk above the skyline, never "0%" or "100%" when partly up
/// ("<1%", ">99%", the same as StatBar.pctText).
String _pct(double frac) {
  final p = (100 * frac).round();
  if (frac > 0 && p < 1) return '<1%';
  if (frac < 1 && p > 99) return '>99%';
  return '$p%';
}

/// Short state for the readout table. A disk that is partly above the skyline
/// but not counted under the current rule (or, for Earth, without a DSN
/// station) says so instead of "dark" / "hidden".
String readoutSunState({required bool visible, required double frac}) {
  if (visible) return 'lit ${_pct(frac)}';
  return frac > 0 ? '${_pct(frac)} up, not counted' : 'dark';
}

/// [terrainVisible]: Earth counts under the Earth rule from the terrain
/// alone, so only the DSN check rejects it ("in view, no DSN").
String readoutEarthState({required bool visible, required double frac, bool terrainVisible = false}) {
  if (visible) return 'in view';
  if (terrainVisible) return 'in view, no DSN';
  return frac > 0 ? '${_pct(frac)} up, not counted' : 'hidden';
}

/// The live power line's label (the power proxy at the time shown).
const powerNowLabel = 'Power on a Sun-facing panel (proxy)';

/// What the live power proxy assumes (its FidelityBadge).
const powerNowNote = 'Proxy: sunlight on a panel always turned to face the Sun, at the time shown: 1361 W/m² × '
    '(1 au / r)² × the visible part of the Sun\'s disk (terrain and Earth removed). No cos(elevation) term, so a fixed '
    'flat or upright panel gets less; no panel efficiency, temperature or dust losses.';

/// Exact Sun/Earth state at the cursor.
class ExpertReadout extends StatelessWidget {
  final AppState state;
  const ExpertReadout({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    final s = state;
    final n = nowAt(s.eph!, s.observer, s.mask, s.cursorMs, s.options);
    final sun = n['sun'] as Map<String, dynamic>, earth = n['earth'] as Map<String, dynamic>;
    final dsn = s.eph!.dsnMask(s.cursorMs);
    final names = [if (dsn & 1 != 0) 'Goldstone', if (dsn & 2 != 0) 'Madrid', if (dsn & 4 != 0) 'Canberra'];
    double d(Map<String, dynamic> m, String k) => (m[k] as num).toDouble();
    String f(num v) => v.toStringAsFixed(2).padLeft(7);
    const cell = TextStyle(fontSize: 13);
    TableRow row(String label, Color c, String az, String el, String hz, String state) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: label == 'Sun' ? BoxShape.circle : BoxShape.rectangle)),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
          Text(az, style: numStyle(size: 13), textAlign: TextAlign.right),
          Text(el, style: numStyle(size: 13), textAlign: TextAlign.right),
          Text(hz, style: numStyle(size: 13, color: PH.muted), textAlign: TextAlign.right),
          Padding(padding: const EdgeInsets.only(left: 8), child: Text(state, style: cell)),
        ]);
    final sunVisible = sun['visible'] == true, earthVisible = earth['visible'] == true;
    final sunLine = sunStatusText(
        visible: sunVisible, elDeg: d(sun, 'el'), rhoDeg: d(sun, 'rho'), frac: d(sun, 'frac'), sunRule: s.options.sunCriterion);
    final earthLine = earthStatusText(
      visible: earthVisible,
      elDeg: d(earth, 'el'),
      rhoDeg: d(earth, 'rho'),
      frac: d(earth, 'frac'),
      dsnRequired: s.options.requireDsn,
      dsnInView: dsn != 0,
      earthRule: s.options.earthCriterion,
      hzDeg: d(earth, 'hz'),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Semantics(header: true, child: Text('At ${utcLabel(s.cursorMs)}', style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
          ),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.1), 3: FlexColumnWidth(1.3), 4: FlexColumnWidth(1.6)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [
                const SizedBox(),
                for (final h in ['Az °', 'El °', 'Skyline °'])
                  Text(h, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: PH.muted)),
                const SizedBox(),
              ]),
              row('Sun', PH.sun, f(sun['az']), f(sun['el']), f(sun['hz']), readoutSunState(visible: sunVisible, frac: d(sun, 'frac'))),
              row('Earth', PH.earth, f(earth['az']), f(earth['el']), f(earth['hz']),
                  readoutEarthState(visible: earthVisible, frac: d(earth, 'frac'), terrainVisible: earth['terrainVisible'] == true)),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text('Sun: $sunLine. Earth: $earthLine.', style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
          const SizedBox(height: 4),
          Text('DSN in view: ${names.isEmpty ? 'none' : names.join(' · ')}', style: const TextStyle(fontSize: 13, color: PH.muted)),
          if (sun['power'] is num) ...[
            const SizedBox(height: 4),
            Text.rich(TextSpan(style: const TextStyle(fontSize: 13), children: [
              const TextSpan(text: '$powerNowLabel: '),
              TextSpan(text: '${(sun['power'] as num).round()} W/m²', style: numStyle(size: 13)),
              if ((sun['eclipse'] as num? ?? 0) > 0)
                TextSpan(text: ' · Earth covers ${((sun['eclipse'] as num) * 100).round().clamp(1, 100)}% of the Sun (lunar eclipse)'),
            ])),
            const SizedBox(height: 4),
            const FidelityBadge(text: powerNowNote),
          ],
        ]),
      ),
    );
  }
}

/// Instrument-style grid of the period's key metrics.
class ExpertMetrics extends StatelessWidget {
  final SiteMetrics m;

  /// The rules [m] was computed with (they label the tiles).
  final SunCriterion sunCriterion;
  final EarthCriterion earthCriterion;

  /// Earth tiles count Earth contact (Earth in view and a DSN station up).
  final bool requireDsn;
  const ExpertMetrics({
    super.key,
    required this.m,
    this.sunCriterion = SunCriterion.upperLimb,
    this.earthCriterion = EarthCriterion.center,
    this.requireDsn = false,
  });

  /// The power line's label: a proxy, not a power-system model.
  static const powerLabel = 'Mean power on a panel facing the Sun (proxy)';

  /// What the power proxy assumes.
  static const powerNote = 'Proxy: sunlight on a panel always turned to face the Sun, not a power-system model. '
      '1361 W/m² × (1 au / r)² × the visible part of the Sun\'s disk, averaged over your dates. There is no '
      'cos(elevation) term, so a fixed flat or upright panel gets less; no panel efficiency, temperature or dust '
      'losses.';

  @override
  Widget build(BuildContext context) {
    final sunRule = switch (sunCriterion) {
      SunCriterion.upperLimb => 'any part of the disk',
      SunCriterion.center => 'disk centre',
      SunCriterion.fullDisk => 'whole disk',
    };
    final earthRule = switch (earthCriterion) {
      EarthCriterion.center => "Earth's centre",
      EarthCriterion.anyPart => 'any part of Earth',
    };
    Widget tile(String label, String value, Color accent, {String? sub}) => Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: PH.sunken,
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: accent, width: 2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, color: PH.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(value, style: numStyle(size: 17, weight: FontWeight.w600)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 13, color: PH.muted)),
          ]),
        );
    final tiles = [
      tile('Sunlit', '${m.pctSunlit.toStringAsFixed(1)}%', PH.sun, sub: sunRule),
      tile('Longest sun', fmtDuration(m.longestSunHours), PH.sun),
      tile(earthMetricLabel(requireDsn: requireDsn), '${m.pctEarth.toStringAsFixed(1)}%', PH.earth,
          sub: requireDsn ? '$earthRule + DSN station' : earthRule),
      tile(earthOutageLabel(requireDsn: requireDsn), fmtDuration(m.longestEarthOutageHours), PH.earth),
      tile(requireDsn ? 'Sun + Earth contact' : 'Sun + Earth', '${m.pctBoth.toStringAsFixed(1)}%', PH.both),
      tile('Longest night', fmtDuration(m.longestDarkHours), PH.lineStrong),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(header: true, child: Text('Exact numbers for your chosen dates', style: PHText.body.copyWith(fontWeight: FontWeight.w600))),
          ),
          // rows grow with their text (large text sizes), never a fixed aspect ratio
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 340 ? 2 : 1;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < tiles.length; i += cols)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var j = i; j < i + cols && j < tiles.length; j++) ...[
                        if (j > i) const SizedBox(width: 8),
                        Expanded(child: tiles[j]),
                      ],
                    ]),
                  ),
                ),
            ]);
          }),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.bolt, size: 16, color: PH.sun),
            const SizedBox(width: 6),
            const Expanded(child: Text(powerLabel, style: TextStyle(fontSize: 13, color: PH.muted))),
            Text('${m.meanPowerWm2.toStringAsFixed(0)} W/m²', style: numStyle(size: 13.5, weight: FontWeight.w600)),
          ]),
          const FidelityBadge(text: powerNote),
        ]),
      ),
    );
  }
}

/// Site › Overview's "Show exact numbers" block: the position (coordinates,
/// elevation, slope) and [ExpertMetrics] for the chosen dates, with the
/// rules the numbers were computed with.
class ExpertNumbers extends StatelessWidget {
  final AppState state;
  const ExpertNumbers({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    // the selected site's numbers only (logic-1), with the rules they were
    // computed under (the previous choices' while those are still shown)
    final site = s.site, m = s.selectedMetrics;
    final o = s.metricsFor(s.selectedId) != null ? s.options : s.resultOptions;
    // east-positive, as everywhere in the app
    final lon = '${site.lon.toStringAsFixed(4)}°E';
    final position = '${site.lat.toStringAsFixed(4)}°  $lon';
    final height = '${site.terrainHeightM.toStringAsFixed(0)} m elevation · ${slopeText(site)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Semantics(
            container: true,
            label: 'Position: latitude ${site.lat.toStringAsFixed(4)} degrees, longitude $lon. $height.',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Position (planetocentric, Moon ME frame)', style: PHText.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              KeyedSubtree(
                key: const PageStorageKey('expert-position'),
                child: SelectableText(position, style: numStyle(size: 14)),
              ),
              Text(height, style: numStyle(size: 13, weight: FontWeight.w400, color: PH.muted).copyWith(height: 1.5)),
            ]),
          ),
        ),
      ),
      if (m != null)
        ExpertMetrics(
          m: m,
          sunCriterion: o.sunCriterion,
          earthCriterion: o.earthCriterion,
          requireDsn: o.requireDsn,
        ),
    ]);
  }
}
