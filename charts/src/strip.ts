/**
 * The "When" strip (charts spec 2.1): three labelled rows under one date
 * axis, Sun + Earth on top because it is the answer. Durations are written
 * on the bars (floored, "+" at the edge of the chosen dates, a chevron where
 * the *window* cuts a bar), and the gaps are drawn too: slate "dark" spells
 * on the Sunlight row, slate "out of view" spells on the Earth row. Row
 * labels carry Dart's `pct`.
 *
 * Render-only: every bar is a run the host sent; gaps are interval
 * bookkeeping on those runs. Flags and the cursor are DOM overlays
 * (TimelineView.tsx), so a cursor message never redraws this figure.
 */
import type { TimelineData } from './bridge'
import { pctText } from './compare'
import { DAY_MS, edgeOf, edgeTip, fmtDate, fmtDur, sortedStable, touchesEdge } from './format'
import type { Glyph, Run } from './timelineAnswer'
import { answerText, comingUp, DEFAULT_EARTH, gaps, longestDark, nextRun, rowPct, runAt, runDur } from './timelineAnswer'
import { C, FONT, HOVER, MONO, utcIso } from './theme'
import { buildHeights, cursorShape } from './timeline'

type FigOut = { data: unknown[]; layout: Record<string, unknown>; alt: string }

type Trace = Record<string, unknown>

export const BOTH_ROW = 'Sun + Earth'
export const SUN_ROW = 'Sunlight'

export type Span = '2w' | '2m' | 'all'
export const SPANS: { id: Span; label: string; short: string; days: number }[] = [
  { id: '2w', label: 'Next 2 weeks', short: '2 wk', days: 14 },
  { id: '2m', label: 'Next 2 months', short: '2 mo', days: 61 },
  { id: 'all', label: 'Whole period', short: 'All', days: Infinity },
]
export const DEFAULT_SPAN: Span = '2m'

/** Row height, px: 64 on phones, 72 on desktop. */
export const rowPx = (narrow: boolean) => (narrow ? 64 : 72)
/** Plot margins, px (the left margin holds the row labels). */
export const stripMargin = (narrow: boolean, live = true) =>
  ({ l: narrow ? 100 : 168, r: 10, t: live ? 26 : 30, b: 42 })
/** Height of the live strip figure, px. */
export const stripHeight = (narrow: boolean) => {
  const m = stripMargin(narrow)
  return 3 * rowPx(narrow) + m.t + m.b
}

/**
 * Row geometry in category units (row i spans i - 0.5 .. i + 0.5, rows from
 * the bottom): the bar sits low in its row, the flags use the band above it.
 */
export const BAR = { offset: -0.42, width: 0.48 } as const
/** Category index of each row (Plotly counts categories bottom-up). */
export const ROW_INDEX = { earth: 0, sun: 1, both: 2 } as const

/**
 * The window shown for [span]: starts at the shown time [t] and is clamped
 * to the period (near the end it slides back so it stays full length).
 */
export function spanWindow(span: Span, t: number, range: Run): Run {
  const days = SPANS.find((s) => s.id === span)?.days ?? Infinity
  const len = days * DAY_MS
  if (!Number.isFinite(len) || len >= range[1] - range[0]) return [range[0], range[1]]
  let a = Math.max(range[0], Math.min(t, range[1]))
  let b = a + len
  if (b > range[1]) { b = range[1]; a = b - len }
  return [a, b]
}

/** True while [t] is inside [w]: the window re-anchors only when the cursor leaves it. */
export function inWindow(t: number, w: Run): boolean {
  return t >= w[0] && t <= w[1]
}

/**
 * The window after a cursor at [t]: the same object while [t] stays inside
 * [prev] (so the figure is not rebuilt and Plotly does not redraw), a new one
 * anchored at [t] when it leaves.
 */
export function windowFor(prev: Run | null, span: Span, t: number, range: Run): Run {
  if (prev && inWindow(t, prev)) return prev
  return spanWindow(span, t, range)
}

/** "21 Oct 18:00" for a span up to 2 months, with the year when needed. */
const when = (ms: number, ref: number) => fmtDate(ms, { refMs: ref })

export interface StripOptions {
  /** live view: the cursor and flags are DOM overlays */
  live?: boolean
  narrow?: boolean
  /** plot width in px (which bars have room for a label) */
  widthPx?: number
  /** export only: lines baked into the figure above the rows */
  header?: string[]
  /** export only: lines baked in under the axis */
  footer?: string[]
}

