/**
 * Sky plot view ("Where to look", charts spec 2.2): a one-line header, two
 * caption lines that answer "is it up and where do I look", the square plot
 * sized to the frame width (max 520 px) and, in a frame shorter than all of
 * that (the wide pane), to the height left ([skyFitSide]), a "Paths over the
 * period" toggle and the key line. "Exact numbers" adds the degree rings and spokes, the
 * legend, the exact block per body and the highest hills.
 *
 * Plotly draws only the static figure (when the payload, the detail mode or
 * the paths toggle changes). A `skyNow` updates the overlay (markers, word
 * labels, path names), the captions and the header time: no Plotly redraw.
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import type { SkyData } from './bridge'
import { skyNowData } from './cursor'
import { DetailToggle, useDetail } from './DetailToggle'
import { SkyHeader } from './SkyHeader'
import { buildSky, skyAlt, skyHeader } from './sky'
import { bodyGlyphSvg, drawSkyOverlay } from './skyOverlay'
import { captionLine, captionText, exactLine, highestHillsText, keyLine, legendNames } from './skyCaption'
import { C, HOST_CORNER_PX, MONO } from './theme'
import { usePlot } from './usePlot'
import { SKY_PAD_PX, skyFitLimit, skySide } from './skyFit'
import { useExport, useHost, useLatest, useLiveMode, Waiting } from './viewHooks'

export { SKY_MAX_PX, skySide } from './skyFit'
/** Side padding of the view, px. */
const PAD = SKY_PAD_PX
/** Bottom padding of the view, px. */
const PAD_B = 8

/** Client width and height of [el] (follows Flutter frame resizes, not only window resizes). */
function useBox(el: React.RefObject<HTMLElement | null>): { w: number; h: number } {
  const [box, setBox] = useState(() => ({ w: window.innerWidth, h: window.innerHeight }))
  useEffect(() => {
    const node = el.current
    if (!node) return
    const f = () => {
      const w = node.clientWidth || window.innerWidth, h = node.clientHeight || window.innerHeight
      setBox((b) => (b.w === w && b.h === h ? b : { w, h }))
    }
    f()
    // no ResizeObserver before Chrome 64 (Android 7's WebView is 51): window resizes there
    const ro = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(f)
    if (ro) ro.observe(node)
    else window.addEventListener('resize', f)
    return () => {
      ro?.disconnect()
      window.removeEventListener('resize', f)
    }
  })
  return box
}

/** A plot side limit measured for a frame and a figure. */
interface SkyFit { limit: number | null; key: string; fig: unknown }

/**
 * The plot side's limit from the frame's height ([skyFitLimit]), measured
 * after layout (before paint) with the plot at its current side. It is
 * measured again when the frame's height or outer width, the figure
 * (payload, Exact, paths) or the fonts change, but not for a new time: the
 * plot keeps its size through Play while the caption lines change (a
 * Plotly resize per step would be slow and jumpy), unless they wrap past
 * the room kept for that and the frame overflows; then the limit only
 * shrinks, so it settles. The frame is keyed by its outer width, so a
 * classic scrollbar coming or going does not count.
 */
