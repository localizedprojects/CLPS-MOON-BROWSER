/**
 * The simple "When" (TimelineView) and "Where to look" (SkyView) views as
 * they live: rendered with React's client renderer on the small DOM in
 * testDom.ts, so their effects and layout effects run, with the frame's
 * layout set by the test and Plotly mocked. K6, 1.13.5: these behaviours
 * were checked by matching the views' source text before (comingFit,
 * skyFit and bridge tests). viewsRender.test.ts reads the first render's
 * markup; the pure parts are tested in comingFit, skyFit and bridge.
 */
import { act, createElement } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { HostMessage } from './bridge'
import sky from './devdata/sky.json'
import timeline from './devdata/timeline.json'
import { type Box, type FakeElement, fakeWindow } from './testDom'

const P = vi.hoisted(() => ({
  /** Every Plotly.react call: the plot box's width and height then, and the x range (the strip's window). */
  react: [] as Array<{ w: number; h: number; range?: string[] }>,
}))
vi.mock('plotly.js-basic-dist-min', () => ({
  default: {
    react: (el: FakeElement & { on?: unknown }, _data: unknown, layout: { xaxis?: { range?: string[] } }) => {
      P.react.push({ w: el.clientWidth, h: el.clientHeight, range: layout.xaxis?.range })
      el.on ??= () => {}
      return new Promise(() => {}) // never drawn: the overlays wait for plotly_afterplot
    },
    Plots: { resize: () => {} },
  },
}))

const dom = fakeWindow()
vi.stubGlobal('window', dom.win)
vi.stubGlobal('document', dom.doc)
vi.stubGlobal('requestAnimationFrame', dom.win.requestAnimationFrame)
vi.stubGlobal('cancelAnimationFrame', dom.win.cancelAnimationFrame)
vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true)
const { createRoot } = await import('react-dom/client')
const { dispatchForTests, resetBridgeForTests } = await import('./bridge')
const { TimelineView } = await import('./TimelineView')
const { SkyView } = await import('./SkyView')
const { fmtDate } = await import('./format')
const { comingMoreText } = await import('./timelineAnswer')
const { SKY_FIT_MIN_PX, SKY_FIT_RESERVE_PX, skySide } = await import('./skyFit')

const DAY = 86400e3
const T0 = timeline.data.range[0]
const send = (m: unknown) => act(() => { dispatchForTests(m as HostMessage) })
/** The animation frames the views asked for (useLatest applies cursor and skyNow messages there). */
const frames = () => act(() => { dom.frames() })

let root: ReturnType<typeof createRoot> | null = null
let host: FakeElement
async function mount(view: () => unknown, width: number) {
  dom.win.innerWidth = width
  host = dom.doc.body.appendChild(dom.doc.createElement('div'))
  root = createRoot(host as unknown as HTMLElement)
  await act(async () => { root!.render(createElement(view as () => null)) })
  await frames()
}
const view = () => host.firstElementChild!
beforeEach(() => {
  resetBridgeForTests()
  P.react.length = 0
})
afterEach(async () => {
  if (root) await act(() => root!.unmount())
  root = null
  dom.doc.body.textContent = ''
  dom.doc.layout = () => ({})
})

// ---------------------------------------------------------------------------
// TimelineView: Coming up keeps inside its frame (F1, 1.13.2, 1.13.3, K3)

/** A classic scrollbar's width, px (Chromium). */
const BAR = 15
/**
 * The timeline frame as Chromium lays it out, simplified: the Coming up list
 * starts [olTop] below the frame's top; a row is [rowH] tall at the width the
 * frame leaves it (a classic scrollbar narrows it), the "more" line 22 px;
 * the frame draws a scrollbar when its gutter is kept or when it overflows
 * and scrollbars are not hidden (timelineScrollStyle; [noScrollbarWidth]: a
 * browser that cannot hide them, Chrome < 121).
 */
