// The chart page never lets the browser/web view zoom it: in the app's
// full-screen view a double-tap or pinch magnified the whole page and the
// zoom stuck (QA on a OnePlus phone, 2026-10-13). The charts zoom themselves.
import { describe, expect, it } from 'vitest'
import html from '../index.html?raw'

describe('index.html', () => {
  it('disables page zoom in its viewport', () => {
    const vp = /<meta name="viewport" content="([^"]+)"/.exec(html)?.[1] ?? ''
    expect(vp).toContain('width=device-width')
    expect(vp).toContain('maximum-scale=1.0')
    expect(vp).toContain('user-scalable=no')
  })
})
