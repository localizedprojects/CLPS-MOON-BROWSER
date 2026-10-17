import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { BodyNow, ChartEvent, HostMessage } from './bridge'
import { dispatchForTests, installBridge, latest, resetBridgeForTests, subscribe, viewFromLocation } from './bridge'
import { skyNowData, timelineCursor } from './cursor'

const body = (o: Partial<BodyNow> = {}): BodyNow => ({ az: 10, el: 1, rho: 0.27, frac: 1, hz: 0.2, visible: true, ...o })
const skyData = (now = { sun: body(), earth: body({ az: 200, visible: false }) }) => ({
  siteName: 's', timeLabel: 't', maskStepDeg: 90, mask: [0, 1, 0, 1], zoom: true, now,
  trails: { sun: { az: [1], el: [1] }, earth: { az: [2], el: [2] } },
})

describe('bridge', () => {
  beforeEach(() => resetBridgeForTests())
  it('reads the view from the hash', () => {
    expect(viewFromLocation({ hash: '#view=timeline', search: '' } as Location)).toBe('timeline')
    expect(viewFromLocation({ hash: '', search: '?view=compare' } as Location)).toBe('compare')
    expect(viewFromLocation({ hash: '', search: '' } as Location)).toBe('sky')
  })
  it('replays the newest message of each type in arrival order to a late subscriber', () => {
    dispatchForTests({ type: 'cursor', t: 1 })
    dispatchForTests({ type: 'compare', data: { rows: [], weights: { power: 50, comms: 50, both: 25, rest: 75 }, earthLabel: '' } })
    dispatchForTests({ type: 'cursor', t: 2 })
    const got: HostMessage[] = []
    subscribe((m) => got.push(m))
    expect(got.map((m) => m.type)).toEqual(['compare', 'cursor'])
    expect((got[1] as { t: number }).t).toBe(2)
  })
  it('never replays a PNG export to a later subscriber', () => {
    dispatchForTests({ type: 'exportPng', id: 'x' })
    const got: HostMessage[] = []
    subscribe((m) => got.push(m))
    expect(got).toEqual([])
  })
})

describe('cursor before the plot mounts (async-1, web-2)', () => {
  beforeEach(() => resetBridgeForTests())
  const tlMsg = (cursor: number): HostMessage => ({ type: 'timeline', data: {
    siteName: 's', curves: { sunEl: { t: [], y: [] }, earthEl: { t: [], y: [] }, sunHz: { t: [], y: [] }, earthHz: { t: [], y: [] } },
    runs: { sun: [], earth: [], both: [] }, range: [0, 10], cursor, earthLabel: '' } })
  it('a cursor message sent after the payload wins over the payload cursor', () => {
    const got: HostMessage[] = []
    subscribe((m) => got.push(m))
    dispatchForTests(tlMsg(0)) // payload built at the period start
    dispatchForTests({ type: 'cursor', t: 5 }) // then 'Show me the best time'
    const m = got.find((x) => x.type === 'timeline') as Extract<HostMessage, { type: 'timeline' }>
    const c = got.find((x) => x.type === 'cursor') as Extract<HostMessage, { type: 'cursor' }>
    expect(timelineCursor(m, c)).toBe(5)
  })
  it('a newer payload (another site) wins over an older cursor message', () => {
    const got: HostMessage[] = []
    subscribe((m) => got.push(m))
    dispatchForTests({ type: 'cursor', t: 5 })
    dispatchForTests(tlMsg(7))
    const m = got.find((x) => x.type === 'timeline') as Extract<HostMessage, { type: 'timeline' }>
    const c = got.find((x) => x.type === 'cursor') as Extract<HostMessage, { type: 'cursor' }>
    expect(timelineCursor(m, c)).toBe(7)
    expect(timelineCursor(m, null)).toBe(7)
  })
  it('the sky plot uses the newest of payload and skyNow', () => {
    const got: HostMessage[] = []
    subscribe((m) => got.push(m))
    dispatchForTests({ type: 'sky', data: skyData() })
    dispatchForTests({ type: 'skyNow', now: { sun: body({ el: 3 }), earth: body() }, timeLabel: 'later' })
    const m = got.find((x) => x.type === 'sky') as Extract<HostMessage, { type: 'sky' }>
    const n = got.find((x) => x.type === 'skyNow') as Extract<HostMessage, { type: 'skyNow' }>
    expect(skyNowData(m, n).timeLabel).toBe('later')
    expect(skyNowData(m, n).now.sun.el).toBe(3)
    expect(skyNowData(m, null).timeLabel).toBe('t')
  })
})