function timelineFrame(o: { w: number; h: number; olTop: number; rowH?: (clientWidth: number) => number; noScrollbarWidth?: boolean }) {
  const st = { measures: 0 }
  const rowH = o.rowH ?? (() => 48)
  const frame = (el: FakeElement) => el === view()
  const bar = (root: FakeElement, content: number) => root.style.scrollbarGutter === 'stable' || (content > o.h && (o.noScrollbarWidth || root.style.scrollbarWidth !== 'none'))
  const content = (root: FakeElement, cw: number) => {
    const rows = root.querySelectorAll('li').length, more = root.querySelector('[data-more]') ? 22 : 0
    return o.olTop + rows * rowH(cw) + more + 4
  }
  const clientWidth = (root: FakeElement) => o.w - (bar(root, content(root, o.w - BAR)) ? BAR : 0)
  dom.doc.layout = (el): Box => {
    const root = view()
    if (frame(el)) {
      const cw = clientWidth(root)
      return { clientWidth: cw, offsetWidth: o.w, clientHeight: o.h, scrollHeight: Math.max(o.h, content(root, cw)), top: 0 }
    }
    if (el.tagName === 'OL') return { top: o.olTop }
    if (el.tagName === 'LI') return { offsetHeight: rowH(clientWidth(root)) }
    if (el.hasAttribute('data-more')) { st.measures++; return { offsetHeight: 22 } } // read only while measuring (every row drawn)
    return {}
  }
  return st
}
/** Measuring passes as a view mounts: the first layout, and again once the fonts are ready. */
const MOUNT_MEASURES = 2
const rows = () => view().querySelectorAll('li').length
const moreLine = () => view().querySelector('[data-more]')?.textContent ?? null
const tl = (cursor: number, siteName = timeline.data.siteName) => ({ type: 'timeline', data: { ...timeline.data, cursor, siteName } })

describe('TimelineView: Coming up lists only the rows that fit, and a line for the rest', () => {
  it('measures with every row and the "more" line drawn, then shows the rows that fit with the line', async () => {
    // 700 px: 5 rows asked for. Room 154: three rows (144) fit only without the line (22), so two and the line
    const st = timelineFrame({ w: 700, h: 558, olTop: 400 })
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(st.measures).toBe(MOUNT_MEASURES)
    expect(rows()).toBe(2)
    expect(moreLine()).toBe(comingMoreText(3, 2))
  })
  it('lists none, and says why, in a frame too short for one row', async () => {
    timelineFrame({ w: 700, h: 430, olTop: 400 })
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(rows()).toBe(0)
    expect(moreLine()).toBe(comingMoreText(5, 0))
  })
  it('counts again on a frame resize that keeps the width, and on the host\'s settle nudge', async () => {
    const o = { w: 700, h: 558, olTop: 400 }
    timelineFrame(o)
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(rows()).toBe(2)
    o.h = 558 + 76 // Flutter's layout: full screen (room 230: four rows and the line)
    await act(() => { dom.send('resize') })
    expect(rows()).toBe(4)
    o.h = 558
    await act(() => { dom.send('ph-settle') })
    expect(rows()).toBe(2)
  })
})

describe('TimelineView: Coming up never re-measures in a loop when a scrollbar comes and goes (1.13.2: error #185, a blank chart)', () => {
  it('keeps the fit when only a scrollbar narrows the frame (keyed by its outer width)', async () => {
    // no row fits: the line overflows the frame, which then scrolls with a classic scrollbar
    const st = timelineFrame({ w: 700, h: 410, olTop: 400 })
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(view().style.scrollbarGutter).toBe('stable')
    expect(st.measures).toBe(MOUNT_MEASURES)
  })
  it('settles when the scrollbar makes the rows wrap taller than measured', async () => {
    // rows wrap to 65 px under a scrollbar: the fit draws them taller than measured, the frame
    // overflows and keeps a scrollbar's room, they are measured again with it, fewer fit, the frame
    // stops scrolling... each change is measured once, then kept
    const st = timelineFrame({ w: 700, h: 558, olTop: 400, rowH: (cw) => (cw < 700 ? 65 : 48) })
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(st.measures).toBeLessThanOrEqual(MOUNT_MEASURES + 2)
    const n = rows()
    expect(n).toBeGreaterThanOrEqual(1)
    expect(moreLine()).toBe(comingMoreText(5 - n, n))
  })
  it('settles where the scrollbar cannot be hidden while every row is drawn (the 1.13.2 loop)', async () => {
    // measured with every row, the frame overflows and its scrollbar wraps the rows to 65 px; two
    // fit, drawn without a scrollbar at 48 px: another height than measured, so measured once
    // more (65 px again), and that change is kept rather than measured again and again
    const st = timelineFrame({ w: 700, h: 558, olTop: 400, rowH: (cw) => (cw < 700 ? 65 : 48), noScrollbarWidth: true })
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(st.measures).toBeLessThanOrEqual(MOUNT_MEASURES + 1)
    expect(rows()).toBe(2)
    expect(moreLine()).toBe(comingMoreText(3, 2))
  })
})

