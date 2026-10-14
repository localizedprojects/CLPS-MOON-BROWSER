import { describe, expect, it } from 'vitest'
import { dispatchForTests, latest, resetBridgeForTests } from './bridge'
import { tabLeaves } from './focusHandoff'

describe('keyboard focus hand-off to the host (a11y-1)', () => {
  it('Tab leaves after the last control, Shift+Tab before the first, and from outside the order', () => {
    const order = ['span', 'detail', 'track', 'next']
    expect(tabLeaves(order, 'next', false)).toBe(true)
    expect(tabLeaves(order, 'track', false)).toBe(false)
    expect(tabLeaves(order, 'span', true)).toBe(true)
    expect(tabLeaves(order, 'detail', true)).toBe(false)
    expect(tabLeaves(order, null, false)).toBe(true)
    expect(tabLeaves([], null, true)).toBe(true)
  })
  it('focusFirst is one-shot: a view that mounts later is not re-focused by a replay', () => {
    resetBridgeForTests()
    dispatchForTests({ type: 'focusFirst' })
    expect(latest('focusFirst')).toBeNull()
  })
})
