/**
 * The timeline's plain-language answers (charts spec 2.1), read off the runs
 * and numbers Dart sent. Render-only: interval bookkeeping on [start, end)
 * runs (gaps, the current and next run, remaining time, edge "+"), no
 * astronomy. "Now" is always the time shown in the app (the cursor), never
 * the wall clock. Durations are floored (format.ts `fmtDur`).
 */
import type { TimelineData } from './bridge'
import { edgePlus, fmtDate, fmtDur, fmtIn, HOUR_MS, sortedStable, touchesEdge } from './format'
import type { DurOpts } from './format'

export type Run = [number, number]

export const DEFAULT_EARTH = 'Earth in view'

/** The run containing [t], or null. */
export function runAt(runs: readonly Run[], t: number): Run | null {
  for (const r of runs) if (r[0] <= t && t < r[1]) return r
  return null
}

/** The first run starting after [t], or null. */
export function nextRun(runs: readonly Run[], t: number, minMs = 0): Run | null {
  for (const r of runs) if (r[0] > t && r[1] - r[0] >= minMs) return r
  return null
}

/** The gaps between [runs] inside [range] (the dark spells between sunlit runs, Earth out of view). */
export function gaps(runs: readonly Run[], range: Run): Run[] {
  const out: Run[] = []
  let t = range[0]
  for (const r of [...runs].sort((a, b) => a[0] - b[0])) {
    if (r[0] > t) out.push([t, Math.min(r[0], range[1])])
    t = Math.max(t, r[1])
    if (t >= range[1]) break
  }
  if (t < range[1]) out.push([t, range[1]])
  return out.filter((g) => g[1] > g[0])
}

/** Share of [range] covered by [runs], 0..100 (fallback when an old payload has no `pct`). */
export function pctOf(runs: readonly Run[], range: Run): number {
  const span = range[1] - range[0]
  if (span <= 0) return 0
  let s = 0
  for (const r of runs) s += Math.max(0, Math.min(r[1], range[1]) - Math.max(r[0], range[0]))
  return (100 * s) / span
}

/** Share of the period per row: Dart's `pct` (= Overview and Compare), else summed runs. */
export function rowPct(d: TimelineData): { sun: number; earth: number; both: number } {
  if (d.pct) return d.pct
  const r = d.range as Run
  return { sun: pctOf(d.runs.sun, r), earth: pctOf(d.runs.earth, r), both: pctOf(d.runs.both, r) }
}

/** The longest dark spell: Dart's `longestDark`, else the longest gap between sunlit runs. */
export function longestDark(d: TimelineData): Run | null {
  if (d.longestDark !== undefined) return d.longestDark
  let best: Run | null = null
  for (const g of gaps(d.runs.sun, d.range as Run)) if (!best || g[1] - g[0] > best[1] - best[0]) best = g
  return best
}

/** Duration of a run with the edge "+" when it touches the start or end of the chosen dates. */
export function runDur(r: Run, range: Run, o: DurOpts = {}): string {
  return edgePlus(fmtDur(r[1] - r[0], o), touchesEdge(r, range))
}

/** "1 day" for goodMinH 24, else "36 h". */
export function goodWords(h: number): string {
  return h % 24 === 0 ? (h === 24 ? '1 day' : `${h / 24} days`) : `${h} h`
}

export type Glyph = 'both' | 'dark' | 'sun' | 'earth'

export interface AnswerLine {
  key: Glyph
  /** glyph filled (true: the state holds now) */
  on: boolean
  /** bold label, e.g. 'Sun + Earth together:' ('' when the state word stands alone) */
  label: string
  /** bold state word: NOW | NEXT | NONE | YES | NO | DARK NOW | a date */
  state: string
  /** the rest of the line, after ' · ' */
  rest: string
}

export const lineText = (l: AnswerLine) => [l.label, l.state].filter(Boolean).join(' ') + (l.rest ? ` · ${l.rest}` : '')

export interface AnswerCtx {
  t: number
  range: Run
  o: DurOpts
  ref: number
}

const ctx = (d: TimelineData, t: number): AnswerCtx => ({ t, range: d.range as Run, o: { stepMin: d.stepMin }, ref: d.range[0] })
const date = (c: AnswerCtx, ms: number) => fmtDate(ms, { refMs: c.ref })

