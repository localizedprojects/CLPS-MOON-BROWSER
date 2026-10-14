/**
 * Timeline view, "When" (charts spec 2.1): answer lines first, then the span
 * presets, the three-row strip with flags, and the Coming up list. Exact
 * numbers adds the "Heights" curves under the strip.
 *
 * Plotly draws only when the payload, the span, the width class, the detail
 * mode or the window changes (the window re-anchors only when the cursor
 * leaves it). A cursor message re-renders the DOM overlays (answer lines,
 * cursor line, flags, Coming up) at most once per animation frame.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { post } from './bridge'
import { timelineCursor } from './cursor'
import { DetailToggle, useDetail } from './DetailToggle'
import { fmtDate, fmtDur } from './format'
import type { PlacedFlag, Span } from './strip'
import { BAR, buildStrip, buildTimelineExport, DEFAULT_SPAN, flagW, placeFlags, SPANS, spanWindow, stripFlags, stripHeight, stripMargin, windowFor } from './strip'
import { buildHeights, HEIGHT_NAMES, totalsLine } from './timeline'
import type { AnswerLine, Glyph, Run } from './timelineAnswer'
import { answerLines, comingUp, stepBoundary } from './timelineAnswer'
import { clickTimeMs, plotAxes, usePlot } from './usePlot'
import type { PlotlyDiv } from './plotGeom'
import { C, MONO } from './theme'
import { box, useExport, useHost, useLatest, useLiveMode, Waiting } from './viewHooks'

const mono: React.CSSProperties = { fontFamily: MONO, fontVariantNumeric: 'tabular-nums' }

function useWidth() {
  const [w, setW] = useState(() => window.innerWidth)
  useEffect(() => {
    const f = () => setW(window.innerWidth)
    window.addEventListener('resize', f)
    f()
    return () => window.removeEventListener('resize', f)
  }, [])
  return w
}

// ---------------------------------------------------------------------------
// Glyphs: shape + colour, never colour alone (aria-hidden: the words carry the state).

export function GlyphIcon({ kind, on = true }: { kind: Glyph; on?: boolean }) {
  const s = 14
  if (kind === 'sun') return <svg width={s} height={s} aria-hidden="true"><circle cx="7" cy="7" r="5.5" fill={on ? C.sun : 'none'} stroke={C.sun} strokeWidth="2" /></svg>
  if (kind === 'earth') return (
    <svg width={s} height={s} aria-hidden="true"><circle cx="7" cy="7" r="5.5" fill="none" stroke={C.earth} strokeWidth="2" strokeDasharray={on ? undefined : '2 2'} />
      {on && <path d="M7 1.5 A5.5 5.5 0 0 0 7 12.5 A4 5.5 0 0 1 7 1.5Z" fill={C.earth} />}</svg>)
  if (kind === 'dark') return <svg width={s} height={s} aria-hidden="true"><rect x="1" y="3.5" width="12" height="7" fill={C.dark} stroke={C.darkLine} strokeDasharray="2 1.5" /></svg>
  return (
    <svg width={s} height={s} aria-hidden="true">
      <defs><pattern id="ph-hatch" width="3" height="3" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="1.4" height="3" fill={C.page} /></pattern></defs>
      <path d="M7 1 L13 7 L7 13 L1 7Z" fill={on ? C.both : 'none'} stroke={C.both} strokeWidth="1.5" />
      {on && <path d="M7 1 L13 7 L7 13 L1 7Z" fill="url(#ph-hatch)" />}
    </svg>)
}

/** Keep durations ('10 d 18 h', 'in 10 d') and dates ('21 Oct 18:00') on one line. */
const MON = 'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec'
const UNIT_AFTER = new RegExp(`(\\d) (d|h|min|${MON})\\b`, 'g')
const NUM_AFTER = new RegExp(`\\b(d|h|${MON}|in) (\\d)`, 'g')
const keep = (s: string) => s.replace(UNIT_AFTER, '$1\u00a0$2').replace(NUM_AFTER, '$1\u00a0$2')

