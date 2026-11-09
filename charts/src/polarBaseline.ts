/**
 * The 1.13.5 polar chart baseline (plan §6 item 9, guard G7): what the
 * builders give for the REAL dev polar payloads in `devdata/` (Shackleton
 * rim, Haworth, the DSN rule, the compare top 3). Never shipped: nothing in
 * the bundle imports this file; only tests do.
 *
 * `charts/src/devdata/polar_baseline_1135.json` holds `{ meta, entries }`,
 * where `entries` is `polarBaseline()` as run at 85c472f (1.13.5) with the
 * clock set to `BASELINE_TIME` (vi.setSystemTime). A later version passes
 * the guard when `polarBaseline()` deep-equals `entries` under the same
 * clock: the polar figures and texts are unchanged.
 *
 * A figure is kept whole except its traces, which are kept as
 * `{ type, name, mode, digest }`: `digest` is cyrb53 (53-bit, hex) of the
 * trace's JSON, so a changed point or style still fails the guard while
 * the file stays small. Sky payloads merged with a skyNow message that
 * give the same entry as the payload alone are kept as `{ sameAs }`.
 *
 * To re-take or re-check it: a temporary vitest file (not committed) sets
 * `vi.useFakeTimers({ toFake: ['Date'] })` and `vi.setSystemTime(BASELINE_TIME)`
 * and writes `formatBaseline({ meta, entries: polarBaseline() })`.
 */
import type { CompareData, HostMessage, SkyData, TimelineData } from './bridge'
import { dispatchForTests } from './bridge'
import { buildCompare, buildCompareSimple, headline, longestDarkText, ranked, reasons, scoreLine, scoreTexts, weightsText } from './compare'
import { skyNowData } from './cursor'
import { buildSky, skyAlt, skyDynamic, skyHeader } from './sky'
import type { BodyName } from './skyCaption'
import { captionLine, captionText, exactLine, highestHillsText, keyLine, legendNames, markerLabel } from './skyCaption'
import * as classic from './skyClassic'
import { buildStrip, buildTimelineExport, DEFAULT_SPAN, rowLabels, spanWindow, stripFlags } from './strip'
import { buildHeights, totalsLine } from './timeline'
import { answerText, comingUp } from './timelineAnswer'
import { buildTimeline } from './timelineClassic'
import compare from './devdata/compare.json'
import sky from './devdata/sky.json'
import skyH from './devdata/sky_haworth.json'
import skyNow from './devdata/skyNow.json'
import skyNowDsn from './devdata/skyNow_dsn.json'
import skyNowH from './devdata/skyNow_haworth.json'
import timeline from './devdata/timeline.json'
import timelineDsn from './devdata/timeline_dsn.json'
import timelineH from './devdata/timeline_haworth.json'

/** The clock the baseline was taken at (vi.setSystemTime), UTC. */
export const BASELINE_TIME = '2026-11-14T06:00:00Z'

/** cyrb53 (public domain, bryc): a 53-bit string hash, as hex. Pure TS (no node:crypto). */
export function cyrb53(s: string, seed = 0): string {
  let h1 = 0xdeadbeef ^ seed
  let h2 = 0x41c6ce57 ^ seed
  for (let i = 0; i < s.length; i++) {
    const ch = s.charCodeAt(i)
    h1 = Math.imul(h1 ^ ch, 2654435761)
    h2 = Math.imul(h2 ^ ch, 1597334677)
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507)
  h1 ^= Math.imul(h2 ^ (h2 >>> 13), 3266489909)
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507)
  h2 ^= Math.imul(h1 ^ (h1 >>> 13), 3266489909)
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16)
}

type Json = unknown
/** JSON round trip (what Plotly receives): drops undefined, NaN becomes null. */
const plain = (v: unknown): Json => (v === undefined ? null : JSON.parse(JSON.stringify(v)))

