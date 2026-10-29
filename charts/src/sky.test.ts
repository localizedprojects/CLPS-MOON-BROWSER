import { describe, expect, it } from 'vitest'
import {
  buildSky, crescentPoints, elToR, exportRPx, FULL_RANGE, labelBox, labelledRings, overlapArea, placeBodyLabels, ringLabelAz, ringValues,
  skyDynamic, skyHeader, skyRange, stateText, toXY, zoomRange,
} from './sky'
import type { Box } from './sky'
import type { BodyNow, SkyData } from './bridge'
import { skyGeom, skyOverlaySvg } from './skyOverlay'
import {
  captionLine, captionText, eclipsePct, exactLine, headerTime, highestHillsText, keyLine, markerLabel, pctShowing, stateOf,
} from './skyCaption'
import sky from './devdata/sky.json'
import skyH from './devdata/sky_haworth.json'
import skyNowDsn from './devdata/skyNow_dsn.json'

const body = (o: Partial<BodyNow> = {}): BodyNow => ({ az: 10, el: 1, rho: 0.27, frac: 1, hz: 0.2, visible: true, ...o })
const skyData = (now = { sun: body(), earth: body({ az: 200, visible: false, el: -3 }) }, o: Partial<SkyData> = {}): SkyData => ({
  siteName: 's', timeLabel: '2026-10-11 00:00 UTC', maskStepDeg: 90, mask: [0, 1, 0, 1], zoom: true, now,
  trails: { sun: { az: [1], el: [1] }, earth: { az: [2], el: [2] } }, ...o,
})
const SR1 = (sky as unknown as { data: SkyData }).data
const HAWORTH = (skyH as unknown as { data: SkyData }).data
const annTexts = (f: ReturnType<typeof buildSky>) => (f.layout.annotations as { text: string }[]).map((a) => a.text)
const svgLabels = (svg: string) => [...svg.matchAll(/<text data-label[^>]*>([^<]*)<\/text>/g)].map((m) => m[1])

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
    const f = buildSky(skyData(), { live: true, paths: true })
    const names = f.data.map((d) => d.name)
    expect(names).not.toContain('Sun now')
    expect(names).toContain('Where the Sun goes (whole period)')
    // only the fixed compass letters and the "hills" label are annotations; no ring labels, no header
    expect(annTexts(f).every((t) => /^(N|E|S|W|\d+°|hills)$/.test(t))).toBe(true)
  })
})

