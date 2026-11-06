/**
 * "Coming up" in the Simple view timeline shows only the rows that fit whole
 * below the strip, and says how many more there are (F1: on phones and in a
 * 1440 px window the frame cut the list, the rest in a scroll area the frame hid).
 */
import { describe, expect, it } from 'vitest'
import timelineSrc from './TimelineView.tsx?raw'
import type { ComingFitState, ComingPass } from './timelineAnswer'
import { comingFit, comingFitNext, comingMoreText } from './timelineAnswer'

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
    // with no row shown, moving the time on lists none either (the frame is too short for one)
    expect(comingMoreText(3, 0)).toBe('3 changes ahead · too little room to list them here')
    expect(comingMoreText(1, 0)).toBe('1 change ahead · too little room to list it here')
    // the view measures the line with the longer wording, so the shown one is never taller
    for (const n of [1, 2, 3, 5]) expect(comingMoreText(n, 0).length).toBeGreaterThanOrEqual(comingMoreText(n, 1).length)
  })
})

describe('TimelineView keeps Coming up inside its frame', () => {
  it('lists only the rows that fit, measured with every row drawn, and a line for the rest', () => {
    expect(timelineSrc).toMatch(/\{shownEvents\.map\(\(ev\) =>/)
    expect(timelineSrc).not.toMatch(/\{events\.map\(/)
    // the "more" line is measured while every row is drawn
    expect(timelineSrc).toMatch(/const more = fit \? null : list\.querySelector\('\[data-more\]'\)/)
    expect(timelineSrc).toMatch(/comingFitNext\(fit, \{ room, frame, heights, moreH: more \? more\.offsetHeight : 0 \}, measuredFor\.current\)/)
    expect(timelineSrc).toMatch(/<div data-more /)
    // measured again on a frame resize that keeps the width (Flutter's layout, full screen)
    expect(timelineSrc).toMatch(/window\.addEventListener\('resize', f\)/)
  })
  // 1.13.2 browser check: with classic scrollbars the measure (every row
  // drawn, the frame overflowing, a scrollbar narrowing it) and the fit (the
  // scrollbar gone) took turns until React stopped them (error #185) and the
  // "When" chart went blank
  it('never re-measures in a loop when a scrollbar comes and goes', () => {
    // the frame keeps the scrollbar's room and is keyed by its outer width
    expect(timelineSrc).toMatch(/const TIMELINE_GUTTER = 'stable'/)
    expect(timelineSrc).toMatch(/overflowY: 'auto', scrollbarGutter: TIMELINE_GUTTER/)
    expect(timelineSrc).toMatch(/const frame = `\$\{root\.offsetWidth\}\|/)
    expect(timelineSrc).not.toMatch(/root\.clientWidth/)
    // and a change the measure itself made is kept rather than measured again
    expect(timelineSrc).toMatch(/measuredFor\.current = next\.pass\s+setFit\(null\)/)
    const F = '563|3|1'
    const measured = comingFitNext(null, { room: 140, frame: F, heights: [48, 48, 48], moreH: 22 }, '')
    expect(measured).toMatchObject({ kind: 'fit', fit: { shown: 2 } })
    // the scrollbar of the measure (every row drawn) gone, the rows drawn another height: measured once more...
    const pass: ComingPass = { room: 140, frame: F, heights: [47, 47], moreH: 0 }
    const again = comingFitNext((measured as { fit: ComingFitState }).fit, pass, '')
    expect(again.kind).toBe('measure')
    // ...and not again for the same change
    expect(comingFitNext((measured as { fit: ComingFitState }).fit, pass, (again as { pass: string }).pass)).toEqual({ kind: 'keep' })
  })
})

// 1.13.3: the fit was measured again (two extra renders with every row
// drawn) on every cursor change that changed a row's words, i.e. on most
// steps of Play. Now only what can change the rows that fit measures again.
describe('Coming up is not measured again for new words during Play', () => {
  const F = '563|5|1'
  const fitted = (room: number) => {
    const r = comingFitNext(null, { room, frame: F, heights: [48, 48, 48, 48, 48], moreH: 22 }, '')
    if (r.kind !== 'fit') throw new Error('a measuring pass gives a fit')
    return r.fit
  }
  it('keeps the fit while the rows drawn are as tall as measured (their words changing)', () => {
    const fit = fitted(160) // 2 rows and the line
    expect(fit.shown).toBe(2)
    expect(TimelineSrcHasNoWordsKey()).toBe(true)
    for (let step = 0; step < 50; step++) {
      expect(comingFitNext(fit, { room: 160, frame: F, heights: [48, 48], moreH: 0 }, '')).toEqual({ kind: 'keep' })
    }
  })
  it('counts a new room again from the measured heights, without measuring', () => {
    const fit = fitted(160)
    // the answer lines above wrap differently: more room, one more row
    const r = comingFitNext(fit, { room: 230, frame: F, heights: [48, 48], moreH: 0 }, '')
    expect(r).toEqual({ kind: 'fit', fit: { ...fit, room: 230, shown: 4 } })
    // the same rows: nothing to do
    expect(comingFitNext(fit, { room: 161, frame: F, heights: [48, 48], moreH: 0 }, '')).toEqual({ kind: 'keep' })
    // all of them (no "more" line): every measured row
    expect(comingFitNext(fit, { room: 240, frame: F, heights: [48, 48], moreH: 0 }, '')).toMatchObject({ kind: 'fit', fit: { shown: 5 } })
  })
  it('measures again for another frame, other rows asked for, late fonts or a row drawn at another height', () => {
    const fit = fitted(160)
    for (const pass of [
      { room: 160, frame: '600|5|1', heights: [48, 48], moreH: 0 }, // outer width
      { room: 160, frame: '563|4|1', heights: [48, 48], moreH: 0 }, // rows asked for (the end of the dates)
      { room: 160, frame: '563|5|2', heights: [48, 48], moreH: 0 }, // fonts loaded
      { room: 160, frame: F, heights: [48, 65], moreH: 0 }, // a row's words wrap to three lines
    ]) {
      const r = comingFitNext(fit, pass, '')
      expect(r.kind, JSON.stringify(pass)).toBe('measure')
      // a measure that changes nothing more is not started again
      expect(comingFitNext(fit, pass, (r as { pass: string }).pass)).toEqual({ kind: 'keep' })
    }
  })
})

/** The fit is keyed by the number of rows, not their words. */
function TimelineSrcHasNoWordsKey() {
  return !/e\.text\}`\)\.join/.test(timelineSrc) && /eventCount\.current = events\.length/.test(timelineSrc)
}

// The browser check's widths, measured in Chromium on the web build (Malapert
// peak, Simple view, the default dates): the frame's width and height, the
// first Coming up row's top, and the rows asked for (3 under 600 px, else 5).
// The single column's frame heights are timelineFrameHeight (sky_time.dart):
// 760 at 288 px, 0.4 px less per px wider (at least 680), 760 from 600 px.
// At 1440 px the When frame was the wide pane's height, 540 px in a 900 px
// window, where no row fitted; it is now at least timelineWideMinHeight, 640 px.
describe('Coming up at the browser check\'s widths (F1)', () => {
  const cases: Array<{ screen: number; frame: number; oldH: number; h: number; top: number; n: number; all: boolean }> = [
    { screen: 320, frame: 288, oldH: 640, h: 760, top: 590, n: 3, all: true },
    { screen: 360, frame: 328, oldH: 640, h: 744, top: 571, n: 3, all: true },
    { screen: 412, frame: 380, oldH: 640, h: 723.2, top: 553, n: 3, all: true },
    { screen: 700, frame: 668, oldH: 680, h: 760, top: 491, n: 5, all: true },
    { screen: 1440, frame: 563, oldH: 540, h: 640, top: 482, n: 3, all: true },
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
        // and at least two rows in the wide pane's frame
        if (h === c.h) expect(k).toBeGreaterThanOrEqual(2)
      }
    })
  }
})
