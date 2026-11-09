/**
 * 1.14.0 "Whole Moon": the sky plot for sites outside the south pole, and the
 * guard that the polar figures are unchanged (plan §7 WP4, guard G7).
 *
 * Global sites differ from polar ones in two ways the charts see:
 * - the payload carries `northNote` ("N = toward the north pole"), chosen in
 *   Dart (chart_hub.dart) for global sites only; polar payloads never carry it;
 * - the Sun climbs high (up to about 90° near the equator) and sinks deep at
 *   night, so a horizon zoom over the period's paths would be wider than the
 *   whole sky: the plot then shows the whole sky ([skyRange]).
 */
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'
import type { BodyNow, SkyData } from './bridge'
import { BASELINE_TIME, polarBaseline } from './polarBaseline'
import { buildSky, elToR, FULL_RANGE, skyDynamic, skyRange, toXY, zoomRange } from './sky'
import { isWholeSky, keyLine, northText, scaleText, ZOOM_MAX_BODY_DEG, zoomFits } from './skyCaption'
import * as classic from './skyClassic'
import baseline from './devdata/polar_baseline_1135.json'
import sky from './devdata/sky.json'
import skyH from './devdata/sky_haworth.json'

describe('the polar figures equal the 1.13.5 baseline (guard G7)', () => {
  beforeAll(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date(BASELINE_TIME))
  })
  afterAll(() => {
    vi.useRealTimers()
  })

  it('was taken at 1.13.5 under the same clock', () => {
    expect(baseline.meta.capturedAt).toBe('85c472f (1.13.5)')
    expect(baseline.meta.systemTime).toBe(BASELINE_TIME)
    expect(new Date().toISOString()).toBe('2026-11-14T06:00:00.000Z')
  })

  it('every polar payload gives the same figures and texts', () => {
    const now = polarBaseline() as Record<string, unknown>
    const want = baseline.entries as Record<string, unknown>
    expect(Object.keys(now)).toEqual(Object.keys(want))
    for (const k of Object.keys(want)) expect(now[k], k).toEqual(want[k])
  })

  it('no polar dev payload carries northNote', () => {
    for (const [f, m] of [['sky.json', sky], ['sky_haworth.json', skyH]] as const) {
      expect((m as unknown as { data: SkyData }).data.northNote, f).toBeUndefined()
      expect(Object.keys((m as unknown as { data: SkyData }).data), f).not.toContain('northNote')
    }
  })
})

/** A BodyNow with defaults. */
const body = (o: Partial<BodyNow> = {}): BodyNow => ({ az: 10, el: 1, rho: 0.27, frac: 1, hz: 0.2, visible: true, ...o })

/**
 * A synthetic global sky payload (not real data, never bundled): a near-side
 * site near the equator, the Sun at 85° now, its path over a lunar day from
 * −88° to 89°, Earth high in the sky, and gentle hills.
 */
export function globalSky(o: Partial<SkyData> = {}): SkyData {
  const n = 72
  const sunAz: number[] = [], sunEl: number[] = [], earthAz: number[] = [], earthEl: number[] = []
  for (let i = 0; i < n; i++) {
    sunAz.push((i * 5) % 360)
    sunEl.push(89 * Math.sin((i / n) * 2 * Math.PI) - (i > n / 2 ? 0.5 : 0))
    earthAz.push(170 + 10 * Math.sin(i / 7))
    earthEl.push(82 + 6 * Math.cos(i / 5))
  }
  return {
    siteName: 'Synthetic equator site',
    timeLabel: '2026-11-14 06:00 UTC',
    refMs: Date.UTC(2026, 9, 1),
    maskStepDeg: 10,
    mask: Array.from({ length: 36 }, (_, i) => 0.8 + 0.6 * Math.sin(i / 3)),
    now: { sun: body({ az: 95, el: 85, hz: 0.9 }), earth: body({ az: 175, el: 84, rho: 0.95, hz: 0.5 }) },
    trails: { sun: { az: sunAz, el: sunEl }, earth: { az: earthAz, el: earthEl } },
    zoom: true,
    northNote: 'N = toward the north pole',
    ...o,
  }
}

const SR1 = (sky as unknown as { data: SkyData }).data
const HAWORTH = (skyH as unknown as { data: SkyData }).data
const NORTH = 'N = toward the north pole'
const annTexts = (f: { layout: Record<string, unknown> }) => ((f.layout.annotations ?? []) as { text: string }[]).map((a) => a.text)

