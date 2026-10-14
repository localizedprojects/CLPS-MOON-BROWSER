// charts-2: the chart tokens mirror app/lib/theme.dart and styles.css.
import { describe, expect, it } from 'vitest'
// @ts-expect-error node's types are not installed; vitest runs these tests in node
import { readFileSync } from 'node:fs'
import dart from '../../app/lib/theme.dart?raw'
import { C } from './theme'

const css: string = readFileSync(new URL('./styles.css', import.meta.url), 'utf8')
const dartColors = new Map([...dart.matchAll(/static const (\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)/g)].map((m) => [m[1], `#${m[2].toUpperCase()}`]))
const dartColor = (name: string) => dartColors.get(name) ?? null
const cssVar = (name: string) => [...css.matchAll(/--([\w-]+):\s*(#[0-9a-fA-F]{6})/g)].find((m) => m[1] === name)?.[2].toUpperCase() ?? null

describe('design tokens (charts-2)', () => {
  it('the chart hairline is the app hairline (PH.line, --line)', () => {
    expect(C.grid).toBe(dartColor('line'))
    expect(C.grid).toBe(cssVar('line'))
  })
  it('the chart background is the card colour (PH.panel)', () => {
    expect(C.bg).toBe(dartColor('panel'))
  })
})
