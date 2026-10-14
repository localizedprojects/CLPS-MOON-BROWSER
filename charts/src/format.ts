/**
 * Shared display formatting for the three charts (charts spec 2.0). Display
 * arithmetic on numbers Dart sent: no astronomy here.
 *
 * `fmtDur` mirrors `fmtDuration` in app/lib/core/wording.dart; both are
 * tested with the same table (format.test.ts / wording_test.dart).
 */

export const MIN_MS = 60e3
export const HOUR_MS = 3600e3
export const DAY_MS = 86400e3

export interface DurOpts {
  /** series step in minutes: a run of exactly one step reads "about 30 min" */
  stepMin?: number
  /** keep the largest unit only ("10 d"), still floored: for narrow bars */
  coarse?: boolean
}

/**
 * `30 min` | `9 h 30 min` | `10 d 21 h`, zero parts dropped (`9 h`, `10 d`).
 * Always floored, never rounded up, so a remaining time never runs past the
 * next event.
 */
export function fmtDur(ms: number, o: DurOpts = {}): string {
  if (!Number.isFinite(ms)) return '–'
  if (o.stepMin && o.stepMin > 0 && Math.abs(ms - o.stepMin * MIN_MS) < 1000) return `about ${fmtDur(ms, { coarse: o.coarse })}`
  const m = Math.floor(Math.max(0, ms) / MIN_MS + 1e-9)
  if (m < 60) return `${m} min`
  if (m < 1440) {
    const h = Math.floor(m / 60), r = m % 60
    return r === 0 || o.coarse ? `${h} h` : `${h} h ${r} min`
  }
  const d = Math.floor(m / 1440), h = Math.floor((m % 1440) / 60)
  return h === 0 || o.coarse ? `${d} d` : `${d} d ${h} h`
}

/** "in 10 d 18 h": a time relative to the time shown (not the wall clock), floored. */
export const fmtIn = (ms: number, o: DurOpts = {}) => `in ${fmtDur(ms, o)}`

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const pad2 = (n: number) => String(n).padStart(2, '0')

export interface DateOpts {
  /** always add the year */
  year?: boolean
  /**
   * The period start (or the start of the shown span): the year is added to
   * dates outside the 12 months that follow it (a date in the second year of
   * "Whole period", or before the start), so every printed day-month is
   * unambiguous. Within those 12 months "21 Jan 00:30" needs no year.
   */
  refMs?: number
  /** false: the day only ("1 May") */
  time?: boolean
}

/** True when [ms] lies outside the 12 months from [refMs] (the same UTC day-month a year later is outside). */
export function needsYear(ms: number, refMs: number): boolean {
  const r = new Date(refMs)
  const next = Date.UTC(r.getUTCFullYear() + 1, r.getUTCMonth(), r.getUTCDate())
  const start = Date.UTC(r.getUTCFullYear(), r.getUTCMonth(), r.getUTCDate())
  return ms < start || ms >= next
}

/** "21 Oct 18:00" in UTC: no weekday, no leading zero on the day; "7 Feb 2028 06:00" with the year (see [DateOpts]). */
export function fmtDate(ms: number, o: DateOpts = {}): string {
  if (!Number.isFinite(ms)) return '–'
  const d = new Date(ms)
  const year = o.year || (o.refMs != null && needsYear(ms, o.refMs))
  const day = `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}${year ? ` ${d.getUTCFullYear()}` : ''}`
  return o.time === false ? day : `${day} ${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`
}

const COMPASS = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW']

/** 16-point compass word for an azimuth in degrees, clockwise from north (161° -> SSE). */
export function compass16(azDeg: number): string {
  const a = ((azDeg % 360) + 360) % 360
  return COMPASS[Math.round(a / 22.5) % 16]
}

/**
 * The fewest decimals (0, 1 or 2) at which all *different* scores stay
 * different: 61.84 / 61.83 / 56.72 -> 2, 62 / 57 -> 0. One rule for every row.
 */
export function scoreDecimals(scores: number[]): number {
  const xs = [...new Set(scores.filter(Number.isFinite))]
  for (let d = 0; d < 2; d++) {
    const f = 10 ** d
    const r = xs.map((x) => Math.round(x * f))
    let ok = true
    for (let i = 0; ok && i < xs.length; i++) {
      for (let j = i + 1; j < xs.length; j++) {
        if (Math.abs(xs[i] - xs[j]) > 1e-9 && r[i] === r[j]) { ok = false; break }
      }
    }
    if (ok) return d
  }
  return 2
}

/** Which end of [range] a run [start, end) touches: the real spell may be longer there. */
export function edgeOf(run: readonly [number, number], range: readonly [number, number]): { start: boolean; end: boolean } {
  return { start: run[0] <= range[0], end: run[1] >= range[1] }
}

/** True when the run touches the start or the end of the period. */
export function touchesEdge(run: readonly [number, number], range: readonly [number, number]): boolean {
  const e = edgeOf(run, range)
  return e.start || e.end
}

/** "102 d+" for a duration text of a spell that touches the edge of the period. */
export const edgePlus = (text: string, atEdge: boolean) => (atEdge ? `${text}+` : text)

/**
 * Tooltip words for a spell at the edge: "at least 102 d 1 h (starts before
 * your chosen dates)"; the plain duration when it touches neither end.
 */
export function edgeTip(run: readonly [number, number], range: readonly [number, number], o: DurOpts = {}): string {
  const d = fmtDur(run[1] - run[0], o)
  const e = edgeOf(run, range)
  if (e.start && e.end) return `at least ${d} (covers all of your chosen dates)`
  if (e.start) return `at least ${d} (starts before your chosen dates)`
  if (e.end) return `at least ${d} (goes on past your chosen dates)`
  return d
}
