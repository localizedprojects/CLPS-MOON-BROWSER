/**
 * The CLASSIC sky plot (the default on Sky & time; restored from before M6
 * step 3 at the user's request, 2026-10-12): degree rings, the terrain
 * skyline, the Sun and Earth paths for the whole period, markers with
 * elevation labels, horizon zoom, the 3-line header and the legend. The
 * "Simple view" ("Where to look") is sky.ts.
 *
 * Sky polar plot geometry: azimuth clockwise from north at the top,
 * radius = elevation mapped linearly from the top of the displayed range
 * (centre) to the bottom (outer ring). "Horizon zoom" shrinks the range to
 * the few degrees around the horizon where polar Sun/Earth actually move;
 * the exaggeration is always stated on the chart.
 *
 * The figure has a static part (rings, terrain, paths: drawn by Plotly once
 * per payload) and a dynamic part that follows the time cursor (the Sun and
 * Earth markers, their labels, the ring labels and the time stamp). The live
 * view draws the dynamic part in a light SVG overlay (see skyOverlay.ts), so
 * scrubbing never re-renders the Plotly figure; [buildSky] with
 * `live: false` puts the same dynamic part into the figure (PNG export).
 * Both use [skyDynamic], so the two always agree.
 */
import type { BodyNow, SkyData } from './bridge'
import { C, FONT, HOVER, MONO } from './theme'
import { pctShowing } from './skyCaption'

export interface ElRange {
  lo: number
  hi: number
}

export const FULL_RANGE: ElRange = { lo: -10, hi: 90 }

/** Axis half-width in plot units (the outer ring has radius 1). */
export const SKY_EXTENT = 1.18
/** Radius of the azimuth labels, plot units. */
const AZ_LABEL_R = 1.09

/** Range for horizon zoom: covers the terrain mask and both bodies with margin. */
export function zoomRange(mask: number[], sunEls: number[], earthEls: number[]): ElRange {
  const all = [...mask, ...sunEls, ...earthEls].filter((x) => Number.isFinite(x))
  // a loop, not Math.min(...all): spreading tens of thousands of arguments can overflow the stack
  let mn = -3, mx = 6
  for (const v of all) {
    if (v < mn) mn = v
    if (v > mx) mx = v
  }
  return { lo: Math.floor(mn - 1), hi: Math.ceil(mx + 1) }
}

/** Elevation -> radius in [0,1] (0 = centre = range.hi). Clamped. */
export function elToR(el: number, r: ElRange): number {
  const v = (r.hi - el) / (r.hi - r.lo)
  return Math.min(1, Math.max(0, v))
}

/** (az, el) -> plot xy with north up and east to the right (as seen from above). */
export function toXY(azDeg: number, el: number, r: ElRange): [number, number] {
  const rr = elToR(el, r)
  const a = (azDeg * Math.PI) / 180
  return [rr * Math.sin(a), rr * Math.cos(a)]
}

function circle(rr: number, n = 181): { x: number[]; y: number[] } {
  const x: number[] = [], y: number[] = []
  for (let i = 0; i < n; i++) {
    const a = (i / (n - 1)) * 2 * Math.PI
    x.push(rr * Math.sin(a))
    y.push(rr * Math.cos(a))
  }
  return { x, y }
}

/** Pick ~5 "nice" elevation ring values inside the range. */
export function ringValues(r: ElRange): number[] {
  const span = r.hi - r.lo
  const step = span > 60 ? 30 : span > 20 ? 5 : span > 10 ? 2 : 1
  const out: number[] = []
  for (let v = Math.ceil(r.lo / step) * step; v <= r.hi; v += step) out.push(v)
  return out
}

/** The labelled rings: every other one when there are many (keeps small screens legible). */
export function labelledRings(r: ElRange): number[] {
  const rings = ringValues(r)
  return rings.filter((_, i) => rings.length <= 6 || i % 2 === 0)
}

// ---------------------------------------------------------------------------
// Dynamic part: where the bodies, their labels and the ring labels go.

function angDist(a: number, b: number): number {
  const d = Math.abs((((a - b) % 360) + 360) % 360)
  return Math.min(d, 360 - d)
}

