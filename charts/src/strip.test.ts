/**
 * Timeline "When" (charts spec 2.1, P1 acceptance) on the real dev payloads
 * (built by the app's Dart code: SR1, Haworth, SR1 with DSN).
 */
import { describe, expect, it } from 'vitest'
import type { TimelineData } from './bridge'
import sr1Msg from './devdata/timeline.json'
import haworthMsg from './devdata/timeline_haworth.json'
import dsnMsg from './devdata/timeline_dsn.json'
import { buildStrip, buildTimelineExport, fitFlag, fitLabel, flagW, inWindow, placeFlags, ROW_INDEX, rowLabels, rowPx, spanWindow, stripFlags, stripHeight, windowFor } from './strip'
import type { Span } from './strip'
import { answerLines, answerText, bothLine, comingUp, darkLine, earthLine, gaps, lineText, stepBoundary, sunLine } from './timelineAnswer'
import type { Run } from './timelineAnswer'

const SR1 = sr1Msg.data as unknown as TimelineData
const HAWORTH = haworthMsg.data as unknown as TimelineData
const DSN = dsnMsg.data as unknown as TimelineData
const OCT11 = Date.UTC(2026, 9, 11)
const DAY = 864e5

type Bar = { name: string; text: string[]; customdata: string[][]; y: string[] }
const bars = (f: { data: unknown[] }) => f.data as Bar[]

describe('answer lines (SR1, Haworth)', () => {
  it('SR1 at 11 Oct 00:00: NEXT both, floored durations', () => {
    expect(SR1.cursor).toBe(OCT11)
    // the run is 21 Oct 18:00 -> 2 Nov 17:30 = 11 d 23 h 30 min: floored, never rounded up to "12 d"
    expect(lineText(bothLine(SR1, OCT11))).toBe('Sun + Earth together: NEXT · 21 Oct 18:00 · in 10 d 18 h · lasts 11 d 23 h')
  })
  it('SR1 dark line: next dark 21 Jan 00:30, about 30 min, longest from Dart (floored)', () => {
    // longestDark 17 Apr 18:00 -> 28 Apr 14:30 = 10 d 20 h 30 min -> "10 d 20 h"
    expect(lineText(darkLine(SR1, OCT11))).toBe('Next dark: 21 Jan 00:30 · about 30 min · longest 10 d 20 h (from 17 Apr)')
  })
  it('the longest dark comes from the payload, not from the bundle', () => {
    const fake: TimelineData = { ...SR1, longestDark: [Date.UTC(2027, 1, 19, 3), Date.UTC(2027, 1, 23, 20)] }
    expect(lineText(darkLine(fake, OCT11))).toContain('longest 4 d 17 h (from 19 Feb)')
  })
  it('SR1 at 15 Jan 08:00: NOW, 5 d 16 h more (floored, never 5 d 17 h)', () => {
    expect(lineText(bothLine(SR1, Date.UTC(2027, 0, 15, 8)))).toBe('Sun + Earth together: NOW · 5 d 16 h more, until 21 Jan 00:30')
  })
  it('Haworth: DARK NOW, sunlight back 28 Oct 05:00', () => {
    const l = darkLine(HAWORTH, OCT11)
    expect(l.state).toBe('DARK NOW')
    expect(lineText(l)).toMatch(/^DARK NOW · sunlight back 28 Oct 05:00, in 17 d 5 h · longest 20 d 23 h \(from 2 May\)$/)
  })
  it('a next window under goodMinH adds "next 1 day or more"', () => {
    const short = SR1.runs.both.find((r) => r[1] - r[0] < 24 * 3600e3 && r[0] > SR1.range[0])!
    expect(short).toBeTruthy()
    const t = short[0] - 60e3
    const good = SR1.runs.both.find((r) => r[0] > t && r[1] - r[0] >= 24 * 3600e3)!
    const txt = lineText(bothLine(SR1, t))
    expect(txt).toContain('· NEXT ·'.replace('· NEXT ·', 'NEXT'))
    expect(txt).toMatch(/ · next 1 day or more: \d{1,2} [A-Z][a-z]{2}( \d{4})? \d\d:\d\d$/)
    expect(txt).toContain(new Date(good[0]).getUTCDate() + ' ')
    // a long next window has no such tail
    expect(lineText(bothLine(SR1, OCT11))).not.toContain('or more')
  })
  it('no window left: NONE left in your chosen dates', () => {
    const last = SR1.runs.both[SR1.runs.both.length - 1]
    expect(lineText(bothLine(SR1, last[1] + 1))).toBe('Sun + Earth together: NONE · left in your chosen dates')
  })
  it('phones get 2 lines, desktop 4 (Sunlight and Earth)', () => {
    expect(answerLines(SR1, OCT11, false).map((l) => l.key)).toEqual(['both', 'dark'])
    expect(answerLines(SR1, OCT11, true).map((l) => l.key)).toEqual(['both', 'dark', 'sun', 'earth'])
    // the sunlit run at the period start touches the edge: "+" and the end time beside it
    expect(lineText(sunLine(SR1, OCT11))).toBe('Sunlight: YES · until 21 Jan 00:30 (102 d+ more)'.replace('102 d+ more', '102 d more'))
    expect(lineText(earthLine(SR1, OCT11))).toBe('Earth in view: NO · next 21 Oct 18:00, in 10 d 18 h · lasts 11 d 23 h')
    expect(lineText(sunLine(HAWORTH, OCT11))).toBe('Sunlight: NO · back 28 Oct 05:00, in 17 d 5 h')
  })
  it('the DSN payload words the Earth line with its label', () => {
    expect(lineText(earthLine(DSN, OCT11))).toMatch(/^Earth contact \(DSN\): NO · next 21 Oct 18:00/)
  })
})

