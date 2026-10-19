// The app supports Android 7.0+, whose stock WebView is Chrome 69 (the API
// 24 emulator's): a bundle with newer syntax is a SyntaxError there and
// every chart stays blank. vite.config.ts lowers the build to Chrome 69
// (build.target); this checks the shipped bundle (app/assets/charts, which
// CI rebuilds and compares) and that it names none of the newer runtime
// APIs that would throw there.
import ts from 'typescript'
import { describe, expect, it } from 'vitest'
import html from '../../app/assets/charts/index.html?raw'

const js = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]).join('\n;\n')
const sf = ts.createSourceFile('bundle.js', js, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS)
const K = ts.SyntaxKind

const inFunction = (n: ts.Node) => {
  for (let p = n.parent; p; p = p.parent) if (ts.isFunctionLike(p)) return true
  return false
}

/** Syntax Chrome 69 cannot parse, by name: how often the bundle has it. */
function newerSyntax(): Record<string, number> {
  const found: Record<string, number> = {}
  const add = (k: string) => { found[k] = (found[k] ?? 0) + 1 }
  const assign: Partial<Record<ts.SyntaxKind, string>> = {
    [K.QuestionQuestionToken]: '??',
    [K.BarBarEqualsToken]: '||=',
    [K.AmpersandAmpersandEqualsToken]: '&&=',
    [K.QuestionQuestionEqualsToken]: '??=',
  }
  const visit = (n: ts.Node) => {
    if ((n as { questionDotToken?: unknown }).questionDotToken) add('?.')
    if (ts.isBinaryExpression(n) && assign[n.operatorToken.kind]) add(assign[n.operatorToken.kind]!)
    if (n.kind === K.PropertyDeclaration) add('class field')
    if (n.kind === K.PrivateIdentifier) add('#private')
    if (n.kind === K.ClassStaticBlockDeclaration) add('static block')
    if (n.kind === K.NumericLiteral && n.getText(sf).includes('_')) add('numeric separator')
    if (n.kind === K.RegularExpressionLiteral && /\/[a-z]*[dv][a-z]*$/.test(n.getText(sf))) add('regex d or v flag')
    if ((ts.isAwaitExpression(n) || (ts.isForOfStatement(n) && n.awaitModifier)) && !inFunction(n)) add('top-level await')
    ts.forEachChild(n, visit)
  }
  visit(sf)
  return found
}

/**
 * Runtime APIs newer than Chrome 69 that the bundle does not name at all: as
 * a property (x.at, Object.hasOwn) or as a global. A new use needs a typeof
 * guard or a small polyfill imported first in main.tsx. (The newer ones it
 * does name are guarded, checked below: globalThis, queueMicrotask and
 * reportError behind typeof; Promise.allSettled inside React's
 * startViewTransition path, which Chrome 69 never takes.) Array sort
 * stability (Chrome 70) is not an API: format.ts sortedStable covers it.
 */
const LATER_PROPS = new Set([
  'at', 'hasOwn', 'replaceAll', 'findLast', 'findLastIndex', 'fromEntries', 'matchAll', 'toSorted', 'toReversed',
  'toSpliced', 'groupBy', 'replaceChildren', 'randomUUID', 'withResolvers', 'formatRange', 'checkVisibility',
])
// minified local names are 1 to 3 characters, so a global is never one of them
const LATER_GLOBALS = new Set(['structuredClone', 'WeakRef', 'FinalizationRegistry', 'AggregateError'])

describe('the shipped bundle runs on Android 7.0 (WebView 69)', () => {
  it('parses: no syntax newer than Chrome 69', () => {
    expect(js.length).toBeGreaterThan(100_000)
    expect(newerSyntax()).toEqual({})
  })
  it('names none of the newer runtime APIs', () => {
    const used = new Set<string>()
    const visit = (n: ts.Node) => {
      if (ts.isPropertyAccessExpression(n) && LATER_PROPS.has(n.name.text)) used.add(`.${n.name.text}: ${n.getText(sf).slice(-60)}`)
      if (ts.isElementAccessExpression(n) && ts.isStringLiteralLike(n.argumentExpression) && LATER_PROPS.has(n.argumentExpression.text)) used.add(`[${n.argumentExpression.text}]`)
      if (ts.isIdentifier(n) && LATER_GLOBALS.has(n.text) && !ts.isPropertyAccessExpression(n.parent)) used.add(n.text)
      ts.forEachChild(n, visit)
    }
    visit(sf)
    expect([...used]).toEqual([])
  })
  it('reaches the newer APIs it does name only where Chrome 69 has them or never goes', () => {
    // globalThis 71, queueMicrotask 71, reportError 95: only behind typeof X
    const guarded = new Set(['globalThis', 'queueMicrotask', 'reportError'])
    const bare: string[] = []
    let settled = 0
    const visit = (n: ts.Node) => {
      if (ts.isIdentifier(n) && guarded.has(n.text) && !ts.isPropertyAccessExpression(n.parent) && !ts.isTypeOfExpression(n.parent)) {
        let ok = false
        for (let p: ts.Node = n; p.parent && !ok; p = p.parent) {
          const c = p.parent
          ok = ts.isConditionalExpression(c) && c.whenTrue === p && c.condition.getText(sf).includes(`typeof ${n.text}`)
        }
        if (!ok) bare.push(`${n.text}: ${js.slice(n.getStart(sf) - 80, n.getEnd() + 20)}`)
      }
      // Promise.allSettled (76): only in React's view transitions (Chrome 111+)
      if (ts.isPropertyAccessExpression(n) && n.name.text === 'allSettled') {
        settled++
        let p: ts.Node | undefined = n.parent
        while (p && !(ts.isFunctionLike(p) && p.getText(sf).includes('.startViewTransition('))) p = p.parent
        if (!p) bare.push(`allSettled: ${js.slice(n.getStart(sf) - 80, n.getEnd() + 20)}`)
      }
      ts.forEachChild(n, visit)
    }
    visit(sf)
    expect(bare).toEqual([])
    expect(settled).toBeLessThanOrEqual(1)
  })
})
