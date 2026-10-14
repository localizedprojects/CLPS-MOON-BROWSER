// The CLASSIC sky plot and timeline (the default on Sky & time, restored at the
// user's request on 2026-10-12): their former charts.test.ts
// cases, plus the later fixes they keep and the Simple view switch.
import { beforeEach, describe, expect, it } from 'vitest'
import {
  buildSky, crescentPoints, elToR, FULL_RANGE, labelBox, labelledRings, placeBodyLabels, ringLabelAz, ringValues, skyDynamic, skyMarginTop,
  SKY_MARGIN_TOP, stateText, toXY, zoomRange,
} from './skyClassic'
import type { Box } from './skyClassic'
import { buildTimeline, lanes, runsToBars, totalHours, wrapLabel } from './timelineClassic'
import type { BodyNow, TimelineData } from './bridge'
import { dispatchForTests, resetBridgeForTests } from './bridge'
import { skyGeom, skyHeaderHtml, skyOverlaySvg } from './skyClassicOverlay'
import { simpleOn, viewKind } from './viewPick'

const body = (o: Partial<BodyNow> = {}): BodyNow => ({ az: 10, el: 1, rho: 0.27, frac: 1, hz: 0.2, visible: true, ...o })
const skyData = (now = { sun: body(), earth: body({ az: 200, visible: false }) }) => ({
  siteName: 's', timeLabel: 't', maskStepDeg: 90, mask: [0, 1, 0, 1], zoom: true, now,
  trails: { sun: { az: [1], el: [1] }, earth: { az: [2], el: [2] } },
})

function overlapArea(a: Box, b: Box): number {
  const w = Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0)
  const h = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0)
  return w > 0 && h > 0 ? w * h : 0
}

describe('sky geometry', () => {
  it('maps elevation to radius (centre = top of range)', () => {
    expect(elToR(90, FULL_RANGE)).toBe(0)
    expect(elToR(-10, FULL_RANGE)).toBe(1)
    expect(elToR(-50, FULL_RANGE)).toBe(1) // clamped
  })
  it('north is up and east is right', () => {
    const r = { lo: -5, hi: 10 }
    const [xn, yn] = toXY(0, 0, r)
    const [xe, ye] = toXY(90, 0, r)
    expect(xn).toBeCloseTo(0)
    expect(yn).toBeGreaterThan(0)
    expect(xe).toBeGreaterThan(0)
    expect(ye).toBeCloseTo(0)
  })
  it('zoom range covers mask and bodies', () => {
    const r = zoomRange([-2, 4.5], [1.2], [-6.5])
    expect(r.lo).toBeLessThanOrEqual(-7.5)
    expect(r.hi).toBeGreaterThanOrEqual(5.5)
    expect(ringValues(r).length).toBeGreaterThan(2)
  })
  it('zoom range survives very long trails (no argument-spread overflow)', () => {
    const big = Array.from({ length: 200000 }, (_, i) => Math.sin(i))
    expect(zoomRange([0], big, big).hi).toBeGreaterThan(1)
  })
  it('the complete figure (export) has terrain, trails and both bodies', () => {
    const f = buildSky(skyData())
    const names = f.data.map((d) => d.name)
    expect(names).toContain('Sun now')
    expect(names).toContain('Earth now')
    const earth = f.data.find((d) => d.name === 'Earth now') as { marker: { symbol: string; color: string } }
    expect(earth.marker.symbol).toBe('circle') // Earth is never the "both" diamond (ux2-5)
    expect(earth.marker.color).toBe('rgba(0,0,0,0)') // blocked -> hollow
    const cres = f.data.find((d) => d.name === 'Earth crescent') as { fillcolor: string; x: number[] }
    expect(cres.fillcolor).toBe('rgba(0,0,0,0)')
    expect(cres.x.length).toBeGreaterThan(10)
    const sun = f.data.find((d) => d.name === 'Sun now') as { marker: { symbol: string } }
    expect(sun.marker.symbol).toBe('circle')
    const lit = buildSky(skyData({ sun: body(), earth: body({ az: 200 }) }))
    expect((lit.data.find((d) => d.name === 'Earth crescent') as { fillcolor: string }).fillcolor).toBe('#3D8BFD')
  })
  it('Earth crescent: a closed outline inside the unit disc, lit on the left (ux2-5)', () => {
    const pts = crescentPoints()
    for (const [x, y] of pts) expect(Math.hypot(x, y)).toBeLessThanOrEqual(1 + 1e-9)
    expect(Math.min(...pts.map((q) => q[0]))).toBeCloseTo(-1)
    expect(Math.max(...pts.map((q) => q[0]))).toBeLessThan(0.3)
  })
  it('the live figure leaves the cursor-dependent part to the overlay', () => {
    const f = buildSky(skyData(), { live: true })
    const names = f.data.map((d) => d.name)
    expect(names).not.toContain('Sun now')
    expect(names).toContain('Sun path (period)')
    // only the fixed azimuth labels are annotations; no ring labels, no header
    const ann = f.layout.annotations as { text: string }[]
    expect(ann.every((a) => /^(N|E|S|W|\d+°)$/.test(a.text))).toBe(true)
  })
})

