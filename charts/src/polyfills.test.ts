import { describe, expect, it } from 'vitest'
import main from './main.tsx?raw'
import polyfillsSrc from './polyfills.ts?raw'
import { defineMissing, getOwnPropertyDescriptors, padStart, parsesSelector, skipUnparsedRules } from './polyfills'

/** A stylesheet that, like Chrome 51's (or 69's), cannot parse :focus-visible. */
class OldSheet {
  rules: string[] = []
  insertRule(rule: string, index = 0) {
    if (rule.includes(':focus-visible')) throw Object.assign(new Error(`Failed to parse the rule '${rule}'.`), { name: 'SyntaxError' })
    if (rule.includes('boom')) throw new TypeError('not a parse error')
    this.rules.splice(index, 0, rule)
    return index
  }
}

describe('polyfills for Chrome 51 (Android 7.0 WebView)', () => {
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
  it('main.tsx loads them before anything else, and they import nothing (so they run first)', () => {
    expect(main.match(/^import .*$/m)?.[0]).toBe("import './polyfills'")
    expect(polyfillsSrc).not.toMatch(/^\s*import\b/m)
  })
  it('defineMissing adds a built-in only where there is none, as built-ins are (not enumerable)', () => {
    const o: Record<string, unknown> = { own: 1 }
    defineMissing(o, 'own', 2)
    defineMissing(o, 'added', 3)
    expect(o.own).toBe(1)
    expect(o.added).toBe(3)
    expect(Object.keys(o)).toEqual(['own'])
    const proto = { inherited() {} }
    const child = Object.create(proto) as object
    defineMissing(child, 'inherited', 4)
    expect(Object.getOwnPropertyNames(child)).toEqual([]) // a newer browser keeps its own
  })
  it('Object.getOwnPropertyDescriptors and String padStart behave as the built-ins do', () => {
    const sym = Symbol('s')
    const o = Object.defineProperty({ a: 1, [sym]: 2 }, 'g', { get: () => 3, enumerable: false })
    Object.defineProperty(o, '__proto__', { value: 4, enumerable: true }) // an own key, not the prototype
    expect(getOwnPropertyDescriptors(o)).toEqual(Object.getOwnPropertyDescriptors(o))
    expect(Object.getPrototypeOf(getOwnPropertyDescriptors(o))).toBe(Object.prototype)
    const cases: Array<[string, number, string?]> = [['5', 2, '0'], ['12', 2, '0'], ['abc', 10, '12'], ['x', 4], ['x', 3, ''], ['x', -1, '0'], ['x', 2.9, '-']]
    for (const [s, n, f] of cases) expect(padStart.call(s, n, f), `${s} ${n} ${f}`).toBe(s.padStart(n, f))
  })
  it('inline styles use no CSS newer than Chrome 51 (the CSS file is lowered, React styles and HTML strings are not)', () => {
    // inset (Chrome 87) left the sky overlay with no size there, so its Sun
    // and Earth markers never showed; top/right/bottom/left say the same.
    // Flex gap is Chrome 84: there the items of a row touch (margins instead).
    // CSS grid is Chrome 57: styles.css has the grids, with fallbacks
    const src = import.meta.glob(['./**/*.{ts,tsx}', '!./**/*.test.{ts,tsx}'], { query: '?raw', import: 'default', eager: true }) as Record<string, string>
    expect(Object.keys(src)).toContain('./skyOverlay.ts')
    // React style objects (gap there is a data field in strip.ts)
    const objects = Object.entries(src).filter(([f, s]) => f.endsWith('.tsx') && (/\b(gap|rowGap|columnGap|inset|aspectRatio|inlineSize|blockSize)\s*:/.test(s) || /display:\s*'(inline-)?grid'/.test(s))).map(([f]) => f)
    // style="..." in the HTML strings (the overlays)
    const strings = Object.entries(src).filter(([, s]) => /[;"'`]\s*(gap|row-gap|column-gap|inset|aspect-ratio)\s*:/.test(s) || /[;"'`]\s*display\s*:\s*(inline-)?grid/.test(s)).map(([f]) => f)
    expect({ objects, strings }).toEqual({ objects: [], strings: [] })
  })
  it('the checks above catch what they are for', () => {
    const obj = /\b(gap|rowGap|columnGap|inset|aspectRatio|inlineSize|blockSize)\s*:/
    const str = /[;"'`]\s*(gap|row-gap|column-gap|inset|aspect-ratio)\s*:/
    for (const s of ["{ display: 'flex', gap: 6 }", "{ rowGap: 4 }", "{ columnGap: 8 }", "{ inset: 0 }"]) expect(s).toMatch(obj)
    for (const s of ['style="position:absolute;inset:0"', '"display:flex;column-gap:8px"', "'gap:4px'", '`a;row-gap: 2px`']) expect(s).toMatch(str)
    for (const s of ["{ gap: 'dark' }", 'bargap: 0.25', 'a 1-point gap)']) expect(s).not.toMatch(str)
  })
  it('styles.css has gap only on grid boxes (flex gap is Chrome 84), and each grid a fallback without grid (Chrome < 57)', async () => {
    // read from disk: vitest hands a .css import over empty (Node, without its types here)
    const fs = (await import(/* @vite-ignore */ 'node:' + 'fs')) as { readFileSync: (p: URL, enc: 'utf8') => string }
    const css = fs.readFileSync(new URL('./styles.css', import.meta.url), 'utf8')
    const rules = css.split('}').filter((r) => /(^|[\s;{])(row-|column-)?gap\s*:/.test(r))
    expect(rules.length).toBeGreaterThan(0) // the grids moved here from the views
    for (const r of rules) expect(r).toMatch(/display:\s*grid/)
    const grids = [...css.matchAll(/(\.[\w-]+)\s*\{[^}]*display:\s*grid/g)].map((m) => m[1])
    const fallback = css.slice(css.indexOf('@supports not (display: grid)'))
    expect(grids.length).toBeGreaterThan(0)
    expect(fallback.length).toBeLessThan(css.length)
    for (const g of grids) expect(fallback, g).toContain(`${g} `)
  })
  it('the scroll columns keep their items at content height (Chrome 51 shrank them: the When key line drew under "Coming up", F3)', async () => {
    const fs = (await import(/* @vite-ignore */ 'node:' + 'fs')) as { readFileSync: (p: URL, enc: 'utf8') => string }
    const css = fs.readFileSync(new URL('./styles.css', import.meta.url), 'utf8')
    expect(css).toMatch(/\.ph-col4 > \*, \.ph-col6 > \* \{ flex-shrink: 0; \}/)
    // only on the views' scroll boxes, where an item never has to shrink (the box scrolls instead)
    const src = import.meta.glob(['./**/*.tsx', '!./**/*.test.tsx'], { query: '?raw', import: 'default', eager: true }) as Record<string, string>
    const uses = Object.entries(src).flatMap(([f, s]) => s.split('\n').filter((l) => /ph-col[46]/.test(l)).map((l) => [f, l] as const))
    expect(uses.map(([f]) => f).sort()).toEqual(['./SkyView.tsx', './TimelineView.tsx'])
    for (const [f, l] of uses) expect(l, f).toMatch(/overflowY: 'auto'/)
  })
})
