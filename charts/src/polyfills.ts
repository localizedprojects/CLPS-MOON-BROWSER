// What the charts run that Android 7.0's stock WebView (Chrome 51, the
// oldest the app supports) lacks. main.tsx imports this first, before any
// library runs. Each fix is feature-detected: a newer browser gets nothing.
// (Syntax is lowered by vite.config.ts build.target; src/bundleTarget.test.ts
// checks the bundle names no newer runtime API unpolyfilled or unguarded.)

/** Whether [doc] parses the selector [sel] (an unknown one throws). */
export function parsesSelector(doc: Pick<Document, 'querySelector'>, sel: string): boolean {
  try {
    doc.querySelector(sel)
    return true
  } catch {
    return false
  }
}

/**
 * Make [proto].insertRule skip a rule the browser cannot parse instead of
 * throwing. Plotly adds its stylesheet rule by rule at load, one of them with
 * :focus-visible (Chrome 86): older ones throw a SyntaxError for it, Plotly
 * never finishes loading and every chart stays blank.
 */
export function skipUnparsedRules(proto: Pick<CSSStyleSheet, 'insertRule'>) {
  const insert = proto.insertRule
  proto.insertRule = function (this: CSSStyleSheet, rule: string, index?: number) {
    try {
      return insert.call(this, rule, index)
    } catch (e) {
      if ((e as { name?: unknown } | null)?.name !== 'SyntaxError') throw e
      return -1 // skipped: nothing reads the index
    }
  }
}

if (typeof document !== 'undefined' && typeof CSSStyleSheet !== 'undefined' && !parsesSelector(document, ':focus-visible')) {
  skipUnparsedRules(CSSStyleSheet.prototype)
}

/** Define [name] on [o] (not enumerable, as built-ins are) only where it has none. */
export function defineMissing(o: object, name: string, value: unknown) {
  if (!(name in o)) Object.defineProperty(o, name, { value, writable: true, configurable: true })
}

/** Object.getOwnPropertyDescriptors (Chrome 54). */
export function getOwnPropertyDescriptors(o: object): PropertyDescriptorMap {
  const r: PropertyDescriptorMap = {}
  for (const k of Reflect.ownKeys(o)) {
    const d = Object.getOwnPropertyDescriptor(o, k)
    // defined, not assigned: an own "__proto__" key stays a key
    if (d) Object.defineProperty(r, k, { value: d, writable: true, enumerable: true, configurable: true })
  }
  return r
}

/** String.prototype.padStart (Chrome 57). */
export function padStart(this: string, maxLength: number, fill?: string): string {
  const s = String(this), n = Math.floor(Number(maxLength)) || 0, f = fill === undefined ? ' ' : String(fill)
  if (n <= s.length || f === '') return s
  const k = n - s.length
  return f.repeat(Math.ceil(k / f.length)).slice(0, k) + s
}

// Chrome 51 (Android 7.0's stock WebView) lacks these, which the bundle calls:
// Object.getOwnPropertyDescriptors (54): Plotly's own build lowered object
// spread with it and reads it once as Plotly loads (then its colour code
// calls it); Object.values and Object.entries (54): bridge.ts, Plotly's
// shapes; String padStart (57) and trimEnd (66): format.ts, strip.ts;
// Node.isConnected (54): usePlot.ts.
defineMissing(Object, 'getOwnPropertyDescriptors', getOwnPropertyDescriptors)
defineMissing(Object, 'values', (o: object) => Object.keys(o).map((k) => (o as Record<string, unknown>)[k]))
defineMissing(Object, 'entries', (o: object) => Object.keys(o).map((k) => [k, (o as Record<string, unknown>)[k]]))
defineMissing(String.prototype, 'padStart', padStart)
defineMissing(String.prototype, 'trimEnd', function (this: string) { return String(this).replace(/\s+$/, '') })
if (typeof Node !== 'undefined' && !('isConnected' in Node.prototype)) {
  Object.defineProperty(Node.prototype, 'isConnected', {
    configurable: true,
    get(this: Node) { return (this.ownerDocument || (this as Node as Document)).contains(this) },
  })
}
