/// "At a glance" (the user's "overview engine"; called *glance* in code and
/// *curated* for the pipeline-built research text): a short description of
/// one site built from fixed templates, the same code for catalogue presets
/// and custom spots.
///
/// Rules:
/// - **Rule N:** a NaN or null input drops its sentence or clause, so the
///   text never contains 'NaN', 'null', 'Infinity' or a negative zero.
/// - **Rule W:** comparisons use whole percents, as displayed, and "more
///   than" counts only presets that are strictly lower, so a line never
///   contradicts two equal printed numbers.
/// - Deterministic and offline: no clock, no DEM decode, no shadow engine.
///
/// Curated text (headline, lede, overview, sources) comes from
/// assets/data/curated_sites.json via [CuratedCatalog]; every other sentence
/// is computed here from the app's numbers. Pure Dart (no Flutter).
library;

import 'catalog.dart';
import 'curated.dart';
import 'horizon.dart';
import 'landing_wording.dart' show ordinal;
import 'metrics.dart';
import 'place.dart';
import 'summary.dart' show Ranked, dateTime, spellDuration;
import 'wording.dart' show bothMetricLabel, earthMetricLabel, longTermCustomNote, siteKindLabel;

/// A longest night at or above this many hours is a watch-out.
const double kLongNightH = 72;

/// A longest Earth outage (or DSN-contact gap) at or above this many hours is
/// a watch-out.
const double kLongOutageH = 72;

/// A preset slope (LOLA 80 m map, as printed to 0.1°) at or above this is a
/// watch-out.
const double kSteepSlopeDeg = 10;

/// The facts line names the nearest other preset when it is this close (km,
/// inclusive).
const double kNearSiteKm = 20;

/// Named features count only within this distance of their centre (km,
/// inclusive).
const double kFeatureMaxKm = 60;

/// WATCH OUT shows at most this many lines; the rest go to Details.
const int kWatchCap = 3;

/// A skyline peak closer than this (km) is "right next to the spot".
const double kNearSkylineKm = 1;

/// Pending line while the period numbers are being recomputed.
const String glanceUpdatingText = 'Updating for your new choices…';

/// Pending line while the catalogue comparison is not ready yet.
const String glanceComparingText = 'Comparing with the catalogue sites…';

/// WATCH OUT when no warning applies.
const String glanceNothingToWatchText = "Nothing above the app's warning thresholds over your dates.";

/// Details for custom spots: what the app cannot say about them.
const String glanceCustomLimitsText = 'For your own spots there are no published sources, no 18.6-year record '
    'and no lander-scale slope; the horizon and terrain come from the 400 m map on this device.';

/// Eyebrow of a glance written by the app (custom spots, uncurated presets).
const String glanceGeneratedEyebrow = 'WRITTEN BY THE APP FROM ITS NUMBERS';
const String glanceGeneratedEyebrowSpoken = 'Written by the app from its numbers';

/// Row labels, in display order.
const Map<GlanceRow, String> glanceRowLabels = {
  GlanceRow.what: 'WHAT IT IS',
  GlanceRow.why: 'WHY HERE',
  GlanceRow.standsOut: 'WHAT STANDS OUT',
  GlanceRow.watch: 'WATCH OUT',
  GlanceRow.compare: 'HOW IT COMPARES',
};

/// Details group headings.
const String glanceAboutHeading = 'About this site';
const String glanceWhereHeading = 'Where it is';
const String glanceGroundHeading = 'Ground and skyline';
const String glanceMoreWatchHeading = 'More watch-outs';
const String glanceLimitsHeading = 'What this cannot tell you';
const String glanceSourcesHeading = 'Sources';

enum GlanceRow { what, why, standsOut, watch, compare }

/// One sentence of the card. [approximate] lines (custom spots: coarse 400 m
/// horizon) end with a muted '(approx.)' in the UI. [pending] lines stand in
/// for numbers that are still being computed (shown with a busy indicator in
/// a live region).
class GlanceLine {
  final String text;
  final bool approximate;
  final bool pending;
  const GlanceLine(this.text, {this.approximate = false, this.pending = false});