/**
 * Azimuth of the diagonal (45, 135, 225 or 315°) farthest from both bodies:
 * the ring labels go there so they never sit under a body or its label.
 * With two bodies some diagonal is always at least 45° from both.
 */
export function ringLabelAz(sunAz: number, earthAz: number): number {
  let best = 45, bestD = -1
  for (const a of [45, 135, 225, 315]) {
    const d = Math.min(angDist(a, sunAz), angDist(a, earthAz))
    if (d > bestD + 1e-9) {
      best = a
      bestD = d
    }
  }
  return best
}

/** Plotly text positions (the overlay reproduces the same offsets). */
export type LabelPos = 'top center' | 'bottom center' | 'middle left' | 'middle right' | 'top left' | 'top right' | 'bottom left' | 'bottom right'
export const LABEL_POSITIONS: LabelPos[] = ['top center', 'bottom center', 'middle right', 'middle left', 'top right', 'top left', 'bottom right', 'bottom left']

/** Axis-aligned box in px, y up, centre of the plot at (0, 0). */
export interface Box {
  x0: number
  x1: number
  y0: number
  y1: number
}

export const LABEL_FONT_PX = 12
/** IBM Plex Mono advance width is 0.6 em. */
export const LABEL_CHAR_PX = 0.6 * LABEL_FONT_PX
const LABEL_H = 15
/** Gap between a marker centre and its label (marker radius 9 px + 4 px). */
export const LABEL_GAP = 13
const HALO_R = 14
/** Body marker radius, px (= Plotly marker size 18). */
export const MARKER_R = 9
/** Light fill of a counted Earth disc around its solid crescent (filled = counted, open = not). */
export const EARTH_DISC_FILL = 'rgba(61,139,253,0.35)'

/**
 * Earth's marker shape, as in the app's Earth glyph (glyphs.dart): a disc
 * with a crescent on its left limb (the unit disc minus the unit disc shifted
 * right by 0.55). Outline points, unit radius, y up. The Sun is a plain disc
 * and "Sun and Earth both" is a hatched diamond elsewhere in the app, so the
 * sky plot never draws Earth as a diamond (ux2-5).
 */
export function crescentPoints(n = 12): [number, number][] {
  const d = 0.55
  const t = Math.acos(d / 2) // outer limb, from the top intersection round the left to the bottom one
  const p = Math.acos(-d / 2) // inner edge (the shifted disc), from the bottom back to the top
  const pts: [number, number][] = []
  for (let i = 0; i <= 2 * n; i++) {
    const a = t + ((2 * Math.PI - 2 * t) * i) / (2 * n)
    pts.push([Math.cos(a), Math.sin(a)])
  }
  for (let i = 1; i < n; i++) {
    const a = 2 * Math.PI - p - ((2 * Math.PI - 2 * p) * i) / n
    pts.push([d + Math.cos(a), Math.sin(a)])
  }
  return pts
}

/** Box of a label of [chars] characters at [pos] around a marker at (mx, my) px. */
export function labelBox(mx: number, my: number, chars: number, pos: LabelPos): Box {
  const w = chars * LABEL_CHAR_PX, h = LABEL_H, g = LABEL_GAP, d = g * 0.72
  switch (pos) {
    case 'top center': return { x0: mx - w / 2, x1: mx + w / 2, y0: my + g, y1: my + g + h }
    case 'bottom center': return { x0: mx - w / 2, x1: mx + w / 2, y0: my - g - h, y1: my - g }
    case 'middle right': return { x0: mx + g, x1: mx + g + w, y0: my - h / 2, y1: my + h / 2 }
    case 'middle left': return { x0: mx - g - w, x1: mx - g, y0: my - h / 2, y1: my + h / 2 }
    case 'top right': return { x0: mx + d, x1: mx + d + w, y0: my + d, y1: my + d + h }
    case 'top left': return { x0: mx - d - w, x1: mx - d, y0: my + d, y1: my + d + h }
    case 'bottom right': return { x0: mx + d, x1: mx + d + w, y0: my - d - h, y1: my - d }
    case 'bottom left': return { x0: mx - d - w, x1: mx - d, y0: my - d - h, y1: my - d }
  }
}