describe('sky labels (android-6, web-10)', () => {
  it('ring labels go on the diagonal farthest from both bodies', () => {
    expect(ringLabelAz(40, 50)).toBe(225)
    expect(ringLabelAz(135, 315)).toBe(45)
    for (let s = 0; s < 360; s += 7) {
      for (let e = 0; e < 360; e += 11) {
        const a = ringLabelAz(s, e)
        const d = (x: number) => { const v = Math.abs(((a - x) % 360 + 360) % 360); return Math.min(v, 360 - v) }
        expect(Math.min(d(s), d(e))).toBeGreaterThanOrEqual(45 - 1e-9)
      }
    }
  })
  it('body labels never overlap the ring labels, the other label or the azimuth letters', () => {
    // Malapert peak case from the report: Sun 2.14° near the 2° ring, Earth close by
    const range = { lo: -4, hi: 7 }
    for (const rPx of [110, 160, 300]) {
      for (let az = 0; az < 360; az += 15) {
        const now = { sun: body({ az, el: 2.14 }), earth: body({ az: az + 20, el: 4.49 }) }
        const dyn = skyDynamic(now, range, rPx)
        const boxes = [dyn.sun, dyn.earth].map((b) => labelBox(b.x * rPx, b.y * rPx, b.text.length, b.pos))
        expect(overlapArea(boxes[0], boxes[1])).toBe(0)
        for (const r of dyn.rings) {
          const rb = { x0: r.x * rPx, x1: r.x * rPx + r.text.length * 6.6 + 2, y0: r.y * rPx - 7, y1: r.y * rPx + 7 }
          for (const b of boxes) expect(overlapArea(b, rb)).toBe(0)
        }
      }
    }
  })
  it('a label near the W letter moves off it', () => {
    const range = { lo: -4, hi: 7 }, rPx = 160
    const dyn = skyDynamic({ sun: body({ az: 268, el: -2.39 }), earth: body({ az: 10, el: 3 }) }, range, rPx)
    const b = labelBox(dyn.sun.x * rPx, dyn.sun.y * rPx, dyn.sun.text.length, dyn.sun.pos)
    const wx = -1.09 * rPx, w: Box = { x0: wx - 4.4, x1: wx + 4.4, y0: -8, y1: 8 }
    expect(overlapArea(b, w)).toBe(0)
  })
  it('places a single label away from an obstacle', () => {
    const [p] = placeBodyLabels([{ x: 0, y: 0, text: 'Sun 1.00°' }], [{ x0: -40, x1: 40, y0: 10, y1: 30 }], { x0: -500, x1: 500, y0: -500, y1: 500 })
    expect(p).not.toBe('top center')
  })
  it('labels only every other ring when there are many', () => {
    expect(labelledRings({ lo: -10, hi: 5 }).length).toBeLessThanOrEqual(6)
  })
})