  /// What a screen reader says: the text, plus ', approximate'.
  String get semanticsLabel => approximate ? '$text, approximate' : text;

  /// The line as plain text, with the '(approx.)' suffix the UI shows.
  String get plain => approximate ? '$text (approx.)' : text;

  @override
  bool operator ==(Object other) =>
      other is GlanceLine && other.text == text && other.approximate == approximate && other.pending == pending;

  @override
  int get hashCode => Object.hash(text, approximate, pending);

  @override
  String toString() => 'GlanceLine($text${approximate ? ', approx' : ''}${pending ? ', pending' : ''})';
}

/// The finished card content (render-only for the widget).
class SiteGlance {
  /// True when the text comes from the curated research asset (presets only).
  final bool curated;

  /// 'CURATED · 5 SOURCES' or [glanceGeneratedEyebrow], and how it is read
  /// aloud.
  final String eyebrow, eyebrowSpoken;

  /// The rows in display order: (row, caps label, lines). Rows with no lines
  /// are left out.
  final List<(GlanceRow row, String label, List<GlanceLine> lines)> rows;

  /// The computed facts under WHAT IT IS ('6.8 km from the pole · elevation
  /// 1,733 m · …'), or null when no fact is known.
  final String? factsLine;

  /// Watch-outs past [kWatchCap] (also listed in [details]).
  final List<GlanceLine> moreWatch;

  /// Groups behind the "Details and sources" disclosure: (heading, lines).
  final List<(String heading, List<GlanceLine> lines)> details;

  /// Curated sources first, then the catalogue's, de-duplicated by URL.
  final List<SiteSource> sources;

  /// [pendingPeriod]: the period rows are being recomputed (stale).
  /// [pendingCompare]: a catalogue comparison is not ready yet.
  final bool pendingPeriod, pendingCompare;

  const SiteGlance({
    required this.curated,
    required this.eyebrow,
    required this.eyebrowSpoken,
    required this.rows,
    required this.factsLine,
    required this.moreWatch,
    required this.details,
    required this.sources,
    required this.pendingPeriod,
    required this.pendingCompare,
  });

  /// The whole card as plain text (eyebrow, rows, details, sources), one line
  /// per sentence; approximate lines end with ' (approx.)'. Deterministic.
  String get plainText {
    final b = <String>[eyebrow];
    for (final (row, label, lines) in rows) {
      b.add(label);
      for (final l in lines) {
        b.add(l.plain);
      }
      if (row == GlanceRow.what && factsLine != null) b.add(factsLine!);
    }
    for (final (heading, lines) in details) {
      b.add(heading);
      for (final l in lines) {
        b.add(l.plain);
      }
    }
    if (sources.isNotEmpty) {
      b.add(glanceSourcesHeading);
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        final t = s.title.trim();
        b.add(t.isEmpty ? '${i + 1}. ${s.url}' : (s.url.isEmpty ? '${i + 1}. $t' : '${i + 1}. $t (${s.url})'));
      }
    }
    return b.join('\n');
  }
}

/// Everything the engine reads. The caller (AppState) passes [ranked] only
/// when the ranking is done and the numbers are not stale, and
/// [presetMetrics] for every preset whose metrics are known.
class GlanceInputs {
  final Site site;
  final Iterable<Site> catalogue;
  final CuratedSite? curated;
  final List<NamedFeature> features;

  /// The 2 m horizon mask of [site] (custom spots: the coarse on-device one).
  final HorizonMask? mask2m;
  final double observerHeightM;
  final SiteMetrics m;
  final bool dsn, stale;
  final List<Ranked>? ranked;

  /// The goal's name as the app prints it (goalName(activeGoal)).
  final String goal;
  final Map<String, SiteMetrics> presetMetrics;

  const GlanceInputs({
    required this.site,
    required this.catalogue,
    this.curated,
    this.features = const [],
    required this.mask2m,
    required this.observerHeightM,
    required this.m,
    this.dsn = false,
    this.stale = false,
    this.ranked,
    required this.goal,
    this.presetMetrics = const {},
  });
}

