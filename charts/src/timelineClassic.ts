/**
 * The CLASSIC timeline (the default on Sky & time; restored from before M6
 * step 3 at the user's request, 2026-10-12). The "Simple view" ("When") is
 * strip.ts with timelineAnswer.ts.
 *
 * Timeline: top = Sun/Earth elevation vs the terrain horizon at their
 * azimuths (the gap between a body line and its dashed horizon line is the
 * clearance); bottom = availability strip (Gantt bars) for power, comms and
 * the standout "both available" window, which is hatched so the state is
 * never encoded by colour alone.
 *
 * The curves arrive min/max-decimated (each bucket keeps its lowest and
 * highest sample, so short dips and peaks survive); the availability runs
 * arrive at full resolution.
 */
import type { Curve, TimelineData } from './bridge'
import { C, FONT, HOVER, TICK, utcIso } from './theme'

type Trace = Record<string, unknown>

export const SUN_LANE = 'Sun (power)'
export const BOTH_LANE = 'Both'
export const DEFAULT_EARTH_LANE = 'Earth in view'

/** Lane order, top to bottom on the category axis (Plotly lists categories bottom-up). */
export function lanes(earthLabel: string): string[] {
  return [BOTH_LANE, earthLabel || DEFAULT_EARTH_LANE, SUN_LANE]
}

/** Convert [start,end] ms runs into a horizontal Gantt bar trace on a date axis. */
export function runsToBars(runs: [number, number][], lane: string, color: string, pattern?: string): Trace {
  return {
    type: 'bar',
    orientation: 'h',
    y: runs.map(() => lane),
    base: runs.map((r) => utcIso(r[0])),
    x: runs.map((r) => r[1] - r[0]),
    marker: { color, line: { width: 0 }, ...(pattern ? { pattern: { shape: pattern, fillmode: 'overlay', fgcolor: C.bg, size: 7, solidity: 0.3 } } : {}) },
    xaxis: 'x',
    yaxis: 'y2',
    name: lane,
    showlegend: false,
    customdata: runs.map((r) => [utcIso(r[0]), utcIso(r[1]), ((r[1] - r[0]) / 3600e3).toFixed(1)]),
    hovertemplate: `${lane}<br>%{customdata[0]} → %{customdata[1]} UTC<br>%{customdata[2]} h<extra></extra>`,
  }
}

export function totalHours(runs: [number, number][]): number {
  return runs.reduce((a, r) => a + (r[1] - r[0]), 0) / 3600e3
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

export interface TimelineOptions {
  /** Live view: no cursor shape (the view draws the cursor as a DOM line). Default false. */
  live?: boolean
  /** Narrow plot (phone): fewer date ticks, wrapped labels, two-line totals. */
  narrow?: boolean
  /**
   * Shown full screen (the host's focus view): drag across the plot to zoom
   * into a time range (time axis only), double-tap to zoom out; the zoom
   * survives cursor and data updates. Otherwise nothing zooms. Default false.
   */
  zoom?: boolean
}

export function buildTimeline(d: TimelineData, opts: TimelineOptions = {}): { data: Trace[]; layout: Record<string, unknown>; alt: string } {
  const narrow = !!opts.narrow
  const earth = d.earthLabel || DEFAULT_EARTH_LANE
  const line = (c: Curve, name: string, color: string, dash = 'solid', width = 1.8): Trace => ({
    x: c.t.map(utcIso), y: c.y, type: 'scatter', mode: 'lines', name, line: { color, dash, width },
    hovertemplate: `${name} %{y:.2f}°<extra>%{x} UTC</extra>`,
  })
  const k = d.curves
  const data: Trace[] = [
    line(k.sunHz, 'Skyline under the Sun', C.sun, 'dot', 1),
    line(k.earthHz, 'Skyline under Earth', C.earth, 'dashdot', 1),
    line(k.sunEl, 'Sun elevation', C.sun, 'solid', 2.2),
    line(k.earthEl, 'Earth elevation', C.earth, 'solid', 1.6),
    runsToBars(d.runs.sun, SUN_LANE, C.sun),
    runsToBars(d.runs.earth, earth, C.earth),
    runsToBars(d.runs.both, BOTH_LANE, C.both, '/'),
  ]
  const order = lanes(earth)
  const hs = totalHours(d.runs.sun).toFixed(0), he = totalHours(d.runs.earth).toFixed(0), hb = totalHours(d.runs.both).toFixed(0)
  const endLabel = (c: Curve, text: string, color: string) =>
    c.t.length ? [{ x: utcIso(c.t[c.t.length - 1]), y: c.y[c.y.length - 1], xref: 'x', yref: 'y', text, showarrow: false,
      xanchor: 'left', xshift: 4, font: { size: 11.5, color } }] : []
  const layout = {
    paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER,
    margin: { l: narrow ? 60 : 112, r: narrow ? 40 : 46, t: 34, b: 44 },
    hovermode: 'x unified',
    bargap: 0.25,
    barmode: 'overlay',
    dragmode: opts.zoom ? 'zoom' : false,
    ...(opts.zoom ? { uirevision: 'focus' } : {}),
    xaxis: { type: 'date', anchor: 'y2', range: [utcIso(d.range[0]), utcIso(d.range[1])], gridcolor: C.grid, linecolor: C.gridStrong, tickfont: TICK,
      fixedrange: !opts.zoom,
      nticks: narrow ? 4 : 9, automargin: true,
      title: { text: 'UTC', font: { size: 11, color: C.muted }, standoff: 6 }, rangeslider: { visible: false } },
    yaxis: { domain: [narrow ? 0.4 : 0.34, 1], title: { text: 'ELEVATION (°)', font: { size: 11, color: C.muted } }, gridcolor: C.grid,
      zerolinecolor: C.gridStrong, tickfont: TICK, automargin: true, fixedrange: true },
    yaxis2: { domain: [0, 0.26], type: 'category', categoryorder: 'array', categoryarray: order,
      tickmode: 'array', tickvals: order, ticktext: order.map((s) => (narrow ? wrapLabel(s, 12) : s)),
      gridcolor: C.grid, fixedrange: true, tickfont: { size: 11.5, color: C.text }, automargin: true },
    legend: { orientation: 'h', x: 0, y: 1.02, yanchor: 'bottom', font: { size: 11, color: C.muted } },
    shapes: opts.live ? [] : [cursorShape(d.cursor)],
    annotations: [
      // direct line labels (identification never relies on colour alone)
      ...endLabel(k.sunEl, 'Sun', C.sun),
      ...endLabel(k.earthEl, 'Earth', C.earth),
      // totals: inside the plot width, left-aligned, so they are never clipped
      { xref: 'paper', yref: 'paper', x: 0, y: 0.27, xanchor: 'left', yanchor: 'bottom', showarrow: false, align: 'left',
        font: { size: 11, color: C.text },
        // phones: two short lines (the Earth label can be 'Earth contact (DSN)')
        text: narrow ? `Sun ${hs} h · Both ${hb} h<br>${earth} ${he} h` : `Sun ${hs} h · ${earth} ${he} h · Both ${hb} h (hatched)` }],
  }
  const alt = `Timeline for ${d.siteName}: sunlight ${hs} hours in ${d.runs.sun.length} periods, ` +
    `${earth} ${he} hours in ${d.runs.earth.length} periods, both together ` +
    `${hb} hours in ${d.runs.both.length} windows. Touch the chart to see it full screen; the time bar moves the time cursor.`
  return { data, layout, alt }
}