/** Bar text that fits [px]: the first label that fits (full, then coarser: "10 d"), or nothing. */
export function fitLabel(px: number, ...labels: string[]): string {
  const need = (s: string) => s.length * 7.3 + 10
  return labels.find((s) => px >= need(s)) ?? ''
}

interface BarKind {
  lane: string
  title: string
  fill: string
  text: string
  pattern?: string
  /** gap bars: slate with a dashed outline, label prefix ('dark', 'out of view', 'no contact') */
  gap?: string
}

/** The row labels with the period share from Dart's `pct`, top to bottom. */
export function rowLabels(d: TimelineData): { key: 'both' | 'sun' | 'earth'; name: string; pct: number }[] {
  const p = rowPct(d)
  return [
    { key: 'both', name: BOTH_ROW, pct: p.both },
    { key: 'sun', name: SUN_ROW, pct: p.sun },
    { key: 'earth', name: d.earthLabel || DEFAULT_EARTH, pct: p.earth },
  ]
}

export function buildStrip(d: TimelineData, win: Run, opts: StripOptions = {}): { data: Trace[]; layout: Record<string, unknown>; alt: string } {
  const narrow = !!opts.narrow
  const earth = d.earthLabel || DEFAULT_EARTH
  const dsn = /dsn/i.test(earth)
  const range = d.range as Run
  const ref = range[0]
  const step = { stepMin: d.stepMin }
  const plotW = Math.max(120, opts.widthPx ?? 900)
  const pxPerMs = plotW / Math.max(1, win[1] - win[0])
  const clip = (r: Run): Run => [Math.max(r[0], win[0]), Math.min(r[1], win[1])]
  const shapes: Record<string, unknown>[] = []

  const bars = (runs: Run[], k: BarKind, row: number): Trace => {
    const vis = runs.filter((r) => r[1] > win[0] && r[0] < win[1])
    const text = vis.map((r) => {
      const c = clip(r)
      const cutL = r[0] < win[0] && r[0] > range[0], cutR = r[1] > win[1] && r[1] < range[1]
      const plus = touchesEdge(r, range) ? '+' : ''
      const dur = fmtDur(r[1] - r[0], step) + plus
      const coarse = fmtDur(r[1] - r[0], { coarse: true }) + plus
      const pre = k.gap ? `${k.gap} ` : ''
      const wrap = (s: string) => `${cutL ? '◂ ' : ''}${s}${cutR ? ' ▸' : ''}`
      return fitLabel((c[1] - c[0]) * pxPerMs, wrap(pre + dur), wrap(pre + coarse), wrap(coarse), coarse)
    })
    if (k.gap) {
      // Plotly bars have no dashed outline: a dashed rectangle per gap bar, same geometry
      for (const r of vis) {
        const c = clip(r)
        shapes.push({ type: 'rect', xref: 'x', yref: 'y', x0: utcIso(c[0]), x1: utcIso(c[1]), y0: row + BAR.offset, y1: row + BAR.offset + BAR.width,
          line: { color: C.darkLine, width: 1, dash: 'dot' }, fillcolor: 'rgba(0,0,0,0)', layer: 'above' })
      }
    }
    return {
      // bars are cut to the window so the label centres in the part on screen; hover and text keep the whole run
      type: 'bar', orientation: 'h', y: vis.map(() => k.lane), base: vis.map((r) => utcIso(clip(r)[0])), x: vis.map((r) => clip(r)[1] - clip(r)[0]),
      offset: BAR.offset, width: vis.map(() => BAR.width),
      marker: { color: k.fill, line: { width: 0 },
        ...(k.pattern ? { pattern: { shape: k.pattern, fillmode: 'overlay', fgcolor: C.page, fgopacity: 0.45, size: k.pattern === '.' ? 6 : 9, solidity: k.pattern === '.' ? 0.3 : 0.2 } } : {}) },
      text, textposition: 'inside', insidetextanchor: 'middle', constraintext: 'none', cliponaxis: true,
      textfont: { family: MONO, size: 12, color: k.text },
      customdata: vis.map((r) => {
        const e = edgeOf(r, range), cut = r[0] < win[0] || r[1] > win[1]
        const tip = touchesEdge(r, range) ? edgeTip(r, range, step) : fmtDur(r[1] - r[0], step)
        return [when(r[0], ref), when(r[1], ref), `${cut && !e.start && !e.end ? 'whole stretch ' : ''}${tip}`]
      }),
      // two lines: one long line was cut at the chart's left edge (rubric-3)
      hovertemplate: `<b>${k.title}</b> %{customdata[0]} → %{customdata[1]} UTC<br>lasts %{customdata[2]}<extra></extra>`,
      xaxis: 'x', yaxis: 'y', showlegend: false, name: k.title,
    }
  }

  const darkGaps = gaps(d.runs.sun, range)
  const earthGaps = gaps(d.runs.earth, range)
  const cats = [earth, SUN_ROW, BOTH_ROW] // bottom-up = ROW_INDEX
  const data: Trace[] = [
    bars(darkGaps, { lane: SUN_ROW, title: 'No sunlight', fill: C.dark, text: C.text, gap: 'dark' }, ROW_INDEX.sun),
    bars(d.runs.sun, { lane: SUN_ROW, title: 'Sunlight', fill: C.sun, text: C.page }, ROW_INDEX.sun),
    bars(earthGaps, { lane: earth, title: dsn ? 'No Earth contact' : 'Earth out of view', fill: C.dark, text: C.text, gap: dsn ? 'no contact' : 'out of view' }, ROW_INDEX.earth),
    bars(d.runs.earth, { lane: earth, title: earth, fill: C.earth, text: C.page, pattern: '.' }, ROW_INDEX.earth),
    bars(d.runs.both, { lane: BOTH_ROW, title: 'Sun + Earth together', fill: C.both, text: C.page, pattern: '/' }, ROW_INDEX.both),
  ]
  const span = win[1] - win[0]
  const short = span <= 75 * DAY_MS
  const m = stripMargin(narrow, !!opts.live)
  const labels = rowLabels(d)
  const ann: Record<string, unknown>[] = []
  // row labels in the left margin, level with the bars: "Sun + Earth · 40%"
  for (const l of labels) {
    const i = ROW_INDEX[l.key]
    const pct = `${l.pct.toFixed(0)}%`
    const text = narrow ? `${l.name.replace(' (DSN)', '<br>(DSN)')}<br><span style="font-family:${MONO}">${pct}</span>`
      : `${l.name} · <span style="font-family:${MONO}">${pct}</span>`
    ann.push({ xref: 'paper', yref: 'y', x: 0, xshift: -8, y: i + BAR.offset + BAR.width / 2, xanchor: 'right', yanchor: 'middle', align: 'right',
      showarrow: false, text, font: { size: narrow ? 12 : 13, color: l.key === 'both' ? C.both : l.key === 'sun' ? C.sun : C.earth } })
  }
  ann.push({ xref: 'paper', yref: 'paper', x: 0, xshift: -8, y: 0, yshift: -6, xanchor: 'right', yanchor: 'top', align: 'right', showarrow: false,
    text: narrow ? '% = share of<br>your chosen dates' : '% = share of your<br>chosen dates', font: { size: 11, color: C.muted } })
  // a row with nothing in the window says so, with the next date at the right edge
  const rows: [Run[], number][] = [[d.runs.both, ROW_INDEX.both], [d.runs.sun, ROW_INDEX.sun], [d.runs.earth, ROW_INDEX.earth]]
  for (const [runs, i] of rows) {
    if (runs.some((r) => r[1] > win[0] && r[0] < win[1])) continue
    const nx = nextRun(runs, win[1] - 1)
    ann.push({ xref: 'paper', yref: 'y', x: 1, y: i + BAR.offset + BAR.width / 2, xanchor: 'right', yanchor: 'middle', showarrow: false,
      text: nx ? `none in this span · next ${fmtDate(nx[0], { refMs: ref, time: false })} ▸` : 'none in this span', font: { size: 12, color: C.muted } })
  }
  const head = opts.header ?? [], foot = opts.footer ?? []
  if (head.length) {
    ann.push({ xref: 'paper', yref: 'paper', x: 0, xshift: -m.l + 16, y: 1, yshift: 14, xanchor: 'left', yanchor: 'bottom', showarrow: false, align: 'left',
      text: head.join('<br>'), font: { size: 15, color: C.text } })
  }
  if (foot.length) {
    ann.push({ xref: 'paper', yref: 'paper', x: 0, xshift: -m.l + 16, y: 0, yshift: -48, xanchor: 'left', yanchor: 'top', showarrow: false, align: 'left',
      text: foot.join('<br>'), font: { size: 14, color: C.text } })
  }
  const layout: Record<string, unknown> = {
    paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER,
    margin: { ...m, t: m.t + 22 * head.length + (head.length ? 14 : 0), b: m.b + 22 * foot.length + (foot.length ? 16 : 0) },
    hovermode: 'closest', barmode: 'overlay',
    xaxis: { type: 'date', range: [utcIso(win[0]), utcIso(win[1])], gridcolor: C.grid, linecolor: C.gridStrong,
      tickfont: { family: MONO, size: 11.5, color: C.muted }, nticks: narrow ? 4 : 8,
      tickformat: short ? '%-d %b' : '%b %Y', fixedrange: true, showline: true },
    yaxis: { type: 'category', range: [-0.5, cats.length - 0.5], categoryorder: 'array', categoryarray: cats,
      showticklabels: false, fixedrange: true, showgrid: false, zeroline: false, ticks: '' },
    shapes: [...shapes, ...(opts.live ? [] : [cursorShape(d.cursor)])],
    annotations: ann,
    dragmode: false,
  }
  const p = rowPct(d)
  const ld = d.longestDark
  const alt = `When ${d.siteName} has sunlight and Earth in view, ${fmtDate(range[0], { year: true, time: false })} to ${fmtDate(range[1], { year: true, time: false })}: ` +
    `Sun and Earth together ${pctText(p.both)} of your chosen dates in ${d.runs.both.length} windows, ` +
    `sunlight ${pctText(p.sun)} in ${d.runs.sun.length} spells, ${earth} ${pctText(p.earth)} in ${d.runs.earth.length} spells, ` +
    // the visible line's "14 d+" in words: "at least 14 d (covers all of your chosen dates)"
    `${darkGaps.length} dark spells${ld ? `, the longest ${edgeTip(ld, range, step)}` : ''}. All times UTC.`
  return { data, layout, alt }
}