function Line({ l }: { l: AnswerLine }) {
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'baseline', lineHeight: 1.35 }}>
      <span style={{ flex: '0 0 auto', transform: 'translateY(2px)' }}><GlyphIcon kind={l.key} on={l.on} /></span>
      <span>
        {l.label && <b style={{ fontWeight: 600 }}>{l.label} </b>}
        <b style={{ fontWeight: 700, color: l.on ? C.text : C.text }}>{keep(l.state)}</b>
        {l.rest && <span style={{ color: C.muted }}> · {keep(l.rest)}</span>}
      </span>
    </div>)
}

/** Span presets: a radio group with arrow keys and a roving tab stop (48 px targets). */
function Presets({ value, onChange, narrow }: { value: Span; onChange: (s: Span) => void; narrow: boolean }) {
  const refs = useRef<(HTMLButtonElement | null)[]>([])
  const key = (e: React.KeyboardEvent, i: number) => {
    const d = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 0
    if (!d) return
    e.preventDefault()
    const j = (i + d + SPANS.length) % SPANS.length
    onChange(SPANS[j].id)
    refs.current[j]?.focus()
  }
  return (
    <div role="radiogroup" aria-label="Time span shown" style={{ display: 'inline-flex', border: `1px solid ${C.gridStrong}`, borderRadius: 6, overflow: 'hidden' }}>
      {SPANS.map((s, i) => {
        const on = s.id === value
        return (
          <button key={s.id} ref={(el) => { refs.current[i] = el }} type="button" role="radio" aria-checked={on} aria-label={s.label}
            tabIndex={on ? 0 : -1} onClick={() => onChange(s.id)} onKeyDown={(e) => key(e, i)}
            style={{ minHeight: 48, padding: narrow ? '0 12px' : '0 14px', border: 0, borderLeft: i ? `1px solid ${C.gridStrong}` : 0, cursor: 'pointer',
              background: on ? C.selected : 'transparent', color: on ? C.text : C.muted, font: `500 13px 'IBM Plex Sans', sans-serif` }}>
            {narrow ? s.short : s.label}
          </button>)
      })}
    </div>)
}

// ---------------------------------------------------------------------------