function useSkyFit(root: React.RefObject<HTMLElement | null>, plot: React.RefObject<HTMLElement | null>, fig: unknown): number | null {
  const [fit, setFit] = useState<SkyFit | null>(null)
  const [fonts, setFonts] = useState(0)
  // the bundled fonts load after the first layout (the fallback font wraps the caption lines otherwise)
  useEffect(() => {
    const set = document.fonts
    if (!set) return
    let live = true
    const f = () => { if (live) setFonts((v) => v + 1) }
    void set.ready.then(f)
    set.addEventListener?.('loadingdone', f)
    return () => {
      live = false
      set.removeEventListener?.('loadingdone', f)
    }
  }, [])
  useLayoutEffect(() => {
    const el = root.current, box = plot.current
    const last = el?.lastElementChild
    if (!el || !box || !last || !fig) return
    const key = `${el.clientHeight}|${el.offsetWidth}|${fonts}`
    const same = !!fit && fit.key === key && fit.fig === fig
    // measured for this frame and figure: again only if a caption grew past the room kept for it
    if (same && el.scrollHeight <= el.clientHeight) return
    const content = last.getBoundingClientRect().bottom - el.getBoundingClientRect().top + el.scrollTop + PAD_B
    const limit = skyFitLimit(el.clientWidth, el.clientHeight, content - box.offsetHeight)
    // for the same frame and figure only ever smaller, so it settles (at SKY_FIT_MIN_PX at the latest)
    if (same && (limit ?? Infinity) >= (fit!.limit ?? Infinity)) return
    setFit({ limit, key, fig })
  })
  // a new figure starts from the last limit (measured again before paint): at
  // no limit the plot would commit at the frame's width first, and Plotly
  // would draw it there (1.13.3 review)
  return fit ? fit.limit : null
}

const Glyph = ({ name, counted }: { name: 'Sun' | 'Earth'; counted: boolean }) => (
  <span aria-hidden="true" style={{ flex: 'none', display: 'inline-flex', marginTop: 2 }}
    dangerouslySetInnerHTML={{ __html: bodyGlyphSvg(name, counted) }} />
)

function Caption({ d }: { d: SkyData }) {
  return (
    <>
      {(['Sun', 'Earth'] as const).map((name) => {
        const l = captionLine(name, name === 'Sun' ? d.now.sun : d.now.earth)
        return (
          <div key={name} data-caption={name} className="ph-row6" style={{ display: 'flex', alignItems: 'flex-start' }}>
            <Glyph name={name} counted={l.counted} />
            <span><b style={{ fontWeight: 600 }}>{l.head}</b>{l.rest.length ? ` · ${l.rest.join(' · ')}` : ''}</span>
          </div>
        )
      })}
    </>
  )
}

function ExactBlock({ d }: { d: SkyData }) {
  return (
    <>
      {(['Sun', 'Earth'] as const).map((name) => {
        const b = name === 'Sun' ? d.now.sun : d.now.earth
        return (
          <div key={name} data-exact={name} className="ph-row6" style={{ display: 'flex', alignItems: 'flex-start' }}>
            <Glyph name={name} counted={b.visible} />
            <span>
              <span style={{ fontFamily: MONO, fontSize: 12.5 }}>{exactLine(name, b)}</span>
              {b.say && <span style={{ display: 'block', color: C.muted }}>{b.say}</span>}
            </span>
          </div>
        )
      })}
      <div style={{ fontFamily: MONO, fontSize: 12.5, paddingLeft: 22 }}>{highestHillsText(d.mask)}</div>
    </>
  )
}

/** The Exact legend under the plot: a line sample and the name of each layer. */
function Legend({ maskApprox }: { maskApprox?: boolean }) {
  const n = legendNames(maskApprox)
  const item = (sample: React.ReactNode, text: string) => (
    <span className="ph-row6" style={{ display: 'inline-flex', alignItems: 'center' }}>{sample}<span>{text}</span></span>
  )
  const line = (color: string, dash?: string) => (
    <svg width="22" height="10" aria-hidden="true"><line x1="1" y1="5" x2="21" y2="5" stroke={color} strokeWidth="2" strokeDasharray={dash} /></svg>
  )
  return (
    <div data-legend className="ph-wrap-legend" style={{ display: 'flex', flexWrap: 'wrap', color: C.muted, fontSize: 12 }}>
      {item(<span style={{ width: 18, height: 10, background: C.terrain, border: `1px solid ${C.terrainEdge}`, display: 'inline-block' }} />, n.hills)}
      {item(line(C.sun), n.sun)}
      {item(line(C.earth, '2 3'), n.earth)}
    </div>
  )
}