// ---------------------------------------------------------------------------
// Flags on the strip (DOM): next both, next dark, longest dark.

export interface Flag { row: number; x: number; text: string; key: Glyph }
export interface PlacedFlag extends Flag { left: number; top: number; flip: boolean; tickTop: number; tickH: number }

/** Flag texts and times for the shown window. */
export function stripFlags(d: TimelineData, t: number, win: Run): { row: number; ms: number; text: string; key: Glyph }[] {
  const range = d.range as Run
  const o = { stepMin: d.stepMin }
  const inWin = (ms: number) => ms >= win[0] && ms <= win[1]
  const out: { row: number; ms: number; text: string; key: Glyph }[] = []
  if (!runAt(d.runs.both, t)) {
    const nb = nextRun(d.runs.both, t)
    if (nb && inWin(nb[0])) out.push({ row: ROW_INDEX.both, ms: nb[0], key: 'both', text: `Next both · ${fmtDate(nb[0], { refMs: range[0] })} · ${runDur(nb, range, o)}` })
  }
  const g = gaps(d.runs.sun, range)
  const darkNow = g.some((r) => r[0] <= t && t < r[1])
  const nd = darkNow ? null : g.find((r) => r[0] > t) ?? null
  const mid = (r: Run) => (Math.max(r[0], win[0]) + Math.min(r[1], win[1])) / 2
  if (nd && nd[0] < win[1]) out.push({ row: ROW_INDEX.sun, ms: mid(nd), key: 'dark', text: `Next dark · ${runDur(nd, range, o)}` })
  const ld = longestDark(d)
  if (ld && ld[1] > win[0] && ld[0] < win[1]) out.push({ row: ROW_INDEX.sun, ms: mid(ld), key: 'dark', text: `Longest dark · ${runDur(ld, range, o)}` })
  return out
}

