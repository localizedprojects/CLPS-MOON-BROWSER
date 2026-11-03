// The app supports Android 7.0+, whose stock WebView is Chrome 51 (the API
// 24 emulator's: 51.0.2704, where the sky plot and timeline were seen to
// draw): a bundle with newer syntax is a SyntaxError there and every chart
// stays blank. vite.config.ts lowers the build to Chrome 51 (build.target)
// and ships it as one classic script (Chrome < 61 runs no module script).
// This checks the shipped bundle (app/assets/charts, which CI rebuilds and
// compares): its syntax, and that every runtime API newer than Chrome 51 it
// names is polyfilled first (src/polyfills.ts), feature-tested, or on a path
// Chrome 51 never takes.
import ts from 'typescript'
import { describe, expect, it } from 'vitest'
import html from '../../app/assets/charts/index.html?raw'

const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)]
const js = scripts.map((m) => m[2]).join('\n;\n')
const parse = (text: string) => ts.createSourceFile('bundle.js', text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS)
const sf = parse(js)
const K = ts.SyntaxKind

const inFunction = (n: ts.Node) => {
  for (let p = n.parent; p; p = p.parent) if (ts.isFunctionLike(p)) return true
  return false
}
const around = (n: ts.Node) => js.slice(Math.max(0, n.getStart(sf) - 80), n.getEnd() + 20)