// ---------------------------------------------------------------------------
// Number formatting (Rule N: never 'NaN', 'Infinity' or a negative zero)

final _negZero = RegExp(r'^-0(?:\.0+)?$');

/// toStringAsFixed without a negative zero; '' when not finite.
String _fixed(double x, int digits) {
  if (!x.isFinite) return '';
  final t = x.toStringAsFixed(digits);
  return _negZero.hasMatch(t) ? t.substring(1) : t;
}

/// '2' or '2.5' (metres of mast).
String _heightText(double h) => h == h.roundToDouble() ? _fixed(h, 0) : _fixed(h, 1);

/// A percentage as displayed (whole percent), or null.
int? _whole(double pct) => pct.isFinite ? pct.round() : null;

/// Whole hours (floored, as spellDuration shows them) of a run, or null.
int? _floorHours(Interval? i) {
  if (i == null) return null;
  final h = i.hours;
  return h.isFinite ? (h + 1e-9).floor() : null;
}

/// spellDuration, or '' when the interval is not usable.
String _spell(Interval? i) => i != null && i.hours.isFinite && i.hours >= 0 ? spellDuration(i) : '';

/// "sunlight and Earth contact (DSN) together" inside a sentence; "Sun" and
/// "Earth" stay capitalised (they are names).
String _mid(String label) => label.startsWith('Sunlight') ? 's${label.substring(1)}' : label;

/// A catalogue site by name; an Artemis region is 'the <short> region
/// centre', so it is not read as the mountain or crater it is named after.
String _siteRef(Site p) => p.isArtemisRegion ? 'the ${p.short} region centre' : p.short;

/// Whether [text] gives the size of the feature [name] itself: a sentence
/// that names it, not as part of a longer name ('Malapert' in 'Mons
/// Malapert' or 'Malapert Massif'), and gives a size in km after it ('a
/// crater about 32 km across', '21 km wide').
bool statesSizeOf(String text, String name) {
  final size = RegExp(r'\d[\d,.]* ?km (across|wide|in diameter)');
  for (final sentence in text.split(RegExp(r'(?<=\.)\s+'))) {
    for (final m in RegExp(RegExp.escape(name)).allMatches(sentence)) {
      final longer = RegExp(r'[A-Z][a-z]* $').hasMatch(sentence.substring(0, m.start)) ||
          RegExp(r'^ [A-Z]').hasMatch(sentence.substring(m.end));
      if (!longer && size.hasMatch(sentence.substring(m.end))) return true;
    }
  }
  return false;
}

/// ' (21 km across)' or ''.
String _across(NamedFeature f) => f.diameterKm.isFinite && f.diameterKm > 0 ? ' (${kmText(f.diameterKm)} across)' : '';

/// The skyline's highest point in one sentence: 'Seen from 2 m up, the
/// skyline peaks at 3.1° toward the pole, on terrain 9.8 km away.' The end is
/// ', where the ground rises right next to the spot.' when [distKm] is under
/// [kNearSkylineKm], and '.' when it is unknown (custom spots). '' when
/// [elevDeg] is not finite.
String skylineSentence({required double elevDeg, required double azDeg, required double distKm, double heightM = 2}) {
  if (!elevDeg.isFinite) return '';
  final from = heightM.isFinite && heightM >= 0 ? 'Seen from ${_heightText(heightM)} m up, the skyline' : 'The skyline';
  final dir = directionWord(azDeg);
  final where = dir.isEmpty ? '' : ' $dir';
  final String tail;
  if (!distKm.isFinite || distKm < 0) {
    tail = '.';
  } else if (distKm < kNearSkylineKm) {
    tail = ', where the ground rises right next to the spot.';
  } else {
    tail = ', on terrain ${kmText(distKm)} away.';
  }
  return '$from peaks at ${_fixed(elevDeg, 1)}°$where$tail';
}

/// '6.8 km from the south pole (-89.90°, 129.20°E).', or null without
/// coordinates.
String? positionLine(Site s) {
  if (!s.lat.isFinite || !s.lon.isFinite) return null;
  return '${kmText(poleDistanceKm(s.lat))} from the south pole (${_fixed(s.lat, 2)}°, ${_fixed(s.lon, 2)}°E).';
}