describe('northNote: what "N" means at sites outside the south pole', () => {
  it('the key line and the classic header print it; the polar text stays otherwise', () => {
    const g = globalSky()
    const r = skyRange(g)
    expect(keyLine(g, r)).toContain('Closer to the centre = higher. N = toward the north pole. Whole sky')
    expect(keyLine(g, r)).not.toContain('away from the pole')
    expect(northText(g)).toBe(NORTH)
    expect(classic.skyHeader(g, classic.skyRange(g)).orient).toBe(NORTH)
    // polar payloads (no northNote): today's words
    expect(northText(SR1)).toBe('N = away from the pole')
    expect(keyLine(SR1, skyRange(SR1))).toContain('Closer to the centre = higher. N = away from the pole. Heights stretched')
    expect(classic.skyHeader(SR1, classic.skyRange(SR1)).orient).toBe('N points away from the pole')
    expect(classic.skyHeader(HAWORTH, classic.skyRange(HAWORTH)).orient).toBe('N points away from the pole')
  })

  it('reaches the exported figure and the classic figure', () => {
    const g = globalSky()
    const exported = annTexts(buildSky(g, { exact: true })).join('\n')
    expect(exported).toContain('N = toward the north pole.')
    expect(exported).not.toContain('away from the pole')
    const cl = annTexts(classic.buildSky(g)).join('\n')
    expect(cl).toContain(NORTH)
    expect(cl).not.toContain('away from the pole')
  })

  it('an empty note is still the payload\'s own (Dart sends it or leaves it out)', () => {
    expect(northText({ northNote: undefined })).toBe('N = away from the pole')
  })
})

describe('a global site with the Sun at 85°: the plot shows the whole sky', () => {
  it('the zoom over its paths would be wider than the whole sky, so the range is the full one', () => {
    const g = globalSky()
    const z = zoomRange(g.mask, g.trails.sun.el, g.trails.earth.el)
    expect(z.hi - z.lo).toBeGreaterThan(FULL_RANGE.hi - FULL_RANGE.lo) // −90°…90°: nothing stretched
    expect(zoomFits(g.trails)).toBe(false)
    expect(skyRange(g)).toEqual(FULL_RANGE)
    expect(buildSky(g).range).toEqual(FULL_RANGE)
    expect(buildSky(g, { live: true }).range).toEqual(FULL_RANGE)
    expect(classic.skyRange(g)).toEqual(classic.FULL_RANGE)
    expect(classic.buildSky(g).range).toEqual(classic.FULL_RANGE)
    expect(classic.buildSky(g, { live: true, narrow: true }).range).toEqual(classic.FULL_RANGE)
  })

  it('the Sun draws inside the plot, 5° from the centre of a −10°…90° sky', () => {
    const g = globalSky()
    const r = skyRange(g)
    for (const dyn of [skyDynamic(g.now, r, 200), skyDynamic(g.now, r, 200, { exact: true, paths: true, d: g })]) {
      const rr = Math.hypot(dyn.sun.x, dyn.sun.y)
      expect(rr).toBeCloseTo(elToR(85, FULL_RANGE), 12)
      expect(rr).toBeCloseTo(0.05, 12)
      expect(rr).toBeGreaterThan(0) // not pinned to the centre
      expect(rr).toBeLessThan(1) // inside the outer ring
      // east of north (azimuth 95°): right of the centre
      expect(dyn.sun.x).toBeGreaterThan(0)
    }
    const cd = classic.skyDynamic(g.now, classic.skyRange(g), 200)
    expect(Math.hypot(cd.sun.x, cd.sun.y)).toBeCloseTo(0.05, 12)
    expect(cd.sun.text).toBe('Sun 85.00°')
  })

  it('every point of the Sun\'s and Earth\'s paths lies inside the outer ring', () => {
    const g = globalSky()
    const r = skyRange(g)
    for (const p of [g.trails.sun, g.trails.earth]) {
      p.az.forEach((a, i) => {
        const [x, y] = toXY(a, p.el[i], r)
        expect(Math.hypot(x, y)).toBeLessThanOrEqual(1 + 1e-12)
      })
    }
  })

  it('the scale says the zoom is on but the paths are too wide for it', () => {
    const g = globalSky()
    expect(keyLine(g, skyRange(g))).toContain(
      `Whole sky: edge −10°, centre straight up (no horizon zoom: the Sun or Earth goes more than ${ZOOM_MAX_BODY_DEG}° from the horizon).`)
    expect(scaleText(true, FULL_RANGE)).toContain('no horizon zoom')
    expect(classic.skyHeader(g, classic.skyRange(g)).scale).toBe('Full sky −10°…90° (paths too wide to zoom)')
    // with the zoom switched off: the plain whole-sky words
    const off = globalSky({ zoom: false })
    expect(keyLine(off, skyRange(off))).toContain('Whole sky: edge −10°, centre straight up.')
    expect(keyLine(off, skyRange(off))).not.toContain('no horizon zoom')
    expect(classic.skyHeader(off, classic.skyRange(off)).scale).toBe('Full sky −10°…90°')
  })

  it('a far-side site: Earth far below the horizon sits on the outer ring, still inside the plot', () => {
    const far = globalSky({
      siteName: 'Synthetic far-side site',
      now: { sun: body({ az: 20, el: 40 }), earth: body({ az: 10, el: -44.6, visible: false, frac: 0, hz: 0.4, rho: 0.95 }) },
      trails: { sun: { az: [0, 90, 180, 270], el: [-47, 0, 47, 0] }, earth: { az: [5, 10, 15], el: [-52, -45, -38] } },
    })
    const r = skyRange(far)
    expect(r).toEqual(FULL_RANGE)
    const dyn = skyDynamic(far.now, r, 200)
    expect(Math.hypot(dyn.earth.x, dyn.earth.y)).toBeCloseTo(1, 12) // clamped to the edge (−10°)
    expect(dyn.earth.text).toContain('below horizon')
    expect(buildSky(far).alt).toContain('Earth at azimuth 10 degrees, elevation -44.6 degrees')
  })
})