describe('TimelineView: Coming up is not measured again for new words during Play (1.13.3)', () => {
  it('keeps the fit while the rows change their words, not their number', async () => {
    const st = timelineFrame({ w: 700, h: 558, olTop: 400 })
    await send(tl(T0))
    await mount(TimelineView, 700)
    expect(st.measures).toBe(MOUNT_MEASURES)
    const words = [view().querySelector('li')!.textContent]
    for (let step = 1; step <= 12; step++) {
      await send({ type: 'cursor', t: T0 + step * DAY }) // Play, a day a step: past events, new rows
      await frames()
      words.push(view().querySelector('li')!.textContent)
    }
    expect(new Set(words).size).toBeGreaterThan(1) // other rows, other words
    expect(rows()).toBe(2)
    expect(st.measures).toBe(MOUNT_MEASURES)
  })
})

// ---------------------------------------------------------------------------
// TimelineView: the strip's window follows the time the page holds (F1)

describe('TimelineView: the strip shows the time the page holds', () => {
  const shown = () => view().getAttribute('aria-label')!
  const inStrip = (t: number, r?: string[]) => !!r && Date.parse(r[0]) <= t && t <= Date.parse(r[1])
  it('a view that mounts after the time moved draws its first window there, not at the payload\'s start', async () => {
    timelineFrame({ w: 700, h: 558, olTop: 400 })
    await send(tl(T0)) // the payload, built at the period start
    await send({ type: 'cursor', t: T0 + 136 * DAY }) // the time moved (the classic timeline was on screen)
    await mount(TimelineView, 700) // the Simple view switched on now
    expect(P.react.length).toBeGreaterThan(0)
    for (const r of P.react) expect(inStrip(T0 + 136 * DAY, r.range), JSON.stringify(r.range)).toBe(true)
    expect(shown()).toContain(`Shown time ${fmtDate(T0 + 136 * DAY, { year: true })} UTC.`)
  })
  it('a newer payload (another site), even after a cursor message, moves the window to its time', async () => {
    timelineFrame({ w: 700, h: 558, olTop: 400 })
    await send(tl(T0))
    await mount(TimelineView, 700)
    await send({ type: 'cursor', t: T0 + 150 * DAY })
    await frames()
    expect(inStrip(T0 + 150 * DAY, P.react.at(-1)!.range)).toBe(true)
    await send(tl(T0 + 200 * DAY, 'Another site'))
    await frames()
    expect(inStrip(T0 + 200 * DAY, P.react.at(-1)!.range)).toBe(true)
    expect(shown()).toContain(`Shown time ${fmtDate(T0 + 200 * DAY, { year: true })} UTC.`)
  })
})

// ---------------------------------------------------------------------------
// SkyView: "Where to look" fits its plot to the frame's height (1.13.3)

/**
 * The sky frame as Chromium lays it out, simplified: a column of the header
 * (40), the captions ([capH]), the plot box (its side), the toggle (40) and
 * the key line (16), 4 px above and 8 px below; [bar] narrows the client
 * width only (a classic scrollbar). [measures] counts the layout passes that
 * measured the content (read the last item's place).
 */
function skyFrame(o: { w: number; h: number; capH: number; bar?: boolean }) {
  const st = { measures: 0 }
  const side = () => parseFloat(view().querySelector('[role="img"]')?.style.width ?? '0')
  const bottom = () => 4 + 40 + o.capH + side() + 40 + 16
  dom.doc.layout = (el): Box => {
    const root = view()
    if (el === root) return { clientWidth: o.w - (o.bar ? BAR : 0), offsetWidth: o.w, clientHeight: o.h, scrollHeight: Math.max(o.h, bottom() + 8), top: 0 }
    if (el === root.lastElementChild) { st.measures++; return { bottom: bottom() } }
    if (el.getAttribute('role') === 'img' && el.parentNode === root) return { offsetHeight: side(), clientWidth: side(), clientHeight: side() }
    if (el.parentNode === root.querySelector('[role="img"]')) return { clientWidth: side(), clientHeight: side() } // Plotly's div
    return {}
  }
  return { st, side }
}
const skyMsg = (siteName = sky.data.siteName) => ({ type: 'sky', data: { ...sky.data, siteName } })
const skyNow = (k: number) => ({ type: 'skyNow', timeLabel: `step ${k}`, now: { ...sky.data.now, sun: { ...sky.data.now.sun, az: sky.data.now.sun.az + k } } })
/** One step of Play: a new time (the caption lines change, the frame does not). */
const play = async (k: number) => { await send(skyNow(k)); await frames() }