// ---------------------------------------------------------------------------
// The engine

/// One STANDS OUT candidate: its in-sentence label and how to read it.
class _Cand {
  final String label;
  final bool night;
  final int? Function(SiteMetrics m) value;
  const _Cand(this.label, this.value, {this.night = false});
}

int? _nightOther(SiteMetrics m) => m.longestDark == null ? 0 : _floorHours(m.longestDark);

/// Builds the card for [g.site]. Never throws on NaN or missing inputs.
SiteGlance buildSiteGlance(GlanceInputs g) {
  final s = g.site;
  final custom = s.custom || s.group == 'custom';
  final cur = custom ? null : g.curated;
  final presets = [for (final p in g.catalogue) if (!p.custom && p.group != 'custom') p];
  final pole = s.lat.isFinite ? poleDistanceKm(s.lat) : double.nan;
  final poleText = kmText(pole);
  final near = nearestSite(s.lat, s.lon, presets, exceptId: custom ? null : s.id);
  final feature = nearestFeature(s.lat, s.lon, g.features, maxKm: kFeatureMaxKm);
  final isCurated = cur != null;

  // Sources: curated first, then the catalogue's, de-duplicated by URL.
  final sources = <SiteSource>[];
  if (!custom) {
    final seen = <String>{};
    for (final x in [...?cur?.sources, ...s.sources]) {
      if (x.url.isEmpty || seen.add(x.url)) sources.add(x);
    }
  }

  final n = sources.length;
  final eyebrow = isCurated ? 'CURATED · $n ${n == 1 ? 'SOURCE' : 'SOURCES'}' : glanceGeneratedEyebrow;
  final eyebrowSpoken = isCurated ? 'Curated from $n ${n == 1 ? 'source' : 'sources'}' : glanceGeneratedEyebrowSpoken;

  // WHAT IT IS
  final kind = siteKindLabel(s);
  final kindLine = kind.isEmpty ? '${s.name}.' : '$kind.';
  final String whatText;
  if (custom) {
    whatText = poleText.isEmpty ? kindLine : 'A spot you placed $poleText from the south pole.';
  } else {
    whatText = cur != null && cur.headline.trim().isNotEmpty ? cur.headline.trim() : kindLine;
  }
  final elevation = metresText(s.terrainHeightM);
  final facts = <String>[
    if (poleText.isNotEmpty) '$poleText from the pole',
    if (elevation.isNotEmpty) 'elevation $elevation${custom ? ' (400 m map)' : ''}',
    // slopeText's '4.5° slope', without a negative zero (Rule N)
    if (!custom && s.slopeDeg.isFinite) '${_fixed(s.slopeDeg, 1)}° slope on the LOLA 80 m map',
    if (near != null && near.km <= kNearSiteKm) '${kmText(near.km)} from ${_siteRef(near.site)}',
    if (custom && feature != null) '${kmText(feature.km)} from the IAU centre of ${feature.f.name}${_across(feature.f)}',
  ];
  final factsLine = facts.isEmpty ? null : facts.join(' · ');

  final rows = <(GlanceRow, String, List<GlanceLine>)>[];
  void row(GlanceRow r, List<GlanceLine> lines) {
    if (lines.isNotEmpty) rows.add((r, glanceRowLabels[r]!, lines));
  }

  const updating = GlanceLine(glanceUpdatingText, pending: true);
  const comparing = GlanceLine(glanceComparingText, pending: true);
  var pendingCompare = false;

  row(GlanceRow.what, [GlanceLine(whatText)]);

  // WHY HERE (curated presets) or WHAT STANDS OUT (everything else)
  if (cur != null) {
    final lede = cur.lede.trim();
    row(GlanceRow.why, [if (lede.isNotEmpty) GlanceLine(lede)]);
  } else if (g.stale) {
    row(GlanceRow.standsOut, [updating]);
  } else {
    final (lines, pending) = _standsOut(g, presets, custom);
    if (pending) pendingCompare = true;
    row(GlanceRow.standsOut, lines);
  }

  // WATCH OUT: (line, period?) in priority order.
  final watch = <(GlanceLine, bool)>[];
  final m = g.m;
  final h = _heightText(g.observerHeightM);
  // Never sunlit implies never together and a night as long as the period:
  // the one line stands in for both, so it does not fill all three slots.
  final neverSun = m.pctSunlit == 0;
  if (neverSun) {
    watch.add((GlanceLine(h.isEmpty ? 'Never sunlit over your dates.' : 'Never sunlit over your dates at $h m.', approximate: custom), true));
  }
  if (m.pctBoth == 0 && !neverSun) {
    // with the DSN required, pctBoth counts Sun + DSN-visible Earth
    final none = g.dsn
        ? 'Sunlight and Earth contact (DSN) never overlap over your dates.'
        : 'Sun and Earth are never up together over your dates.';
    watch.add((GlanceLine(none, approximate: custom), true));
  }
  final dark = m.longestDark;
  if (!neverSun && dark != null && dark.hours.isFinite && dark.hours >= kLongNightH && dark.startMs.isFinite) {
    watch.add((
      GlanceLine('Longest night over your dates: ${_spell(dark)}, from ${dateTime(dark.startMs)}.', approximate: custom),
      true
    ));
  }
  final outage = m.longestEarthOutage;
  if (outage != null && outage.hours.isFinite && outage.hours >= kLongOutageH) {
    final what = g.dsn ? 'No Earth contact' : 'Earth out of view';
    watch.add((GlanceLine('$what for up to ${_spell(outage)} at a time.', approximate: custom), true));
  }
  if (!custom && s.slopeDeg.isFinite && (s.slopeDeg * 10).round() >= (kSteepSlopeDeg * 10).round()) {
    watch.add((
      GlanceLine('${_fixed(s.slopeDeg, 1)}° slope at the point on the 80 m map: a rough guide, not a hazard check.'),
      false
    ));
  }
  if (!custom && s.isArtemisRegion) {
    watch.add((
      const GlanceLine(
          'Region centre: the candidate region is about 15 × 15 km, and other spots in it have different light.'),
      false
    ));
  }
  if (!custom && s.kind == 'exact-point') {
    watch.add((const GlanceLine('Peak or ridge point: the answer depends on the exact spot and mast height.'), false));
  }
  final shown = [for (final (l, period) in watch) if (!g.stale || !period) l];
  final moreWatch = shown.length > kWatchCap ? shown.sublist(kWatchCap) : <GlanceLine>[];
  final top = shown.take(kWatchCap).toList();
  if (g.stale) {
    row(GlanceRow.watch, [updating, ...top]);
  } else {
    row(GlanceRow.watch, top.isEmpty ? const [GlanceLine(glanceNothingToWatchText)] : top);
  }

  // HOW IT COMPARES
  final cmp = <GlanceLine>[];
  if (g.stale) {
    cmp.add(updating);
  } else if (g.ranked == null) {
    cmp.add(comparing);
    pendingCompare = true;
  } else {
    final r = g.ranked!;
    final i = r.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      // N matches the Explore rank badges (all sites); say so when it counts
      // the user's spots, and mark a preset's rank approximate when a spot
      // (400 m map numbers) ranks above it.
      final presetIds = {for (final p in presets) p.id};
      final mine = r.where((x) => !presetIds.contains(x.id)).length;
      final goal = g.goal.trim();
      final of = mine == 0 ? '' : ' sites, including your $mine spot${mine == 1 ? '' : 's'},';
      cmp.add(GlanceLine('${ordinal(i + 1)} of ${r.length}$of${goal.isEmpty ? '' : ' for $goal'} over your dates.',
          approximate: custom || r.take(i).any((x) => !presetIds.contains(x.id))));
    }
  }
  if (!custom) {
    final lt = _whole(s.longTermBothPct);
    if (lt != null) {
      final others = [
        for (final p in presets)
          if (p.id != s.id && p.longTermBothPct.isFinite) p.longTermBothPct.round()
      ];
      final rank = 1 + others.where((x) => x > lt).length;
      final joint = others.contains(lt);
      cmp.add(GlanceLine('Over 18.6 years at 2 m: Sun and Earth together $lt% of the time, '
          '${joint ? 'joint ' : ''}${ordinal(rank)} of ${others.length + 1} catalogue sites.'));
    }
  } else {
    if (!g.stale && near != null) {
      final pm = g.presetMetrics[near.site.id];
      final v = _whole(m.pctBoth), w = pm == null ? null : _whole(pm.pctBoth);
      if (v != null && w != null) {
        cmp.add(GlanceLine(
            'Against ${_siteRef(near.site)} (${kmText(near.km)} away): ${_mid(bothMetricLabel(requireDsn: g.dsn))} '
            '$v% here, $w% there, over your dates.',
            approximate: true));
      } else if (pm == null && !cmp.any((l) => l.pending)) {
        cmp.add(comparing);
        pendingCompare = true;
      }
    }
    cmp.add(const GlanceLine('$longTermCustomNote.'));
  }
  row(GlanceRow.compare, cmp);

  // Details
  final details = <(String, List<GlanceLine>)>[];
  void group(String heading, List<GlanceLine> lines) {
    if (lines.isNotEmpty) details.add((heading, lines));
  }

  if (cur != null && cur.overview.trim().isNotEmpty) group(glanceAboutHeading, [GlanceLine(cur.overview.trim())]);

  final where = <GlanceLine>[];
  final pos = positionLine(s);
  if (pos != null) where.add(GlanceLine(pos));
  if (near != null) {
    final dir = directionWordTo(near.az, s.lat, near.site.lat);
    where.add(GlanceLine('The nearest catalogue site is ${_siteRef(near.site)}, ${kmText(near.km)} '
        '${dir.isEmpty ? 'away' : dir}.'));
  }
  if (feature != null) {
    final dir = directionWordTo(feature.az, s.lat, feature.f.lat);
    // The checked text gives its own size for a feature it describes; a
    // second, different figure (the Gazetteer's) would contradict it on the
    // same card.
    final size = cur != null && statesSizeOf(cur.overview, feature.f.name) ? '' : _across(feature.f);
    where.add(GlanceLine('The nearest named feature is ${feature.f.name}$size; '
        'its centre is ${kmText(feature.km)} ${dir.isEmpty ? 'away' : dir}.'));
  }
  group(glanceWhereHeading, where);

  final ground = <GlanceLine>[];
  final mask = g.mask2m;
  final String sky;
  if (custom) {
    final peak = mask == null ? (elevDeg: double.nan, azDeg: double.nan) : skylinePeak(mask);
    sky = skylineSentence(elevDeg: peak.elevDeg, azDeg: peak.azDeg, distKm: double.nan);
  } else {
    sky = skylineSentence(elevDeg: s.horizonMaxDeg, azDeg: s.horizonMaxAzDeg, distKm: s.horizonMaxDistanceKm);
  }
  if (sky.isNotEmpty) ground.add(GlanceLine(sky, approximate: custom));
  final mean = mask == null ? double.nan : skylineMeanDeg(mask);
  if (mean.isFinite) {
    ground.add(GlanceLine(
        (mean * 100).round() < 0
            ? 'On average the skyline is below level (${_fixed(mean, 2)}°): the ground falls away in most directions.'
            : 'On average the skyline sits ${_fixed(mean, 1)}° up.',
        approximate: custom));
  }
  group(glanceGroundHeading, ground);
  group(glanceMoreWatchHeading, moreWatch);
  if (custom) group(glanceLimitsHeading, const [GlanceLine(glanceCustomLimitsText)]);

  return SiteGlance(
    curated: isCurated,
    eyebrow: eyebrow,
    eyebrowSpoken: eyebrowSpoken,
    rows: rows,
    factsLine: factsLine,
    moreWatch: moreWatch,
    details: details,
    sources: sources,
    pendingPeriod: g.stale,
    pendingCompare: pendingCompare,
  );
}

