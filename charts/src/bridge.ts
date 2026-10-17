/**
 * Flutter <-> React message bridge. Keep in sync with
 * app/lib/widgets/chart_bridge.dart.
 *
 * Flutter -> JS : window.phRender(msg)  (Android: runJavaScript)
 *                 or window.postMessage({source:'ph-host', msg}) (web iframe)
 * JS -> Flutter : PH.postMessage(json)  (Android JavaScriptChannel)
 *                 or parent.postMessage({source:'ph-charts', event}) (web)
 *
 * Acks: a host message may carry a sequence number n (the web host puts it
 * on the envelope, {source:'ph-host', msg, n}; window.phRender(msg, n) takes
 * it too). Once the page has run and drawn every message up to n it answers
 * {type:'ack', n} on the same path as 'ready', so the host's Play can wait
 * for the chart (ChartAcks in chart_bridge.dart). Messages without n (the
 * Android host, which waits on runJavaScript instead) are never acked.
 *
 * The charts are render-only: every number arrives from the Dart core.
 */

export type View = 'sky' | 'timeline' | 'compare'

/**
 * One state word per body, decided in Dart (`bodyStateShort` in
 * app/lib/core/wording.dart; charts spec 2.0):
 * up (counted, whole disk up) | partly (counted, part showing) |
 * notCounted (part showing, the user's rule does not count it) |
 * behindHills (above the flat horizon, none of it clears the hills) |
 * belowHorizon (el + rho < 0) | noDsn (Earth only: clears the hills, fails the DSN check).
 */
export type BodyState = 'up' | 'partly' | 'notCounted' | 'behindHills' | 'belowHorizon' | 'noDsn'

export interface BodyNow {
  az: number
  el: number
  /** angular radius, deg */
  rho: number
  /** visible fraction of the disk 0..1 */
  frac: number
  /** horizon elevation at the body's azimuth */
  hz: number
  /** counted as up under the user's rule (and, for Earth, the DSN check) */
  visible: boolean
  /** Earth only: counted under the Earth rule from the terrain alone (before the DSN check) */
  terrainVisible?: boolean
  /** el - hz at the disk centre, deg (Dart). Optional: old payloads lack it. */
  clear?: number
  /** the shared state word (Dart `bodyStateShort`). Optional: old payloads lack it. */
  state?: BodyState
  /** the full Dart sentence (`sunStatusText` / `earthStatusText`). Optional. */
  say?: string
}

export interface SkyData {
  siteName: string
  timeLabel: string
  /** the period start, Unix ms: the header adds the year outside its 12 months (fmtDate). Optional: old payloads lack it. */
  refMs?: number
  maskStepDeg: number
  mask: number[]
  maskApprox?: boolean
  now: { sun: BodyNow; earth: BodyNow }
  trails: { sun: { az: number[]; el: number[] }; earth: { az: number[]; el: number[] } }
  zoom: boolean
}

/**
 * One chart curve after min/max decimation on the Dart side: every bucket
 * keeps its lowest and highest sample, so each curve has its own time axis.
 */
export interface Curve {
  /** Unix ms (UTC), increasing */
  t: number[]
  y: number[]
}

export interface TimelineData {
  siteName: string
  /** elevations and terrain-horizon elevations at the bodies' azimuths, deg */
  curves: { sunEl: Curve; earthEl: Curve; sunHz: Curve; earthHz: Curve }
  /** availability runs [start, end) in Unix ms, full resolution */
  runs: { sun: [number, number][]; earth: [number, number][]; both: [number, number][] }
  range: [number, number]
  cursor: number
  /** lane label of the Earth run ('Earth in view' or 'Earth contact (DSN)') */
  earthLabel: string
  /** share of the period, percent, from the site's SiteMetrics (the numbers Overview and Compare show) */
  pct?: { sun: number; earth: number; both: number }
  /** the longest dark spell [startMs, endMs) from SiteMetrics.longestDark (null: never dark) */
  longestDark?: [number, number] | null
  /** series step in minutes (a run of exactly one step reads "about 30 min") */
  stepMin?: number
  /** minHours of "Next good stretch" (24): a shorter next window adds "next 1 day or more" */
  goodMinH?: number
}

export interface CompareRow {
  id: string
  name: string
  score: number
  pctSunlit: number
  pctEarth: number
  pctBoth: number
  longestDarkH: number
  /** the longest dark spell touches the start or end of the period (its length gets a "+") */
  longestDarkAtEdge?: boolean
}

export interface CompareData {
  rows: CompareRow[]
  /**
   * Score weights in whole percent, as the formula shows them:
   * Score = rest% x [power% Power + comms% Comms] + both% x Both (rest = 100 - both).
   */
  weights: { power: number; comms: number; both: number; rest: number }
  /** label of the Earth metric ('Earth in view' or 'Earth contact (DSN)') */
  earthLabel: string
}

export type HostMessage =
  | { type: 'sky'; data: SkyData }
  | { type: 'timeline'; data: TimelineData }
  | { type: 'compare'; data: CompareData }
  | { type: 'cursor'; t: number }
  | { type: 'skyNow'; now: { sun: BodyNow; earth: BodyNow }; timeLabel: string }
  | { type: 'setView'; view: View }
  /** a PNG of the chart at width x height CSS px, rendered at [scale] device pixels per px (default 1) */
  | { type: 'exportPng'; id: string; width?: number; height?: number; scale?: number }
  /** "Exact numbers" on or off (the app's expert mode); kept for replay, not one-shot */
  | { type: 'detail'; exact: boolean }
  /**
   * Sky & time's "Simple view" switch (default off: the classic sky plot and
   * timeline). On: the simple views ("Where to look", "When"). Kept for
   * replay, not one-shot. Compare ignores it.
   */
  | { type: 'simple'; on: boolean }
  /** web: Tab reached the chart frame; focus the page's first control, or its last on Shift+Tab (focusHandoff.ts, one-shot) */
  | { type: 'focusFirst'; last?: boolean }
  /**
   * The chart is shown full screen (the app's focus view) or back in its page.
   * In focus the classic timeline zooms by dragging across it (double-tap to
   * zoom out). Kept for replay, not one-shot.
   */
  | { type: 'focus'; on: boolean }