describe('sky overlay', () => {
  const gd = {
    _fullLayout: {
      xaxis: { _offset: 20, _length: 300, l2p: (v: number) => 150 + v * 100, p2l: (p: number) => (p - 150) / 100 },
      yaxis: { _offset: 62, _length: 300, l2p: (v: number) => 150 - v * 100, p2l: (p: number) => (150 - p) / 100 },
      _size: { l: 20, r: 20, t: 62, b: 20, w: 300, h: 300 },
    },
  }
  it('reads the plot centre and scale from the drawn figure', () => {
    expect(skyGeom(gd as never)).toEqual({ cx: 170, cy: 212, k: 100, left: 20 })
    expect(skyGeom(null)).toBeNull()
    expect(skyGeom({ _fullLayout: {} } as never)).toBeNull()
  })
  it('draws both markers, labels and ring labels (open = blocked)', () => {
    const g = skyGeom(gd as never)!
    const svg = skyOverlaySvg(skyDynamic(skyData().now, { lo: -3, hi: 6 }, g.k), g)
    expect(svg).toContain('data-body="Sun"')
    expect(svg).toContain('data-body="Earth"')
    expect(svg).toContain('Sun 1.00°')
    expect(svg).toMatch(/<g fill="none" stroke="#3D8BFD"[^>]*><circle[^>]*fill="none"\/><path data-crescent/) // blocked Earth: hollow crescent disc
    expect(svg).not.toMatch(/<path d="M[^"]*L[^"]*L[^"]*L[^"]*Z"\/>/) // no 4-point diamond (ux2-5)
    expect((svg.match(/°<\/text>/g) ?? []).length).toBeGreaterThanOrEqual(4)
  })
})

describe('sky state words (science-1, science-2)', () => {
  it('says why a body that is up is not counted', () => {
    expect(stateText(body())).toBe('visible')
    expect(stateText(body({ frac: 0.4 }))).toBe('partly visible (40%)')
    // Earth fully up, rejected only by the DSN check
    expect(stateText(body({ visible: false, terrainVisible: true }))).toBe('in view, but no DSN station can see the Moon')
    // 97.6% of the Sun's disk up under the whole-disk rule: not "below terrain horizon"
    expect(stateText(body({ visible: false, frac: 0.976 }))).toBe('98% above the skyline, not counted under the current rule')
    expect(stateText(body({ visible: false, frac: 0.9996 }))).toContain('99% above the skyline')
    expect(stateText(body({ visible: false, frac: 0 }))).toBe('below terrain horizon')
  })
})

describe('timeline', () => {
  const runs: [number, number][] = [[Date.UTC(2027, 0, 1), Date.UTC(2027, 0, 1, 6)], [Date.UTC(2027, 0, 2), Date.UTC(2027, 0, 2, 3)]]
  const curve = (y: number[]) => ({ t: y.map((_, i) => i * 3600e3), y })
  const tl = (o: Partial<TimelineData> = {}): TimelineData => ({
    siteName: 's', curves: { sunEl: curve([1, 2]), earthEl: curve([0, 1]), sunHz: curve([0, 0]), earthHz: curve([0, 0, 0]) },
    runs: { sun: runs, earth: [], both: [] }, range: [0, 7200e3], cursor: 3600e3, earthLabel: 'Earth contact (DSN)', ...o,
  })
  it('converts runs to Gantt bars with UTC bases and ms durations', () => {
    const b = runsToBars(runs, 'Both', '#0f0', '/') as { base: string[]; x: number[]; marker: { pattern: { shape: string } } }
    expect(b.base[0]).toBe('2027-01-01 00:00:00')
    expect(b.x[0]).toBe(6 * 3600e3)
    expect(b.marker.pattern.shape).toBe('/')
    expect(totalHours(runs)).toBe(9)
  })
  it('draws each decimated curve on its own time axis', () => {
    const f = buildTimeline(tl())
    expect(f.data.length).toBe(7)
    const hz = f.data.find((d: Record<string, unknown>) => d.name === 'Skyline under Earth') as { x: string[] }
    expect(hz.x.length).toBe(3)
  })
  it('the export figure has a cursor; the live figure leaves it to the DOM line', () => {
    expect((buildTimeline(tl()).layout.shapes as unknown[]).length).toBe(1)
    expect((buildTimeline(tl(), { live: true }).layout.shapes as unknown[]).length).toBe(0)
  })

  it('zooms only full screen (the focus view): drag across time, keep the zoom across updates', () => {
    type Ax = { fixedrange?: boolean }
    const page = buildTimeline(tl()).layout
    expect(page.dragmode).toBe(false)
    expect((page.xaxis as Ax).fixedrange).toBe(true)
    expect(page.uirevision).toBeUndefined()
    const focus = buildTimeline(tl(), { live: true, zoom: true }).layout
    expect(focus.dragmode).toBe('zoom')
    expect((focus.xaxis as Ax).fixedrange).toBe(false)
    expect((focus.yaxis as Ax).fixedrange).toBe(true)
    expect((focus.yaxis2 as Ax).fixedrange).toBe(true)
    expect(focus.uirevision).toBe('focus')
  })
  it('labels the Earth lane with the metric label from the host (science-3)', () => {
    expect(lanes('Earth contact (DSN)')).toContain('Earth contact (DSN)')
    const f = buildTimeline(tl())
    const ann = f.layout.annotations as { text: string }[]
    expect(ann.some((a) => a.text.includes('Earth contact (DSN)'))).toBe(true)
  })
  it('keeps the totals inside the plot and wraps them on phones (web-10)', () => {
    const totals = (buildTimeline(tl(), { narrow: true }).layout.annotations as { text: string; x: number; xanchor: string }[])
      .find((a) => a.text.startsWith('Sun '))!
    expect(totals.x).toBe(0)
    expect(totals.xanchor).toBe('left')
    expect(totals.text).toContain('<br>')
    // each line fits a 320 px phone (about 30 characters at 11 px)
    for (const line of totals.text.split('<br>')) expect(line.length).toBeLessThanOrEqual(30)
    expect(wrapLabel('Earth contact (DSN)', 12)).toBe('Earth contact<br>(DSN)')
  })
})