/** Syntax Chrome 51 cannot parse (the Chrome that can), by name: how often [src] has it. */
function newerSyntax(src: ts.SourceFile): Record<string, number> {
  const found: Record<string, number> = {}
  const add = (k: string) => { found[k] = (found[k] ?? 0) + 1 }
  const ops: Partial<Record<ts.SyntaxKind, string>> = {
    [K.AsteriskAsteriskToken]: '** (52)',
    [K.AsteriskAsteriskEqualsToken]: '** (52)',
    [K.QuestionQuestionToken]: '?? (80)',
    [K.BarBarEqualsToken]: 'logical assignment (85)',
    [K.AmpersandAmpersandEqualsToken]: 'logical assignment (85)',
    [K.QuestionQuestionEqualsToken]: 'logical assignment (85)',
  }
  const modifier = (n: ts.Node, k: ts.SyntaxKind) => ts.canHaveModifiers(n) && !!ts.getModifiers(n)?.some((m) => m.kind === k)
  const visit = (n: ts.Node) => {
    if ((n as { questionDotToken?: unknown }).questionDotToken) add('?. (80)')
    if (ts.isBinaryExpression(n) && ops[n.operatorToken.kind]) add(ops[n.operatorToken.kind]!)
    if (modifier(n, K.AsyncKeyword)) add('async function (55)')
    if (ts.isAwaitExpression(n) || (ts.isForOfStatement(n) && n.awaitModifier)) add('await (55, for await 63)')
    if (ts.isSpreadAssignment(n)) add('object spread (60)')
    if (ts.isObjectBindingPattern(n) && n.elements.some((e) => e.dotDotDotToken)) add('object rest (60)')
    if (ts.isCatchClause(n) && !n.variableDeclaration) add('catch without binding (66)')
    if ((ts.isCallExpression(n) || ts.isNewExpression(n)) && n.arguments?.hasTrailingComma) add('trailing comma (58)')
    if (ts.isFunctionLike(n) && n.parameters.hasTrailingComma) add('trailing comma (58)')
    if (n.kind === K.PropertyDeclaration) add('class field (72)')
    if (n.kind === K.PrivateIdentifier) add('#private (74)')
    if (n.kind === K.ClassStaticBlockDeclaration) add('static block (94)')
    if (n.kind === K.NumericLiteral && n.getText(src).includes('_')) add('numeric separator (75)')
    if (n.kind === K.BigIntLiteral) add('bigint (67)')
    // a classic script: module syntax is a SyntaxError there
    if (ts.isImportDeclaration(n) || ts.isExportDeclaration(n) || ts.isExportAssignment(n) || modifier(n, K.ExportKeyword)) add('import/export')
    if (ts.isMetaProperty(n) && n.keywordToken === K.ImportKeyword) add('import.meta')
    if (ts.isCallExpression(n) && n.expression.kind === K.ImportKeyword) add('import() (63)')
    if (n.kind === K.RegularExpressionLiteral) {
      const t = n.getText(src), body = t.slice(1, t.lastIndexOf('/')), flags = t.slice(t.lastIndexOf('/') + 1)
      if (/[sdv]/.test(flags)) add('regex s, d or v flag (62+)')
      if (/\(\?<[=!]/.test(body)) add('regex lookbehind (62)')
      if (/\(\?<[A-Za-z_$]|\\k</.test(body)) add('regex named group (64)')
      if (/\\[pP]\{/.test(body) && flags.includes('u')) add('regex \\p{...} (64)')
    }
    ts.forEachChild(n, visit)
  }
  visit(src)
  // a raw U+2028/U+2029 in a string literal parses only from Chrome 66 (ES2019)
  if (/[\u2028\u2029]/.test(src.text)) add('raw U+2028/U+2029 (66)')
  return found
}

/**
 * Runtime APIs newer than Chrome 51 (versions in the comments) that the
 * bundle must not name at all, as a property (x.padEnd, Object.fromEntries)
 * or as a global. A new use needs a polyfill in src/polyfills.ts (and the
 * list below) or a typeof guard. Not listed: names libraries use for their
 * own things (d3's selection.append, Plotly's Lib.flat, a d3 chord's groups).
 */
const NEVER_PROPS = new Set([
  'padEnd', 'formatToParts', 'getAttributeNames', 'visualViewport', // 57, 61
  'timeOrigin', 'asyncIterator', 'PluralRules', 'trimStart', // 62 to 66
  'flatMap', 'toggleAttribute', 'transferControlToOffscreen', // 69
  'RelativeTimeFormat', 'ListFormat', 'fromEntries', 'matchAll', 'adoptedStyleSheets', // 71 to 73
  'formatRange', 'replaceAll', 'any', 'replaceChildren', 'Segmenter', // 76 to 87
  'at', 'randomUUID', 'hasOwn', 'findLast', 'findLastIndex', 'checkVisibility', // 92 to 105
  'toSorted', 'toReversed', 'toSpliced', 'groupBy', 'withResolvers', // 110 to 119
  'prepend', 'replaceWith', 'composedPath', 'attachShadow', // DOM, 53 and 54
])
// minified local names are 1 to 3 characters, so a global is never one of them
const NEVER_GLOBALS = new Set([
  'PointerEvent', 'customElements', 'WebAssembly', 'DOMMatrix', 'BigInt', 'OffscreenCanvas', // 54 to 69
  'WeakRef', 'FinalizationRegistry', 'AggregateError', 'structuredClone', // 84 to 98
])

/** Newer than Chrome 51 and named by the bundle: src/polyfills.ts defines each where it is missing. */
const POLYFILLED: Array<[owner: string, name: string]> = [
  ['Object', 'getOwnPropertyDescriptors'], // 54
  ['Object', 'values'], // 54
  ['Object', 'entries'], // 54
  ['String.prototype', 'padStart'], // 57
  ['String.prototype', 'trimEnd'], // 66
]

/** Newer than Chrome 51 and named by the bundle, only behind `typeof X` (with a fallback). */
const GUARDED = new Set(['ResizeObserver', 'AbortController', 'globalThis', 'queueMicrotask', 'reportError', 'setImmediate']) // 64 66 71 71 95, none

/** Whether [n] runs only where `typeof name` was tested first (a ?: or an if on it), or in a try block. */
function guarded(n: ts.Node, name: string): boolean {
  for (let p: ts.Node = n; p.parent; p = p.parent) {
    const c = p.parent
    if (ts.isConditionalExpression(c) && p !== c.condition && c.condition.getText(sf).includes(`typeof ${name}`)) return true
    if (ts.isIfStatement(c) && p !== c.expression && c.expression.getText(sf).includes(`typeof ${name}`)) return true
    if (ts.isTryStatement(c) && p === c.tryBlock) return true
    // a function expression made in a guarded branch exists only there; a declared one may run anywhere
    if (ts.isFunctionLike(c) && !ts.isFunctionExpression(c) && !ts.isArrowFunction(c)) return false
  }
  return false
}

describe('the shipped bundle runs on Android 7.0 (WebView 51)', () => {
  it('is one classic script at the end of <body>: Chrome < 61 runs no <script type="module">', () => {
    expect(js.length).toBeGreaterThan(100_000)
    expect(scripts.map((m) => m[1].trim())).toEqual(['']) // no type, no src
    expect(html).toMatch(/<\/script>\s*<\/body>\s*<\/html>\s*$/) // the page is parsed when it runs, as with a module
  })
  it('parses: no syntax newer than Chrome 51', () => {
    expect(newerSyntax(sf)).toEqual({})
  })
  it('the syntax check finds what it is for', () => {
    const lines = [
      'a ** 2', 'a ?? b', 'a?.b', 'a ||= b', 'async function f() {}', 'for await (const x of y) {}', 'x = { ...o }',
      '({ a, ...r } = o)', 'try {} catch {}', 'f(a, b,)', 'class C { p = 1 }', 'class D { #q; static {} }', '1_000', '1n',
      'export const z = 1', 'import.meta', 'import("x")', '/./s', '/(?<=\\.) /', '/(?<y>1)/', '/\\p{L}/u', '"\u2028"',
    ]
    const found = lines.map((l) => Object.keys(newerSyntax(parse(l))))
    expect(found.filter((f) => f.length === 0)).toEqual([])
    expect(newerSyntax(parse('var a = [1, 2]; function f(b = 1, ...c) { return `${b}` + [...c] }; class E {}; /./gimuy'))).toEqual({})
  })
  it('names none of the newer runtime APIs that have no polyfill or guard', () => {
    const used = new Set<string>()
    const visit = (n: ts.Node) => {
      if (ts.isPropertyAccessExpression(n) && NEVER_PROPS.has(n.name.text)) used.add(`.${n.name.text}: ${n.getText(sf).slice(-60)}`)
      if (ts.isElementAccessExpression(n) && ts.isStringLiteralLike(n.argumentExpression) && NEVER_PROPS.has(n.argumentExpression.text)) used.add(`[${n.argumentExpression.text}]`)
      if (ts.isIdentifier(n) && NEVER_GLOBALS.has(n.text) && !ts.isPropertyAccessExpression(n.parent)) used.add(n.text)
      ts.forEachChild(n, visit)
    }
    visit(sf)
    expect([...used]).toEqual([])
  })
  it('has the polyfills (src/polyfills.ts, which runs before any library) for the newer ones it calls', () => {
    // polyfills.ts is main.tsx's first import and imports nothing (polyfills.test.ts checks)
    for (const [owner, name] of POLYFILLED) expect(js, `${owner}.${name}`).toContain(`${owner},\`${name}\``)
    expect(js, 'Node.prototype.isConnected (54)').toMatch(/`isConnected`in Node\.prototype/)
  })
  it('reaches the feature-tested ones only behind typeof (or in a try)', () => {
    const bare: string[] = []
    let domPoint = 0
    const visit = (n: ts.Node) => {
      if (ts.isIdentifier(n) && !ts.isPropertyAccessExpression(n.parent) && !ts.isTypeOfExpression(n.parent)) {
        if (GUARDED.has(n.text) && !guarded(n, n.text)) bare.push(`${n.text}: ${around(n)}`)
        // new DOMPoint (61): Plotly's isPointInFill test, in a try with a fallback
        if (n.text === 'DOMPoint' && ++domPoint && !guarded(n, n.text)) bare.push(`DOMPoint: ${around(n)}`)
      }
      ts.forEachChild(n, visit)
    }
    visit(sf)
    expect(bare).toEqual([])
    expect(domPoint).toBeLessThanOrEqual(1)
  })
  it('reaches the rest only in React view transitions, which Chrome 51 never starts', () => {
    // Promise.allSettled (76), Promise#finally (63) and new DOMRect (61) are
    // React DOM's view-transition code: document.startViewTransition is Chrome
    // 111, and the charts render no <ViewTransition> (checked in the source)
    const bare: string[] = []
    const count = { allSettled: 0, finally: 0, DOMRect: 0 }
    const inReactDom = (n: ts.Node) => {
      // the CommonJS module function it is in (the outermost one inside the bundle's IIFE)
      let fn: ts.Node | undefined
      for (let p = n.parent; p; p = p.parent) if (ts.isFunctionLike(p) && inFunction(p)) fn = p
      const text = fn?.getText(sf) ?? ''
      return text.includes('.startViewTransition(') && text.includes('__reactViewTransition')
    }
    const visit = (n: ts.Node) => {
      if (ts.isPropertyAccessExpression(n) && n.name.text === 'allSettled') {
        count.allSettled++
        let p: ts.Node | undefined = n.parent
        while (p && !(ts.isFunctionLike(p) && p.getText(sf).includes('.startViewTransition('))) p = p.parent
        if (!p) bare.push(`allSettled: ${around(n)}`)
      }
      // only on a ViewTransition's `finished` promise
      if (ts.isPropertyAccessExpression(n) && n.name.text === 'finally') {
        count.finally++
        const onFinished = ts.isPropertyAccessExpression(n.expression) && n.expression.name.text === 'finished'
        if (!onFinished || !inReactDom(n)) bare.push(`finally: ${around(n)}`)
      }
      if (ts.isIdentifier(n) && n.text === 'DOMRect' && !ts.isPropertyAccessExpression(n.parent)) {
        count.DOMRect++
        if (!inReactDom(n)) bare.push(`DOMRect: ${around(n)}`)
      }
      ts.forEachChild(n, visit)
    }
    visit(sf)
    expect(bare).toEqual([])
    expect(count, 'a new one: recheck it, then the count').toEqual({ allSettled: 1, finally: 2, DOMRect: 1 })
    const src = import.meta.glob(['./**/*.{ts,tsx}', '!./**/*.test.{ts,tsx}'], { query: '?raw', import: 'default', eager: true }) as Record<string, string>
    expect(Object.keys(src)).toContain('./main.tsx')
    expect(Object.entries(src).filter(([, s]) => /ViewTransition|addTransitionType/.test(s)).map(([f]) => f)).toEqual([])
  })
})