describe('Coming up', () => {
  it('lists the next changes, never "rises" or "sets"', () => {
    const ev = comingUp(SR1, OCT11, 5).map((e) => `${e.mark} ${e.text}`)
    expect(ev[0]).toBe('◇ Sun + Earth together start · 21 Oct 18:00 · lasts 11 d 23 h')
    expect(ev[1]).toBe('▲ Earth comes into view · 21 Oct 18:00 · in view 11 d 23 h')
    expect(ev.join(' ')).not.toMatch(/rises|sets/)
    expect(comingUp(SR1, OCT11, 3)).toHaveLength(3)
    const later = comingUp(SR1, Date.UTC(2027, 0, 20), 5).map((e) => e.text)
    expect(later).toContain('Sunlight ends · 21 Jan 00:30 · dark about 30 min')
  })
  it('DSN payload: "Earth contact starts/ends"', () => {
    const ev = comingUp(DSN, OCT11, 5).map((e) => e.text)
    expect(ev.some((s) => s.startsWith('Earth contact starts · 21 Oct 18:00 · contact '))).toBe(true)
    expect(ev.some((s) => /^Earth contact ends · .* · no contact /.test(s))).toBe(true)
    expect(ev.join(' ')).not.toContain('comes into view')
  })
  it('arrow keys step through the run boundaries', () => {
    expect(stepBoundary(SR1, OCT11, 1)).toBe(Date.UTC(2026, 9, 21, 18))
    expect(stepBoundary(SR1, Date.UTC(2026, 9, 21, 18), -1)).toBe(OCT11)
  })
})

