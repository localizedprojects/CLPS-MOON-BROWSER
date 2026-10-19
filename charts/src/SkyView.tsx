/**
 * Sky plot view ("Where to look", charts spec 2.2): a one-line header, two
 * caption lines that answer "is it up and where do I look", the square plot
 * sized to the frame width (max 520 px), a "Paths over the period" toggle
 * and the key line. "Exact numbers" adds the degree rings and spokes, the
 * legend, the exact block per body and the highest hills.
 *
 * Plotly draws only the static figure (when the payload, the detail mode or
 * the paths toggle changes). A `skyNow` updates the overlay (markers, word
 * labels, path names), the captions and the header time: no Plotly redraw.
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import type { SkyData } from './bridge'
import { skyNowData } from './cursor'
import { DetailToggle, useDetail } from './DetailToggle'
import { SkyHeader } from './SkyHeader'
import { buildSky, skyAlt, skyHeader } from './sky'
import { bodyGlyphSvg, drawSkyOverlay } from './skyOverlay'
import { captionLine, captionText, exactLine, highestHillsText, keyLine, legendNames } from './skyCaption'
import { C, MONO } from './theme'
import { usePlot } from './usePlot'
import { useExport, useHost, useLatest, useLiveMode, Waiting } from './viewHooks'

/** Largest plot side, px (charts spec 2.2). */
export const SKY_MAX_PX = 520
/** Side padding of the view, px. */
const PAD = 12

/** Plot side for a frame [width] px wide: the frame width minus padding, at most 520 px. */
export const skySide = (width: number) => Math.max(160, Math.min(SKY_MAX_PX, Math.floor(width - 2 * PAD)))

/** Width of [el] (follows Flutter frame resizes, not only window resizes). */
function useWidth(el: React.RefObject<HTMLElement | null>): number {
  const [w, setW] = useState(() => window.innerWidth)
  useEffect(() => {
    const node = el.current
    if (!node) return
    const f = () => setW(node.clientWidth || window.innerWidth)
    f()
    const ro = new ResizeObserver(f)
    ro.observe(node)
    return () => ro.disconnect()
  })
  return w
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
          <div key={name} data-caption={name} style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
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
          <div key={name} data-exact={name} style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
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
    <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>{sample}<span>{text}</span></span>
  )
  const line = (color: string, dash?: string) => (
    <svg width="22" height="10" aria-hidden="true"><line x1="1" y1="5" x2="21" y2="5" stroke={color} strokeWidth="2" strokeDasharray={dash} /></svg>
  )
  return (
    <div data-legend style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 14px', color: C.muted, fontSize: 12 }}>
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
  const side = skySide(useWidth(root))
  // static part only (rings, terrain, paths, compass, "hills"); the overlay draws the rest
  const fig = useMemo(() => (m ? buildSky(m.data, { live: true, exact, paths }) : null), [m, exact, paths])
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
    <div ref={root} style={{ height: '100%', overflowY: 'auto', overflowX: 'hidden', boxSizing: 'border-box', padding: `4px ${PAD}px 8px`,
      display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13, lineHeight: 1.3, color: C.text }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, minHeight: 40 }}>
        <SkyHeader title={h.title} site={h.site} time={h.time} tip={`${h.title} · ${h.site} · ${d.timeLabel}`} />
        <DetailToggle exact={exact} onChange={setExact} />
      </div>
      <div data-captions aria-live={live} style={{ display: 'grid', gap: 3 }}>
        {exact ? <ExactBlock d={d} /> : <Caption d={d} />}
      </div>
      <div role="img" aria-label={skyAlt(d)} style={{ position: 'relative', width: side, height: side, flex: 'none', alignSelf: 'center' }}>
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
