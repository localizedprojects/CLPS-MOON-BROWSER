/**
 * Compare view (charts spec 2.3): the headline and "Exact numbers" switch on
 * top (real text, read first), the simple blocks or the exact figure, and the
 * plain score line under the simple blocks. The headline and score line are
 * prose (Plex Sans with tabular figures); the standalone numbers in the
 * figure (scores, shares, durations) are Plex Mono. The PNG export draws the
 * same headline and score line into the figure.
 */
import { useMemo, useRef } from 'react'
import { buildCompare, buildCompareSimple, headline, scoreLine } from './compare'
import { DetailToggle, useDetail } from './DetailToggle'
import { C } from './theme'
import { usePlot } from './usePlot'
import { useExport, useHost, useLiveMode, useNarrow, Waiting } from './viewHooks'

const col: React.CSSProperties = { width: '100%', height: '100%', display: 'flex', flexDirection: 'column' }

export function CompareView() {
  const m = useHost('compare')
  const narrow = useNarrow(600)
  const [exact, setExact] = useDetail()
  const live = useLiveMode(['compare'])
  const fig = useMemo(() => (m ? (exact ? buildCompare(m.data, { narrow }) : buildCompareSimple(m.data, { narrow })) : null), [m, narrow, exact])
  const ref = usePlot(fig)
  const state = useRef({ m, exact })
  state.current = { m, exact }
  useExport(() => {
    const s = state.current
    if (!s.m) return null
    return s.exact ? buildCompare(s.m.data, { png: true }) : buildCompareSimple(s.m.data, { png: true })
  })
  if (!m) return <Waiting what="comparison data" />
  return (
    <div style={col}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8, padding: narrow ? '6px 4px 2px 6px' : '8px 8px 4px 6px' }}>
        <div aria-live={live} style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 600, fontSize: narrow ? 14 : 15, lineHeight: 1.35, color: C.text }}>{headline(m.data, exact)}</div>
          <div style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.4, marginTop: 2 }}>Bars: share of your chosen dates</div>
        </div>
        <DetailToggle exact={exact} onChange={setExact} />
      </div>
      <div ref={ref} style={{ flex: 1, minHeight: 0 }} role="img" aria-label={fig?.alt ?? 'Comparison of candidate sites'} />
      {!exact && (
        <div style={{ color: C.muted, fontSize: 12.5, lineHeight: 1.45, padding: narrow ? '4px 8px 8px 6px' : '4px 8px 10px 6px' }}>
          {scoreLine(m.data.weights)}
        </div>
      )}
    </div>
  )
}
