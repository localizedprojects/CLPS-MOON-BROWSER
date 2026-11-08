/**
 * A small DOM for the behaviour tests of the views (K6, 1.13.5: these
 * checks matched the views' source text before). Node has no DOM and the
 * charts carry no DOM library, so this one has what React's client renderer
 * and the views use: elements, text, attributes, inline styles, events,
 * simple selectors, document.fonts and a layout the test sets (the sizes an
 * element reports). The views' effects and layout effects then run as in
 * the browser. Test-only: nothing in the bundle imports it.
 */

/** What an element reports for its size and place, px (unset: 0). */
export interface Box {
  clientWidth?: number
  clientHeight?: number
  offsetWidth?: number
  offsetHeight?: number
  scrollHeight?: number
  scrollTop?: number
  top?: number
  bottom?: number
}

const HTML_NS = 'http://www.w3.org/1999/xhtml'
type Listener = (ev: FakeEvent) => void
export interface FakeEvent { type: string; target: FakeNode; bubbles: boolean; defaultPrevented: boolean; preventDefault(): void; stopPropagation(): void; [k: string]: unknown }

export class FakeNode {
  parentNode: FakeNode | null = null
  childNodes: FakeNode[] = []
  readonly listeners = new Map<string, Set<Listener>>()
  constructor(readonly nodeType: number, readonly nodeName: string, public ownerDocument: FakeDocument | null) {}
  get firstChild(): FakeNode | null { return this.childNodes[0] ?? null }
  get lastChild(): FakeNode | null { return this.childNodes[this.childNodes.length - 1] ?? null }
  get parentElement(): FakeElement | null { return this.parentNode instanceof FakeElement ? this.parentNode : null }
  get nextSibling(): FakeNode | null { const s = this.parentNode?.childNodes; return s ? s[s.indexOf(this) + 1] ?? null : null }
  get previousSibling(): FakeNode | null { const s = this.parentNode?.childNodes; return s ? s[s.indexOf(this) - 1] ?? null : null }
  get isConnected(): boolean { let n: FakeNode = this; while (n.parentNode) n = n.parentNode; return n.nodeType === 9 }
  appendChild<T extends FakeNode>(c: T): T { return this.insertBefore(c, null) }
  insertBefore<T extends FakeNode>(c: T, ref: FakeNode | null): T {
    c.parentNode?.removeChild(c)
    const i = ref ? this.childNodes.indexOf(ref) : -1
    if (i < 0) this.childNodes.push(c)
    else this.childNodes.splice(i, 0, c)
    c.parentNode = this
    return c
  }
  removeChild<T extends FakeNode>(c: T): T {
    const i = this.childNodes.indexOf(c)
    if (i >= 0) this.childNodes.splice(i, 1)
    c.parentNode = null
    return c
  }
  contains(n: FakeNode | null): boolean { for (let x = n; x; x = x.parentNode) if (x === this) return true; return false }
  get textContent(): string { return this.childNodes.map((c) => c.textContent).join('') }
  set textContent(v: string) {
    for (const c of this.childNodes) c.parentNode = null
    this.childNodes = []
    if (v) this.appendChild(this.ownerDocument!.createTextNode(v))
  }
  addEventListener(type: string, f: Listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set())
    this.listeners.get(type)!.add(f)
  }
  removeEventListener(type: string, f: Listener) { this.listeners.get(type)?.delete(f) }
  dispatchEvent(ev: { type: string }) {
    for (const f of [...(this.listeners.get(ev.type) ?? [])]) f(ev as FakeEvent)
    return true
  }
}

export class FakeText extends FakeNode {
  constructor(public data: string, doc: FakeDocument) { super(3, '#text', doc) }
  get nodeValue() { return this.data }
  set nodeValue(v: string) { this.data = v }
  override get textContent() { return this.data }
  override set textContent(v: string) { this.data = v }
}

