// The simple "When" (TimelineView) and "Where to look" (SkyView) views as
// they render, read from their markup (K6, 1.13.4: these checks matched the
// views' source text before). Rendered on the server with the dev sample as
// the host's payload: the layout effects do not run, so this is the first
// render, before the Coming up rows are fitted.
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import sky from './devdata/sky.json'
import timeline from './devdata/timeline.json'
import { HOST_CORNER_PX } from './theme'

const win = { innerWidth: 360, innerHeight: 800, addEventListener() {}, removeEventListener() {}, location: { hash: '', search: '' } }
vi.stubGlobal('window', win)
// Plotly needs a browser to load; nothing is drawn before the effects run
vi.mock('plotly.js-basic-dist-min', () => ({ default: {} }))
vi.mock('./viewHooks', async (orig) => ({
  ...(await orig<typeof import('./viewHooks')>()),
  useHost: (type: string) => (type === 'timeline' ? timeline : type === 'sky' ? sky : null),
}))
const { TimelineView } = await import('./TimelineView')
const { SkyView } = await import('./SkyView')

// --- a small reader for React's markup (attribute values have <, >, " escaped) ---
interface El { tag: string; attrs: Record<string, string>; style: Record<string, string>; children: El[]; html: string }
function parse(html: string): El {
  const root: El = { tag: '#root', attrs: {}, style: {}, children: [], html }
  const stack: Array<{ el: El; start: number }> = [{ el: root, start: 0 }]
  const tags = /<(\/?)([a-zA-Z][\w-]*)((?:\s+[\w:-]+(?:="[^"]*")?)*)\s*(\/?)>/g
  for (let m = tags.exec(html); m; m = tags.exec(html)) {
    const [whole, close, tag, attrText, selfClose] = m
    if (close) {
      const open = stack.pop()!
      expect(open.el.tag, `</${tag}> closes <${open.el.tag}>`).toBe(tag)
      open.el.html = html.slice(open.start, m.index + whole.length)
      continue
    }
    const attrs: Record<string, string> = {}
    for (const a of attrText.matchAll(/([\w:-]+)(?:="([^"]*)")?/g)) attrs[a[1]] = a[2] ?? ''
    const style: Record<string, string> = {}
    for (const d of (attrs.style ?? '').split(';')) {
      const i = d.indexOf(':')
      if (i > 0) style[d.slice(0, i).trim()] = d.slice(i + 1).trim()
    }
    const el: El = { tag, attrs, style, children: [], html: whole }
    stack[stack.length - 1].el.children.push(el)
    if (!selfClose && !['br', 'img', 'input', 'hr'].includes(tag)) stack.push({ el, start: m.index })
  }
  expect(stack.length, 'every element closed').toBe(1)
  return root
}
const all = (el: El): El[] => [el, ...el.children.flatMap(all)]
const hasClass = (el: El, c: string) => (el.attrs.class ?? '').split(/\s+/).includes(c)
const px = (v: string | undefined) => (v === undefined ? NaN : Number(/^(-?[\d.]+)px$/.exec(v)?.[1] ?? NaN))
/** The side padding of a `padding: top right bottom` (or `top sides`) style. */
const sidePad = (el: El) => px(el.style.padding.split(/\s+/)[1])

function render(view: typeof TimelineView, width: number): El {
  win.innerWidth = width
  const doc = parse(renderToStaticMarkup(createElement(view)))
  expect(doc.children).toHaveLength(1)
  return doc.children[0]
}

const WIDTHS = [
  { width: 360, narrow: true }, // a phone: one column of answer lines
  { width: 563, narrow: true }, // the wide pane's When frame at 1440 x 900
  { width: 800, narrow: false }, // two columns, Coming up under the strip
  { width: 1440, narrow: false }, // two columns, Coming up beside the strip
]

describe("the simple views keep their top-right corner clear of the host's full-screen button (F3)", () => {
  for (const { width, narrow } of WIDTHS) {
    it(`When at ${width} px: only the top-right answer line keeps the corner free (${narrow ? 'the first of one column' : 'the second of two'})`, () => {
      const root = render(TimelineView, width)
      const facts = all(root).find((e) => hasClass(e, narrow ? 'ph-facts' : 'ph-facts-wide'))
      expect(facts, 'the answer lines').toBeDefined()
      expect(facts!.children.length).toBeGreaterThanOrEqual(2)
      const corner = facts!.children.map((l, i) => [i, l.style['padding-right']] as const).filter(([, p]) => p !== undefined)
      expect(corner.map(([i]) => i)).toEqual([narrow ? 0 : 1])
      // from the frame's right edge: the view's side padding and the line's own
      expect(sidePad(root)).toBeGreaterThan(0)
      expect(sidePad(root) + px(corner[0][1])).toBe(HOST_CORNER_PX)
    })
  }
  for (const width of [360, 800]) {
    it(`Where to look at ${width} px: the header row with "Exact numbers" keeps the corner free`, () => {
      const root = render(SkyView, width)
      const header = root.children[0]
      expect(header.style['min-height']).toBe('40px')
      expect(header.html).toMatch(/<button[^>]*>Exact numbers<\/button>/)
      expect(sidePad(root)).toBeGreaterThan(0)
      expect(sidePad(root) + px(header.style['padding-right'])).toBe(HOST_CORNER_PX)
    })
  }
})

describe('the scroll columns are scroll boxes (styles.css keeps their items at content height, F3)', () => {
  for (const { width } of WIDTHS) {
    it(`When and Where to look at ${width} px`, () => {
      for (const view of [TimelineView, SkyView]) {
        const cols = all(render(view, width)).filter((e) => hasClass(e, 'ph-col4') || hasClass(e, 'ph-col6'))
        expect(cols.length).toBeGreaterThan(0)
        for (const c of cols) expect(c.style['overflow-y'], view.name).toBe('auto')
      }
    })
  }
  it('the reader sees what it checks', () => {
    const d = parse('<div class="a ph-col4" style="overflow-y:auto;padding:4px 12px 8px"><svg><path d="M0 0"/></svg><br/><b>x &gt; y</b></div>')
    const [el] = d.children
    expect(hasClass(el, 'ph-col4')).toBe(true)
    expect(el.style['overflow-y']).toBe('auto')
    expect(sidePad(el)).toBe(12)
    expect(el.children.map((c) => c.tag)).toEqual(['svg', 'br', 'b'])
    expect(() => parse('<div><span></div>')).toThrow()
  })
})
