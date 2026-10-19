/**
 * The part of the sky plot that follows the time cursor (Sun and Earth
 * markers, their word labels, the ring labels and the path names), drawn as
 * a light SVG overlay on top of the Plotly figure. A `skyNow` only rewrites
 * this overlay (well under a millisecond) and the view's text, never the
 * Plotly figure, whose redraw costs 0.1-0.5 s (seconds on a slow phone).
 *
 * The geometry and label placement come from [skyDynamic] in sky.ts, which
 * the complete figure used for PNG export also uses, so both always agree.
 */
import type { SkyData } from './bridge'
import type { ElRange, SkyDynamic, BodyDyn, DynOptions } from './sky'
import { crescentPoints, EARTH_DISC_FILL, labelBox, LABEL_FONT_PX, MARKER_R, skyDynamic } from './sky'
import type { PlotlyDiv } from './plotGeom'
import { plotAxes } from './plotGeom'
import { C, MONO, SANS } from './theme'

/** Where the plot is inside its div, px: centre (cx, cy, y down) and px per plot unit [k]. */
export interface SkyGeom {
  cx: number
  cy: number
  k: number
  /** left edge of the plot area */
  left: number
}

/** Geometry of a drawn sky figure, or null before Plotly has drawn it. */
export function skyGeom(gd: PlotlyDiv | null): SkyGeom | null {
  const a = plotAxes(gd)
  if (!a) return null
  const x0 = a.xa.l2p(0), x1 = a.xa.l2p(1), y0 = a.ya.l2p(0)
  const k = x1 - x0
  if (!Number.isFinite(k) || k <= 0 || !Number.isFinite(y0)) return null
  return { cx: a.xa._offset + x0, cy: a.ya._offset + y0, k, left: a.size.l }
}

export function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

const n = (v: number) => (Math.round(v * 10) / 10).toString()

/** Marker radius (= Plotly marker size 18) and halo radius. */
const R = MARKER_R, HALO = 14

/** Earth's crescent as an SVG path at (x, y) px, radius [r] (y down). */
export function crescentPath(x: number, y: number, r: number): string {
  return crescentPoints().map(([px, py], i) => `${i ? 'L' : 'M'}${n(x + px * r)},${n(y - py * r)}`).join('') + 'Z'
}

/**
 * A small body glyph for the caption lines (aria-hidden: the state is in
 * words too). Filled = counted as up, open = not; Sun = disc, Earth = disc
 * with a crescent.
 */
export function bodyGlyphSvg(name: 'Sun' | 'Earth', counted: boolean, size = 16): string {
  const c = name === 'Sun' ? C.sun : C.earth
  const body = name === 'Sun'
    ? `<circle cx="8" cy="8" r="5.5" fill="${counted ? c : 'none'}" stroke="${c}" stroke-width="2"/>`
    : `<circle cx="8" cy="8" r="5.5" fill="${counted ? EARTH_DISC_FILL : 'none'}" stroke="${c}" stroke-width="2"/>` +
      `<path d="${crescentPath(8, 8, 4.5)}" fill="${counted ? c : 'none'}" stroke="${c}" stroke-width="1"/>`
  return `<svg width="${size}" height="${size}" viewBox="0 0 16 16" aria-hidden="true" focusable="false">${body}</svg>`
}

function bodySvg(b: BodyDyn, g: SkyGeom): string {
  const x = g.cx + b.x * g.k, y = g.cy - b.y * g.k
  // filled = counted as up, open = not counted (the label and <title> say why).
  // Shape encodes the state, not just colour. Sun = plain disc,
  // Earth = disc with a crescent (the app's Earth glyph), never the "both" diamond.
  const fill = b.visible ? b.color : 'none'
  const shape = b.symbol === 'circle'
    ? `<circle cx="${n(x)}" cy="${n(y)}" r="${R}"/>`
    : `<circle cx="${n(x)}" cy="${n(y)}" r="${R}" fill="${b.visible ? EARTH_DISC_FILL : 'none'}"/>` +
      `<path data-crescent d="${crescentPath(x, y, R - 1.5)}" stroke-width="1.5"/>`
  const box = labelBox(b.x * g.k, b.y * g.k, b.text.length, b.pos)
  const tx = g.cx + (box.x0 + box.x1) / 2, ty = g.cy - (box.y0 + box.y1) / 2
  return `<g data-body="${b.name}" style="pointer-events:visiblePainted">` +
    `<title>${esc(b.title)}</title>` +
    `<circle cx="${n(x)}" cy="${n(y)}" r="${HALO}" fill="${C.halo}"/>` +
    `<g fill="${fill}" stroke="${b.color}" stroke-width="2.5">${shape}</g>` +
    `<text data-label x="${n(tx)}" y="${n(ty)}" text-anchor="middle" dominant-baseline="central" font-family="${esc(SANS)}" ` +
    `font-size="${LABEL_FONT_PX}" fill="${C.text}" stroke="${C.bg}" stroke-width="3" paint-order="stroke">${esc(b.text)}</text></g>`
}

/** The overlay's SVG markup: ring labels, path names, markers and their labels. */
export function skyOverlaySvg(dyn: SkyDynamic, g: SkyGeom): string {
  const rings = dyn.rings.map((r) =>
    `<text x="${n(g.cx + r.x * g.k)}" y="${n(g.cy - r.y * g.k)}" dominant-baseline="central" font-family="${esc(MONO)}" font-size="11" ` +
    `fill="${C.text}" stroke="${C.bg}" stroke-width="3" paint-order="stroke">${esc(r.text)}</text>`).join('')
  // path names on the path, with a navy halo stroke
  const paths = dyn.paths.map((p) =>
    `<text data-path x="${n(g.cx + p.x * g.k)}" y="${n(g.cy - p.y * g.k)}" text-anchor="middle" dominant-baseline="central" ` +
    `font-family="${esc(SANS)}" font-size="12" fill="${p.color}" stroke="${C.bg}" stroke-width="4" paint-order="stroke">${esc(p.text)}</text>`).join('')
  return `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" style="position:absolute;top:0;right:0;bottom:0;left:0;overflow:visible" aria-hidden="true">` +
    `<g data-rings="${dyn.ringAz}">${rings}</g><g data-paths>${paths}</g>${bodySvg(dyn.sun, g)}${bodySvg(dyn.earth, g)}</svg>`
}

/**
 * Redraw the overlay in [el] for the bodies' positions in [d].
 * Returns false (and draws nothing) when the figure has not been drawn yet.
 */
export function drawSkyOverlay(el: HTMLElement | null, gd: PlotlyDiv | null, d: SkyData, range: ElRange,
  o: Omit<DynOptions, 'd'> = {}): boolean {
  const g = skyGeom(gd)
  if (!el || !g) return false
  el.innerHTML = skyOverlaySvg(skyDynamic(d.now, range, g.k, { ...o, d }), g)
  return true
}
