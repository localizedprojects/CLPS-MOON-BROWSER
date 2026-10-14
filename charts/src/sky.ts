/**
 * Sky polar plot geometry ("Where to look", charts spec 2.2): azimuth
 * clockwise from north at the top, radius = elevation mapped linearly from
 * the top of the displayed range (centre) to the bottom (outer ring).
 * "Horizon zoom" stretches the few degrees around the horizon where polar
 * Sun/Earth actually move; the key line always states the stretch.
 *
 * Simple view (default): the grey hills labelled "hills", the dashed flat
 * horizon with "0°", N/E/S/W, the two bodies with word labels and, behind a
 * toggle, the faint period paths named on the path. Exact numbers adds the
 * degree rings and labels, the 30° spokes and the legend (paths on).
 *
 * The figure has a static part (rings, terrain, paths: drawn by Plotly once
 * per payload / mode) and a dynamic part that follows the time cursor (the
 * markers, their labels, the ring labels and the path names). The live view
 * draws the dynamic part in a light SVG overlay (skyOverlay.ts), so a
 * `skyNow` never re-renders the Plotly figure; [buildSky] with `live: false`
 * puts the same dynamic part, the header, captions, key line and Exact block
 * into one figure (PNG export). Both use [skyDynamic], so the two agree.
 */
import type { BodyNow, SkyData } from './bridge'
import { C, FONT, HOVER, MONO, SANS } from './theme'
import {
  captionLine, exactLine, headerTime, highestHills, highestHillsText, hillsText, keyLine, legendNames, markerLabel, pctShowing,
} from './skyCaption'
import type { CaptionLine } from './skyCaption'

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

/** The plotted elevation range of a payload. */
export const skyRange = (d: Pick<SkyData, 'zoom' | 'mask' | 'trails'>): ElRange =>
  d.zoom ? zoomRange(d.mask, d.trails.sun.el, d.trails.earth.el) : FULL_RANGE

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

/** The labelled rings: every other one when there are many (at most 6 labels). */
export function labelledRings(r: ElRange): number[] {
  const rings = ringValues(r)
  return rings.filter((_, i) => rings.length <= 6 || i % 2 === 0)
}

// ---------------------------------------------------------------------------
// Dynamic part: where the bodies, their labels, the ring labels and the path names go.

function angDist(a: number, b: number): number {
  const d = Math.abs((((a - b) % 360) + 360) % 360)
  return Math.min(d, 360 - d)
}

/**
 * Azimuth of the diagonal (45, 135, 225 or 315°) for the ring labels: at
 * least 45° from both bodies (some diagonal always is), and among those the
 * one farthest from [avoidAz] too (the "hills" label).
 */
export function ringLabelAz(sunAz: number, earthAz: number, avoidAz?: number): number {
  let best = 45, bestD = -1
  for (const a of [45, 135, 225, 315]) {
    const body = Math.min(angDist(a, sunAz), angDist(a, earthAz))
    const d = avoidAz == null || body < 45 - 1e-9 ? body : 1000 + Math.min(body, angDist(a, avoidAz))
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
/** Generous advance width for 12 px Plex Sans labels (boxes err on the large side). */
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

export function overlapArea(a: Box, b: Box): number {
  const w = Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0)
  const h = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0)
  return w > 0 && h > 0 ? w * h : 0
}

/** Gap between two boxes, px (0 when they touch or overlap). */
function boxGap(a: Box, b: Box): number {
  const dx = Math.max(0, a.x0 - b.x1, b.x0 - a.x1)
  const dy = Math.max(0, a.y0 - b.y1, b.y0 - a.y1)
  return Math.hypot(dx, dy)
}

