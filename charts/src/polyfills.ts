// What the charts run that Android 7.0's stock WebView (Chrome 69, the
// oldest the app supports) lacks. main.tsx imports this first, before any
// library runs. Each fix is feature-detected: a newer browser gets nothing.
// (Syntax is lowered by vite.config.ts build.target; src/bundleTarget.test.ts
// checks the bundle names no newer runtime API unguarded.)

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
 * :focus-visible (Chrome 86): Chrome 69 throws a SyntaxError for it, Plotly
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
