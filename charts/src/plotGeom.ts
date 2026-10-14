/**
 * Plot geometry of a drawn Plotly figure (no Plotly import, so it is unit
 * tested in node): the axes and plot box the overlays are positioned with,
 * and the time under a click.
 */

/** The parts of a Plotly axis the overlays use (pixels are relative to the plot div). */
export interface AxisPx {
  _offset: number
  _length: number
  l2p: (v: number) => number
  p2l: (px: number) => number
}

export type PlotlyDiv = HTMLDivElement & {
  on?: (ev: string, cb: (e: unknown) => void) => void
  _fullLayout?: { xaxis?: AxisPx; yaxis?: AxisPx; _size?: { l: number; r: number; t: number; b: number; w: number; h: number } }
}

/** Axes and plot-area box of a drawn figure, or null before the first draw. */
export function plotAxes(gd: Pick<PlotlyDiv, '_fullLayout'> | null | undefined):
  { xa: AxisPx; ya: AxisPx; size: { t: number; h: number; l: number; w: number } } | null {
  const fl = gd?._fullLayout
  const xa = fl?.xaxis, ya = fl?.yaxis, size = fl?._size
  if (!xa || !ya || !size || typeof xa.l2p !== 'function' || typeof ya.l2p !== 'function') return null
  return { xa, ya, size }
}

/**
 * Unix ms under a plotly_click, from the pointer position on the x axis.
 * The clicked point's own x is not used: on the availability strip it is a
 * Gantt bar, whose x is the bar's end (base + duration), not the clicked time.
 */
export function clickTimeMs(gd: Pick<PlotlyDiv, '_fullLayout' | 'getBoundingClientRect'>, e: unknown): number | null {
  const ev = (e as { event?: { clientX?: number } }).event
  const xa = gd._fullLayout?.xaxis
  if (ev && typeof ev.clientX === 'number' && xa && typeof xa.p2l === 'function') {
    const px = ev.clientX - gd.getBoundingClientRect().left - xa._offset
    const t = xa.p2l(px)
    if (Number.isFinite(t) && px >= 0 && px <= xa._length) return t
  }
  // fallback: a line trace's own sample time ('YYYY-MM-DD HH:MM:SS', UTC); never a bar's end
  const p = (e as { points?: { x?: unknown; data?: { type?: string } }[] }).points?.find((q) => q.data?.type !== 'bar')
  if (typeof p?.x === 'string') {
    const t = Date.parse(p.x.replace(' ', 'T') + 'Z')
    if (Number.isFinite(t)) return t
  }
  return null
}
