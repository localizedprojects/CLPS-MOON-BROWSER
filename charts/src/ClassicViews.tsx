/**
 * The CLASSIC sky plot and timeline: the default on Site > Sky & time,
 * restored from before M6 step 3 (df457e3) at the user's request
 * (2026-10-12). The host's `{type:'simple', on:true}` swaps in the simple
 * views (SkyView.tsx "Where to look", TimelineView.tsx "When"); see views.tsx.
 *
 * Each draws its Plotly figure only when a full payload arrives (or the width
 * class changes). What follows the time cursor is cheap: the sky plot's
 * markers, labels and header live in an SVG overlay (skyClassicOverlay.ts)
 * and the timeline's cursor is a DOM line, both moved at most once per
 * animation frame with the newest message, so scrubbing and Play never queue
 * Plotly redraws.
 *
 * A cursor message that arrives before the figure exists (the host replays
 * its buffer as soon as the page reports ready) is kept and applied after
 * the first draw; the newer of payload and cursor message always wins.
 *
 * Keyboard: each chart is one focus stop (role img, its alt text as the
 * label), so the chart keyboard hand-off (focusHandoff.ts) has a stop to
 * land on; on the timeline the left and right arrow keys move the time to
 * the previous or next change.
 */
import { useMemo, useRef } from 'react'
import { post } from './bridge'
import { skyNowData, timelineCursor } from './cursor'
import { buildSky, skyAlt, SKY_EXTENT, SKY_MARGIN_TOP } from './skyClassic'
import { drawSkyOverlay } from './skyClassicOverlay'
import { buildTimeline } from './timelineClassic'
import { stepBoundary } from './timelineAnswer'
import { clickTimeMs, plotAxes, usePlot } from './usePlot'
import { C } from './theme'
import { box, useExport, useFocusView, useHost, useLatest, useNarrow, Waiting } from './viewHooks'

export function ClassicSkyView() {
  const m = useHost('sky')
  const narrow = useNarrow(480)
  // static part only (rings, terrain, paths); the overlay draws the rest
  const fig = useMemo(() => (m ? buildSky(m.data, { live: true, narrow }) : null), [m, narrow])
  const wrap = useRef<HTMLDivElement | null>(null)
  const overlay = useRef<HTMLDivElement | null>(null)
  const state = useRef({ m, fig })
  state.current = { m, fig }

  const draw = () => {
    const { m, fig } = state.current
    if (!m || !fig) return
    const d = skyNowData(m, nowMsg.current)
    if (drawSkyOverlay(overlay.current, ref.current, d, fig.range)) wrap.current?.setAttribute('aria-label', skyAlt(d))
  }
  const nowMsg = useLatest('skyNow', draw)
  const ref = usePlot(fig, { onAfterPlot: draw })

  useExport((w, h) => {
    const { m } = state.current
    if (!m) return null
    // complete figure (markers, labels, header inside the figure) at the export size
    // (a 1600 x 1000 file, or the phone-sized full-screen picture)
    const rPx = Math.max(60, Math.min(w - 40, h - SKY_MARGIN_TOP - 70)) / 2 / SKY_EXTENT
    return buildSky(skyNowData(m, nowMsg.current), { rPx, narrow: w < 480 })
  })

  if (!m) return <Waiting what="sky data" />
  return (
    <div ref={wrap} data-classic="sky" style={{ ...box, position: 'relative' }} role="img" tabIndex={0}
      aria-label={skyAlt(skyNowData(m, nowMsg.current))}>
      <div ref={ref} style={box} />
      <div ref={overlay} style={{ position: 'absolute', inset: 0, pointerEvents: 'none', overflow: 'hidden' }} />
    </div>
  )
}

export function ClassicTimelineView() {
  const m = useHost('timeline')
  const narrow = useNarrow(600)
  // full screen (the host's focus view): drag across it to zoom into a time range
  const zoom = useFocusView()
  // no cursor shape in the live figure: the cursor is the DOM line below
  const fig = useMemo(() => (m ? buildTimeline(m.data, { live: true, narrow, zoom }) : null), [m, narrow, zoom])
  const line = useRef<HTMLDivElement | null>(null)
  const state = useRef({ m })
  state.current = { m }

  const draw = () => {
    const { m } = state.current
    const el = line.current, a = plotAxes(ref.current)
    if (!m || !el || !a) return
    const t = timelineCursor(m, cur.current)
    const x = a.xa.l2p(t)
    const on = Number.isFinite(x) && x >= -0.5 && x <= a.xa._length + 0.5
    el.style.display = on ? 'block' : 'none'
    if (on) {
      el.style.transform = `translateX(${(a.xa._offset + x - 0.75).toFixed(1)}px)`
      el.style.top = `${a.size.t}px`
      el.style.height = `${a.size.h}px`
    }
  }
  const cur = useLatest('cursor', draw)
  const ref = usePlot(fig, {
    onAfterPlot: draw,
    onClick: (gd, e) => {
      const t = clickTimeMs(gd, e)
      if (t != null) post({ type: 'seek', t })
    },
  })

  useExport((w) => {
    const { m } = state.current
    return m ? buildTimeline({ ...m.data, cursor: timelineCursor(m, cur.current) }, { narrow: w < 600 }) : null
  })

  if (!m) return <Waiting what="timeline data" />
  const onKey = (e: React.KeyboardEvent) => {
    const dir = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
    if (!dir) return
    e.preventDefault()
    const nt = stepBoundary(m.data, timelineCursor(m, cur.current), dir)
    if (nt != null) post({ type: 'seek', t: nt })
  }
  return (
    <div data-classic="timeline" style={{ ...box, position: 'relative' }} role="img" tabIndex={0} onKeyDown={onKey}
      aria-label={`${fig?.alt ?? ''} Left and right arrow keys move the time to the previous or next change.`}>
      <div ref={ref} style={box} />
      <div ref={line} data-cursor style={{ position: 'absolute', left: 0, top: 0, width: 1.5, height: 0, display: 'none',
        background: C.ice, pointerEvents: 'none' }} />
    </div>
  )
}