export function SkyView() {
  const m = useHost('sky')
  const [exact, setExact] = useDetail()
  // "Paths over the period": off by default; Exact always shows them (and names them in the legend)
  const [pathsOn, setPathsOn] = useState(false)
  const paths = exact || pathsOn
  const live = useLiveMode(['skyNow'])
  const root = useRef<HTMLDivElement | null>(null)
  const plotBox = useRef<HTMLDivElement | null>(null)
  // static part only (rings, terrain, paths, compass, "hills"); the overlay draws the rest
  const fig = useMemo(() => (m ? buildSky(m.data, { live: true, exact, paths }) : null), [m, exact, paths])
  // as wide as the frame allows, but no taller than the frame leaves (the wide pane)
  const limit = useSkyFit(root, plotBox, fig)
  const side = Math.min(skySide(useBox(root).w), limit ?? Infinity)
  const overlay = useRef<HTMLDivElement | null>(null)
  const [shown, setShown] = useState<SkyData | null>(null)
  const state = useRef({ m, fig, exact, paths })
  state.current = { m, fig, exact, paths }

  const draw = () => {
    const { m, fig, exact, paths } = state.current
    if (!m || !fig) return
    const d = skyNowData(m, nowMsg.current)
    drawSkyOverlay(overlay.current, ref.current, d, fig.range, { exact, paths })
    setShown(d)
  }
  const nowMsg = useLatest('skyNow', draw)
  const ref = usePlot(fig, { onAfterPlot: draw })

  useExport(() => {
    const { m, exact } = state.current
    if (!m) return null
    // complete figure: header, captions, plot with paths, key line (and the Exact block)
    return buildSky(skyNowData(m, nowMsg.current), { exact })
  })

  if (!m) return <Waiting what="sky data" />
  // the newest of the payload and the latest skyNow (a new payload replaces an older skyNow)
  const d = shown && shown.siteName === m.data.siteName && shown.mask === m.data.mask ? shown : skyNowData(m, nowMsg.current)
  const h = skyHeader(d)
  const range = fig!.range
  return (
    <div ref={root} className="ph-col4" style={{ height: '100%', overflowY: 'auto', overflowX: 'hidden', boxSizing: 'border-box', padding: `4px ${PAD}px ${PAD_B}px`,
      display: 'flex', flexDirection: 'column', fontSize: 13, lineHeight: 1.3, color: C.text }}>
      {/* clear of the host's full-screen button: "Exact numbers" sat under it (F3) */}
      <div className="ph-row8" style={{ display: 'flex', alignItems: 'center', minHeight: 40, paddingRight: HOST_CORNER_PX - PAD }}>
        <SkyHeader title={h.title} site={h.site} time={h.time} tip={`${h.title} · ${h.site} · ${d.timeLabel}`} />
        <DetailToggle exact={exact} onChange={setExact} />
      </div>
      <div data-captions aria-live={live} className="ph-grid3">
        {exact ? <ExactBlock d={d} /> : <Caption d={d} />}
      </div>
      <div ref={plotBox} role="img" aria-label={skyAlt(d)} style={{ position: 'relative', width: side, height: side, flex: 'none', alignSelf: 'center' }}>
        <div ref={ref} style={{ width: '100%', height: '100%' }} />
        <div ref={overlay} style={{ position: 'absolute', top: 0, right: 0, bottom: 0, left: 0, pointerEvents: 'none', overflow: 'hidden' }} />
      </div>
      {exact ? <Legend maskApprox={d.maskApprox} /> : (
        <div style={{ height: 40, display: 'flex', alignItems: 'center' }}>
          <button type="button" className="ph-detail" aria-pressed={pathsOn} onClick={() => setPathsOn(!pathsOn)} style={{ paddingLeft: 0 }}>
            Paths over the period
          </button>
        </div>
      )}
      <div data-key style={{ color: C.muted, fontSize: 12, lineHeight: 1.3 }}>{keyLine(d, range)}</div>
    </div>
  )
}

/** The caption lines as plain text (tests, alt checks). */
export const skyCaptionTexts = (d: SkyData) => [captionText(captionLine('Sun', d.now.sun)), captionText(captionLine('Earth', d.now.earth))]