describe('the horizon zoom where it still fits', () => {
  it('every polar dev payload keeps its zoom range (the paths stay near the horizon)', () => {
    for (const d of [SR1, HAWORTH]) {
      expect(zoomFits(d.trails)).toBe(true)
      const z = zoomRange(d.mask, d.trails.sun.el, d.trails.earth.el)
      expect(skyRange(d)).toEqual(z)
      expect(classic.skyRange(d)).toEqual(classic.zoomRange(d.mask, d.trails.sun.el, d.trails.earth.el))
      expect(isWholeSky(skyRange(d))).toBe(false)
    }
  })

  it('at the edge of the polar region (−80.01°) the Sun (±12°) and Earth (±19°) still fit', () => {
    const edge = globalSky({
      northNote: undefined,
      trails: { sun: { az: [0, 180], el: [-11.9, 11.9] }, earth: { az: [0, 180], el: [-19, 19] } },
      now: { sun: body({ el: 11.9 }), earth: body({ az: 180, el: 19 }) },
    })
    expect(zoomFits(edge.trails)).toBe(true)
    expect(skyRange(edge)).toEqual({ lo: -20, hi: 20 })
    expect(classic.skyRange(edge)).toEqual({ lo: -20, hi: 20 })
  })

  it('a high-latitude site off the pole (Chandrayaan-3, 69° S) keeps a zoom, with its Sun inside', () => {
    const c3 = globalSky({
      trails: { sun: { az: [0, 90, 180, 270], el: [-22.2, 0, 22.2, 0] }, earth: { az: [20, 30, 40], el: [10, 17, 24.5] } },
      now: { sun: body({ az: 40, el: 22 }), earth: body({ az: 30, el: 17, rho: 0.95 }) },
    })
    const r = skyRange(c3)
    expect(r).toEqual({ lo: -24, hi: 26 })
    expect(keyLine(c3, r)).toContain('N = toward the north pole. Heights stretched: edge −24°, centre 26°.')
    const dyn = skyDynamic(c3.now, r, 200)
    const rr = Math.hypot(dyn.sun.x, dyn.sun.y)
    expect(rr).toBeGreaterThan(0)
    expect(rr).toBeLessThan(1)
  })

  it('the limit is 30° either way, inclusive; non-finite samples are ignored', () => {
    const t = (sun: number[], earth: number[] = [0]): SkyData['trails'] => ({ sun: { az: sun.map(() => 0), el: sun }, earth: { az: earth.map(() => 0), el: earth } })
    expect(ZOOM_MAX_BODY_DEG).toBe(30)
    expect(zoomFits(t([-30, 30]))).toBe(true)
    expect(zoomFits(t([30.01]))).toBe(false)
    expect(zoomFits(t([0], [-30.01]))).toBe(false)
    expect(zoomFits(t([NaN, 5, Infinity * 0]))).toBe(true)
    expect(isWholeSky(FULL_RANGE)).toBe(true)
    expect(isWholeSky({ lo: -10, hi: 89 })).toBe(false)
  })
})
