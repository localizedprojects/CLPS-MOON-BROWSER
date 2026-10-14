/**
 * Minimal React hook around Plotly.react (avoids react-plotly.js peer issues)
 * and the PNG export.
 *
 * A Plotly redraw of these figures costs ~0.1-0.5 s (seconds on a slow
 * phone), so the views call Plotly only when a full payload arrives; whatever
 * follows the time cursor is drawn in a DOM overlay positioned with
 * [plotAxes] (plotGeom.ts).
 */
import { useEffect, useRef } from 'react'
// @ts-expect-error - the dist bundle ships without type declarations
import Plotly from 'plotly.js-basic-dist-min'
import { post } from './bridge'
import type { PlotlyDiv } from './plotGeom'

export type { AxisPx, PlotlyDiv } from './plotGeom'
export { clickTimeMs, plotAxes } from './plotGeom'

export interface Fig {
  data: unknown[]
  layout: Record<string, unknown>
}

export interface PlotHooks<F extends Fig> {
  /** plotly_click (fires for clicks, not drags) */
  onClick?: (gd: PlotlyDiv, e: unknown) => void
  /** after every draw of [fig] (first plot, new payload, resize) */
  onAfterPlot?: (gd: PlotlyDiv, fig: F) => void
}

const CONFIG = { displayModeBar: false, scrollZoom: false }

export function usePlot<F extends Fig>(fig: F | null, hooks: PlotHooks<F> = {}) {
  const ref = useRef<PlotlyDiv | null>(null)
  const hk = useRef(hooks)
  hk.current = hooks
  /** The figure last handed to Plotly (what is on screen once it has drawn). */
  const shown = useRef<F | null>(null)
  const bound = useRef<PlotlyDiv | null>(null)
  const ro = useRef<ResizeObserver | null>(null)
  const fitRef = useRef<() => void>(() => {})
  const settleRef = useRef<() => void>(() => {})

  useEffect(() => {
    const el = ref.current
    if (!el || !fig) return
    shown.current = fig
    const done = Plotly.react(el, fig.data, { ...fig.layout, autosize: true }, CONFIG)
    if (bound.current !== el && el.on) {
      bound.current = el
      el.on('plotly_click', (e: unknown) => hk.current.onClick?.(el, e))
      el.on('plotly_afterplot', () => { if (shown.current) hk.current.onAfterPlot?.(el, shown.current) })
      // the container can change size without a window resize (Flutter layout);
      // redraw only for a real change (the observer also fires once on observe)
      let w = el.clientWidth, h = el.clientHeight
      const redraw = () => {
        w = el.clientWidth
        h = el.clientHeight
        // rejects while the div is not displayed (mid-move): the next settle redraws it
        void Promise.resolve(Plotly.Plots.resize(el)).catch(() => {})
      }
      const fit = () => {
        if (!el.isConnected || (el.clientWidth === w && el.clientHeight === h)) return
        redraw()
      }
      // the host moved this page (full screen and back): redraw at the size it has
      // now, whether or not a size change was seen (a hidden div reports none)
      const settle = () => { if (el.isConnected && el.clientWidth > 0) redraw() }
      ro.current?.disconnect()
      ro.current = new ResizeObserver(fit)
      ro.current.observe(el)
      // also on a window resize (the full-screen view's settle nudge, a rotation)
      window.removeEventListener('resize', fitRef.current)
      window.removeEventListener('ph-settle', settleRef.current)
      fitRef.current = fit
      settleRef.current = settle
      window.addEventListener('resize', fit)
      window.addEventListener('ph-settle', settle)
    }
    Promise.resolve(done).then(() => { if (shown.current === fig) hk.current.onAfterPlot?.(el, fig) }, () => {})
  }, [fig])

  useEffect(() => () => {
    ro.current?.disconnect()
    window.removeEventListener('resize', fitRef.current)
    window.removeEventListener('ph-settle', settleRef.current)
  }, [])

  return ref
}

/**
 * Render [fig] off screen at [width] x [height] to a PNG data URL and hand
 * it to the host (works whether or not the chart is on screen).
 */
export async function exportPng(fig: Fig | null, id: string, width = 1600, height = 1000, scale = 1) {
  if (!fig) {
    post({ type: 'error', message: 'export failed: no chart data yet' })
    return
  }
  try {
    const dataUrl: string = await Plotly.toImage(
      { data: fig.data, layout: { ...fig.layout, width, height, autosize: false }, config: { staticPlot: true } },
      { format: 'png', width, height, scale: Math.min(4, Math.max(1, scale)) })
    post({ type: 'png', id, dataUrl })
  } catch (e) {
    post({ type: 'error', message: `export failed: ${String(e)}` })
  }
}
