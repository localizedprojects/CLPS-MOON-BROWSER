/**
 * "Where to look" fits its plot to the frame's height when the frame is
 * shorter than the plot at its width plus the rest (1.13.3 browser check:
 * the wide pane's frame hid the "Paths over the period" toggle and the key
 * line in its scroll area). Frames that hold it all (the phones' single
 * column) keep the plot at its width.
 */
import { describe, expect, it } from 'vitest'
import skySrc from './SkyView.tsx?raw'
import plotSrc from './usePlot.ts?raw'
import { SKY_FIT_MIN_PX, SKY_FIT_RESERVE_PX, skyFitLimit, skyFitSide, skySide } from './skyFit'

// Measured in Chromium on the web build (Malapert peak, Simple view): the
// frame, and the content besides the plot (header, captions, toggle, key line, padding).
const cases = [
  { what: '1440 x 900, wide pane', w: 397, h: 532, rest: 220, fits: false },
  { what: '1920 x 1080, wide pane', w: 597, h: 604, rest: 202, fits: false },
  { what: '1280 x 800, single column', w: 580, h: 750, rest: 202, fits: true },
  { what: '320 px phone', w: 288, h: 572, rest: 285, fits: true },
  { what: '360 px phone', w: 328, h: 582, rest: 253, fits: true },
  { what: '412 px phone', w: 380, h: 610, rest: 220, fits: true },
]

describe('skyFitSide', () => {
  for (const c of cases) {
    it(`${c.what} (${c.w} x ${c.h}): ${c.fits ? 'the plot keeps its width' : 'the plot fits the height, the rest stays in the frame'}`, () => {
      const side = skyFitSide(c.w, c.h, c.rest)
      // the old plot (at its width) and the rest overflowed the wide pane's frames
      expect(skySide(c.w) + c.rest <= c.h).toBe(c.fits)
      if (c.fits) {
        expect(side).toBe(skySide(c.w))
        expect(skyFitLimit(c.w, c.h, c.rest)).toBeNull()
      } else {
        expect(side + c.rest + SKY_FIT_RESERVE_PX).toBeLessThanOrEqual(c.h)
        expect(side).toBeGreaterThanOrEqual(SKY_FIT_MIN_PX)
      }
    })
  }
  it('never under the smallest side (a shorter frame scrolls), never wider than the frame allows', () => {
    expect(skyFitSide(397, 300, 220)).toBe(SKY_FIT_MIN_PX)
    for (let h = 200; h <= 900; h += 7) for (const w of [288, 397, 597, 800]) expect(skyFitSide(w, h, 210)).toBeLessThanOrEqual(skySide(w))
  })
  it('is measured for the frame and the figure, not for every time (Play), and only shrinks for the same frame', () => {
    expect(skySrc).toMatch(/const key = `\$\{el\.clientHeight\}\|\$\{el\.offsetWidth\}\|\$\{fonts\}`/)
    expect(skySrc).toMatch(/if \(same && el\.scrollHeight <= el\.clientHeight\) return/)
    expect(skySrc).toMatch(/if \(same && \(limit \?\? Infinity\) >= \(fit!\.limit \?\? Infinity\)\) return/)
    expect(skySrc).toMatch(/addEventListener\?\.\('loadingdone', f\)/)
  })
  // 1.13.3 review (Playwright, 597 x 604 and 397 x 532): after a new payload or
  // the Paths toggle, Plotly drew at the frame's width (520) in a 385 px box
  // and the plot spilled over the toggle and the key line
  it('a new figure starts from the last limit, not at the frame\'s width', () => {
    expect(skySrc).toMatch(/return fit \? fit\.limit : null/)
    expect(skySrc).not.toMatch(/fit\.fig === fig \? fit\.limit/)
  })
  it('Plotly redraws when the box differs from the size it drew at, checked on every commit', () => {
    expect(plotSrc).toMatch(/drawnAt\.current = \{ w: el\.clientWidth, h: el\.clientHeight \}\n\s*const done = Plotly\.react/)
    expect(plotSrc).toMatch(/el\.clientWidth === at\.w && el\.clientHeight === at\.h/)
    expect(plotSrc).toMatch(/useLayoutEffect\(\(\) => \{ fitRef\.current\(\) \}\)/)
  })
})
