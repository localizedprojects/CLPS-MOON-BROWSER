// The narrow-layout width follows the page itself, not only window resize events
// (moving a chart to and from the app's full-screen view; QA 2026-10-13).
import { describe, expect, it } from 'vitest'
import { viewportWidth } from './viewport'

describe('viewportWidth', () => {
  it('is the smaller of the window and the page (a shrunken web view whose window size lags)', () => {
    expect(viewportWidth({ innerWidth: 1000 }, { documentElement: { clientWidth: 360 } })).toBe(360)
  })
  it('ignores a side that reports no width yet', () => {
    expect(viewportWidth({ innerWidth: 412 }, { documentElement: { clientWidth: 0 } })).toBe(412)
    expect(viewportWidth({ innerWidth: 0 }, { documentElement: { clientWidth: 390 } })).toBe(390)
  })
})
