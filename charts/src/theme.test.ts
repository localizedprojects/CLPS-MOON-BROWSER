// charts-2: the chart tokens mirror app/lib/theme.dart and styles.css.
import { describe, expect, it } from 'vitest'
// @ts-expect-error node's types are not installed; vitest runs these tests in node
import { readFileSync } from 'node:fs'
import dart from '../../app/lib/theme.dart?raw'
import focus from '../../app/lib/widgets/chart_focus.dart?raw'
import skySrc from './SkyView.tsx?raw'
import { C, HOST_CORNER_PX } from './theme'
import timelineSrc from './TimelineView.tsx?raw'

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

describe("the host's full-screen button corner (F3, 2026-11-03)", () => {
  it('HOST_CORNER_PX covers the 48 px button FocusableChart puts 2 px in from the top-right corner, plus 2 px', () => {
    const btn = /Positioned\(\s*top: (\d+),\s*right: (\d+),\s*child: ChartFocusButton\(/.exec(focus)
    const size = /minimumSize: const Size\((\d+), (\d+)\)/.exec(focus)
    expect(btn, 'FocusableChart overlay button').not.toBeNull()
    expect(size, 'ChartFocusButton size').not.toBeNull()
    expect(btn![1]).toBe(btn![2])
    expect(Number(btn![2]) + Number(size![1]) + 2).toBe(HOST_CORNER_PX)
    expect(Number(btn![1]) + Number(size![2]) + 2).toBe(HOST_CORNER_PX)
  })
  it('the simple When and Where views keep their top-right line and "Exact numbers" clear of it', () => {
    expect(timelineSrc).toMatch(/paddingRight: HOST_CORNER_PX - PAD_X/)
    expect(timelineSrc).toMatch(/corner=\{i === \(narrow \? 0 : 1\)\}/) // the top-right line: one column, or the second of two
    expect(skySrc).toMatch(/minHeight: 40, paddingRight: HOST_CORNER_PX - PAD/)
  })
})