export type ChartEvent =
  | { type: 'ready'; view: View }
  | { type: 'seek'; t: number }
  | { type: 'hover'; t: number }
  | { type: 'png'; id: string; dataUrl: string }
  | { type: 'error'; message: string }
  /** the viewer toggled "Exact numbers" inside this chart (the host keeps it for this chart's replay only) */
  | { type: 'detail'; exact: boolean }
  /** Tab left the page's last control (dir 1) or Shift+Tab its first (dir -1): the host moves focus on */
  | { type: 'focusExit'; dir: 1 | -1 }
  /** every host message up to sequence number [n] has been run and drawn (see the header) */
  | { type: 'ack'; n: number }

declare global {
  interface Window {
    phRender?: (msg: HostMessage | string, n?: number) => void
    PH?: { postMessage: (s: string) => void }
  }
}

type Handler = (m: HostMessage) => void
const handlers = new Set<Handler>()
let seq = 0
const SEQ = new WeakMap<object, number>()

/** Arrival order of a host message (lets views pick the newest of two message types). */
export function seqOf(m: HostMessage | null | undefined): number {
  return m ? SEQ.get(m) ?? 0 : 0
}
let last: Partial<Record<HostMessage['type'], HostMessage>> = {}
/** Commands that act once (a file export): not kept in [last]. */
const ONE_SHOT = new Set<HostMessage['type']>(['exportPng', 'focusFirst'])

/** The newest message of [type] received so far (null before the first). */
export function latest<T extends HostMessage['type']>(type: T): Extract<HostMessage, { type: T }> | null {
  return (last[type] as Extract<HostMessage, { type: T }> | undefined) ?? null
}

function dispatch(raw: HostMessage | string, n?: number) {
  try {
    let m: HostMessage
    try {
      m = typeof raw === 'string' ? (JSON.parse(raw) as HostMessage) : raw
    } catch (e) {
      post({ type: 'error', message: `bad message: ${String(e)}` })
      return
    }
    SEQ.set(m, ++seq)
    // one-shot commands (a file export) are never replayed to a later subscriber
    if (!ONE_SHOT.has(m.type)) last = { ...last, [m.type]: m }
    handlers.forEach((h) => h(m))
  } finally {
    // acked even when it failed: a bad message must not hold the host's Play
    if (typeof n === 'number' && Number.isFinite(n)) ackAfterDraw(n)
  }
}

/** The newest sequence number run and not yet taken by an ack round (0: none). */
let ackQueued = 0
/** An ack round is under way (it waits two animation frames). */
let ackRound = false

/**
 * Ack [n] once it is drawn. The views draw at most once per animation frame,
 * in a frame callback asked for while the message is handled (before this
 * one: frame callbacks run in the order asked), and a payload re-renders
 * React in a task before the next frame. So the first frame takes every
 * number queued so far, after their draws ran; the second starts once that
 * frame is painted, and posts one ack for the newest of them. A message that
 * arrives in between waits for the next round. Many messages in one frame
 * give one ack (the newest number covers the older ones).
 */
function ackAfterDraw(n: number) {
  if (n > ackQueued) ackQueued = n
  if (ackRound) return
  ackRound = true
  requestAnimationFrame(() => {
    const k = ackQueued
    ackQueued = 0
    requestAnimationFrame(() => {
      ackRound = false
      if (k) post({ type: 'ack', n: k })
      if (ackQueued) ackAfterDraw(ackQueued)
    })
  })
}

/** Install the global entry points once. */
export function installBridge() {
  window.phRender = dispatch
  window.addEventListener('message', (ev: MessageEvent) => {
    const d = ev.data as { source?: string; msg?: HostMessage; n?: unknown }
    if (d && d.source === 'ph-host' && d.msg) dispatch(d.msg, typeof d.n === 'number' ? d.n : undefined)
  })
}

/**
 * Call [h] for every message from now on, after replaying the newest message
 * of each type received so far (in arrival order), so a view that mounts late
 * still sees the payload and the cursor that came before it.
 */
export function subscribe(h: Handler): () => void {
  handlers.add(h)
  Object.values(last).filter((m): m is HostMessage => !!m).sort((a, b) => seqOf(a) - seqOf(b)).forEach(h)
  return () => handlers.delete(h)
}

/** Test hook: forget every message (each test starts from a fresh page). */
export function resetBridgeForTests() {
  last = {}
  handlers.clear()
  ackQueued = 0
  ackRound = false
}

/** Test hook: deliver [m] (with the host's sequence number [n], if any) as the host would. */
export const dispatchForTests = (m: HostMessage | string, n?: number) => dispatch(m, n)

export function post(ev: ChartEvent) {
  const json = JSON.stringify(ev)
  if (window.PH) window.PH.postMessage(json)
  else if (window.parent && window.parent !== window) window.parent.postMessage({ source: 'ph-charts', event: ev }, '*')
}

export function viewFromLocation(loc: Location = window.location): View {
  const q = new URLSearchParams(loc.hash.replace(/^#/, '') || loc.search.replace(/^\?/, ''))
  const v = q.get('view')
  return v === 'timeline' || v === 'compare' ? v : 'sky'
}