/** Estimated flag width, px (11.5 px Plex Sans/Mono). */
export const flagW = (s: string) => s.length * 6.4 + 12

/**
 * A flag text that fits [maxW] px: as it is, else without its middle parts
 * ("Next both · 20 Oct 05:00 · 15 d 3 h" -> "Next both · 15 d 3 h"), else
 * cut with an ellipsis (rubric-2: at 320 px the full flag ran past the
 * chart's right edge).
 */
export function fitFlag(text: string, maxW: number): string {
  if (flagW(text) <= maxW) return text
  const parts = text.split(' · ')
  if (parts.length > 2) {
    const short = `${parts[0]} · ${parts[parts.length - 1]}`
    if (flagW(short) <= maxW) return short
    text = short
  }
  const n = Math.max(1, Math.floor((maxW - 12) / 6.4) - 1)
  return text.length > n ? `${text.slice(0, n).trimEnd()}…` : text
}

/**
 * Place the flags: each sits in the band above its bar with a tick down to
 * the bar; it flips to the left of its tick near the right edge, and a later
 * flag that would overlap an earlier one on the same row moves up a line.
 */
export function placeFlags(flags: Flag[], plot: { l: number; w: number }, rowTop: (row: number) => number): PlacedFlag[] {
  const out: PlacedFlag[] = []
  const byRow = new Map<number, Flag[]>()
  for (const f of flags) byRow.set(f.row, [...(byRow.get(f.row) ?? []), f])
  for (const [row, fs] of byRow) {
    const placed: { a: number; b: number; line: number }[] = []
    for (const f0 of sortedStable(fs, (p, q) => p.x - q.x)) {
      const f = { ...f0, text: fitFlag(f0.text, plot.w) }
      const w = flagW(f.text)
      const flip = f.x + w > plot.l + plot.w
      // never over the row labels or past the right edge: the tick keeps pointing at the exact time
      const a = Math.max(plot.l, Math.min(flip ? f.x - w : f.x, plot.l + plot.w - w)), b = a + w
      let line = 0
      while (placed.some((p) => p.line === line && a < p.b + 4 && b > p.a - 4)) line++
      placed.push({ a, b, line })
      const barTop = rowTop(row)
      const top = barTop - 17 - line * 16
      out.push({ ...f, left: a, top, flip, tickTop: top + 14, tickH: Math.max(4, barTop - (top + 14) + 6) })
    }
  }
  return out
}