function overlap(a: Box, b: Box): number {
  const w = Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0)
  const h = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0)
  return w > 0 && h > 0 ? w * h : 0
}

/** Area of [a] outside [frame]. */
function outside(a: Box, frame: Box): number {
  const area = (a.x1 - a.x0) * (a.y1 - a.y0)
  return area - overlap(a, frame)
}

const PREF: Record<LabelPos, number> = {
  'top center': 0, 'bottom center': 4, 'middle right': 6, 'middle left': 6,
  'top right': 9, 'top left': 9, 'bottom right': 12, 'bottom left': 12,
}

export interface BodyMark {
  /** marker centre, px (y up, plot centre at 0,0) */
  x: number
  y: number
  text: string
}

/** Cost per px² of overlap: any overlap costs more than the position preference. */
const OVERLAP_COST = 10

/**
 * Choose text positions for the body labels so they avoid each other, both
 * markers, the [obstacles] (ring and azimuth labels) and the edge of the
 * plot ([frame]). Tries every pair of positions; the cost is the overlapping
 * area in px² (weighted well above the preference) plus a small preference
 * for 'top center'.
 */
export function placeBodyLabels(bodies: BodyMark[], obstacles: Box[], frame: Box): LabelPos[] {
  const halo = (b: BodyMark): Box => ({ x0: b.x - HALO_R, x1: b.x + HALO_R, y0: b.y - HALO_R, y1: b.y + HALO_R })
  const halos = bodies.map(halo)
  const single = (i: number, p: LabelPos): number => {
    const box = labelBox(bodies[i].x, bodies[i].y, bodies[i].text.length, p)
    let c = PREF[p] + 2 * OVERLAP_COST * outside(box, frame)
    for (const o of obstacles) c += OVERLAP_COST * overlap(box, o)
    halos.forEach((h, j) => { if (j !== i) c += 2 * OVERLAP_COST * overlap(box, h) })
    return c
  }
  if (bodies.length === 1) {
    return [LABEL_POSITIONS.reduce((a, p) => (single(0, p) < single(0, a) ? p : a))]
  }
  let best: LabelPos[] = [LABEL_POSITIONS[0], LABEL_POSITIONS[0]], bestC = Infinity
  const c0 = new Map(LABEL_POSITIONS.map((p) => [p, single(0, p)]))
  const c1 = new Map(LABEL_POSITIONS.map((p) => [p, single(1, p)]))
  for (const p of LABEL_POSITIONS) {
    const b0 = labelBox(bodies[0].x, bodies[0].y, bodies[0].text.length, p)
    for (const q of LABEL_POSITIONS) {
      const b1 = labelBox(bodies[1].x, bodies[1].y, bodies[1].text.length, q)
      const c = c0.get(p)! + c1.get(q)! + 2 * OVERLAP_COST * overlap(b0, b1)
      if (c < bestC - 1e-9) {
        bestC = c
        best = [p, q]
      }
    }
  }
  return best
}

export interface RingLabel {
  value: number
  text: string
  /** plot units */
  x: number
  y: number
}

export interface BodyDyn {
  name: 'Sun' | 'Earth'
  color: string
  /** Sun = plain disc, Earth = disc with a crescent (see [crescentPoints]) */
  symbol: 'circle' | 'crescent'
  /** plot units */
  x: number
  y: number
  text: string
  pos: LabelPos
  visible: boolean
  /** hover / tooltip text */
  title: string
  b: BodyNow
}

export interface SkyDynamic {
  sun: BodyDyn
  earth: BodyDyn
  rings: RingLabel[]
  ringAz: number
}

/**
 * The body's state in words, from the flags Dart sent: counted as up, up but
 * rejected only by the DSN check, partly above the skyline but not counted
 * under a stricter rule, or hidden.
 */