describe('SkyView: the plot fits the frame\'s height, measured for the frame and the figure', () => {
  // the 1440 x 900 wide pane: 397 x 532, 220 px besides the plot (skyFit.test.ts)
  const wide = { w: 397, h: 532, capH: 112 }
  const fitted = 532 - 220 - SKY_FIT_RESERVE_PX
  it('fits the plot in the wide pane, and is not measured again for a new time (Play)', async () => {
    const { st, side } = skyFrame({ ...wide })
    await send(skyMsg())
    await mount(SkyView, 397)
    expect(skySide(397)).toBeGreaterThan(fitted)
    expect(side()).toBe(fitted)
    const n = st.measures
    for (let k = 1; k <= 10; k++) await play(k)
    expect(st.measures).toBe(n)
    expect(side()).toBe(fitted)
  })
  it('a caption grown past the room kept shrinks the plot, which then only shrinks for that frame', async () => {
    const o = { ...wide }
    const { side } = skyFrame(o)
    await send(skyMsg())
    await mount(SkyView, 397)
    o.capH += 30
    await play(1)
    expect(side()).toBe(fitted - 30)
    o.capH -= 30
    await play(2)
    expect(side()).toBe(fitted - 30)
  })
  it('settles at the smallest side in a frame too short for it (it scrolls)', async () => {
    const { side } = skyFrame({ w: 397, h: 300, capH: 112 })
    await send(skyMsg())
    await mount(SkyView, 397)
    expect(side()).toBe(SKY_FIT_MIN_PX)
    for (let k = 1; k <= 3; k++) await play(k)
    expect(side()).toBe(SKY_FIT_MIN_PX)
  })
  it('measures again for a new frame height, but not for a classic scrollbar coming or going', async () => {
    const o = { ...wide, bar: false }
    const { st, side } = skyFrame(o)
    await send(skyMsg())
    await mount(SkyView, 397)
    // no ResizeObserver before Chrome 64: the window's resize
    o.h = 604
    await act(() => { dom.send('resize') })
    expect(side()).toBe(skySide(397)) // 604 px hold the plot at its width and the rest
    const n = st.measures
    o.bar = true
    await act(() => { dom.send('resize') })
    await play(1)
    o.bar = false
    await act(() => { dom.send('resize') })
    await play(2)
    expect(st.measures).toBe(n)
  })
  it('measures again when the fonts load (the fallback font wrapped the captions otherwise)', async () => {
    const o = { ...wide }
    const { side } = skyFrame(o)
    await send(skyMsg())
    await mount(SkyView, 397)
    expect(side()).toBe(fitted)
    o.capH -= 30
    await act(() => { dom.doc.fonts.dispatchEvent({ type: 'loadingdone' }) })
    expect(side()).toBe(fitted + 30)
  })
  // 1.13.3 review (597 x 604 and 397 x 532): after a new payload or the Paths
  // toggle, Plotly drew at the frame's width in a smaller box and the plot
  // spilled over the toggle and the key line
  it('a new figure draws at the last limit, not at the frame\'s width', async () => {
    const { side } = skyFrame({ ...wide })
    await send(skyMsg())
    await mount(SkyView, 397)
    expect(side()).toBe(fitted)
    const before = P.react.length
    await send(skyMsg('Another site'))
    await frames()
    expect(P.react.length).toBe(before + 1)
    expect(P.react.at(-1)).toMatchObject({ w: fitted, h: fitted })
    // the Paths toggle (another figure, the same frame)
    view().querySelector('button[aria-pressed]')!.click()
    await frames()
    expect(P.react.length).toBe(before + 2)
    expect(P.react.at(-1)).toMatchObject({ w: fitted, h: fitted })
  })
})