/** "5 d 16 h more, until 21 Jan 00:30" (floored; "+" when the run goes on past the chosen dates). */
function remaining(c: AnswerCtx, r: Run): string {
  const atEnd = r[1] >= c.range[1]
  return `${edgePlus(fmtDur(r[1] - c.t), atEnd)} more, until ${date(c, r[1])}${atEnd ? ' (end of your chosen dates)' : ''}`
}

/** "21 Oct 18:00 · in 10 d 18 h · lasts 11 d 23 h" */
function upcoming(c: AnswerCtx, r: Run): string {
  return `${date(c, r[0])} · ${fmtIn(r[0] - c.t)} · lasts ${runDur(r, c.range, c.o)}`
}

/** Line 1: Sun + Earth together. */
export function bothLine(d: TimelineData, t: number): AnswerLine {
  const c = ctx(d, t)
  const label = 'Sun + Earth together:'
  const cur = runAt(d.runs.both, t)
  if (cur) return { key: 'both', on: true, label, state: 'NOW', rest: remaining(c, cur) }
  const nx = nextRun(d.runs.both, t)
  if (!nx) return { key: 'both', on: false, label, state: 'NONE', rest: 'left in your chosen dates' }
  let rest = upcoming(c, nx)
  const goodH = d.goodMinH ?? 24
  if (nx[1] - nx[0] < goodH * HOUR_MS) {
    const good = nextRun(d.runs.both, t, goodH * HOUR_MS)
    rest += good ? ` · next ${goodWords(goodH)} or more: ${date(c, good[0])}` : ` · none ${goodWords(goodH)} or more left`
  }
  return { key: 'both', on: false, label, state: 'NEXT', rest }
}

/** Line 2: the next (or current) dark spell, with Dart's longest dark. */
export function darkLine(d: TimelineData, t: number): AnswerLine {
  const c = ctx(d, t)
  const ld = longestDark(d)
  const longest = ld ? ` · longest ${runDur(ld, c.range, c.o)} (from ${fmtDate(ld[0], { refMs: c.ref, time: false })})` : ''
  const g = gaps(d.runs.sun, c.range)
  const now = g.find((r) => r[0] <= t && t < r[1])
  if (now) {
    const back = nextRun(d.runs.sun, t)
    const rest = back ? `sunlight back ${date(c, back[0])}, ${fmtIn(back[0] - t)}` : 'no sunlight left in your chosen dates'
    return { key: 'dark', on: true, label: '', state: 'DARK NOW', rest: rest + longest }
  }
  const nx = g.find((r) => r[0] > t)
  if (!nx) return { key: 'dark', on: false, label: 'Next dark:', state: 'NONE', rest: `in your chosen dates${longest}` }
  return { key: 'dark', on: false, label: 'Next dark:', state: date(c, nx[0]), rest: runDur(nx, c.range, c.o) + longest }
}

/** Desktop line: Sunlight YES / NO. */
export function sunLine(d: TimelineData, t: number): AnswerLine {
  const c = ctx(d, t)
  const label = 'Sunlight:'
  const cur = runAt(d.runs.sun, t)
  if (cur) {
    const atEnd = cur[1] >= c.range[1]
    return { key: 'sun', on: true, label, state: 'YES', rest: `until ${date(c, cur[1])} (${edgePlus(fmtDur(cur[1] - t), atEnd)} more)` }
  }
  const nx = nextRun(d.runs.sun, t)
  return { key: 'sun', on: false, label, state: 'NO', rest: nx ? `back ${date(c, nx[0])}, ${fmtIn(nx[0] - t)}` : 'none left in your chosen dates' }
}

/** Desktop line: Earth in view (or Earth contact (DSN)) YES / NO. */
export function earthLine(d: TimelineData, t: number): AnswerLine {
  const c = ctx(d, t)
  const label = `${d.earthLabel || DEFAULT_EARTH}:`
  const cur = runAt(d.runs.earth, t)
  if (cur) {
    const atEnd = cur[1] >= c.range[1]
    return { key: 'earth', on: true, label, state: 'YES', rest: `until ${date(c, cur[1])} (${edgePlus(fmtDur(cur[1] - t), atEnd)} more)` }
  }
  const nx = nextRun(d.runs.earth, t)
  return { key: 'earth', on: false, label, state: 'NO', rest: nx ? `next ${date(c, nx[0])}, ${fmtIn(nx[0] - t)} · lasts ${runDur(nx, c.range, c.o)}` : 'none left in your chosen dates' }
}