describe('strip', () => {
  const whole = SR1.range as Run
  it('rows: Sun + Earth on top; labels carry pct from the payload, not summed runs', () => {
    const f = buildStrip(SR1, whole, { widthPx: 1300 })
    const ann = (f.layout.annotations as { text: string }[]).map((a) => a.text)
    expect(ann.some((s) => s.startsWith('Sun + Earth · ') && s.includes('40%'))).toBe(true)
    expect(ann.some((s) => s.startsWith('Sunlight · ') && s.includes('81%'))).toBe(true)
    expect(ann.some((s) => s.startsWith('Earth in view · ') && s.includes('45%'))).toBe(true)
    const fake = buildStrip({ ...SR1, pct: { sun: 12.3, earth: 7.6, both: 3.2 } }, whole, { widthPx: 1300 })
    const t2 = (fake.layout.annotations as { text: string }[]).map((a) => a.text).join(' ')
    expect(t2).toContain('12%')
    expect(t2).toContain('8%')
    expect(t2).toContain('3%')
    expect(rowLabels(DSN).map((r) => r.name)).toEqual(['Sun + Earth', 'Sunlight', 'Earth contact (DSN)'])
    expect(ann.some((s) => s.includes('% = share of'))).toBe(true)
  })
  it('the 102 d sunlit run at the period start reads "102 d+", with an edge tooltip', () => {
    const f = buildStrip(SR1, whole, { widthPx: 1300 })
    const sun = bars(f).find((b) => b.name === 'Sunlight')!
    expect(sun.text[0]).toBe('102 d+')
    expect(sun.customdata[0][2]).toBe('at least 102 d (starts before your chosen dates)')
  })
  it('gaps are bars too: slate "dark" on Sunlight, "out of view" / "no contact" on Earth, none on Sun + Earth', () => {
    const f = buildStrip(SR1, whole, { widthPx: 1300 })
    const feb = buildStrip(SR1, spanWindow('2m', Date.UTC(2027, 1, 10), whole), { widthPx: 900, live: true })
    const names = bars(f).map((b) => b.name)
    expect(names).toEqual(['No sunlight', 'Sunlight', 'Earth out of view', 'Earth in view', 'Sun + Earth together'])
    const dark = bars(feb).find((b) => b.name === 'No sunlight')!
    expect(dark.text).toContain('dark 8 d 3 h')
    expect(dark.customdata.some((c) => c[0] === '19 Feb 03:00' && c[1] === '23 Feb 20:00' && c[2] === '4 d 17 h')).toBe(true)
    const out = bars(feb).find((b) => b.name === 'Earth out of view')!
    expect(out.text.some((s) => s.startsWith('out of view '))).toBe(true)
    const d = bars(buildStrip(DSN, spanWindow('2m', Date.UTC(2027, 1, 10), whole), { widthPx: 900, live: true })).find((b) => b.name === 'No Earth contact')!
    expect(d.text.some((s) => s.startsWith('no contact '))).toBe(true)
    // dashed outlines, one per visible gap bar
    const rects = (f.layout.shapes as { type: string; line: { dash: string } }[]).filter((s) => s.type === 'rect')
    expect(rects.length).toBe(gaps(SR1.runs.sun, whole).length + gaps(SR1.runs.earth, whole).length)
    expect(rects[0].line.dash).toBe('dot')
  })
  it('a bar cut by the window shows a chevron and the whole run', () => {
    const t = Date.UTC(2026, 11, 1)
    const win = spanWindow('2w', t, whole)
    const f = buildStrip(SR1, win, { widthPx: 900, live: true })
    const sun = bars(f).find((b) => b.name === 'Sunlight')!
    // the sunlit run 11 Oct -> 21 Jan covers the whole window: chevron on the right, "+" because it starts at the period start
    expect(sun.text[0]).toBe('102 d+ ▸')
    const earth = bars(f).find((b) => b.name === 'Earth in view')!
    expect(earth.customdata.length).toBeGreaterThan(0)
  })
  it('narrow bars drop to the coarse unit, then to no text', () => {
    expect(fitLabel(200, '10 d 20 h', '10 d')).toBe('10 d 20 h')
    expect(fitLabel(50, '10 d 20 h', '10 d')).toBe('10 d')
    expect(fitLabel(20, '10 d 20 h', '10 d')).toBe('')
  })
  it('an empty row says so with the next date', () => {
    const win: Run = [Date.UTC(2026, 9, 11), Date.UTC(2026, 9, 18)]
    const f = buildStrip(SR1, win, { widthPx: 600, live: true })
    const ann = (f.layout.annotations as { text: string }[]).map((a) => a.text)
    expect(ann).toContain('none in this span · next 21 Oct ▸')
  })
  it('axis: day-month up to 2 months, month-year for the whole period; no axis title', () => {
    const x = (w: Run) => buildStrip(SR1, w, { live: true }).layout.xaxis as { tickformat: string; title?: unknown }
    expect(x(spanWindow('2m', OCT11, whole)).tickformat).toBe('%-d %b')
    expect(x(whole).tickformat).toBe('%b %Y')
    expect(x(whole).title).toBeUndefined()
  })
  it('rows are 64 px on phones and 72 px on desktop', () => {
    expect(rowPx(true)).toBe(64)
    expect(rowPx(false)).toBe(72)
    expect(stripHeight(true)).toBe(3 * 64 + 26 + 42)
  })
})

describe('window and redraws', () => {
  const range = SR1.range as Run
  it('the default span is 2 months, starting at the time shown', () => {
    const w = spanWindow('2m', OCT11 + 5 * DAY, range)
    expect(w[0]).toBe(OCT11 + 5 * DAY)
    expect(w[1] - w[0]).toBe(61 * DAY)
    expect(spanWindow('all', OCT11, range)).toEqual(range)
    // near the end the window slides back and stays full length
    const e = spanWindow('2w', range[1] - DAY, range)
    expect(e[1]).toBe(range[1])
    expect(e[1] - e[0]).toBe(14 * DAY)
  })
  it('cursor messages inside the window keep the same window (no redraw); leaving it re-anchors once', () => {
    const span: Span = '2m'
    let w = windowFor(null, span, OCT11, range)
    let redraws = 0
    // Play: one step per 30 min for 70 days
    for (let t = OCT11; t < OCT11 + 70 * DAY; t += 1800e3) {
      const nw = windowFor(w, span, t, range)
      if (nw !== w) { redraws++; w = nw }
    }
    expect(redraws).toBe(1)
    expect(inWindow(OCT11 + 70 * DAY, w)).toBe(true)
  })
})

