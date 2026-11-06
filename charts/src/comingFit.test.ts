/**
 * "Coming up" in the Simple view timeline shows only the rows that fit whole
 * below the strip, and says how many more there are (F1: on phones and in a
 * 1440 px window the frame cut the list, the rest in a scroll area the frame hid).
 */
import { describe, expect, it } from 'vitest'
import timelineSrc from './TimelineView.tsx?raw'
import { comingFit, comingMoreText } from './timelineAnswer'

/** A Coming up row (48 px target) and the "N more" line, as Chromium draws them. */
const ROW = 48
const MORE = 22
/** The view's bottom padding. */
const PAD_B = 4

/** Where the last thing in the list ends, from the first row's top, with [k] of [n] rows shown. */
const end = (top: number, k: number, n: number) => top + k * ROW + (k < n ? MORE : 0)

describe('comingFit', () => {
  it('keeps every row when they all fit, with no "more" line', () => {
    expect(comingFit(3 * ROW, [ROW, ROW, ROW], MORE)).toBe(3)
    expect(comingFit(3 * ROW - 0.4, [ROW, ROW, ROW], MORE)).toBe(3) // sub-pixel rounding
    expect(comingFit(0, [], MORE)).toBe(0)
  })
  it('else the first rows that fit whole together with the "more" line', () => {
    expect(comingFit(3 * ROW - 1, [ROW, ROW, ROW], MORE)).toBe(2) // 2 rows + the line: 118 px
    expect(comingFit(ROW + MORE, [ROW, ROW, ROW], MORE)).toBe(1)
    expect(comingFit(ROW + MORE - 1, [ROW, ROW, ROW], MORE)).toBe(0) // the line alone
  })
  it('never more than fit, and never a part of a row', () => {
    for (let room = -20; room <= 300; room += 1) {
      for (const n of [1, 3, 5]) {
        const k = comingFit(room, Array(n).fill(ROW), MORE)
        expect(k).toBeGreaterThanOrEqual(0)
        expect(k).toBeLessThanOrEqual(n)
        // what is shown ends inside the room (a room shorter than the line itself shows only the line)
        if (room >= MORE) expect(end(0, k, n)).toBeLessThanOrEqual(room + 0.5)
        // one more row would not fit (with the line, if still some are left out)
        if (k < n) expect(end(0, k + 1, n)).toBeGreaterThan(room + 0.5)
      }
    }
  })
  it('counts taller (wrapped) rows by their own height', () => {
    expect(comingFit(48 + 70 + MORE, [48, 70, 48], MORE)).toBe(2)
    expect(comingFit(48 + 70 + MORE - 1, [48, 70, 48], MORE)).toBe(1)
  })
  it('says how many more there are, starting with the number (set in Plex Mono)', () => {
    expect(comingMoreText(2, 1)).toBe('2 more later · move the time on to see them')
    expect(comingMoreText(1, 2)).toBe('1 more later · move the time on to see it')
    expect(comingMoreText(3, 0)).toBe('3 changes ahead · move the time on to see them')
    expect(comingMoreText(1, 0)).toBe('1 change ahead · move the time on to see it')
    // the view measures the line with the longer wording, so the shown one is never taller
    for (const n of [1, 2, 3, 5]) expect(comingMoreText(n, 0).length).toBeGreaterThanOrEqual(comingMoreText(n, 1).length)
  })
})

describe('TimelineView keeps Coming up inside its frame', () => {
  it('lists only the rows that fit, measured with every row drawn, and a line for the rest', () => {
    expect(timelineSrc).toMatch(/\{shownEvents\.map\(\(ev\) =>/)
    expect(timelineSrc).not.toMatch(/\{events\.map\(/)
    expect(timelineSrc).toMatch(/comingFit\(room, heights, more \? more\.offsetHeight : 0\)/)
    expect(timelineSrc).toMatch(/<div data-more /)
    // measured again on a frame resize that keeps the width (Flutter's layout, full screen)
    expect(timelineSrc).toMatch(/window\.addEventListener\('resize', f\)/)
  })
})

// The browser check's widths, measured in Chromium on the web build (Malapert
// peak, Simple view, the default dates): the frame's width and height, the
// first Coming up row's top, and the rows asked for (3 under 600 px, else 5).
// The single column's frame heights are timelineFrameHeight (sky_time.dart):
// 760 at 288 px, 0.4 px less per px wider (at least 680), 760 from 600 px.
// At 1440 px the When frame is the wide pane's height, 540 px in a 900 px window.
describe('Coming up at the browser check\'s widths (F1)', () => {
  const cases: Array<{ screen: number; frame: number; oldH: number; h: number; top: number; n: number; all: boolean }> = [
    { screen: 320, frame: 288, oldH: 640, h: 760, top: 590, n: 3, all: true },
    { screen: 360, frame: 328, oldH: 640, h: 744, top: 571, n: 3, all: true },
    { screen: 412, frame: 380, oldH: 640, h: 723.2, top: 553, n: 3, all: true },
    { screen: 700, frame: 668, oldH: 680, h: 760, top: 491, n: 5, all: true },
    { screen: 1440, frame: 563, oldH: 540, h: 540, top: 482, n: 3, all: false },
  ]
  for (const c of cases) {
    it(`${c.screen} px wide (${c.frame} x ${c.h} frame): ${c.all ? 'every row fits' : 'the rows that fit, and how many more'}, nothing cut`, () => {
      const rows = Array(c.n).fill(ROW)
      // the old frames cut the list (the rest was in a scroll area the frame hid)
      expect(c.top + c.n * ROW).toBeGreaterThan(c.oldH - PAD_B)
      for (const h of [c.oldH, c.h]) {
        const k = comingFit(h - PAD_B - c.top, rows, MORE)
        expect(end(c.top, k, c.n), `${h} px frame: ${k} of ${c.n} rows`).toBeLessThanOrEqual(h - PAD_B + 0.5)
        if (h === c.h) expect(k === c.n).toBe(c.all)
      }
    })
  }
})
