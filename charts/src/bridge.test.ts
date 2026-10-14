import { beforeEach, describe, expect, it } from 'vitest'
import type { BodyNow, HostMessage } from './bridge'
import { dispatchForTests, latest, resetBridgeForTests, subscribe, viewFromLocation } from './bridge'
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