describe('sky simple view (charts spec 2.2)', () => {
  it('Simple: only the dashed 0° ring, N/E/S/W, no spokes, no legend, paths off by default', () => {
    const f = buildSky(SR1, { live: true })
    const rings = f.data.filter((d) => (d.line as { dash?: string })?.dash === 'dash' || (d.line as { dash?: string })?.dash === 'dot')
    expect(rings.length).toBe(1) // the flat horizon only (no dotted degree rings)
    expect(f.data.some((d) => Array.isArray(d.x) && (d.x as number[]).length === 2)).toBe(false) // no spokes
    expect(annTexts(f).filter((t) => t !== 'hills')).toEqual(['N', 'E', 'S', 'W'])
    expect(f.layout.showlegend).toBe(false)
    expect(f.data.map((d) => d.name)).not.toContain('Where the Sun goes (whole period)')
    const on = buildSky(SR1, { live: true, paths: true })
    const sunPath = on.data.find((d) => d.name === 'Where the Sun goes (whole period)') as { opacity: number }
    expect(sunPath.opacity).toBe(0.32)
    expect((on.data.find((d) => d.name === 'Where Earth goes (whole period)') as { line: { dash: string } }).line.dash).toBe('dot')
  })
  it('Exact: degree rings, 30° spokes with labels, paths on', () => {
    const f = buildSky(SR1, { live: true, exact: true })
    expect(annTexts(f)).toContain('30°')
    expect(f.data.filter((d) => Array.isArray(d.x) && (d.x as number[]).length === 2).length).toBe(12)
    expect(f.data.map((d) => d.name)).toContain('Where Earth goes (whole period)')
    const dyn = skyDynamic(SR1.now, f.range, 200, { exact: true, d: SR1 })
    expect(dyn.rings.length).toBeGreaterThan(1)
    expect(dyn.rings.length).toBeLessThanOrEqual(6)
    expect(skyDynamic(SR1.now, f.range, 200, { d: SR1 }).rings.map((r) => r.text)).toEqual(['0°'])
  })
  it('SR1 at 11 Oct 00:00: Sun up, look NNW, 1.6° above the hills; Earth below the horizon toward SSE', () => {
    const [sun, earth] = [captionLine('Sun', SR1.now.sun), captionLine('Earth', SR1.now.earth)]
    expect(captionText(sun)).toBe('Sun: up · look NNW · 1.6° above the hills')
    expect(captionText(earth)).toBe('Earth: below the horizon · toward SSE · 5.9° below the hills')
    expect(sun.counted).toBe(true)
    expect(earth.counted).toBe(false)
    for (const t of [captionText(sun), captionText(earth)]) expect(t).not.toMatch(/hidden by the terrain/)
  })
  it('the header time comes from Dart’s label, without weekday or leading zero, always with the year (charts-3, qa-1)', () => {
    expect(headerTime('2026-10-11 00:00 UTC')).toBe('11 Oct 2026 00:00')
    expect(headerTime('2027-02-07 06:30 UTC')).toBe('7 Feb 2027 06:30')
    expect(headerTime('odd label UTC')).toBe('odd label')
    // like the app's time label under the charts ("20 Oct 2026 19:00 UTC"): a period can cross New Year
    expect(headerTime('2027-01-21 00:30 UTC')).toBe('21 Jan 2027 00:30')
    expect(skyHeader({ siteName: 'SR1', timeLabel: '2028-02-07 06:30 UTC' }).time).toBe('7 Feb 2028 06:30 UTC')
  })
  it('every state word of the shared table', () => {
    expect(captionText(captionLine('Earth', body({ az: 0, state: 'partly', frac: 0.51, clear: 0.1 })))).toBe('Earth: partly up · toward N · 51% showing')
    expect(captionText(captionLine('Earth', body({ az: 0, visible: false, terrainVisible: true, state: 'noDsn' }))))
      .toBe('Earth: up, but no DSN dish can reach it · toward N')
    expect(captionText(captionLine('Sun', body({ az: 270, visible: false, frac: 0, el: 0.4, hz: 1.2, clear: -0.8, state: 'behindHills' }))))
      .toBe('Sun: behind the hills · toward W · 0.8° too low')
    expect(captionText(captionLine('Sun', body({ az: 90, visible: false, frac: 0.51, state: 'notCounted' }))))
      .toBe('Sun: 51% showing, not counted · toward E')
  })
  it('a lunar eclipse: Earth, not the hills, stops the Sun counting', () => {
    // total cover: Dart's state word is 'behindHills' (no disc showing), but the hills are below the Sun
    const total = body({ az: 90, visible: false, frac: 0, el: 3.9, hz: 1.9, clear: 2, state: 'behindHills', eclipse: 1, eclipseHides: true })
    expect(captionText(captionLine('Sun', total))).toBe('Sun: Earth hides it (lunar eclipse) · toward E · 2.0° above the hills')
    expect(captionText(captionLine('Sun', total))).not.toMatch(/behind the hills/)
    expect(markerLabel('Sun', total)).toBe('Sun · behind Earth')
    // a partial cover the Sun rule does not count: Earth's share, never "hides"
    const part = body({ az: 90, visible: false, frac: 0.6, el: 3.9, hz: 1.9, clear: 2, state: 'notCounted', eclipse: 0.4, eclipseHides: true })
    expect(captionText(captionLine('Sun', part))).toBe('Sun: Earth covers 40% of it (lunar eclipse), not counted · toward E · 2.0° above the hills')
    expect(markerLabel('Sun', part)).toBe('Sun · 40% behind Earth')
    expect(eclipsePct(0.002)).toBe(1)
    expect(eclipsePct(0.996)).toBe(99)
    // an eclipse the terrain decides (eclipseHides false): the hills' words stand
    const hills = body({ az: 270, visible: false, frac: 0, el: 0.4, hz: 1.2, clear: -0.8, state: 'behindHills', eclipse: 1, eclipseHides: false })
    expect(captionText(captionLine('Sun', hills))).toBe('Sun: behind the hills · toward W · 0.8° too low')
  })
  it('a counted body with clear < 0 reads "partly up", never a negative clearance', () => {
    const b = body({ az: 0, visible: true, frac: 0.6, el: 0.1, hz: 0.3, clear: -0.2, state: 'up' })
    const t = captionText(captionLine('Sun', b))
    expect(t).toBe('Sun: partly up · toward N · 60% showing')
    expect(t).not.toMatch(/below|too low|−/)
    expect(markerLabel('Sun', b)).toBe('Sun · 60% up')
  })
  it('falls back to the flags when an old payload has no state / clear', () => {
    expect(stateOf(body({ visible: false, frac: 0, el: -1, rho: 0.27 }))).toBe('belowHorizon')
    expect(stateOf(body({ visible: false, frac: 0, el: 0.5 }))).toBe('behindHills')
    expect(stateOf(body({ visible: false, terrainVisible: true }))).toBe('noDsn')
    expect(captionText(captionLine('Sun', body({ az: 337, el: 1.41, hz: -0.19 })))).toBe('Sun: up · look NNW · 1.6° above the hills')
    expect(pctShowing(0.9996)).toBe(100)
    expect(pctShowing(0.996)).toBe(99)
    expect(pctShowing(0.001)).toBe(1)
  })
  it('no marker label carries a signed number (Simple and Exact)', () => {
    const cases: BodyNow[] = [SR1.now.sun, SR1.now.earth, HAWORTH.now.sun, HAWORTH.now.earth,
      body({ el: -2.81, visible: false, frac: 0 }), body({ frac: 0.51, state: 'partly' }), body({ visible: false, terrainVisible: true, state: 'noDsn' })]
    for (const b of cases) for (const n of ['Sun', 'Earth'] as const) expect(markerLabel(n, b)).not.toMatch(/[-−+]?\d+(\.\d+)?°/)
    const g = { cx: 200, cy: 200, k: 160, left: 0 }
    for (const exact of [false, true]) {
      const svg = skyOverlaySvg(skyDynamic(SR1.now, skyRange(SR1), g.k, { exact, d: SR1 }), g)
      const labels = svgLabels(svg)
      expect(labels).toEqual(['Sun · up', 'Earth · below horizon'])
      for (const l of labels) expect(l).not.toMatch(/\d/)
    }
    expect(markerLabel('Earth', body({ frac: 0.51, state: 'partly' }))).toBe('Earth · 51% up')
    expect(markerLabel('Earth', body({ visible: false, terrainVisible: true, state: 'noDsn' }))).toBe('Earth · no DSN')
    expect(markerLabel('Sun', body({ visible: false, frac: 0, el: 0.4, hz: 1, state: 'behindHills' }))).toBe('Sun · behind hills')
  })
  it('the key line names LOLA and the stretch ("edge −9°, centre 8°" for SR1)', () => {
    const r = skyRange(SR1)
    expect(r).toEqual({ lo: -9, hi: 8 })
    const k = keyLine(SR1, r)
    expect(k).toContain('Grey = hills and crater rims (NASA LOLA map)')
    expect(k).toContain('Heights stretched: edge −9°, centre 8°.')
    expect(k).toContain('N = away from the pole')
    expect(k).toContain('Dashed ring = flat horizon (0°)')
    expect(keyLine({ ...SR1, zoom: false }, FULL_RANGE)).toContain('Whole sky: edge −10°, centre straight up')
  })
  it('maskApprox: "(coarse map, approximate)" in the key and "hills (approx.)" on the plot', () => {
    const d = { ...SR1, maskApprox: true }
    const r = skyRange(d)
    expect(keyLine(d, r)).toContain('(coarse map, approximate)')
    expect(keyLine(d, r)).not.toContain('LOLA')
    expect(annTexts(buildSky(d, { live: true }))).toContain('hills (approx.)')
    expect(annTexts(buildSky(SR1, { live: true }))).toContain('hills')
    expect(buildSky(d, { live: true, exact: true }).data.map((t) => t.name)).toContain('Hills and crater rims (coarse map, approximate)')
  })
  it('Exact block: azimuth, height, hills there, clearance, disc radius, % showing; highest hills', () => {
    expect(exactLine('Sun', SR1.now.sun)).toBe('Sun · azimuth 337.25° · height 1.41° · hills there −0.22° · clearance 1.63° · disc radius 0.27° · 100% showing')
    expect(exactLine('Earth', SR1.now.earth)).toContain('height −5.83°')
    expect(exactLine('Earth', SR1.now.earth)).toContain('disc radius 0.94°')
    expect(highestHillsText(SR1.mask)).toBe('Highest hills: 1.08°')
  })
  it('a skyNow changes only the overlay: the live figure does not depend on the shown time', () => {
    const later = { ...SR1, now: (skyNowDsn as unknown as { now: SkyData['now'] }).now, timeLabel: '2026-11-01 00:00 UTC' }
    const moved = { ...SR1, now: { sun: { ...SR1.now.sun, az: 10, el: 2 }, earth: { ...SR1.now.earth, az: 100 } } }
    for (const o of [{}, { exact: true }, { paths: true }]) {
      const a = buildSky(SR1, { live: true, ...o }), b = buildSky(moved, { live: true, ...o })
      expect(JSON.stringify(b.data)).toBe(JSON.stringify(a.data))
      expect(JSON.stringify(b.layout)).toBe(JSON.stringify(a.layout))
      expect(JSON.stringify(buildSky(later, { live: true, ...o }).data)).toBe(JSON.stringify(a.data))
    }
    const g = { cx: 200, cy: 200, k: 160, left: 0 }
    expect(skyOverlaySvg(skyDynamic(moved.now, skyRange(SR1), g.k, { d: SR1 }), g))
      .not.toBe(skyOverlaySvg(skyDynamic(SR1.now, skyRange(SR1), g.k, { d: SR1 }), g))
  })
  it('the PNG export carries the header, the caption lines, the key line and the paths', () => {
    const f = buildSky(SR1)
    const all = annTexts(f).join('\n')
    expect(all).toContain('<b>Where to look</b> · Shackleton rim (SR1)')
    expect(all).toContain('11 Oct 2026 00:00 UTC')
    expect(all).toContain('<b>Sun: up</b> · look NNW · 1.6° above the hills')
    expect(all).toContain('Heights stretched: edge −9°,')
    expect(all).toContain('NASA LOLA')
    expect(f.data.map((d) => d.name)).toContain('Where the Sun goes (whole period)')
    expect(f.data.map((d) => d.name)).toContain('Where Earth goes (whole period)')
    expect(all).toContain("Sun's path") // Simple export names the paths on the plot
    expect(f.layout.showlegend).toBe(false)
    expect(all).not.toContain('azimuth')
    const ex = buildSky(SR1, { exact: true })
    const exAll = annTexts(ex).join('\n')
    expect(exAll).toContain('Sun · azimuth 337.25°')
    expect(exAll).toContain('Highest hills: 1.08°')
    expect(exAll).toContain('in full sunlight')
    expect(ex.layout.showlegend).toBe(true)
  })
})

