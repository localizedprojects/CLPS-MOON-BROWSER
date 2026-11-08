/**
 * usePlot redraws when the plot's box differs from the size Plotly drew at,
 * checked on every commit (1.13.3 review: a box the view sizes can change
 * and change back within one task, which a ResizeObserver never reports;
 * the sky plot then spilled over the toggle and the key line). Rendered with
 * React's client renderer on the small DOM in testDom.ts, Plotly mocked
 * (K6, 1.13.5: this matched usePlot.ts's source text before).
 */
import { act, createElement } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { type FakeElement, fakeWindow } from './testDom'

const P = vi.hoisted(() => ({
  react: [] as Array<{ w: number; h: number }>,
  resize: [] as Array<{ w: number; h: number }>,
  /** Called inside Plotly.react (what drawing does to the box). */
  during: null as null | (() => void),
}))
vi.mock('plotly.js-basic-dist-min', () => ({
  default: {
    react: (el: FakeElement & { on?: unknown }) => {
      P.react.push({ w: el.clientWidth, h: el.clientHeight })
      el.on ??= () => {}
      P.during?.()
      return new Promise(() => {}) // never drawn: no plotly_afterplot
    },
    Plots: { resize: (el: FakeElement) => { P.resize.push({ w: el.clientWidth, h: el.clientHeight }) } },
  },
}))

const dom = fakeWindow()
vi.stubGlobal('window', dom.win)
vi.stubGlobal('document', dom.doc)
vi.stubGlobal('requestAnimationFrame', dom.win.requestAnimationFrame)
vi.stubGlobal('cancelAnimationFrame', dom.win.cancelAnimationFrame)
vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true)
const { createRoot } = await import('react-dom/client')
const { usePlot } = await import('./usePlot')

const box = { w: 400, h: 400 }
dom.doc.layout = (el) => (el.hasAttribute('data-plot') ? { clientWidth: box.w, clientHeight: box.h } : {})
const fig = { data: [], layout: {} }
function Probe({ n }: { n: number }) {
  const ref = usePlot(fig)
  return createElement('div', { ref, 'data-plot': n })
}

let root: ReturnType<typeof createRoot>
const commit = (n: number) => act(() => root.render(createElement(Probe, { n })))
beforeEach(async () => {
  Object.assign(box, { w: 400, h: 400 })
  P.react.length = 0
  P.resize.length = 0
  P.during = null
  const host = dom.doc.body.appendChild(dom.doc.createElement('div'))
  root = createRoot(host as unknown as HTMLElement)
  await commit(0)
})
afterEach(async () => {
  await act(() => root.unmount())
  dom.doc.body.textContent = ''
})

describe('usePlot redraws for the box it is in', () => {
  it('draws at the box\'s size, and on a commit only when the box differs from it', async () => {
    expect(P.react).toEqual([{ w: 400, h: 400 }])
    await commit(1)
    expect(P.resize).toEqual([])
    // the box changed (no window resize, no observer: a commit)
    Object.assign(box, { w: 300, h: 350 })
    await commit(2)
    expect(P.resize).toEqual([{ w: 300, h: 350 }])
    await commit(3)
    expect(P.resize).toHaveLength(1)
    expect(P.react).toHaveLength(1) // the same figure: never drawn again
  })
  it('needs no redraw for a box that changed and changed back between commits', async () => {
    box.w = 300
    box.w = 400
    await commit(1)
    expect(P.resize).toEqual([])
  })
  it('compares with the size the box had when Plotly was asked to draw', async () => {
    await act(() => root.unmount())
    P.react.length = 0
    // the box takes another size as the figure draws: drawn at 400, now 380
    P.during = () => { box.w = 380 }
    root = createRoot(dom.doc.body.appendChild(dom.doc.createElement('div')) as unknown as HTMLElement)
    await commit(0)
    expect(P.react).toEqual([{ w: 400, h: 400 }])
    await commit(1)
    expect(P.resize).toEqual([{ w: 380, h: 400 }])
  })
  it('also redraws on a window resize that changed the box, and on the host\'s settle nudge at any size', async () => {
    dom.send('resize')
    expect(P.resize).toEqual([])
    box.h = 300
    dom.send('resize')
    expect(P.resize).toEqual([{ w: 400, h: 300 }])
    dom.send('ph-settle') // the page was moved (full screen and back): a hidden div reports no change
    expect(P.resize).toEqual([{ w: 400, h: 300 }, { w: 400, h: 300 }])
    // and lets go of the window once unmounted
    await act(() => root.unmount())
    expect([dom.listening('resize'), dom.listening('ph-settle')]).toEqual([0, 0])
    root = createRoot(dom.doc.body.appendChild(dom.doc.createElement('div')) as unknown as HTMLElement)
  })
})
