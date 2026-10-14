/**
 * The timeline's Exact-numbers figure, "Heights" (charts spec 2.1): the Sun
 * and Earth heights above the flat horizon, each with the height of the
 * hills in its direction (a body clears the hills while its solid line is
 * above its dotted line). It is added under the "When" strip (strip.ts),
 * never swapped for it.
 *
 * The curves arrive min/max-decimated (each bucket keeps its lowest and
 * highest sample, so short dips and peaks survive).
 */
import type { Curve, TimelineData } from './bridge'
import { C, FONT, HOVER, MONO, TICK, utcIso } from './theme'

type Trace = Record<string, unknown>

export const DEFAULT_EARTH_LANE = 'Earth in view'

/** The four curve names, in legend order. */
export const HEIGHT_NAMES = {
  sunEl: 'Sun height',
  sunHz: 'Hills toward the Sun',
  earthEl: 'Earth height',
  earthHz: 'Hills toward Earth',
} as const

export function totalHours(runs: [number, number][]): number {
  return runs.reduce((a, r) => a + (r[1] - r[0]), 0) / 3600e3
}

/** "Sunlight 7105 h in 37 spells · Earth in view 3914 h in 13 · Sun + Earth 3477 h in 34 windows" */
export function totalsLine(d: TimelineData): string {
  const earth = d.earthLabel || DEFAULT_EARTH_LANE
  const h = (r: [number, number][]) => totalHours(r).toFixed(0)
  return `Sunlight ${h(d.runs.sun)} h in ${d.runs.sun.length} spells · ${earth} ${h(d.runs.earth)} h in ${d.runs.earth.length} · ` +
    `Sun + Earth ${h(d.runs.both)} h in ${d.runs.both.length} windows`
}

/** Break a label at the space nearest its middle when it is longer than [max] characters. */
export function wrapLabel(s: string, max: number): string {
  if (s.length <= max || !s.includes(' ')) return s
  const mid = s.length / 2
  let best = -1
  for (let i = 0; i < s.length; i++) if (s[i] === ' ' && (best < 0 || Math.abs(i - mid) < Math.abs(best - mid))) best = i
  return `${s.slice(0, best)}<br>${s.slice(best + 1)}`
}

/** The cursor line (a layout shape) at Unix ms [t]. */
export function cursorShape(t: number): Record<string, unknown> {
  const x = utcIso(t)
  return { type: 'line', xref: 'x', yref: 'paper', x0: x, x1: x, y0: 0, y1: 1, line: { color: C.ice, width: 1.5, dash: 'solid' } }
}

export interface HeightsOptions {
  /** live view: no cursor shape (the view draws the cursor as a DOM line) */
  live?: boolean
  narrow?: boolean
  /** x range [startMs, endMs] (the strip's window); the whole period when absent */
  window?: [number, number]
}

/** Margins of the Heights figure (the left one matches the strip, so the time axes line up). */
export const heightsMargin = (narrow: boolean) => ({ l: narrow ? 100 : 168, r: 10, t: 12, b: 92 })

export function buildHeights(d: TimelineData, opts: HeightsOptions = {}): { data: Trace[]; layout: Record<string, unknown> } {
  const narrow = !!opts.narrow
  const line = (c: Curve, name: string, color: string, dash = 'solid', width = 1.8): Trace => ({
    x: c.t.map(utcIso), y: c.y, type: 'scatter', mode: 'lines', name, line: { color, dash, width },
    hovertemplate: `${name} %{y:.2f}°<extra>%{x} UTC</extra>`,
  })
  const k = d.curves
  const data: Trace[] = [
    line(k.sunEl, HEIGHT_NAMES.sunEl, C.sun, 'solid', 2.4),
    line(k.sunHz, HEIGHT_NAMES.sunHz, C.sun, 'dot', 1.2),
    line(k.earthEl, HEIGHT_NAMES.earthEl, C.earth, 'solid', 1.7),
    line(k.earthHz, HEIGHT_NAMES.earthHz, C.earth, 'dashdot', 1.2),
  ]
  const w = opts.window ?? d.range
  const short = w[1] - w[0] <= 75 * 86400e3
  const layout = {
    paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER,
    margin: heightsMargin(narrow),
    hovermode: 'x unified',
    xaxis: { type: 'date', range: [utcIso(w[0]), utcIso(w[1])], gridcolor: C.grid, linecolor: C.gridStrong,
      tickfont: { ...TICK, family: MONO }, nticks: narrow ? 4 : 8, tickformat: short ? '%-d %b' : '%b %Y', fixedrange: true },
    yaxis: { title: { text: 'HEIGHT ABOVE FLAT (°)', font: { size: 11, color: C.muted } }, gridcolor: C.grid,
      zerolinecolor: C.gridStrong, tickfont: { ...TICK, family: MONO }, automargin: true, fixedrange: true },
    // the legend sits below the plot: never clipped on phones, no end labels to collide
    legend: { orientation: 'h', x: 0, xanchor: 'left', y: -0.2, yanchor: 'top', font: { size: 12, color: C.muted } },
    shapes: opts.live ? [] : [cursorShape(d.cursor)],
    dragmode: false,
  }
  return { data, layout }
}
