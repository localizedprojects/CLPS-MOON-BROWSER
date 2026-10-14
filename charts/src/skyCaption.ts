/**
 * Words for the sky plot ("Where to look", charts spec 2.2): the two caption
 * lines, the marker labels, the key line, the Exact block and the header
 * time. Display only: the state, the clearance and the sentence come from
 * Dart (`state`, `clear`, `say`); the bundle adds compass words and number
 * formatting. Old payloads without those fields fall back to the same rules
 * on the flags Dart sent (visible / terrainVisible / frac, el + rho < 0).
 */
import type { BodyNow, BodyState, SkyData } from './bridge'
import { compass16, fmtDate } from './format'
import type { ElRange } from './sky'

export type BodyName = 'Sun' | 'Earth'

/** Dart's state word, or the same rule on the flags for an old payload. */
export function stateOf(b: BodyNow): BodyState {
  if (b.state) return b.state
  if (b.visible) return b.frac < 0.999 ? 'partly' : 'up'
  if (b.terrainVisible) return 'noDsn'
  if (b.frac > 0) return 'notCounted'
  return b.el + b.rho < 0 ? 'belowHorizon' : 'behindHills'
}

/** Height of the disc centre above (+) or below (-) the hills there, deg: Dart's `clear`, else el - hz. */
export function clearOf(b: BodyNow): number {
  return Number.isFinite(b.clear) ? (b.clear as number) : b.el - b.hz
}

/** Share of the disc showing, whole percent; never 0 or 100 for a disc that is only partly showing. */
export function pctShowing(frac: number): number {
  if (!(frac > 0)) return 0
  if (frac >= 0.9995) return 100
  return Math.min(99, Math.max(1, Math.round(frac * 100)))
}

/** Degrees with a real minus sign ("−0.19°"). */
export function deg(v: number, dp = 1): string {
  const s = Math.abs(v).toFixed(dp)
  return `${v < 0 && Number(s) !== 0 ? '−' : ''}${s}°`
}

export interface CaptionLine {
  name: BodyName
  /** filled glyph = counted as up, open = not */
  counted: boolean
  /** the bold part: "Sun: up" */
  head: string
  /** the rest, joined with " · ": "look NNW", "1.6° above the hills" */
  rest: string[]
}

/**
 * One caption line (charts spec 2.2):
 * "Sun: up · look NNW · 1.6° above the hills",
 * "Earth: below the horizon · toward SSE · 5.9° below the hills".
 * A counted body with negative clearance (upper-limb rule) reads
 * "partly up · N% showing" and never shows its negative clearance.
 */
export function captionLine(name: BodyName, b: BodyNow): CaptionLine {
  const st = stateOf(b)
  const c = clearOf(b)
  const dir = compass16(b.az)
  const pct = pctShowing(b.frac)
  const line = (word: string, rest: string[]): CaptionLine => ({ name, counted: b.visible, head: `${name}: ${word}`, rest })
  if (b.visible && (st === 'partly' || c < 0)) return line('partly up', [`toward ${dir}`, `${Math.min(pct, 99)}% showing`])
  switch (st) {
    case 'up': return line('up', [`look ${dir}`, `${deg(Math.abs(c))} above the hills`])
    case 'partly': return line('partly up', [`toward ${dir}`, `${pct}% showing`])
    case 'notCounted': return line(`${pct}% showing, not counted`, [`toward ${dir}`])
    case 'noDsn': return line('up, but no DSN dish can reach it', [`toward ${dir}`])
    case 'behindHills': return line('behind the hills', [`toward ${dir}`, c < 0 ? `${deg(-c)} too low` : `${deg(c)} above the hills`])
    case 'belowHorizon': return line('below the horizon', [`toward ${dir}`, c < 0 ? `${deg(-c)} below the hills` : `${deg(c)} above the hills`])
  }
}

export const captionText = (l: CaptionLine) => [l.head, ...l.rest].join(' · ')

/** Marker label in plain words, never a signed number: "Sun · up", "Earth · 51% up", "Earth · no DSN". */
export function markerLabel(name: BodyName, b: BodyNow): string {
  const st = stateOf(b)
  const pct = pctShowing(b.frac)
  if (b.visible && (st === 'partly' || clearOf(b) < 0)) return `${name} · ${Math.min(pct, 99)}% up`
  switch (st) {
    case 'up': return `${name} · up`
    case 'partly': return `${name} · ${pct}% up`
    case 'notCounted': return `${name} · ${pct}%, not counted`
    case 'noDsn': return `${name} · no DSN`
    case 'behindHills': return `${name} · behind hills`
    case 'belowHorizon': return `${name} · below horizon`
  }
}

/** The hills label on the plot. */
export const hillsText = (maskApprox?: boolean) => (maskApprox ? 'hills (approx.)' : 'hills')

/** Provenance of the hills, as the key and the Exact legend name it. */
export const maskSource = (maskApprox?: boolean) => (maskApprox ? 'coarse map, approximate' : 'NASA LOLA map')

/** The radius scale: "Heights stretched: edge −9°, centre 8°" (zoom) or the whole sky. */
export function scaleText(zoom: boolean, range: ElRange): string {
  return zoom ? `Heights stretched: edge ${deg(range.lo, 0)}, centre ${deg(range.hi, 0)}` : 'Whole sky: edge −10°, centre straight up'
}

/** The muted key line under the plot (charts spec 2.2 item 5). */
export function keyLine(d: Pick<SkyData, 'maskApprox' | 'zoom'>, range: ElRange): string {
  return `Seen from above. Grey = hills and crater rims (${maskSource(d.maskApprox)}). Filled = counted as up, open = not. ` +
    `Dashed ring = flat horizon (0°). Closer to the centre = higher. N = away from the pole. ${scaleText(d.zoom, range)}.`
}

/** Exact legend entries (Exact numbers), in drawing order. */
export function legendNames(maskApprox?: boolean): { hills: string; sun: string; earth: string } {
  return {
    hills: `Hills and crater rims (${maskSource(maskApprox)})`,
    sun: 'Where the Sun goes (whole period)',
    earth: 'Where Earth goes (whole period)',
  }
}

/** The Exact block line of one body (Dart's numbers, 2 dp). */
export function exactLine(name: BodyName, b: BodyNow): string {
  return `${name} · azimuth ${deg(b.az, 2)} · height ${deg(b.el, 2)} · hills there ${deg(b.hz, 2)} · ` +
    `clearance ${deg(clearOf(b), 2)} · disc radius ${deg(b.rho, 2)} · ${pctShowing(b.frac)}% showing`
}

/** Highest point of the hills, deg (max of the mask). */
export function highestHills(mask: number[]): number {
  let m = -Infinity
  for (const v of mask) if (v > m) m = v
  return m
}

export const highestHillsText = (mask: number[]) => `Highest hills: ${deg(highestHills(mask), 2)}`

/**
 * Dart's time label ("2026-10-11 00:00 UTC") as the header shows it:
 * "11 Oct 2026 00:00" (no weekday, no leading zero; "UTC" follows in the
 * header). Always with the year, like the app's time label under the charts
 * ("20 Oct 2026 19:00 UTC"): a period can cross New Year (charts-3, qa-1).
 * A label in another shape is shown as sent.
 */
export function headerTime(timeLabel: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/.exec(timeLabel)
  if (!m) return timeLabel.replace(/\s*UTC$/, '')
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]))
  return fmtDate(ms, { year: true })
}