/** Area of [a] outside [frame]. */
function outside(a: Box, frame: Box): number {
  const area = (a.x1 - a.x0) * (a.y1 - a.y0)
  return area - overlapArea(a, frame)
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
 * markers, the [obstacles] (ring, compass and hills labels) and the edge of
 * the plot ([frame]). Tries every pair of positions; the cost is the
 * overlapping area in px² (weighted well above the preference) plus a small
 * preference for 'top center'.
 */
export function placeBodyLabels(bodies: BodyMark[], obstacles: Box[], frame: Box): LabelPos[] {
  const halo = (b: BodyMark): Box => ({ x0: b.x - HALO_R, x1: b.x + HALO_R, y0: b.y - HALO_R, y1: b.y + HALO_R })
  const halos = bodies.map(halo)
  const single = (i: number, p: LabelPos): number => {
    const box = labelBox(bodies[i].x, bodies[i].y, bodies[i].text.length, p)
    let c = PREF[p] + 2 * OVERLAP_COST * outside(box, frame)
    for (const o of obstacles) c += OVERLAP_COST * overlapArea(box, o)
    halos.forEach((h, j) => { if (j !== i) c += 2 * OVERLAP_COST * overlapArea(box, h) })
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
      const c = c0.get(p)! + c1.get(q)! + 2 * OVERLAP_COST * overlapArea(b0, b1)
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
  /** plain-word label ("Sun · up"), never a signed number */
  text: string
  pos: LabelPos
  visible: boolean
  /** hover / tooltip text with the exact values */
  title: string
  b: BodyNow
}

/** A path name drawn on the path ("Sun's path"), plot units, centred. */
export interface PathLabel {
  x: number
  y: number
  text: string
  color: string
}

export interface SkyDynamic {
  sun: BodyDyn
  earth: BodyDyn
  rings: RingLabel[]
  ringAz: number
  /** path names (Simple view with paths on); empty otherwise */
  paths: PathLabel[]
}

/**
 * The body's state in words, from the flags Dart sent (fallback for a
 * payload without Dart's `say` sentence).
 */
export function stateText(b: BodyNow, hidden = 'below terrain horizon'): string {
  if (b.visible) return b.frac < 0.999 ? `partly visible (${Math.min(99, pctShowing(b.frac))}%)` : 'visible'
  if (b.terrainVisible) return 'in view, but no DSN station can see the Moon'
  if (b.frac > 0) return `${Math.min(99, pctShowing(b.frac))}% above the skyline, not counted under the current rule`
  return hidden
}

/** Dart's sentence when sent, else [stateText]. */
export const sayOf = (b: BodyNow, hidden?: string) => b.say ?? stateText(b, hidden)

/** Index of the highest point of the mask. */
function maskTop(mask: number[]): number {
  let iMax = 0
  for (let i = 1; i < mask.length; i++) if (mask[i] > mask[iMax]) iMax = i
  return iMax
}

/** Where the "hills" label sits, plot units: halfway between the highest point of the silhouette and the outer ring. */
export function hillsLabelXY(d: Pick<SkyData, 'mask' | 'maskStepDeg'>, range: ElRange): [number, number] {
  const i = maskTop(d.mask)
  const rr = (elToR(d.mask[i], range) + 1) / 2, a = (i * d.maskStepDeg * Math.PI) / 180
  return [rr * Math.sin(a), rr * Math.cos(a)]
}

/** px box of a centred text of [chars] characters at (x, y) px. */
function centredBox(x: number, y: number, chars: number, charPx: number, h = 16): Box {
  const w = chars * charPx + 4
  return { x0: x - w / 2, x1: x + w / 2, y0: y - h / 2, y1: y + h / 2 }
}

/** Azimuth label texts, by azimuth (Exact: every 30°; Simple: N/E/S/W). */
function azLabels(exact: boolean): [number, string][] {
  const names: Record<number, string> = { 0: 'N', 90: 'E', 180: 'S', 270: 'W' }
  const out: [number, string][] = []
  for (let a = 0; a < 360; a += exact ? 30 : 90) out.push([a, names[a] ?? `${a}°`])
  return out
}

/** Path-name advance width, px (12 px Plex Sans, generous). */
const PATH_CHAR_PX = 7

/**
 * Name each period path on the path ("Sun's path", "Earth's path"): at the
 * point whose label box is farthest from every [obstacle] (markers, their
 * labels, the hills label, the compass letters, ring labels) and the other
 * name, and fully inside the plot. Overlapping candidates are never used;
 * a path with no free spot is left unnamed. Plot units out, px inside.
 */
export function pathLabels(trails: SkyData['trails'], range: ElRange, rPx: number, obstacles: Box[]): PathLabel[] {
  const k = Math.max(rPx, 1)
  const avoid = [...obstacles]
  const out: PathLabel[] = []
  const pick = (az: number[], el: number[], text: string, color: string) => {
    let best: [number, number] | null = null, bestD = -1
    const step = Math.max(1, Math.floor(az.length / 400))
    for (let i = 0; i < az.length; i += step) {
      const [x, y] = toXY(az[i], el[i], range)
      const b = centredBox(x * k, y * k, text.length, PATH_CHAR_PX)
      // inside the outer ring (all four corners)
      if (Math.hypot(Math.max(Math.abs(b.x0), Math.abs(b.x1)), Math.max(Math.abs(b.y0), Math.abs(b.y1))) > 0.98 * k) continue
      let dmin = Infinity
      for (const o of avoid) dmin = Math.min(dmin, boxGap(b, o))
      if (dmin <= 2) continue
      if (dmin > bestD) { bestD = dmin; best = [x, y] }
    }
    if (!best) return
    out.push({ x: best[0], y: best[1], text, color })
    avoid.push(centredBox(best[0] * k, best[1] * k, text.length, PATH_CHAR_PX))
  }
  pick(trails.sun.az, trails.sun.el, "Sun's path", C.sun)
  pick(trails.earth.az, trails.earth.el, "Earth's path", C.earth)
  return out
}

export interface DynOptions {
  /** Exact numbers: all ring labels and every 30° compass label */
  exact?: boolean
  /** name the paths on the plot (Simple view with paths on) */
  paths?: boolean
  /** the payload fields the hills label and the path names need */
  d?: Pick<SkyData, 'mask' | 'maskStepDeg' | 'maskApprox' | 'trails'>
}

/**
 * Everything that follows the cursor, in plot units. [rPx] is the radius of
 * the outer ring in screen px (label sizes are in px).
 */
export function skyDynamic(now: { sun: BodyNow; earth: BodyNow }, range: ElRange, rPx: number, o: DynOptions = {}): SkyDynamic {
  const exact = !!o.exact
  const k = Math.max(rPx, 1)
  const obstacles: Box[] = []
  let hillsAz: number | undefined
  if (o.d && o.d.mask.length) {
    hillsAz = maskTop(o.d.mask) * o.d.maskStepDeg
    const [hx, hy] = hillsLabelXY(o.d, range)
    obstacles.push(centredBox(hx * k, hy * k, hillsText(o.d.maskApprox).length, 7.4, 18))
  }
  const ringAz = ringLabelAz(now.sun.az, now.earth.az, hillsAz)
  // Simple: only the flat horizon ("0°", when it is inside the range); Exact: up to 6 ring labels
  const ringVals = exact ? labelledRings(range) : range.lo <= 0 && range.hi >= 0 ? [0] : []
  const rings: RingLabel[] = ringVals.map((v) => {
    const [x, y] = toXY(ringAz, v, range)
    return { value: v, text: `${v < 0 ? "−" : ""}${Math.abs(v)}°`, x, y }
  })
  // ring labels are drawn left-anchored at their point (11 px Mono)
  for (const r of rings) obstacles.push({ x0: r.x * k, x1: r.x * k + r.text.length * 6.6 + 2, y0: r.y * k - 7, y1: r.y * k + 7 })
  // azimuth labels at r = 1.09 (centred)
  for (const [a, t] of azLabels(exact)) {
    const cx = AZ_LABEL_R * Math.sin((a * Math.PI) / 180) * k, cy = AZ_LABEL_R * Math.cos((a * Math.PI) / 180) * k
    const w = t.length * 6.8 + 2
    obstacles.push({ x0: cx - w / 2, x1: cx + w / 2, y0: cy - 8, y1: cy + 8 })
  }
  const frame: Box = { x0: -SKY_EXTENT * k, x1: SKY_EXTENT * k, y0: -SKY_EXTENT * k, y1: SKY_EXTENT * k }
  const mk = (b: BodyNow, name: 'Sun' | 'Earth') => {
    const [x, y] = toXY(b.az, b.el, range)
    return { x, y, text: markerLabel(name, b) }
  }
  const s = mk(now.sun, 'Sun'), e = mk(now.earth, 'Earth')
  const [ps, pe] = placeBodyLabels([{ x: s.x * k, y: s.y * k, text: s.text }, { x: e.x * k, y: e.y * k, text: e.text }], obstacles, frame)
  const body = (b: BodyNow, m: { x: number; y: number; text: string }, name: 'Sun' | 'Earth', pos: LabelPos): BodyDyn => ({
    name, color: name === 'Sun' ? C.sun : C.earth, symbol: name === 'Sun' ? 'circle' : 'crescent',
    x: m.x, y: m.y, text: m.text, pos, visible: b.visible, b,
    title: `${name}: azimuth ${b.az.toFixed(2)}°, elevation ${b.el.toFixed(2)}°, terrain horizon ${b.hz.toFixed(2)}°, ` +
      `clearance ${(b.el - b.hz).toFixed(2)}°, disc radius ${b.rho.toFixed(2)}°, ${pctShowing(b.frac)}% showing. ${sayOf(b)}`,
  })
  const sun = body(now.sun, s, 'Sun', ps), earth = body(now.earth, e, 'Earth', pe)
  let paths: PathLabel[] = []
  if (o.paths && !exact && o.d) {
    const avoid = [...obstacles]
    for (const bd of [sun, earth]) {
      avoid.push({ x0: bd.x * k - HALO_R, x1: bd.x * k + HALO_R, y0: bd.y * k - HALO_R, y1: bd.y * k + HALO_R })
      avoid.push(labelBox(bd.x * k, bd.y * k, bd.text.length, bd.pos))
    }
    paths = pathLabels(o.d.trails, range, k, avoid)
  }
  return { sun, earth, rings, ringAz, paths }
}

/** Header: "Where to look · <site> · <time> UTC" (the time in Mono, from Dart's label, always with the year). */
export function skyHeader(d: Pick<SkyData, 'siteName' | 'timeLabel'>): { title: string; site: string; time: string } {
  return { title: 'Where to look', site: d.siteName, time: `${headerTime(d.timeLabel)} UTC` }
}

/** Alt text (aria-label): unchanged content; uses Dart's sentence when sent. */
export function skyAlt(d: Pick<SkyData, 'siteName' | 'timeLabel' | 'mask' | 'now'>): string {
  const st = (b: BodyNow) => sayOf(b, 'hidden by terrain')
  const hmax = highestHills(d.mask)
  return `Sky plot for ${d.siteName} at ${d.timeLabel}. Sun at azimuth ${d.now.sun.az.toFixed(0)} degrees, elevation ` +
    `${d.now.sun.el.toFixed(1)} degrees, ${st(d.now.sun)}. Earth at azimuth ${d.now.earth.az.toFixed(0)} degrees, elevation ` +
    `${d.now.earth.el.toFixed(1)} degrees, ${st(d.now.earth)}. Highest terrain horizon ${hmax.toFixed(1)} degrees.`
}

// ---------------------------------------------------------------------------

// Plotly types are loose; keep these as plain objects.
type Trace = Record<string, unknown>

export interface SkyOptions {
  /**
   * Live view: leave out the dynamic part (markers, body, ring and path
   * labels) and all text around the plot, which the view draws. Default
   * false (complete figure for the PNG export).
   */
  live?: boolean
  /** Exact numbers: degree rings with labels, 30° spokes with labels, legend (export), paths on. */
  exact?: boolean
  /** Draw the period paths (Simple view toggle; always on in Exact and in the export). */
  paths?: boolean
  /** Outer-ring radius in px used to place labels in a complete figure (export). */
  rPx?: number
}

/** Export layout (1600 x 1000 by default): plot on the left half, text on the right. */
const EXPORT_MARGIN = { l: 40, r: 40, t: 96, b: 40 }
const EXPORT_PLOT_W = 0.5
/** Characters per line of the export's text column. */
const EXPORT_WRAP = 70

/** Greedy word wrap for the export's text (Plotly annotations do not wrap). */
export function wrapText(s: string, max = EXPORT_WRAP, sep: RegExp = / /): string[] {
  const out: string[] = []
  let line = ''
  for (const w of s.split(sep)) {
    if (w.length > max) {
      // a unit longer than a line (a long sentence): wrap it by words
      if (line) out.push(line)
      const words = wrapText(w, max)
      line = words.pop() ?? ''
      out.push(...words)
      continue
    }
    if (line && line.length + 1 + w.length > max) {
      out.push(line)
      line = w
    } else line = line ? `${line} ${w}` : w
  }
  if (line) out.push(line)
  return out
}

/** Outer-ring radius in px of the exported figure at [w] x [h]. */
export function exportRPx(w = 1600, h = 1000): number {
  const side = Math.min((w - EXPORT_MARGIN.l - EXPORT_MARGIN.r) * EXPORT_PLOT_W, h - EXPORT_MARGIN.t - EXPORT_MARGIN.b)
  return side / 2 / SKY_EXTENT
}

const escHtml = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

function captionHtml(l: CaptionLine): string {
  const color = l.name === 'Sun' ? C.sun : C.earth
  return `<span style="color:${color}">${l.counted ? '●' : '○'}</span> <b>${escHtml(l.head)}</b> · ${escHtml(l.rest.join(' · '))}`
}

export function buildSky(d: SkyData, opts: SkyOptions = {}): { data: Trace[]; layout: Record<string, unknown>; range: ElRange; alt: string } {
  const range = skyRange(d)
  const exact = !!opts.exact
  const live = !!opts.live
  // paths: the toggle in the live Simple view; always on in Exact and in the export
  const paths = exact || !live || !!opts.paths
  const names = legendNames(d.maskApprox)
  const data: Trace[] = []

  // elevation rings (Simple: only the dashed flat horizon, 0°)
  for (const v of ringValues(range).filter((v) => exact || v === 0)) {
    const c = circle(elToR(v, range))
    data.push({ ...c, type: 'scatter', mode: 'lines', hoverinfo: 'skip', showlegend: false,
      line: { color: v === 0 ? C.gridStrong : C.grid, width: v === 0 ? 1.5 : 1, dash: v === 0 ? 'dash' : 'dot' } })
  }
  // azimuth spokes (Exact only)
  if (exact) {
    for (let a = 0; a < 360; a += 30) {
      const [x, y] = toXY(a, range.lo, range)
      data.push({ x: [0, x], y: [0, y], type: 'scatter', mode: 'lines', hoverinfo: 'skip', showlegend: false,
        line: { color: C.grid, width: 1 } })
    }
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
    line: { color: C.terrainEdge, width: 1.2 }, name: names.hills, hoverinfo: 'skip',
  })

  // paths over the period: one polyline each; solid Sun, dotted Earth (not colour alone)
  if (paths) {
    const trail = (az: number[], el: number[], color: string, name: string, dash: string) => {
      const x: number[] = [], y: number[] = []
      az.forEach((a, i) => { const p = toXY(a, el[i], range); x.push(p[0]); y.push(p[1]) })
      data.push({ x, y, type: 'scatter', mode: 'lines', name, line: { color, width: exact ? 1.2 : 1, dash },
        opacity: exact ? 0.6 : 0.32, hoverinfo: 'skip' })
    }
    trail(d.trails.sun.az, d.trails.sun.el, C.sun, names.sun, 'solid')
    trail(d.trails.earth.az, d.trails.earth.el, C.earth, names.earth, 'dot')
  }

  // compass labels (Exact: every 30°) and the "hills" label at the highest point
  const annotations: Record<string, unknown>[] = []
  for (const [a, t] of azLabels(exact)) {
    const [x, y] = toXY(a, range.lo, range)
    const cardinal = !t.endsWith('°')
    annotations.push({ x: x * AZ_LABEL_R, y: y * AZ_LABEL_R, text: t, showarrow: false,
      font: { color: cardinal ? C.text : C.muted, size: cardinal ? 13 : 11, family: cardinal ? SANS : MONO } })
  }
  if (d.mask.length) {
    const [hx, hy] = hillsLabelXY(d, range)
    annotations.push({ x: hx, y: hy, text: hillsText(d.maskApprox), showarrow: false, font: { size: 13, color: C.text, family: SANS } })
  }

  if (!live) {
    // complete figure (PNG export): the dynamic part, header, captions, key line and Exact block
    const k = Math.max(opts.rPx ?? exportRPx(), 1)
    const dyn = skyDynamic(d.now, range, k, { exact, paths: true, d })
    for (const b of [dyn.sun, dyn.earth]) {
      // dark halo so the marker keeps >= 3:1 contrast on the grey terrain fill (WCAG 1.4.11)
      data.push({ x: [b.x], y: [b.y], type: 'scatter', mode: 'markers', hoverinfo: 'skip', showlegend: false,
        marker: { size: 28, color: C.halo } })
      // filled = counted as up, open = not counted. Shape encodes the state, not just colour.
      data.push({
        x: [b.x], y: [b.y], type: 'scatter', mode: 'text+markers', name: `${b.name} now`, showlegend: false,
        text: [b.text], textposition: b.pos, textfont: { color: C.text, size: LABEL_FONT_PX, family: SANS },
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
    for (const p of dyn.paths) {
      annotations.push({ x: p.x, y: p.y, text: p.text, showarrow: false, font: { size: 12, color: p.color, family: SANS }, bgcolor: C.halo })
    }
    const h = skyHeader(d)
    annotations.push({
      xref: 'paper', yref: 'paper', x: 0, y: 1, yshift: 48, xanchor: 'left', yanchor: 'bottom', showarrow: false, align: 'left',
      text: `<b>${escHtml(h.title)}</b> · ${escHtml(h.site)} · <span style="font-family:${MONO}">${escHtml(h.time)}</span>`,
      font: { size: 22, color: C.text, family: SANS },
    })
    const lines: string[] = [captionHtml(captionLine('Sun', d.now.sun)), captionHtml(captionLine('Earth', d.now.earth)), '']
    // the key breaks between sentences, so "Heights stretched: edge −9°, centre 8°." stays on one line
    for (const l of wrapText(keyLine(d, range), EXPORT_WRAP, /(?<=\.) /)) lines.push(`<span style="color:${C.muted}">${escHtml(l)}</span>`)
    if (exact) {
      lines.push('')
      for (const [name, b] of [['Sun', d.now.sun], ['Earth', d.now.earth]] as const) {
        for (const l of wrapText(exactLine(name, b))) lines.push(`<span style="font-family:${MONO}">${escHtml(l)}</span>`)
        if (b.say) lines.push(`<span style="color:${C.muted}">${escHtml(b.say)}</span>`)
      }
      lines.push(`<span style="font-family:${MONO}">${escHtml(highestHillsText(d.mask))}</span>`)
    }
    annotations.push({
      xref: 'paper', yref: 'paper', x: EXPORT_PLOT_W + 0.04, y: 1, xanchor: 'left', yanchor: 'top', showarrow: false, align: 'left',
      text: lines.join('<br>'), font: { size: 17, color: C.text, family: SANS },
    })
  }

  const layout = {
    paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER,
    margin: live ? { l: 4, r: 4, t: 4, b: 4 } : EXPORT_MARGIN,
    xaxis: { visible: false, range: [-SKY_EXTENT, SKY_EXTENT], fixedrange: true, ...(live ? {} : { domain: [0, EXPORT_PLOT_W] }) },
    yaxis: { visible: false, range: [-SKY_EXTENT, SKY_EXTENT], scaleanchor: 'x', fixedrange: true },
    // the live view lists the legend in HTML under the plot; the Exact export carries it in the figure
    showlegend: !live && exact,
    legend: { orientation: 'v', x: EXPORT_PLOT_W + 0.04, xanchor: 'left', y: 0, yanchor: 'bottom', font: { size: 16, color: C.muted } },
    annotations,
    dragmode: false,
  }
  return { data, layout, range, alt: skyAlt(d) }
}