describe('later fixes kept by the classic charts', () => {
  it('a partly visible disc never reads 0% or 100% (pctShowing)', () => {
    expect(stateText(body({ frac: 0.9985 }))).toBe('partly visible (99%)')
    expect(stateText(body({ frac: 0.001 }))).toBe('partly visible (1%)')
    expect(stateText(body({ visible: false, frac: 0.0004 }))).toBe('1% above the skyline, not counted under the current rule')
  })
  it('the header shows the site name in full and the year, wrapping instead of an ellipsis', () => {
    const g = { cx: 0, cy: 0, k: 100, left: 8 }
    const html = skyHeaderHtml({ siteName: 'Connecting ridge extension (CRX)', timeLabel: '2026-10-20 19:00 UTC', zoom: true }, { lo: -3, hi: 6 }, g)
    expect(html).toContain('Connecting ridge extension (CRX)')
    expect(html).toContain('2026-10-20 19:00 UTC')
    expect(html).not.toContain('ellipsis')
    expect(html).toContain('flex-wrap:wrap')
    // a long name on a phone gets one header line more above the plot
    expect(skyMarginTop('Connecting ridge extension (CRX)', true)).toBeGreaterThan(SKY_MARGIN_TOP)
    expect(skyMarginTop('Shackleton rim (SR1)', true)).toBe(SKY_MARGIN_TOP)
  })
  it("the timeline legend names the skylines 'Skyline under the Sun / Earth'", () => {
    const curve = (y: number[]) => ({ t: y.map((_, i) => i * 3600e3), y })
    const f = buildTimeline({ siteName: 's', curves: { sunEl: curve([1]), earthEl: curve([1]), sunHz: curve([0]), earthHz: curve([0]) },
      runs: { sun: [], earth: [], both: [] }, range: [0, 3600e3], cursor: 0, earthLabel: 'Earth in view' })
    const names = f.data.map((d: Record<string, unknown>) => d.name)
    expect(names).toContain('Skyline under the Sun')
    expect(names).toContain('Skyline under Earth')
  })
})

describe('Simple view switch (default off: the classic charts)', () => {
  beforeEach(() => resetBridgeForTests())
  it('shows the classic sky plot and timeline by default', () => {
    expect(simpleOn()).toBe(false)
    expect(viewKind('sky', simpleOn())).toBe('classicSky')
    expect(viewKind('timeline', simpleOn())).toBe('classicTimeline')
  })
  it("the host's switch shows the simple views; off again brings the classic charts back", () => {
    dispatchForTests({ type: 'simple', on: true })
    expect(simpleOn()).toBe(true)
    expect(viewKind('sky', simpleOn())).toBe('sky')
    expect(viewKind('timeline', simpleOn())).toBe('timeline')
    dispatchForTests({ type: 'simple', on: false })
    expect(viewKind('sky', simpleOn())).toBe('classicSky')
  })
  it('Compare keeps its new chart either way', () => {
    expect(viewKind('compare', false)).toBe('compare')
    expect(viewKind('compare', true)).toBe('compare')
  })
})