/// WHAT STANDS OUT for a custom spot or an uncurated preset: its numbers
/// against the other catalogue presets (whole percents, Rule W). Returns the
/// lines and whether they are a pending placeholder.
(List<GlanceLine>, bool) _standsOut(GlanceInputs g, List<Site> presets, bool custom) {
  final s = g.site;
  final others = [for (final p in presets) if (p.id != s.id) p];
  if (others.isEmpty) return (const <GlanceLine>[], false);
  final withM = [
    for (final p in others)
      if (g.presetMetrics[p.id] case final pm?) (p, pm)
  ];
  if (withM.length < others.length) {
    return (const [GlanceLine(glanceComparingText, pending: true)], true);
  }
  final n = withM.length;
  final many = custom ? 'catalogue sites' : 'other catalogue sites';
  final one = custom ? 'catalogue site' : 'other catalogue site';
  final cands = [
    _Cand(_mid(bothMetricLabel(requireDsn: g.dsn)), (x) => _whole(x.pctBoth)),
    _Cand('sunlight', (x) => _whole(x.pctSunlit)),
    _Cand(earthMetricLabel(requireDsn: g.dsn), (x) => _whole(x.pctEarth)),
    _Cand('shorter longest night', (x) => _floorHours(x.longestDark), night: true),
  ];

  // (candidate, my value, beat, above, best other) per usable candidate
  final stats = <(_Cand, int, int, int, (Site, SiteMetrics, int)?)>[];
  for (final c in cands) {
    final v = c.value(g.m);
    if (v == null) continue;
    var beat = 0, above = 0;
    (Site, SiteMetrics, int)? best;
    for (final (p, pm) in withM) {
      final w = c.night ? _nightOther(pm) : c.value(pm);
      if (w == null) continue;
      final worse = c.night ? w > v : w < v;
      final better = c.night ? w < v : w > v;
      if (worse) beat++;
      if (better) above++;
      if (best == null || (c.night ? w < best.$3 : w > best.$3)) best = (p, pm, w);
    }
    stats.add((c, v, beat, above, best));
  }
  final line = _standsOutLine(stats, g.m, n, many, one);
  return (line == null ? const <GlanceLine>[] : [GlanceLine(line, approximate: custom)], false);
}