export class FakeElement extends FakeNode {
  readonly attrs = new Map<string, string>()
  readonly style: Record<string, string> & { setProperty(k: string, v: string): void; removeProperty(k: string): void }
  innerHTML = ''
  constructor(readonly tagName: string, readonly namespaceURI: string, doc: FakeDocument) {
    super(1, tagName, doc)
    const style = {} as FakeElement['style']
    Object.defineProperty(style, 'setProperty', { value: (k: string, v: string) => { style[k] = v } })
    Object.defineProperty(style, 'removeProperty', { value: (k: string) => { delete style[k] } })
    this.style = style
  }
  setAttribute(k: string, v: unknown) { this.attrs.set(k, String(v)) }
  setAttributeNS(_ns: string | null, k: string, v: unknown) { this.attrs.set(k, String(v)) }
  getAttribute(k: string) { return this.attrs.get(k) ?? null }
  hasAttribute(k: string) { return this.attrs.has(k) }
  removeAttribute(k: string) { this.attrs.delete(k) }
  removeAttributeNS(_ns: string | null, k: string) { this.attrs.delete(k) }
  get className() { return this.attrs.get('class') ?? '' }
  get children(): FakeElement[] { return this.childNodes.filter((c): c is FakeElement => c instanceof FakeElement) }
  get firstElementChild() { return this.children[0] ?? null }
  get lastElementChild() { return this.children[this.children.length - 1] ?? null }
  /** Every element below this one, in document order. */
  descendants(): FakeElement[] { return this.children.flatMap((c) => [c, ...c.descendants()]) }
  querySelectorAll(sel: string): FakeElement[] { return this.descendants().filter((e) => e.matches(sel)) }
  querySelector(sel: string): FakeElement | null { return this.querySelectorAll(sel)[0] ?? null }
  /** A compound selector: an optional tag, then .class and [attr] or [attr="value"] parts (no combinators). */
  matches(sel: string): boolean {
    const m = /^([a-zA-Z][\w-]*)?((?:\.[\w-]+|\[[\w-]+(?:="[^"]*")?\])*)$/.exec(sel.trim())
    if (!m) throw new Error(`testDom: selector not supported: ${sel}`)
    if (m[1] && m[1].toLowerCase() !== this.tagName.toLowerCase()) return false
    for (const p of m[2].match(/\.[\w-]+|\[[^\]]+\]/g) ?? []) {
      if (p[0] === '.') { if (!this.className.split(/\s+/).includes(p.slice(1))) return false; continue }
      const [, k, v] = /^\[([\w-]+)(?:="([^"]*)")?\]$/.exec(p)!
      if (!this.attrs.has(k) || (v !== undefined && this.attrs.get(k) !== v)) return false
    }
    return true
  }
  private box(): Box { return this.ownerDocument!.layout(this) }
  get clientWidth() { return this.box().clientWidth ?? 0 }
  get clientHeight() { return this.box().clientHeight ?? 0 }
  get offsetWidth() { return this.box().offsetWidth ?? this.box().clientWidth ?? 0 }
  get offsetHeight() { return this.box().offsetHeight ?? this.box().clientHeight ?? 0 }
  get scrollHeight() { return this.box().scrollHeight ?? this.box().clientHeight ?? 0 }
  get scrollTop() { return this.box().scrollTop ?? 0 }
  set scrollTop(_v: number) {}
  getBoundingClientRect() {
    const b = this.box(), top = b.top ?? 0, height = b.offsetHeight ?? b.clientHeight ?? 0
    const width = b.offsetWidth ?? b.clientWidth ?? 0
    return { top, bottom: b.bottom ?? top + height, left: 0, right: width, width, height, x: 0, y: top }
  }
  focus() { this.ownerDocument!.activeElement = this }
  blur() { if (this.ownerDocument!.activeElement === this) this.ownerDocument!.activeElement = this.ownerDocument!.body }
  /** A click as the browser sends it: capture listeners from the top down, then bubbling ones up. */
  click() {
    const path: FakeNode[] = []
    for (let n: FakeNode | null = this; n; n = n.parentNode) path.push(n)
    let stopped = false
    const ev: FakeEvent = { type: 'click', target: this, bubbles: true, cancelable: true, defaultPrevented: false, timeStamp: 0, button: 0, buttons: 0,
      preventDefault() { ev.defaultPrevented = true }, stopPropagation() { stopped = true }, getModifierState: () => false }
    for (const n of path) { n.dispatchEvent(ev); if (stopped) break }
  }
}

/** document.fonts: [ready] resolved, 'loadingdone' sent by the test. */
export class FakeFonts extends FakeNode {
  ready = Promise.resolve()
  constructor() { super(11, '#fonts', null) }
}

export class FakeDocument extends FakeNode {
  readonly documentElement: FakeElement
  readonly head: FakeElement
  readonly body: FakeElement
  activeElement: FakeElement
  defaultView: unknown = null
  readonly fonts = new FakeFonts()
  /** The size and place of [el] (the test sets it). */
  layout: (el: FakeElement) => Box = () => ({})
  constructor() {
    super(9, '#document', null)
    this.ownerDocument = null
    this.documentElement = this.appendChild(this.createElement('html'))
    this.head = this.documentElement.appendChild(this.createElement('head'))
    this.body = this.documentElement.appendChild(this.createElement('body'))
    this.activeElement = this.body
  }
  createElement(tag: string) { return new FakeElement(tag.toUpperCase(), HTML_NS, this) }
  createElementNS(ns: string, tag: string) { return new FakeElement(ns === HTML_NS ? tag.toUpperCase() : tag, ns, this) }
  createTextNode(t: string) { return new FakeText(t, this) }
}

/**
 * A window and document for the views ([vi.stubGlobal] them before React DOM
 * loads: it looks for a DOM once, as it starts), with animation frames the
 * test runs ([frames]) and window events it sends ([send]).
 */
export function fakeWindow(width = 1000, height = 800) {
  const doc = new FakeDocument()
  const frames = new Map<number, () => void>()
  let next = 1
  const target = new FakeNode(0, '#window', doc)
  const win = {
    document: doc, innerWidth: width, innerHeight: height,
    location: { hash: '', search: '', protocol: 'http:' },
    HTMLIFrameElement: class {},
    navigator: { userAgent: 'testDom' },
    event: undefined,
    addEventListener: (t: string, f: Listener) => target.addEventListener(t, f),
    removeEventListener: (t: string, f: Listener) => target.removeEventListener(t, f),
    dispatchEvent: (e: { type: string }) => target.dispatchEvent(e),
    requestAnimationFrame: (f: () => void) => { frames.set(next, f); return next++ },
    cancelAnimationFrame: (id: number) => { frames.delete(id) },
    getComputedStyle: () => ({}),
  } as Record<string, unknown>
  win.window = win
  win.self = win
  win.top = win
  win.parent = win
  doc.defaultView = win
  return {
    win, doc,
    /** Run the animation frames asked for so far. */
    frames() {
      const due = [...frames.values()]
      frames.clear()
      for (const f of due) f()
    },
    /** Send a window event ('resize', 'ph-settle'). */
    send(type: string) { target.dispatchEvent({ type }) },
    /** How many listeners the window holds for [type]. */
    listening: (type: string) => target.listeners.get(type)?.size ?? 0,
  }
}
