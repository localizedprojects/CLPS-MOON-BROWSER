import { describe, expect, it } from 'vitest'
import main from './main.tsx?raw'
import { parsesSelector, skipUnparsedRules } from './polyfills'

/** A stylesheet that, like Chrome 69's, cannot parse :focus-visible. */
class OldSheet {
  rules: string[] = []
  insertRule(rule: string, index = 0) {
    if (rule.includes(':focus-visible')) throw Object.assign(new Error(`Failed to parse the rule '${rule}'.`), { name: 'SyntaxError' })
    if (rule.includes('boom')) throw new TypeError('not a parse error')
    this.rules.splice(index, 0, rule)
    return index
  }
}

describe('polyfills for Chrome 69 (Android 7.0 WebView)', () => {
  it('the :focus-visible rule of Plotly is skipped, not thrown, and the other rules still go in', () => {
    const plotlyRule = '.js-plotly-plot .plotly .modebar-btn:focus-visible{outline:1px solid #000;}'
    expect(() => new OldSheet().insertRule(plotlyRule, 0)).toThrow() // what blanked every chart
    skipUnparsedRules(OldSheet.prototype)
    const s = new OldSheet()
    expect(s.insertRule('.a{color:red}', 0)).toBe(0)
    expect(s.insertRule(plotlyRule, 0)).toBe(-1)
    expect(s.insertRule('.b{color:blue}', 0)).toBe(0)
    expect(s.rules).toEqual(['.b{color:blue}', '.a{color:red}'])
    expect(() => s.insertRule('.boom{}')).toThrow(TypeError) // only parse errors are skipped
  })
  it('is installed only where :focus-visible does not parse', () => {
    const doc = (ok: boolean) => ({ querySelector: (sel: string) => { if (!ok && sel.includes(':focus-visible')) throw new SyntaxError(sel); return null } })
    expect(parsesSelector(doc(true), ':focus-visible')).toBe(true)
    expect(parsesSelector(doc(false), ':focus-visible')).toBe(false)
  })
  it('main.tsx loads them before anything else', () => {
    expect(main.match(/^import .*$/m)?.[0]).toBe("import './polyfills'")
  })
  it('inline styles use no CSS newer than Chrome 69 (the CSS file is lowered, React styles are not)', () => {
    // inset (Chrome 87) left the sky overlay with no size there, so its Sun
    // and Earth markers never showed; top/right/bottom/left say the same
    const views = import.meta.glob('./*.tsx', { query: '?raw', import: 'default', eager: true }) as Record<string, string>
    const found = Object.entries(views).filter(([, src]) => /\b(inset|aspectRatio|inlineSize|blockSize)\s*:/.test(src)).map(([f]) => f)
    expect(found).toEqual([])
  })
})