/** A trace as `{ type, name, mode, digest }`. */
export function traceDigest(t: unknown): Json {
  const r = (t ?? {}) as Record<string, unknown>
  return { type: r.type ?? null, name: r.name ?? null, mode: r.mode ?? null, digest: cyrb53(JSON.stringify(t)) }
}

/** A figure with its traces digested and everything else kept whole. */
export function figDigest(f: { data: unknown[] } & Record<string, unknown>): Json {
  const out: Record<string, Json> = {}
  for (const k of Object.keys(f).sort()) out[k] = k === 'data' ? f.data.map(traceDigest) : plain(f[k])
  return out
}

/** A fresh copy of a payload (the builders never see the shared import). */
const copy = <T,>(v: unknown): T => JSON.parse(JSON.stringify(v)) as T

/** The sky payload merged with a later skyNow message, as the views do (cursor.ts). */
function merged(skyMsg: unknown, nowMsg: unknown): SkyData {
  const m = copy<Extract<HostMessage, { type: 'sky' }>>(skyMsg)
  const n = copy<Extract<HostMessage, { type: 'skyNow' }>>(nowMsg)
  dispatchForTests(m)
  dispatchForTests(n)
  return skyNowData(m, n)
}

function skyEntry(d: SkyData): Json {
  const figs: Record<string, Json> = {}
  const variants: [string, Parameters<typeof buildSky>[1]][] = [
    ['default', {}], ['live', { live: true }], ['live_exact', { live: true, exact: true }],
    ['live_paths', { live: true, paths: true }], ['exact', { exact: true }],
  ]
  let range = buildSky(d).range
  for (const [k, o] of variants) {
    const f = buildSky(d, o)
    figs[k] = figDigest(f)
    if (k === 'default') range = f.range
  }
  const classicVariants: [string, classic.SkyOptions][] = [
    ['default', {}], ['live', { live: true }], ['live_narrow', { live: true, narrow: true }], ['rPx', { rPx: 200 }],
  ]
  const classicFigs: Record<string, Json> = {}
  let classicRange = classic.buildSky(d).range
  for (const [k, o] of classicVariants) {
    const f = classic.buildSky(d, o)
    classicFigs[k] = figDigest(f)
    if (k === 'default') classicRange = f.range
  }
  const bodies: Record<string, Json> = {}
  for (const name of ['Sun', 'Earth'] as BodyName[]) {
    const b = name === 'Sun' ? d.now.sun : d.now.earth
    const l = captionLine(name, b)
    bodies[name] = { captionLine: plain(l), captionText: captionText(l), exactLine: exactLine(name, b), markerLabel: markerLabel(name, b) }
  }
  return {
    figs,
    classicFigs,
    texts: {
      bodies,
      keyLine: keyLine(d, range),
      legendNames: plain(legendNames(d.maskApprox)),
      highestHillsText: highestHillsText(d.mask),
      skyHeader: plain(skyHeader(d)),
      skyAlt: skyAlt(d),
      classicSkyHeader: plain(classic.skyHeader(d, classicRange)),
      classicSkyAlt: classic.skyAlt(d),
    },
    dynamic: plain(skyDynamic(d.now, range, 200)),
    classicDynamic: plain(classic.skyDynamic(d.now, classicRange, 200)),
  }
}

function timelineEntry(msg: unknown): Json {
  const d = copy<{ data: TimelineData }>(msg).data
  const t = d.cursor
  const win = spanWindow(DEFAULT_SPAN, t, d.range)
  const all = spanWindow('all', t, d.range)
  return {
    windows: { [DEFAULT_SPAN]: win, all },
    strip: {
      [DEFAULT_SPAN]: figDigest(buildStrip(d, win)),
      [`${DEFAULT_SPAN}_live_narrow`]: figDigest(buildStrip(d, win, { live: true, narrow: true, widthPx: 320 })),
      all: figDigest(buildStrip(d, all)),
      all_live: figDigest(buildStrip(d, all, { live: true, widthPx: 900 })),
    },
    heights: {
      default: figDigest(buildHeights(d)),
      live_window: figDigest(buildHeights(d, { live: true, window: win })),
    },
    export: {
      plain: figDigest(buildTimelineExport(d, t, false)),
      exact: figDigest(buildTimelineExport(d, t, true)),
    },
    classic: {
      default: figDigest(buildTimeline(d)),
      narrow: figDigest(buildTimeline(d, { narrow: true })),
    },
    texts: {
      totalsLine: totalsLine(d),
      rowLabels: plain(rowLabels(d)),
      flags: plain(stripFlags(d, t, win)),
      answerDesktop: answerText(d, t, true),
      answerPhone: answerText(d, t, false),
      comingUp: plain(comingUp(d, t, 6)),
    },
  }
}

