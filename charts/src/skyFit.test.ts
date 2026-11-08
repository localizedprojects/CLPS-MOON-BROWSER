/**
 * "Where to look" fits its plot to the frame's height when the frame is
 * shorter than the plot at its width plus the rest (1.13.3 browser check:
 * the wide pane's frame hid the "Paths over the period" toggle and the key
 * line in its scroll area). Frames that hold it all (the phones' single
 * column) keep the plot at its width.
 */
import { describe, expect, it } from 'vitest'
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
  // the view's measure (for the frame and the figure, not for Play; only shrinking for the same
  // frame; a new figure from the last limit): viewsLive.test.ts. Plotly's redraw: plotRedraw.test.ts
})
