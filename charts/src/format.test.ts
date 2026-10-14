import { describe, expect, it } from 'vitest'
import { compass16, edgePlus, edgeTip, fmtDate, fmtDur, fmtIn, needsYear, scoreDecimals, touchesEdge } from './format'

const M = 60e3, H = 3600e3, D = 86400e3

/** The duration table shared with app/test/core/wording_test.dart (keep the two in sync). */
export const DURATION_TABLE: [ms: number, stepMin: number | undefined, text: string][] = [
  [0, undefined, '0 min'],
  [30 * M, undefined, '30 min'],
  [30 * M, 30, 'about 30 min'], // exactly one sample step
  [10 * M, 10, 'about 10 min'],
  [60 * M, 30, '1 h'], // two steps: not "about"
  [59 * M + 59e3, undefined, '59 min'], // floored, never "1 h"
  [9 * H + 30 * M, undefined, '9 h 30 min'],
  [9 * H, undefined, '9 h'], // "0 min" dropped
  [23 * H + 59 * M, undefined, '23 h 59 min'],
  [D, undefined, '1 d'],
  [10 * D + 21 * H, undefined, '10 d 21 h'],
  [10 * D + 21 * H + 59 * M, undefined, '10 d 21 h'], // floored, never 10 d 22 h
  [10 * D, undefined, '10 d'], // "0 h" dropped
  [5 * D + 16 * H + 30 * M, undefined, '5 d 16 h'], // never rounded up to 5 d 17 h
  [102 * D + 1 * H, undefined, '102 d 1 h'],
]

describe('fmtDur (charts spec 2.0)', () => {
  it('follows the shared duration table', () => {
    for (const [ms, stepMin, text] of DURATION_TABLE) expect(fmtDur(ms, { stepMin }), `${ms} ms`).toBe(text)
  })
  it('coarse keeps the largest unit, floored', () => {
    expect(fmtDur(10 * D + 21 * H + 59 * M, { coarse: true })).toBe('10 d')
    expect(fmtDur(9 * H + 59 * M, { coarse: true })).toBe('9 h')
    expect(fmtDur(30 * M, { coarse: true })).toBe('30 min')
  })
  it('relative times are floored too', () => {
    expect(fmtIn(10 * D + 18 * H + 59 * M)).toBe('in 10 d 18 h')
  })
  it('never prints NaN', () => {
    expect(fmtDur(NaN)).toBe('–')
  })
})

describe('fmtDate', () => {
  it('has no weekday and no leading zero, in UTC', () => {
    expect(fmtDate(Date.UTC(2026, 9, 21, 18, 0))).toBe('21 Oct 18:00')
    expect(fmtDate(Date.UTC(2027, 1, 7, 6, 5))).toBe('7 Feb 06:05')
    expect(fmtDate(Date.UTC(2027, 4, 1), { time: false })).toBe('1 May')
    expect(fmtDate(Date.UTC(2027, 1, 7, 6, 5))).not.toMatch(/Sun|Mon|Tue|Wed|Thu|Fri|Sat/)
  })
  it('adds the year only outside the 12 months from the period start', () => {
    const start = Date.UTC(2026, 9, 11)
    expect(fmtDate(Date.UTC(2027, 0, 21, 0, 30), { refMs: start })).toBe('21 Jan 00:30')
    expect(fmtDate(Date.UTC(2027, 9, 11, 0, 0), { refMs: start })).toBe('11 Oct 2027 00:00')
    expect(fmtDate(Date.UTC(2028, 1, 7, 6, 0), { refMs: start })).toBe('7 Feb 2028 06:00')
    expect(fmtDate(Date.UTC(2026, 9, 21, 18, 0), { year: true })).toBe('21 Oct 2026 18:00')
    expect(needsYear(Date.UTC(2026, 9, 10), start)).toBe(true)
  })
})

describe('compass16', () => {
  it('uses 16 points', () => {
    expect(compass16(161)).toBe('SSE')
    expect(compass16(161.27)).toBe('SSE')
    expect(compass16(337.25)).toBe('NNW')
    expect(compass16(0)).toBe('N')
    expect(compass16(359)).toBe('N')
    expect(compass16(-90)).toBe('W')
    expect(compass16(90)).toBe('E')
  })
})

describe('scoreDecimals', () => {
  it('uses the fewest decimals that keep different scores different', () => {
    expect(scoreDecimals([61.84375, 61.825913, 56.724315])).toBe(2)
    expect(scoreDecimals([61.84, 61.83, 56.72])).toBe(2)
    expect(scoreDecimals([62, 57])).toBe(0)
    expect(scoreDecimals([61.8, 61.6, 50])).toBe(1)
    expect(scoreDecimals([60, 60])).toBe(0) // equal scores are allowed to look equal
    expect(scoreDecimals([])).toBe(0)
  })
})

describe('edge +', () => {
  const range: [number, number] = [0, 365 * D]
  it('marks spells that touch the period ends', () => {
    expect(touchesEdge([0, 102 * D + H], range)).toBe(true)
    expect(touchesEdge([D, 2 * D], range)).toBe(false)
    expect(touchesEdge([300 * D, 365 * D], range)).toBe(true)
    expect(edgePlus('102 d', true)).toBe('102 d+')
    expect(edgePlus('7 d', false)).toBe('7 d')
  })
  it('says why in the tooltip', () => {
    expect(edgeTip([0, 102 * D + H], range)).toBe('at least 102 d 1 h (starts before your chosen dates)')
    expect(edgeTip([300 * D, 365 * D], range)).toBe('at least 65 d (goes on past your chosen dates)')
    expect(edgeTip([D, 2 * D], range)).toBe('1 d')
  })
})