describe('flags', () => {
  it('next both, next dark and longest dark when in the window', () => {
    const t = Date.UTC(2027, 3, 1)
    const f = stripFlags(SR1, t, spanWindow('2m', t, SR1.range as Run))
    const texts = f.map((x) => x.text)
    expect(texts).toContain('Next both · 3 Apr 09:00 · 4 h')
    expect(texts).toContain('Next dark · 2 d 1 h')
    // both "now": no Next both flag (the answer line says NOW)
    expect(stripFlags(SR1, Date.UTC(2027, 3, 10), spanWindow('2m', Date.UTC(2027, 3, 10), SR1.range as Run)).some((x) => x.text.startsWith('Next both'))).toBe(false)
    expect(texts).toContain('Longest dark · 10 d 20 h')
    expect(f.find((x) => x.text.startsWith('Next both'))!.row).toBe(ROW_INDEX.both)
  })
  it('flags on one row never overlap (the later one moves up a line) and flip near the right edge', () => {
    const p = placeFlags([
      { row: 1, x: 100, text: 'Next dark · about 30 min', key: 'dark' },
      { row: 1, x: 130, text: 'Longest dark · 10 d 20 h', key: 'dark' },
      { row: 2, x: 590, text: 'Next both · 21 Oct 18:00 · 11 d 23 h', key: 'both' },
    ], { l: 100, w: 500 }, (row) => 200 - row * 64)
    const [a, b] = p.filter((x) => x.row === 1)
    expect(b.top).toBeLessThan(a.top)
    expect(a.top - b.top).toBeGreaterThanOrEqual(14)
    const c = p.find((x) => x.row === 2)!
    expect(c.flip).toBe(true)
    expect(c.left).toBeLessThan(590)
  })
})

describe('PNG export', () => {
  it('spans the whole period and carries the header, answer lines and Coming up', () => {
    const t = Date.UTC(2027, 0, 15, 8)
    const f = buildTimelineExport(SR1, t, false)
    expect((f.layout.xaxis as { range: string[] }).range).toEqual(['2026-10-11 00:00:00', '2027-10-11 00:00:00'])
    const ann = (f.layout.annotations as { text: string }[]).map((a) => a.text).join('\n')
    expect(ann).toContain('Whole period 11 Oct 2026 – 11 Oct 2027')
    for (const line of answerText(SR1, t, true)) expect(ann).toContain(line)
    expect(ann).toContain('Coming up')
    expect((f.layout.shapes as { type: string }[]).some((s) => s.type === 'line')).toBe(true)
  })
  it('Exact on: the Heights curves are appended under the strip', () => {
    const f = buildTimelineExport(SR1, OCT11, true)
    expect(f.data.some((d) => (d as { name: string }).name === 'Sun height')).toBe(true)
    expect(f.layout.yaxis2).toBeTruthy()
  })
})

describe('charts-4: timeline alt text matches the visible line', () => {
  it('gives the edge "at least" for a longest dark that touches the chosen dates, and never "100%" below 99.95', () => {
    // Haworth 12 Oct to 26 Oct 2026: all dark (Sun below the horizon until 28 Oct 05:00)
    const r0 = Date.UTC(2026, 9, 12), r1 = Date.UTC(2026, 9, 26)
    const d = { ...HAWORTH, range: [r0, r1], cursor: r0, longestDark: [r0, r1],
      runs: { sun: [], earth: [[r0, r1]], both: [] }, pct: { sun: 0, earth: 99.7, both: 0 } } as unknown as TimelineData
    const { alt } = buildStrip(d, [r0, r1])
    expect(alt).toContain('the longest at least 14 d (covers all of your chosen dates)')
    expect(alt).toContain('99.7%')
    expect(alt).not.toContain('100%')
  })
})

describe('flags fit a narrow strip (rubric-2)', () => {
  it('a flag wider than the plot drops its date, then is cut with an ellipsis, and never passes the right edge', () => {
    const plot = { l: 70, w: 180 }
    const long = 'Next both · 20 Oct 05:00 · 15 d 3 h'
    expect(flagW(long)).toBeGreaterThan(plot.w)
    const [p] = placeFlags([{ row: 2, x: 120, text: long, key: 'both' }], plot, () => 100)
    expect(p.text).toBe('Next both · 15 d 3 h')
    expect(p.left).toBeGreaterThanOrEqual(plot.l)
    expect(p.left + flagW(p.text)).toBeLessThanOrEqual(plot.l + plot.w)
    expect(p.x).toBe(120)
    const tiny = fitFlag(long, 90)
    expect(tiny.endsWith('…')).toBe(true)
    expect(flagW(tiny)).toBeLessThanOrEqual(90)
    expect(fitFlag('Next dark · about 30 min', 500)).toBe('Next dark · about 30 min')
  })
})