export function stateText(b: BodyNow, hidden = 'below terrain horizon'): string {
  // pctShowing: a partly visible disc never reads 0% or 100%
  if (b.visible) return b.frac < 0.999 ? `partly visible (${Math.min(99, pctShowing(b.frac))}%)` : 'visible'
  if (b.terrainVisible) return 'in view, but no DSN station can see the Moon'
  if (b.frac > 0) return `${Math.min(99, pctShowing(b.frac))}% above the skyline, not counted under the current rule`
  return hidden
}

/**
 * Everything that follows the cursor, in plot units. [rPx] is the radius of
 * the outer ring in screen px (label sizes are in px).
 */
export function skyDynamic(now: { sun: BodyNow; earth: BodyNow }, range: ElRange, rPx: number): SkyDynamic {
  const ringAz = ringLabelAz(now.sun.az, now.earth.az)
  const rings: RingLabel[] = labelledRings(range).map((v) => {
    const [x, y] = toXY(ringAz, v, range)
    return { value: v, text: `${v}°`, x, y }
  })
  const k = Math.max(rPx, 1)
  const obstacles: Box[] = []
  // ring labels are drawn left-anchored at their point (11 px Mono)
  for (const r of rings) obstacles.push({ x0: r.x * k, x1: r.x * k + r.text.length * 6.6 + 2, y0: r.y * k - 7, y1: r.y * k + 7 })
  // azimuth labels at r = 1.09 (centred)
  for (let a = 0; a < 360; a += 30) {
    const t = ({ 0: 'N', 90: 'E', 180: 'S', 270: 'W' } as Record<number, string>)[a] ?? `${a}°`
    const cx = AZ_LABEL_R * Math.sin((a * Math.PI) / 180) * k, cy = AZ_LABEL_R * Math.cos((a * Math.PI) / 180) * k
    const w = t.length * 6.8 + 2
    obstacles.push({ x0: cx - w / 2, x1: cx + w / 2, y0: cy - 8, y1: cy + 8 })
  }
  const frame: Box = { x0: -SKY_EXTENT * k, x1: SKY_EXTENT * k, y0: -SKY_EXTENT * k, y1: SKY_EXTENT * k }
  const mk = (b: BodyNow, name: 'Sun' | 'Earth') => {
    const [x, y] = toXY(b.az, b.el, range)
    return { x, y, text: `${name} ${b.el.toFixed(2)}°` }
  }
  const s = mk(now.sun, 'Sun'), e = mk(now.earth, 'Earth')
  const [ps, pe] = placeBodyLabels([{ x: s.x * k, y: s.y * k, text: s.text }, { x: e.x * k, y: e.y * k, text: e.text }], obstacles, frame)
  const body = (b: BodyNow, m: { x: number; y: number; text: string }, name: 'Sun' | 'Earth', pos: LabelPos): BodyDyn => ({
    name, color: name === 'Sun' ? C.sun : C.earth, symbol: name === 'Sun' ? 'circle' : 'crescent',
    x: m.x, y: m.y, text: m.text, pos, visible: b.visible, b,
    title: `${name}: azimuth ${b.az.toFixed(2)}°, elevation ${b.el.toFixed(2)}°, terrain horizon ${b.hz.toFixed(2)}°, ${stateText(b)}`,
  })
  return { sun: body(now.sun, s, 'Sun', ps), earth: body(now.earth, e, 'Earth', pe), rings, ringAz }
}

/** Header lines: site and time (bold / mono), then the radius scale and orientation. */
export function skyHeader(d: Pick<SkyData, 'siteName' | 'timeLabel' | 'zoom'>, range: ElRange): { site: string; time: string; scale: string; orient: string } {
  return {
    site: d.siteName,
    time: d.timeLabel,
    scale: d.zoom ? `Horizon zoom ${range.lo}°…${range.hi}° (radius exaggerated)` : 'Full sky −10°…90°',
    orient: 'N points away from the pole',
  }
}

export function skyAlt(d: Pick<SkyData, 'siteName' | 'timeLabel' | 'mask' | 'now'>): string {
  const st = (b: BodyNow) => stateText(b, 'hidden by terrain')
  let hmax = -Infinity
  for (const v of d.mask) if (v > hmax) hmax = v
  return `Sky plot for ${d.siteName} at ${d.timeLabel}. Sun at azimuth ${d.now.sun.az.toFixed(0)} degrees, elevation ` +
    `${d.now.sun.el.toFixed(1)} degrees, ${st(d.now.sun)}. Earth at azimuth ${d.now.earth.az.toFixed(0)} degrees, elevation ` +
    `${d.now.earth.el.toFixed(1)} degrees, ${st(d.now.earth)}. Highest terrain horizon ${hmax.toFixed(1)} degrees.`
}