/**
 * The answer lines: Sun + Earth, dark, Sunlight and Earth with [desktop], else
 * the first two. TimelineView asks for all four on phones too (the Sun and
 * Earth countdowns are the brief's "time remaining"); they sit in normal flow
 * above the plot in a one-column grid and wrap, so a 360 px view grows (and
 * scrolls) rather than overlapping the plot or overflowing sideways.
 */
export function answerLines(d: TimelineData, t: number, desktop: boolean): AnswerLine[] {
  const two = [bothLine(d, t), darkLine(d, t)]
  return desktop ? [...two, sunLine(d, t), earthLine(d, t)] : two
}

/** The answer lines as plain text (PNG export, alt text, tests). */
export function answerText(d: TimelineData, t: number, desktop = true): string[] {
  return answerLines(d, t, desktop).map(lineText)
}

// ---------------------------------------------------------------------------
// Coming up: the next changes after the time shown.

export interface ComingEvent {
  t: number
  /** ▲ starts, ▼ ends, ◇ Sun + Earth together start */
  mark: '▲' | '▼' | '◇'
  key: Glyph
  text: string
}

/** The next [n] changes after [t]: Sunlight / Earth starts and ends, Sun + Earth starts. Never "rises" or "sets". */
export function comingUp(d: TimelineData, t: number, n: number): ComingEvent[] {
  const c = ctx(d, t)
  const range = c.range
  const dsn = /dsn/i.test(d.earthLabel || '')
  const out: ComingEvent[] = []
  const sunGaps = gaps(d.runs.sun, range), earthGaps = gaps(d.runs.earth, range)
  const gapFrom = (gs: Run[], s: number) => gs.find((g) => g[0] === s)
  for (const r of d.runs.sun) {
    if (r[0] > t && r[0] > range[0]) out.push({ t: r[0], mark: '▲', key: 'sun', text: `Sunlight starts · ${date(c, r[0])} · lasts ${runDur(r, range, c.o)}` })
    if (r[1] > t && r[1] < range[1]) {
      const g = gapFrom(sunGaps, r[1])
      out.push({ t: r[1], mark: '▼', key: 'dark', text: `Sunlight ends · ${date(c, r[1])}${g ? ` · dark ${runDur(g, range, c.o)}` : ''}` })
    }
  }
  for (const r of d.runs.earth) {
    if (r[0] > t && r[0] > range[0]) {
      out.push({ t: r[0], mark: '▲', key: 'earth', text: `${dsn ? 'Earth contact starts' : 'Earth comes into view'} · ${date(c, r[0])} · ${dsn ? 'contact' : 'in view'} ${runDur(r, range, c.o)}` })
    }
    if (r[1] > t && r[1] < range[1]) {
      const g = gapFrom(earthGaps, r[1])
      out.push({ t: r[1], mark: '▼', key: 'earth',
        text: `${dsn ? 'Earth contact ends' : 'Earth goes out of view'} · ${date(c, r[1])}${g ? ` · ${dsn ? 'no contact' : 'out of view'} ${runDur(g, range, c.o)}` : ''}` })
    }
  }
  for (const r of d.runs.both) {
    if (r[0] > t && r[0] > range[0]) out.push({ t: r[0], mark: '◇', key: 'both', text: `Sun + Earth together start · ${date(c, r[0])} · lasts ${runDur(r, range, c.o)}` })
  }
  // same time: the answer (Sun + Earth) first, then Earth, then Sun
  const rank = { both: 0, earth: 1, sun: 2, dark: 2 }
  return sortedStable(out, (a, b) => a.t - b.t || rank[a.key] - rank[b.key]).slice(0, n)
}

/**
 * How many Coming up rows to show in a frame with [room] px left below the
 * list's top (to the frame's bottom padding), from each row's measured height:
 * all of them when they fit, else the first rows that fit whole together with
 * the "N more" line ([moreH] px) under them. Nothing is cut or left in a
 * scroll area the frame hides (a phone frame, or the wide pane's height).
 */