function compareEntry(msg: unknown): Json {
  const d = copy<{ data: CompareData }>(msg).data
  const rows = ranked(d)
  return {
    compare: { default: figDigest(buildCompare(d)), narrow: figDigest(buildCompare(d, { narrow: true })), png: figDigest(buildCompare(d, { png: true, widthPx: 400 })) },
    simple: { default: figDigest(buildCompareSimple(d)), narrow: figDigest(buildCompareSimple(d, { narrow: true })), png: figDigest(buildCompareSimple(d, { png: true, widthPx: 400 })) },
    texts: {
      headline: headline(d),
      headlineExact: headline(d, true),
      scoreLine: scoreLine(d.weights),
      weightsText: weightsText(d.weights),
      ranked: rows.map((r) => r.id),
      reasons: reasons(rows),
      scoreTexts: scoreTexts(rows),
      longestDark: rows.map(longestDarkText),
    },
  }
}

/**
 * The entry for a sky payload merged with a skyNow message, or
 * `{ sameAs: base }` when it equals the base payload's entry (the dev skyNow
 * messages carry the payload's own "now", so in 1.13.5 they all do).
 */
function mergedEntry(base: string, baseEntry: Json, skyMsg: unknown, nowMsg: unknown): Json {
  const e = skyEntry(merged(skyMsg, nowMsg))
  return JSON.stringify(e) === JSON.stringify(baseEntry) ? { sameAs: base } : e
}

/** Every baseline entry, keyed by payload (run under `BASELINE_TIME`). */
export function polarBaseline(): Record<string, Json> {
  const sr1 = skyEntry(copy<{ data: SkyData }>(sky).data)
  const haworth = skyEntry(copy<{ data: SkyData }>(skyH).data)
  return {
    'sky.json': sr1,
    'sky_haworth.json': haworth,
    'sky.json+skyNow.json': mergedEntry('sky.json', sr1, sky, skyNow),
    'sky.json+skyNow_dsn.json': mergedEntry('sky.json', sr1, sky, skyNowDsn),
    'sky_haworth.json+skyNow_haworth.json': mergedEntry('sky_haworth.json', haworth, skyH, skyNowH),
    'timeline.json': timelineEntry(timeline),
    'timeline_dsn.json': timelineEntry(timelineDsn),
    'timeline_haworth.json': timelineEntry(timelineH),
    'compare.json': compareEntry(compare),
  }
}

/**
 * The baseline file's text: nested objects one key per line down to a
 * figure's keys, everything deeper (a trace digest, a layout key) on one
 * line, so a change shows as a short diff.
 */
export function formatBaseline(v: Json, depth = 0): string {
  const pad = ' '.repeat(depth + 1)
  const end = ' '.repeat(depth)
  if (depth >= 6 || v === null || typeof v !== 'object') return JSON.stringify(v)
  if (Array.isArray(v)) {
    if (!v.length) return '[]'
    return `[\n${v.map((x) => pad + formatBaseline(x, depth + 1)).join(',\n')}\n${end}]`
  }
  const keys = Object.keys(v as Record<string, Json>)
  if (!keys.length) return '{}'
  return `{\n${keys.map((k) => `${pad}${JSON.stringify(k)}: ${formatBaseline((v as Record<string, Json>)[k], depth + 1)}`).join(',\n')}\n${end}}`
}