/**
 * The PNG export: the whole period (whatever span is on screen), the cursor,
 * the header, the answer lines and Coming up; the Heights curves under it
 * when Exact numbers is on.
 */
export function buildTimelineExport(d: TimelineData, t: number, exact: boolean): FigOut {
  const range = d.range as Run
  const day = (ms: number) => fmtDate(ms, { year: true, time: false })
  const header = [
    `<b>When · ${d.siteName}</b> · Whole period ${day(range[0])} – ${day(range[1])} · all times UTC`,
    `Shown ${fmtDate(t, { year: true })}`,
    ...answerText(d, t, true).map((s) => `· ${s}`),
  ]
  const footer = ['<b>Coming up</b>', ...comingUp(d, t, 5).map((e) => `${e.mark} ${e.text}`)]
  const s = buildStrip({ ...d, cursor: t }, range, { widthPx: 1300, header, footer: exact ? [] : footer })
  if (!exact) return s
  const h = buildHeights({ ...d, cursor: t })
  const sl = s.layout, hl = h.layout as Record<string, Record<string, unknown>>
  return {
    alt: s.alt,
    data: [...s.data, ...h.data.map((tr) => ({ ...tr, xaxis: 'x2', yaxis: 'y2' }))],
    layout: {
      ...sl,
      margin: { ...(sl.margin as object), b: 60 + 22 * footer.length },
      xaxis: { ...(sl.xaxis as object), anchor: 'y' },
      yaxis: { ...(sl.yaxis as object), domain: [0.52, 1] },
      xaxis2: { ...hl.xaxis, anchor: 'y2' },
      yaxis2: { ...hl.yaxis, domain: [0, 0.36], anchor: 'x2' },
      legend: { orientation: 'h', x: 0, y: 0.38, yanchor: 'bottom', font: { size: 13, color: C.muted } },
      // the strip's cursor line spans the whole paper, so it crosses the Heights panel too (same time range)
      shapes: sl.shapes,
      annotations: [...(sl.annotations as unknown[]),
        { xref: 'paper', yref: 'paper', x: 0, y: 0, yshift: -40, xanchor: 'left', yanchor: 'top', showarrow: false, align: 'left',
          text: footer.join('<br>'), font: { size: 14, color: C.text } }],
    },
  }
}