// ---------------------------------------------------------------------------

// Plotly types are loose; keep these as plain objects.
type Trace = Record<string, unknown>

export interface SkyOptions {
  /**
   * Live view: leave out the dynamic part (markers, body and ring labels,
   * header), which the overlay draws. Default false (complete figure).
   */
  live?: boolean
  /** Narrow plot (phone): smaller margins and legend. */
  narrow?: boolean
  /** Outer-ring radius in px used to place labels in a complete figure (export). */
  rPx?: number
}

/** Top margin that holds the three header lines. */
export const SKY_MARGIN_TOP = 62

/**
 * Top margin of the live figure: one header line more on a phone when a long
 * site name wraps the first line (the header shows the name in full).
 */
export function skyMarginTop(siteName: string, narrow: boolean): number {
  return narrow && siteName.length > 24 ? SKY_MARGIN_TOP + 16 : SKY_MARGIN_TOP
}

export function buildSky(d: SkyData, opts: SkyOptions = {}): { data: Trace[]; layout: Record<string, unknown>; range: ElRange; alt: string } {
  const range = d.zoom ? zoomRange(d.mask, d.trails.sun.el, d.trails.earth.el) : FULL_RANGE
  const data: Trace[] = []

  // elevation rings
  for (const v of ringValues(range)) {
    const c = circle(elToR(v, range))
    data.push({ ...c, type: 'scatter', mode: 'lines', hoverinfo: 'skip', showlegend: false,
      line: { color: v === 0 ? C.gridStrong : C.grid, width: v === 0 ? 1.5 : 1, dash: v === 0 ? 'dash' : 'dot' } })
  }
  // azimuth spokes
  for (let a = 0; a < 360; a += 30) {
    const [x, y] = toXY(a, range.lo, range)
    data.push({ x: [0, x], y: [0, y], type: 'scatter', mode: 'lines', hoverinfo: 'skip', showlegend: false,
      line: { color: C.grid, width: 1 } })
  }

  // terrain silhouette: horizon mask polyline closed against the outer ring
  const mx: number[] = [], my: number[] = []
  for (let i = 0; i <= d.mask.length; i++) {
    const az = (i % d.mask.length) * d.maskStepDeg
    const [x, y] = toXY(az, d.mask[i % d.mask.length], range)
    mx.push(x)
    my.push(y)
  }
  const outer = circle(1, 361)
  data.push({
    x: [...mx, ...outer.x.slice().reverse()], y: [...my, ...outer.y.slice().reverse()],
    type: 'scatter', mode: 'lines', fill: 'toself', fillcolor: C.terrain,
    line: { color: C.terrainEdge, width: 1.2 }, name: d.maskApprox ? 'Terrain (coarse DEM)' : 'Terrain horizon (LOLA)',
    hoverinfo: 'skip',
  })

  // paths over the selected range: one polyline each (thousands of marker
  // nodes made every redraw slow); solid Sun, dotted Earth (not colour alone)
  const trail = (az: number[], el: number[], color: string, name: string, dash: string) => {
    const x: number[] = [], y: number[] = []
    az.forEach((a, i) => { const p = toXY(a, el[i], range); x.push(p[0]); y.push(p[1]) })
    data.push({ x, y, type: 'scatter', mode: 'lines', name, line: { color, width: 1.2, dash }, opacity: 0.6, hoverinfo: 'skip' })
  }
  trail(d.trails.sun.az, d.trails.sun.el, C.sun, 'Sun path (period)', 'solid')
  trail(d.trails.earth.az, d.trails.earth.el, C.earth, 'Earth path (period)', 'dot')

  // azimuth labels
  const annotations: Record<string, unknown>[] = []
  const names: Record<number, string> = { 0: 'N', 90: 'E', 180: 'S', 270: 'W' }
  for (let a = 0; a < 360; a += 30) {
    const [x, y] = toXY(a, range.lo, range)
    annotations.push({ x: x * AZ_LABEL_R, y: y * AZ_LABEL_R, text: names[a] ?? `${a}°`, showarrow: false,
      font: { color: names[a] ? C.text : C.muted, size: names[a] ? 13 : 11 } })
  }

  if (!opts.live) {
    // complete figure: the dynamic part as traces and annotations
    const k = Math.max(opts.rPx ?? 300, 1)
    const dyn = skyDynamic(d.now, range, k)
    for (const b of [dyn.sun, dyn.earth]) {
      // dark halo so the marker keeps >= 3:1 contrast on the grey terrain fill (WCAG 1.4.11)
      data.push({ x: [b.x], y: [b.y], type: 'scatter', mode: 'markers', hoverinfo: 'skip', showlegend: false,
        marker: { size: 28, color: C.halo } })
      // filled = counted as up, open = not counted (terrain, a stricter rule or no DSN; the
      // hover text says which). Shape encodes the state, not just colour.
      data.push({
        x: [b.x], y: [b.y], type: 'scatter', mode: 'text+markers', name: `${b.name} now`, showlegend: false,
        text: [b.text], textposition: b.pos, textfont: { color: C.text, size: LABEL_FONT_PX, family: MONO },
        marker: b.symbol === 'circle'
          ? { size: 18, color: b.color, symbol: b.visible ? 'circle' : 'circle-open', // open symbols are drawn in marker.color
            line: { color: b.color, width: 2.5 } }
          // Earth: outlined disc, lightly filled when counted; the crescent is the trace below
          : { size: 18, color: b.visible ? EARTH_DISC_FILL : 'rgba(0,0,0,0)', symbol: 'circle', line: { color: b.color, width: 2.5 } },
        hovertemplate: `${b.title}<extra></extra>`,
      })
      if (b.symbol === 'crescent') {
        // the crescent in plot units (marker radius px / px per unit), solid when counted
        const s = (MARKER_R - 1.5) / k
        const pts = crescentPoints()
        data.push({
          x: [...pts.map((q) => b.x + q[0] * s), b.x + pts[0][0] * s], y: [...pts.map((q) => b.y + q[1] * s), b.y + pts[0][1] * s],
          type: 'scatter', mode: 'lines', fill: 'toself', fillcolor: b.visible ? b.color : 'rgba(0,0,0,0)',
          line: { color: b.color, width: 1.5 }, hoverinfo: 'skip', showlegend: false, name: `${b.name} crescent`,
        })
      }
    }
    for (const r of dyn.rings) {
      annotations.push({ x: r.x, y: r.y, text: r.text, showarrow: false, font: { color: C.text, size: 11, family: MONO }, xanchor: 'left' })
    }
    const h = skyHeader(d, range)
    annotations.push({
      xref: 'paper', yref: 'paper', x: 0, y: 1.0, xanchor: 'left', yanchor: 'bottom', showarrow: false, align: 'left',
      text: `<b>${h.site}</b>  <span style="font-family:${MONO}">${h.time}</span><br><span style="color:${C.muted}">${h.scale}` +
        `<br>${h.orient}</span>`,
      font: { size: 12, color: C.text },
    })
  }

  const layout = {
    paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER,
    margin: { l: opts.narrow ? 8 : 20, r: opts.narrow ? 8 : 20, t: skyMarginTop(d.siteName, !!opts.narrow), b: 20 },
    xaxis: { visible: false, range: [-SKY_EXTENT, SKY_EXTENT], fixedrange: true },
    yaxis: { visible: false, range: [-SKY_EXTENT, SKY_EXTENT], scaleanchor: 'x', fixedrange: true },
    showlegend: true,
    legend: { orientation: 'h', x: 0.5, xanchor: 'center', y: -0.02, yanchor: 'top', font: { size: opts.narrow ? 10 : 11, color: C.muted } },
    annotations,
    dragmode: false,
  }
  return { data, layout, range, alt: skyAlt(d) }
}