export function comingFit(room: number, rowHeights: readonly number[], moreH: number): number {
  const slack = 0.5 // sub-pixel rounding of the measured boxes
  if (rowHeights.reduce((a, h) => a + h, 0) <= room + slack) return rowHeights.length
  let used = moreH
  let k = 0
  while (k < rowHeights.length && used + rowHeights[k] <= room + slack) used += rowHeights[k++]
  return k
}

/**
 * A Coming up fit measured with every row drawn: the rows [shown], for the
 * [frame] (outer width, rows asked for, fonts) and [room] it was counted for,
 * every row's height and the "more" line's height.
 */
export interface ComingFitState { shown: number; frame: string; room: number; heights: number[]; moreH: number }

/**
 * What a layout pass reads: the [room] below the list's top, the [frame] key,
 * the heights of the rows drawn (every row while measuring) and, while
 * measuring, the "more" line's height.
 */
export interface ComingPass { room: number; frame: string; heights: readonly number[]; moreH: number }

/** What the view does after a layout pass: nothing, show [fit], or measure again (every row drawn) for [pass]. */
export type ComingFitNext = { kind: 'keep' } | { kind: 'fit'; fit: ComingFitState } | { kind: 'measure'; pass: string }

/**
 * The next step of the Coming up fit after a layout pass, given the [fit]
 * (null: this pass drew every row to measure them) and the pass a measure
 * was last started for ([measuredFor]). Measuring costs two extra renders
 * with every row drawn, so it is done only when the rows that fit could
 * change and the measured heights cannot tell: another frame (outer width,
 * rows asked for, fonts) or a row drawn at another height than measured.
 * A row's new words alone (Play changes them on most steps) are not
 * measured, nor is a new room (the answer lines above wrapping
 * differently): the measured heights count the rows again. A change the
 * last measure itself made is kept, never measured again (1.13.2 browser
 * check: with classic scrollbars a measure and the fit took turns until
 * React stopped them, error #185).
 */
export function comingFitNext(fit: ComingFitState | null, pass: ComingPass, measuredFor: string): ComingFitNext {
  const room = Math.round(pass.room)
  if (!fit) return { kind: 'fit', fit: { shown: comingFit(room, pass.heights, pass.moreH), frame: pass.frame, room, heights: [...pass.heights], moreH: pass.moreH } }
  if (pass.frame === fit.frame && pass.heights.every((h, i) => h === fit.heights[i])) {
    if (room === fit.room) return { kind: 'keep' }
    const shown = comingFit(room, fit.heights, fit.moreH)
    return shown === fit.shown ? { kind: 'keep' } : { kind: 'fit', fit: { ...fit, room, shown } }
  }
  const key = `${pass.frame}|${room}|${pass.heights.join(',')}`
  if (key === measuredFor) return { kind: 'keep' } // what the last measure itself changed
  return { kind: 'measure', pass: key }
}

/** The line under the [shown] Coming up rows that fit, for the [hidden] ones left out (it starts with the number). */
export function comingMoreText(hidden: number, shown: number): string {
  const them = hidden === 1 ? 'it' : 'them'
  // with no row shown, moving the time on lists none either: the frame is too short for one
  return shown > 0 ? `${hidden} more later · move the time on to see ${them}`
    : `${hidden} ${hidden === 1 ? 'change' : 'changes'} ahead · too little room to list ${them} here`
}

/** Every run boundary (all rows), sorted: ←/→ on the strip step through them. */
export function boundaries(d: TimelineData): number[] {
  const s = new Set<number>()
  for (const rs of [d.runs.sun, d.runs.earth, d.runs.both]) for (const r of rs) { s.add(r[0]); s.add(r[1]) }
  return [...s].filter((x) => x >= d.range[0] && x <= d.range[1]).sort((a, b) => a - b)
}

/** The boundary before (dir -1) or after (dir +1) [t], or null. */
export function stepBoundary(d: TimelineData, t: number, dir: 1 | -1): number | null {
  const b = boundaries(d)
  if (dir > 0) return b.find((x) => x > t) ?? null
  for (let i = b.length - 1; i >= 0; i--) if (b[i] < t) return b[i]
  return null
}