String? _standsOutLine(List<(_Cand, int, int, int, (Site, SiteMetrics, int)?)> stats, SiteMetrics mine, int n,
    String many, String one) {
  // 1. Better than every preset (first in tie order).
  for (final (c, v, beat, _, best) in stats) {
    if (beat != n || best == null) continue;
    if (!c.night) return 'More ${c.label} than any $one over your dates: $v% here, ${best.$3}% at ${best.$1.short}.';
    final a = _spell(mine.longestDark), b = _spell(best.$2.longestDark);
    if (a.isEmpty || b.isEmpty) continue;
    return 'Shorter longest night than any $one over your dates: $a here, $b at ${best.$1.short}.';
  }
  // 2. The candidate that beats the most presets, if at least half (the
  // ⌈0.75n⌉ tier is the same pick: the highest count wins, ties in order).
  (_Cand, int, int, int, (Site, SiteMetrics, int)?)? pick;
  for (final st in stats) {
    if (st.$3 * 2 < n) continue;
    if (st.$1.night && _spell(mine.longestDark).isEmpty) continue;
    if (pick == null || st.$3 > pick.$3) pick = st;
  }
  if (pick != null) {
    final (c, v, beat, _, _) = pick;
    return c.night
        ? 'Shorter longest night than $beat of the $n $many: ${_spell(mine.longestDark)}.'
        : 'More ${c.label} than $beat of the $n $many over your dates ($v%).';
  }
  // 3. Nothing stands out: the best percentage candidate.
  (_Cand, int, int, int, (Site, SiteMetrics, int)?)? low;
  for (final st in stats) {
    if (st.$1.night) continue;
    if (low == null || st.$3 > low.$3) low = st;
  }
  if (low == null) return null;
  final (c, v, beat, above, _) = low;
  return above > 0
      ? 'Nothing stands out over your dates: ${c.label} $v%, below $above of the $n $many.'
      : 'Nothing stands out over your dates: ${c.label} $v%, the same as ${n - beat} of the $n $many.';
}
