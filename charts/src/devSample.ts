/**
 * Development feed for `npm run dev` only (never shipped: imported behind
 * import.meta.env.DEV). REAL payloads built by the app's Dart code for the
 * default period (11 Oct 2026 - 11 Oct 2027, 30-min step), with the charts
 * spec section 4 fields (clear/state/say, pct, longestDark, stepMin,
 * goodMinH, longestDarkAtEdge):
 *   Shackleton rim (SR1) by default, `?site=haworth` for Haworth,
 *   `?dsn=1` for SR1 with the DSN rule on (Earth contact wording),
 *   compare = Malapert peak (MP1), IM-1 Odysseus, IM-2 Athena.
 * `?t=<unix ms>` sends a later cursor message, `?exact=1` the host's
 * "Exact numbers" mode, `?simple=1` the "Simple view" switch. Regenerate them from the app, never by hand.
 */
import type { HostMessage, View } from './bridge'
import sky from './devdata/sky.json'
import skyNow from './devdata/skyNow.json'
import skyNowDsn from './devdata/skyNow_dsn.json'
import timeline from './devdata/timeline.json'
import timelineDsn from './devdata/timeline_dsn.json'
import cursor from './devdata/cursor.json'
import skyH from './devdata/sky_haworth.json'
import skyNowH from './devdata/skyNow_haworth.json'
import timelineH from './devdata/timeline_haworth.json'
import compare from './devdata/compare.json'

export function feedDevSample(view: View) {
  if (!window.phRender) return
  const q = new URLSearchParams(window.location.search)
  const haworth = q.get('site') === 'haworth'
  const dsn = q.get('dsn') === '1'
  const send = (m: unknown) => window.phRender!(m as HostMessage)
  if (q.has('exact')) send({ type: 'detail', exact: q.get('exact') === '1' })
  // `?simple=1`: the host's "Simple view" switch on (default: the classic charts)
  if (q.has('simple')) send({ type: 'simple', on: q.get('simple') === '1' })
  if (view === 'sky') {
    send(haworth ? skyH : sky)
    send(haworth ? skyNowH : dsn ? skyNowDsn : skyNow)
  }
  if (view === 'timeline') {
    send(haworth ? timelineH : dsn ? timelineDsn : timeline)
    send(cursor)
  }
  if (view === 'compare') send(compare)
  const t = Number(q.get('t'))
  if (t && view === 'timeline') setTimeout(() => send({ type: 'cursor', t }), 400)
}