describe('detail mode (charts spec 4.4)', () => {
  beforeEach(() => resetBridgeForTests())
  it('is kept and replayed to a late subscriber (not one-shot)', () => {
    dispatchForTests({ type: 'detail', exact: false })
    dispatchForTests({ type: 'detail', exact: true })
    const got: HostMessage[] = []
    subscribe((m) => got.push(m))
    expect(got).toEqual([{ type: 'detail', exact: true }])
    expect(latest('detail')?.exact).toBe(true)
  })
  it('arrives as JSON from Android too', () => {
    dispatchForTests(JSON.stringify({ type: 'detail', exact: true }))
    expect(latest('detail')).toEqual({ type: 'detail', exact: true })
  })
})

describe('ack: the page tells the host what it has drawn (web Play waits on it)', () => {
  let frames: FrameRequestCallback[] = []
  let sent: ChartEvent[] = []
  /** Run one animation frame: the callbacks asked for before it, in order. */
  const frame = () => frames.splice(0).forEach((f) => f(0))
  beforeEach(() => {
    resetBridgeForTests()
    frames = []
    sent = []
    vi.stubGlobal('requestAnimationFrame', (f: FrameRequestCallback) => frames.push(f))
    // the Android JavaScript channel (the web path is checked below)
    vi.stubGlobal('window', { PH: { postMessage: (s: string) => sent.push(JSON.parse(s) as ChartEvent) } })
  })
  afterEach(() => vi.unstubAllGlobals())
  const acks = () => sent.filter((e) => e.type === 'ack')

  it('acks a numbered message two frames on, after the view drew it', () => {
    const drawn: number[] = []
    // as useLatest: the view asks for a frame while it handles the message
    subscribe((m) => { if (m.type === 'cursor') requestAnimationFrame(() => drawn.push(m.t)) })
    dispatchForTests({ type: 'cursor', t: 5 }, 1)
    expect(acks()).toEqual([])
    frame()
    expect(drawn).toEqual([5])
    expect(acks()).toEqual([]) // not before the drawn frame is painted
    frame()
    expect(acks()).toEqual([{ type: 'ack', n: 1 }])
    frame()
    expect(acks()).toHaveLength(1)
  })
  it('gives one ack, for the newest number, to a burst in one frame', () => {
    dispatchForTests({ type: 'cursor', t: 1 }, 7)
    dispatchForTests({ type: 'skyNow', now: { sun: body(), earth: body() }, timeLabel: 'x' }, 8)
    dispatchForTests({ type: 'cursor', t: 2 }, 9)
    frame()
    frame()
    expect(acks()).toEqual([{ type: 'ack', n: 9 }])
  })
  it('a message that arrives after the round took its numbers waits for the next round', () => {
    dispatchForTests({ type: 'cursor', t: 1 }, 1)
    frame() // the round takes n = 1
    dispatchForTests({ type: 'cursor', t: 2 }, 2) // drawn in the next frame
    frame()
    expect(acks()).toEqual([{ type: 'ack', n: 1 }])
    frame()
    frame()
    expect(acks()).toEqual([{ type: 'ack', n: 1 }, { type: 'ack', n: 2 }])
  })
  it('never acks a message without a number (the Android host waits on runJavaScript)', () => {
    dispatchForTests(JSON.stringify({ type: 'cursor', t: 1 }))
    frame()
    frame()
    expect(frames).toEqual([])
    expect(acks()).toEqual([])
  })
  it('acks a message it could not read, so a bad message never holds Play', () => {
    dispatchForTests('{not json', 3)
    expect(sent.map((e) => e.type)).toEqual(['error'])
    frame()
    frame()
    expect(acks()).toEqual([{ type: 'ack', n: 3 }])
  })
  it('on the web: the number rides on the envelope and the ack goes to the parent like ready', () => {
    const toParent: unknown[] = []
    let onMessage: ((ev: MessageEvent) => void) | undefined
    vi.stubGlobal('window', {
      parent: { postMessage: (d: unknown) => toParent.push(d) },
      addEventListener: (type: string, f: (ev: MessageEvent) => void) => { if (type === 'message') onMessage = f },
    })
    installBridge()
    onMessage!({ data: { source: 'ph-host', msg: { type: 'cursor', t: 4 }, n: 12 } } as MessageEvent)
    onMessage!({ data: { source: 'ph-host', msg: { type: 'focusFirst' } } } as MessageEvent) // posted by the host itself: no number
    expect(latest('cursor')?.t).toBe(4)
    frame()
    frame()
    expect(toParent).toEqual([{ source: 'ph-charts', event: { type: 'ack', n: 12 } }])
  })
})