describe('sky labels (android-6, web-10)', () => {
  it('ring labels go on the diagonal farthest from both bodies', () => {
    expect(ringLabelAz(40, 50)).toBe(225)
    expect(ringLabelAz(135, 315)).toBe(45)
    for (let s = 0; s < 360; s += 7) {
      for (let e = 0; e < 360; e += 11) {
        for (const h of [undefined, 0, 100, 225]) {
          const a = ringLabelAz(s, e, h)
          const d = (x: number) => { const v = Math.abs(((a - x) % 360 + 360) % 360); return Math.min(v, 360 - v) }
          expect(Math.min(d(s), d(e))).toBeGreaterThanOrEqual(45 - 1e-9)
        }
      }
    }
  })
  it('body labels never overlap the ring labels, the other label or the azimuth letters', () => {
    // Malapert peak case from the report: Sun 2.14° near the 2° ring, Earth close by
    const range = { lo: -4, hi: 7 }
    for (const exact of [false, true]) {
      for (const rPx of [110, 160, 300]) {
        for (let az = 0; az < 360; az += 15) {
          const now = { sun: body({ az, el: 2.14 }), earth: body({ az: az + 20, el: 4.49 }) }
          const dyn = skyDynamic(now, range, rPx, { exact })
          const boxes = [dyn.sun, dyn.earth].map((b) => labelBox(b.x * rPx, b.y * rPx, b.text.length, b.pos))
          expect(overlapArea(boxes[0], boxes[1])).toBe(0)
          for (const r of dyn.rings) {
            const rb = { x0: r.x * rPx, x1: r.x * rPx + r.text.length * 6.6 + 2, y0: r.y * rPx - 7, y1: r.y * rPx + 7 }
            for (const b of boxes) expect(overlapArea(b, rb)).toBe(0)
          }
        }
      }
    }
  })
  it('a label near the W letter moves off it', () => {
    const range = { lo: -4, hi: 7 }, rPx = 160
    const dyn = skyDynamic({ sun: body({ az: 268, el: -2.39, visible: false, frac: 0 }), earth: body({ az: 10, el: 3 }) }, range, rPx)
    const b = labelBox(dyn.sun.x * rPx, dyn.sun.y * rPx, dyn.sun.text.length, dyn.sun.pos)
    const wx = -1.09 * rPx, w: Box = { x0: wx - 4.4, x1: wx + 4.4, y0: -8, y1: 8 }
    expect(overlapArea(b, w)).toBe(0)
  })
  it('places a single label away from an obstacle', () => {
    const [p] = placeBodyLabels([{ x: 0, y: 0, text: 'Sun · up' }], [{ x0: -40, x1: 40, y0: 10, y1: 30 }], { x0: -500, x1: 500, y0: -500, y1: 500 })
    expect(p).not.toBe('top center')
  })
  it('labels only every other ring when there are many', () => {
    expect(labelledRings({ lo: -10, hi: 5 }).length).toBeLessThanOrEqual(6)
  })
  it('path names sit on the path and never on a marker, a marker label, the hills label or a compass letter', () => {
    for (const d of [SR1, HAWORTH]) {
      const range = skyRange(d)
      for (const rPx of [150, 200, exportRPx()]) {
        for (let shift = 0; shift < 360; shift += 45) {
          const now = { sun: { ...d.now.sun, az: (d.now.sun.az + shift) % 360 }, earth: { ...d.now.earth, az: (d.now.earth.az + shift) % 360 } }
          const dyn = skyDynamic(now, range, rPx, { paths: true, d })
          expect(dyn.paths.length).toBeGreaterThan(0)
          const avoid: Box[] = []
          for (const b of [dyn.sun, dyn.earth]) {
            avoid.push({ x0: b.x * rPx - 14, x1: b.x * rPx + 14, y0: b.y * rPx - 14, y1: b.y * rPx + 14 })
            avoid.push(labelBox(b.x * rPx, b.y * rPx, b.text.length, b.pos))
          }
          const nb = (p: { x: number; y: number; text: string }) => {
            const w = p.text.length * 7 + 4
            return { x0: p.x * rPx - w / 2, x1: p.x * rPx + w / 2, y0: p.y * rPx - 8, y1: p.y * rPx + 8 }
          }
          for (const p of dyn.paths) for (const a of avoid) expect(overlapArea(nb(p), a)).toBe(0)
          if (dyn.paths.length === 2) expect(overlapArea(nb(dyn.paths[0]), nb(dyn.paths[1]))).toBe(0)
        }
      }
      // Exact names the paths in the legend instead
      expect(skyDynamic(d.now, range, 200, { exact: true, paths: true, d }).paths).toEqual([])
    }
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
  it('draws both markers, word labels and ring labels (open = blocked)', () => {
    const g = skyGeom(gd as never)!
    const svg = skyOverlaySvg(skyDynamic(skyData().now, { lo: -3, hi: 6 }, g.k, { exact: true }), g)
    expect(svg).toContain('data-body="Sun"')
    expect(svg).toContain('data-body="Earth"')
    expect(svg).toContain('Sun · up')
    expect(svg).toMatch(/<g fill="none" stroke="#3D8BFD"[^>]*><circle[^>]*fill="none"\/><path data-crescent/) // blocked Earth: hollow crescent disc
    expect(svg).not.toMatch(/<path d="M[^"]*L[^"]*L[^"]*L[^"]*Z"\/>/) // no 4-point diamond (ux2-5)
    expect((svg.match(/°<\/text>/g) ?? []).length).toBeGreaterThanOrEqual(4)
    // Simple: the "0°" label only
    const simple = skyOverlaySvg(skyDynamic(skyData().now, { lo: -3, hi: 6 }, g.k), g)
    expect((simple.match(/°<\/text>/g) ?? []).length).toBe(1)
    expect(simple).toContain('>0°</text>')
  })
  it('each marker keeps a <title> with the exact values and Dart’s sentence', () => {
    const svg = skyOverlaySvg(skyDynamic(SR1.now, skyRange(SR1), 160, { d: SR1 }), { cx: 200, cy: 200, k: 160, left: 0 })
    expect(svg).toContain('<title>Sun: azimuth 337.25°, elevation 1.41°, terrain horizon -0.22°')
    expect(svg).toContain('in full sunlight</title>')
    expect(svg).toContain('disc radius 0.94°')
  })
})

describe('sky state words (science-1, science-2)', () => {
  it('says why a body that is up is not counted (fallback without Dart’s sentence)', () => {
    expect(stateText(body())).toBe('visible')
    expect(stateText(body({ frac: 0.4 }))).toBe('partly visible (40%)')
    // Earth fully up, rejected only by the DSN check
    expect(stateText(body({ visible: false, terrainVisible: true }))).toBe('in view, but no DSN station can see the Moon')
    // 97.6% of the Sun's disk up under the whole-disk rule: not "below terrain horizon"
    expect(stateText(body({ visible: false, frac: 0.976 }))).toBe('98% above the skyline, not counted under the current rule')
    expect(stateText(body({ visible: false, frac: 0.9996 }))).toContain('99% above the skyline')
    expect(stateText(body({ visible: false, frac: 0 }))).toBe('below terrain horizon')
  })

  it('the marker hover never reads 0% or 100% for a partly showing disc, like the caption (pre-new-1)', () => {
    expect(stateText(body({ frac: 0.0036 }))).toBe('partly visible (1%)')
    expect(stateText(body({ frac: 0.9978 }))).toBe('partly visible (99%)')
    for (const [frac, want] of [[0.0036, '1% showing'], [0.9978, '99% showing']] as const) {
      const now = { ...SR1.now, sun: { ...SR1.now.sun, visible: true, frac, state: 'partly' as const, clear: -0.1 } }
      const dyn = skyDynamic(now, skyRange(SR1), 200, { d: SR1 })
      expect(dyn.sun.title).toContain(`, ${want}.`)
    }
  })
})