export function TimelineView() {
  const m = useHost('timeline')
  const [exact, setExact] = useDetail()
  const width = useWidth()
  const narrow = width < 600
  const wide = width >= 1000
  const live = useLiveMode(['cursor'])
  const [span, setSpan] = useState<Span>(DEFAULT_SPAN)
  const [t, setT] = useState<number | null>(null)
  const [win, setWin] = useState<{ span: Span; w: Run } | null>(null)
  const [plotVer, setPlotVer] = useState(0)
  const range = (m?.data.range ?? [0, 1]) as Run
  const tNow = t ?? m?.data.cursor ?? range[0]

  // a new payload (another site, other dates) shows its own cursor
  useEffect(() => { if (m) setT(timelineCursor(m, cur.current)) }, [m]) // eslint-disable-line react-hooks/exhaustive-deps

  // the span's window: kept while the cursor stays inside it, survives payload updates and site switches
  const shownWin = useMemo<Run>(() => (win && win.span === span && win.w[0] >= range[0] && win.w[1] <= range[1]
    ? win.w : spanWindow(span, tNow, range)), [win, m, span]) // eslint-disable-line react-hooks/exhaustive-deps

  const m0 = stripMargin(narrow)
  const comingW = wide ? 320 : 0
  const plotW = Math.max(120, width - 24 - m0.l - m0.r - comingW)
  const fig = useMemo(() => (m ? buildStrip(m.data, shownWin, { live: true, narrow, widthPx: plotW }) : null), [m, shownWin, narrow, plotW])
  const hFig = useMemo(() => (m && exact ? buildHeights(m.data, { live: true, narrow, window: shownWin }) : null), [m, exact, narrow, shownWin])

  const state = useRef({ m, span, shownWin })
  state.current = { m, span, shownWin }
  const apply = () => {
    const { m, span, shownWin } = state.current
    if (!m) return
    const tc = timelineCursor(m, cur.current)
    setT(tc)
    const nw = windowFor(shownWin, span, tc, m.data.range as Run)
    if (nw !== shownWin) setWin({ span, w: nw })
  }
  const cur = useLatest('cursor', apply)
  const seekClick = (gd: PlotlyDiv | null, ev: MouseEvent) => {
    if (!gd) return
    const tc = clickTimeMs(gd, { event: ev })
    if (tc != null) post({ type: 'seek', t: tc })
  }
  const ref = usePlot(fig, { onAfterPlot: () => setPlotVer((v) => v + 1) })
  const href = usePlot(hFig, { onAfterPlot: () => setPlotVer((v) => v + 1) })

  useExport(() => {
    const { m } = state.current
    return m ? buildTimelineExport(m.data, timelineCursor(m, cur.current), exact) : null
  })

  if (!m || !fig) return <Waiting what="timeline data" />
  const d = m.data
  const lines = answerLines(d, tNow, !narrow)
  const events = comingUp(d, tNow, narrow ? 3 : 5)
  const sh = stripHeight(narrow)

  // overlays from the drawn figure's geometry (plotVer: re-read after every draw)
  void plotVer
  const a = plotAxes(ref.current)
  let cursorX: number | null = null
  let flags: PlacedFlag[] = []
  if (a) {
    const px = (ms: number) => a.xa._offset + a.xa.l2p(ms)
    const x = px(tNow)
    if (Number.isFinite(x) && x >= a.size.l - 0.5 && x <= a.size.l + a.size.w + 0.5) cursorX = x
    const rowTop = (row: number) => a.ya._offset + a.ya.l2p(row + BAR.offset + BAR.width)
    flags = placeFlags(stripFlags(d, tNow, shownWin).map((f) => ({ row: f.row, x: px(f.ms), text: f.text, key: f.key })), a.size, rowTop)
  }
  const ha = exact ? plotAxes(href.current) : null
  const hx = ha ? ha.xa._offset + ha.xa.l2p(tNow) : NaN
  const hOn = ha && Number.isFinite(hx) && hx >= ha.size.l - 0.5 && hx <= ha.size.l + ha.size.w + 0.5
  const shownText = `Shown ${fmtDate(tNow, { refMs: range[0] })}`
  const sw = flagW(shownText)

  const onKey = (e: React.KeyboardEvent) => {
    const dir = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
    if (!dir) return
    e.preventDefault()
    const nt = stepBoundary(d, tNow, dir)
    if (nt != null) post({ type: 'seek', t: nt })
  }
  const pickSpan = (s: Span) => { setSpan(s); setWin({ span: s, w: spanWindow(s, tNow, range) }) }

  const coming = (
    <div style={{ minWidth: 0 }}>
      <div style={{ color: C.muted, fontSize: 12, fontWeight: 600, margin: '2px 0 2px' }}>Coming up</div>
      {events.length ? (
        <ol style={{ listStyle: 'none', margin: 0, padding: 0 }}>
          {events.map((ev) => (
            <li key={`${ev.t}-${ev.key}-${ev.mark}`}>
              <button type="button" onClick={() => post({ type: 'seek', t: ev.t })} aria-label={`${ev.text}. Move the time there.`}
                style={{ display: 'flex', gap: 8, alignItems: 'center', width: '100%', minHeight: 48, padding: '0 4px', background: 'transparent', border: 0,
                  borderTop: `1px solid ${C.grid}`, color: C.text, font: `400 13px 'IBM Plex Sans', sans-serif`, textAlign: 'left', cursor: 'pointer' }}>
                <span aria-hidden="true" style={{ flex: '0 0 auto', width: 14, color: ev.key === 'both' ? C.both : ev.key === 'earth' ? C.earth : C.sun }}>{ev.mark}</span>
                <span>{keep(ev.text)}</span>
              </button>
            </li>))}
        </ol>) : <div style={{ color: C.muted, fontSize: 13, minHeight: 32 }}>No more changes in your chosen dates.</div>}
    </div>)

  return (
    <div style={{ ...box, overflowY: 'auto', boxSizing: 'border-box', padding: '4px 12px 4px', display: 'flex', flexDirection: 'column', gap: narrow ? 4 : 6, fontSize: 13.5, color: C.text }}
      aria-label={`${fig.alt} Shown time ${fmtDate(tNow, { year: true })} UTC.`} role="group">
      <div style={{ color: C.muted, fontSize: 12.5 }}>When · all times UTC</div>
      <div aria-live={live} style={{ display: 'grid', gap: narrow ? 4 : '4px 18px', gridTemplateColumns: narrow ? '1fr' : '1fr 1fr' }}>
        {lines.map((l) => <Line key={l.key} l={l} />)}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center', justifyContent: 'space-between' }}>
        <Presets value={span} onChange={pickSpan} narrow={narrow} />
        <DetailToggle exact={exact} onChange={setExact} />
      </div>
      <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
        <div style={{ flex: '1 1 auto', minWidth: 0 }}>
          {/* a slider, not an image: assistive tech then passes the arrow keys through (charts-1) */}
          <div style={{ position: 'relative', height: sh }} tabIndex={0} role="slider" aria-orientation="horizontal"
            aria-valuemin={range[0]} aria-valuemax={range[1]} aria-valuenow={tNow}
            aria-valuetext={`Shown ${fmtDate(tNow, { year: true })} UTC`}
            aria-label={`Time on the rows Sun + Earth, Sunlight, ${d.earthLabel || 'Earth in view'}. Left and right arrow keys move the time to the previous or next change.`}
            onKeyDown={onKey} onClick={(e) => seekClick(ref.current, e.nativeEvent)}>
            <div ref={ref} style={box} />
            {cursorX != null && a && <>
              <div data-cursor style={{ position: 'absolute', left: cursorX - 1, top: a.size.t, width: 2, height: a.size.h, background: C.ice, pointerEvents: 'none' }} />
              <div data-flag="shown" style={{ position: 'absolute', top: Math.max(0, a.size.t - 21), pointerEvents: 'none', whiteSpace: 'nowrap',
                left: Math.min(Math.max(cursorX - sw / 2, a.size.l - 2), a.size.l + a.size.w - sw + 2),
                font: `500 11.5px ${MONO}`, color: C.page, background: C.ice, borderRadius: 4, padding: '1px 6px' }}>{shownText}</div>
            </>}
            {flags.map((f) => (
              <div key={f.text} data-flag={f.key} style={{ position: 'absolute', left: 0, top: 0, pointerEvents: 'none' }}>
                <div style={{ position: 'absolute', left: f.x - 0.75, top: f.tickTop, width: 1.5, height: f.tickH, background: C.text }} />
                <div style={{ position: 'absolute', left: f.left, top: f.top, whiteSpace: 'nowrap', font: `500 11.5px 'IBM Plex Sans', sans-serif`,
                  color: C.text, background: C.panel, border: `1px solid ${f.key === 'both' ? C.both : C.darkLine}`, borderRadius: 4, padding: '0 5px', lineHeight: '13px' }}>
                  {keep(f.text)}
                </div>
              </div>))}
          </div>
          <div style={{ color: C.muted, fontSize: 12, lineHeight: 1.4 }}>
            Click or tap anywhere on the rows to move the time there · Times on a {fmtDur((d.stepMin ?? 30) * 60e3).replace(' ', '-')} grid
          </div>
        {exact && (
          <div>
            <div style={{ color: C.muted, fontSize: 11.5, letterSpacing: 1.2, fontWeight: 600, marginTop: 4 }}>HEIGHTS</div>
            <div style={{ position: 'relative', height: narrow ? 280 : 300 }} role="img"
              aria-label={`Heights: ${HEIGHT_NAMES.sunEl}, ${HEIGHT_NAMES.sunHz}, ${HEIGHT_NAMES.earthEl}, ${HEIGHT_NAMES.earthHz}, in degrees above the flat horizon.`}
              onClick={(e) => seekClick(href.current, e.nativeEvent)}>
              <div ref={href} style={box} />
              {hOn && ha && <div style={{ position: 'absolute', left: hx - 1, top: ha.size.t, width: 2, height: ha.size.h, background: C.ice, pointerEvents: 'none' }} />}
            </div>
            <div style={{ color: C.muted, fontSize: 12, lineHeight: 1.4 }}>A body clears the hills when its solid line is above its dotted line.</div>
            <div style={{ ...mono, fontSize: 12, color: C.text, lineHeight: 1.4, marginTop: 2 }}>{totalsLine(d)}</div>
          </div>)}
        </div>
        {wide && <div style={{ flex: `0 0 ${comingW - 16}px` }}>{coming}</div>}
      </div>
      {!wide && coming}
    </div>
  )
}
