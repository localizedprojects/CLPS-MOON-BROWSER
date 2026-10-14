/**
 * CLASSIC sky plot overlay (skyClassic.ts). The part of the sky plot that follows the time cursor (Sun and Earth
 * markers, their labels, the ring labels and the header), drawn as a light
 * SVG + HTML overlay on top of the Plotly figure. Moving the cursor only
 * rewrites this overlay (well under a millisecond), never the Plotly figure,
 * whose redraw costs 0.1-0.5 s (seconds on a slow phone).
 *
 * The geometry and label placement come from [skyDynamic] in sky.ts, which
 * the complete figure used for PNG export also uses, so both always agree.
 */
import type { SkyData } from './bridge'
import type { ElRange, SkyDynamic, BodyDyn } from './skyClassic'
import { crescentPoints, EARTH_DISC_FILL, labelBox, LABEL_FONT_PX, MARKER_R, skyDynamic, skyHeader } from './skyClassic'
import type { PlotlyDiv } from './plotGeom'
import { plotAxes } from './plotGeom'
import { C, MONO, SANS } from './theme'

/** Where the plot is inside its div, px: centre (cx, cy, y down) and px per plot unit [k]. */
export interface SkyGeom {
  cx: number
  cy: number
  k: number
  /** left edge of the plot area (the header starts there) */
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

function bodySvg(b: BodyDyn, g: SkyGeom): string {
  const x = g.cx + b.x * g.k, y = g.cy - b.y * g.k
  // filled = counted as up, open = not counted (terrain, a stricter rule or no DSN; the
  // <title> says which). Shape encodes the state, not just colour. Sun = plain disc,
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
    `<text x="${n(tx)}" y="${n(ty)}" text-anchor="middle" dominant-baseline="central" font-family="${esc(MONO)}" ` +
    `font-size="${LABEL_FONT_PX}" fill="${C.text}" stroke="${C.bg}" stroke-width="3" paint-order="stroke">${esc(b.text)}</text></g>`
}

/** The overlay's SVG markup (everything that follows the cursor except the header). */
export function skyOverlaySvg(dyn: SkyDynamic, g: SkyGeom): string {
  const rings = dyn.rings.map((r) =>
    `<text x="${n(g.cx + r.x * g.k)}" y="${n(g.cy - r.y * g.k)}" dominant-baseline="central" font-family="${esc(MONO)}" font-size="11" ` +
    `fill="${C.text}" stroke="${C.bg}" stroke-width="3" paint-order="stroke">${esc(r.text)}</text>`).join('')
  return `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" style="position:absolute;inset:0;overflow:visible" aria-hidden="true">` +
    `<g data-rings="${dyn.ringAz}">${rings}</g>${bodySvg(dyn.sun, g)}${bodySvg(dyn.earth, g)}</svg>`
}

/** The header lines (site and time, then the radius scale and orientation), as HTML. */
export function skyHeaderHtml(d: Pick<SkyData, 'siteName' | 'timeLabel' | 'zoom'>, range: ElRange, g: SkyGeom): string {
  const h = skyHeader(d, range)
  // the site name in full: the first line wraps between the name and the
  // time (never an ellipsis), and the time keeps its year (yyyy-MM-dd)
  return `<div data-header style="position:absolute;left:${n(g.left)}px;top:4px;right:8px;font:12px/1.3 ${esc(SANS)};color:${C.text}" aria-hidden="true">` +
    `<div style="display:flex;flex-wrap:wrap;column-gap:8px"><b data-site style="font-weight:600;overflow-wrap:anywhere">${esc(h.site)}</b>` +
    `<span data-time style="font-family:${esc(MONO)};white-space:nowrap">${esc(h.time)}</span></div>` +
    `<div style="color:${C.muted}">${esc(h.scale)}</div><div style="color:${C.muted}">${esc(h.orient)}</div></div>`
}

/**
 * Redraw the overlay in [el] for the bodies' positions [now] at [timeLabel].
 * Returns false (and draws nothing) when the figure has not been drawn yet.
 */
export function drawSkyOverlay(el: HTMLElement | null, gd: PlotlyDiv | null, d: SkyData, range: ElRange): boolean {
  const g = skyGeom(gd)
  if (!el || !g) return false
  const dyn = skyDynamic(d.now, range, g.k)
  el.innerHTML = skyOverlaySvg(dyn, g) + skyHeaderHtml(d, range, g)
  return true
}
