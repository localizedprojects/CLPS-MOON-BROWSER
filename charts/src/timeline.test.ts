import { describe, expect, it } from 'vitest'
import { buildHeights, HEIGHT_NAMES, totalHours, totalsLine, wrapLabel } from './timeline'
import type { TimelineData } from './bridge'
import { clickTimeMs, plotAxes } from './plotGeom'

describe('timeline Heights figure (Exact numbers)', () => {
  const runs: [number, number][] = [[Date.UTC(2027, 0, 1), Date.UTC(2027, 0, 1, 6)], [Date.UTC(2027, 0, 2), Date.UTC(2027, 0, 2, 3)]]
  const curve = (y: number[]) => ({ t: y.map((_, i) => i * 3600e3), y })
  const tl = (o: Partial<TimelineData> = {}): TimelineData => ({
    siteName: 's', curves: { sunEl: curve([1, 2]), earthEl: curve([0, 1]), sunHz: curve([0, 0]), earthHz: curve([0, 0, 0]) },
    runs: { sun: runs, earth: [], both: [] }, range: [0, 7200e3], cursor: 3600e3, earthLabel: 'Earth contact (DSN)', ...o,
  })
  it('draws the four renamed curves, each on its own decimated time axis', () => {
    const f = buildHeights(tl())
    expect(f.data.map((d) => d.name)).toEqual([HEIGHT_NAMES.sunEl, HEIGHT_NAMES.sunHz, HEIGHT_NAMES.earthEl, HEIGHT_NAMES.earthHz])
    expect(HEIGHT_NAMES).toEqual({ sunEl: 'Sun height', sunHz: 'Hills toward the Sun', earthEl: 'Earth height', earthHz: 'Hills toward Earth' })
    const hz = f.data.find((d) => d.name === 'Hills toward Earth') as { x: string[]; line: { dash: string } }
    expect(hz.x.length).toBe(3)
    expect(hz.line.dash).toBe('dashdot')
    expect((f.data[1] as { line: { dash: string } }).line.dash).toBe('dot')
    expect(String(f.data[0].hovertemplate)).toContain('%{y:.2f}°')
  })
  it('titles the y axis, puts the legend below and drops the colliding end labels', () => {
    const f = buildHeights(tl(), { narrow: true })
    const y = f.layout.yaxis as { title: { text: string } }
    expect(y.title.text).toBe('HEIGHT ABOVE FLAT (°)')
    const lg = f.layout.legend as { y: number; yanchor: string }
    expect(lg.y).toBeLessThan(0)
    expect(lg.yanchor).toBe('top')
    expect(f.layout.annotations).toBeUndefined()
  })
  it('the export figure has a cursor; the live figure leaves it to the DOM line', () => {
    expect((buildHeights(tl()).layout.shapes as unknown[]).length).toBe(1)
    expect((buildHeights(tl(), { live: true }).layout.shapes as unknown[]).length).toBe(0)
  })
  it('follows the strip window on the x axis', () => {
    const f = buildHeights(tl(), { window: [0, 3600e3] })
    expect((f.layout.xaxis as { range: string[] }).range).toEqual(['1970-01-01 00:00:00', '1970-01-01 01:00:00'])
  })
  it('totals line: hours and run counts, with the Earth label from the host (science-3)', () => {
    expect(totalHours(runs)).toBe(9)
    expect(totalsLine(tl())).toBe('Sunlight 9 h in 2 spells · Earth contact (DSN) 0 h in 0 · Sun + Earth 0 h in 0 windows')
    expect(wrapLabel('Earth contact (DSN)', 12)).toBe('Earth contact<br>(DSN)')
  })
})

describe('timeline click (web-1)', () => {
  // x axis: 100 px offset, 600 px long, 1 px = 1 hour from t=0
  const gd = {
    _fullLayout: { xaxis: { _offset: 100, _length: 600, l2p: (v: number) => v / 3600e3, p2l: (p: number) => p * 3600e3 } },
    getBoundingClientRect: () => ({ left: 10 }) as DOMRect,
  }
  it('seeks to the clicked time, not to the end of the clicked bar', () => {
    // the strip reports the bar end (base + duration) as the point's x
    const e = { event: { clientX: 10 + 100 + 250 }, points: [{ x: '2027-01-14 00:00:00', data: { type: 'bar' } }] }
    expect(clickTimeMs(gd as never, e)).toBe(250 * 3600e3)
  })
  it('falls back to a line point, never a bar end, without a pointer position', () => {
    expect(clickTimeMs(gd as never, { points: [{ x: '2027-01-14 00:00:00', data: { type: 'bar' } }] })).toBeNull()
    expect(clickTimeMs(gd as never, { points: [{ x: '2026-10-24 03:00:00', data: { type: 'scatter' } }] })).toBe(Date.UTC(2026, 9, 24, 3))
  })
  it('ignores clicks outside the axis', () => {
    expect(clickTimeMs(gd as never, { event: { clientX: 10 + 50 } })).toBeNull()
  })
  it('plotAxes is null before the first draw', () => {
    expect(plotAxes(null)).toBeNull()
    expect(plotAxes({ _fullLayout: { xaxis: gd._fullLayout.xaxis } } as never)).toBeNull()
  })
})
