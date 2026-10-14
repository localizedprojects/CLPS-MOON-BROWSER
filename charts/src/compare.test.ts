import { describe, expect, it } from 'vitest'
import type { CompareData } from './bridge'
import {
  buildCompare, buildCompareSimple, headline, longestDarkText, pctText, ranked, reasons, scoreLine, scoreTexts, weightsText, wrapAt,
} from './compare'
import top3 from './devdata/compare.json'

describe('compare (web-3, android-5, science-6)', () => {
  const rows = [
    { id: 'a', name: 'A', score: 10, pctSunlit: 1, pctEarth: 1, pctBoth: 1, longestDarkH: 1 },
    { id: 'b', name: 'Malapert Massif', score: 90, pctSunlit: 1, pctEarth: 1, pctBoth: 1, longestDarkH: 1 }]
  const w = { power: 50, comms: 50, both: 25, rest: 75 }
  it('sorts by score', () => {
    const f = buildCompare({ weights: w, earthLabel: 'Earth in view', rows })
    expect((f.data[0] as { y: string[] }).y[0]).toBe('Malapert Massif')
  })
  it('puts the legend above the plot area, never over the bars', () => {
    for (const narrow of [false, true]) {
      const l = buildCompare({ weights: w, earthLabel: 'Earth in view', rows }, { narrow }).layout.legend as { y: number; yanchor: string }
      expect(l.y).toBeGreaterThanOrEqual(1)
      expect(l.yanchor).toBe('bottom')
    }
  })
  it('separates the two x domains so the end ticks never touch', () => {
    for (const narrow of [false, true]) {
      const l = buildCompare({ weights: w, earthLabel: 'Earth in view', rows }, { narrow }).layout as Record<string, { domain: number[]; range: number[] }>
      expect(l.xaxis2.domain[0] - l.xaxis.domain[1]).toBeGreaterThanOrEqual(0.08)
      expect(l.xaxis.range[1]).toBeGreaterThan(100)
    }
  })
  it('describes all three score terms, as the formula does', () => {
    expect(weightsText(w)).toBe('Score = 75% × [50% power + 50% comms] + 25% × Sun and Earth together')
    const f = buildCompare({ weights: { power: 70, comms: 30, both: 60, rest: 40 }, earthLabel: 'Earth contact (DSN)', rows })
    expect(f.alt).toContain('60% × Sun and Earth together')
    expect(f.data.map((d) => d.name)).toContain('Earth contact (DSN) %')
  })
})

// charts spec 2.3 / P3 acceptance, on the real top-3 payload (MP1, IM-1, IM-2)
describe('compare simple view (charts spec 2.3)', () => {
  const d = top3.data as CompareData
  type Ann = { text: string; hovertext?: string }
  const texts = (f: { layout: Record<string, unknown> }) => (f.layout.annotations as Ann[]).map((a) => a.text)
  const plain = (s: string) => s.replace(/<[^>]+>/g, '').replace(/[  ]/g, ' ')

  it('headline names the best site and the near tie with both scores (exact view)', () => {
    expect(headline(d, true)).toBe('Best: Malapert peak (MP1) · almost tied with IM-1 Odysseus (landed), 61.84 vs 61.83')
    const apart = { ...d, rows: [d.rows[0], d.rows[2]] }
    expect(headline(apart)).toBe('Best: Malapert peak (MP1), score 62')
    expect(headline({ ...d, rows: [] })).toBe('No sites to compare')
  })

  it('simple headline uses whole scores and says Tied when they round equal, like the WinnerCard', () => {
    expect(headline(d)).toBe('Tied: Malapert peak (MP1) and IM-1 Odysseus (landed), both 62')
    const mk = (name: string, score: number) => ({ ...d.rows[0], name, score })
    expect(headline({ ...d, rows: [mk('A', 62.4), mk('B', 61.6)] })).toBe('Tied: A and B, both 62')
    expect(headline({ ...d, rows: [mk('A', 62.6), mk('B', 61.8), mk('C', 62.5)] })).toBe('Tied: A and C, both 63')
    expect(headline({ ...d, rows: [mk('A', 62.4), mk('B', 61.45)] })).toBe('Best: A · almost tied with B, 62 vs 61')
    expect(headline({ ...d, rows: [mk('A', 62.4), mk('B', 61.5), mk('C', 62)] })).toBe('Tied: A, C and B, all 62')
  })

  it('prints every score with the same tie-aware decimals (56.72, not 56.7) (exact view and star panel)', () => {
    expect(scoreTexts(ranked(d))).toEqual(['61.84', '61.83', '56.72'])
  })

  it('the simple view prints whole scores, matching its "both 62" headline and the rank cards (pre-ux-4)', () => {
    const titles = texts(buildCompareSimple(d)).map((t) => plain(t.split('<br>')[0])).filter((t) => /score/.test(t) && /^\d/.test(t))
    expect(titles).toEqual(['1 Malapert peak (MP1) score 62', '2 IM-1 Odysseus (landed) score 62', '3 IM-2 Athena (landed) score 57'])
    expect(texts(buildCompareSimple(d)).join(' ')).not.toMatch(/61\.8|56\.7/)
  })

  it('gives factual reasons only, with "all the time" for 100% Earth', () => {
    const why = reasons(ranked(d), d.earthLabel)
    expect(why[0]).toBe('Most sunlight · most time with both · shortest longest-dark (6 d 23 h)')
    expect(why[1]).toBe('Earth in view all the time · least sunlight')
    expect(why[2]).toBe('') // leads or trails in nothing: line omitted
    for (const r of why) expect(r).not.toMatch(/because|mostly from/i)
    const simple = texts(buildCompareSimple(d)).flatMap((t) => t.split('<br>')).map(plain)
    expect(simple).toContain('Earth in view all the time · least sunlight')
    expect(simple.join(' ')).not.toMatch(/because|mostly from/i)
    // DSN wording, and 99.9% is not "all the time"
    const dsn = reasons([{ ...d.rows[1], pctEarth: 99.9 }, d.rows[0]], 'Earth contact (DSN)')
    expect(dsn[0]).toMatch(/^Most time with Earth contact/)
    expect(reasons([d.rows[0]])).toEqual([''])
  })

  it('charts-5: leads go by the printed numbers, so two sites both printed "81%" share "most sunlight"', () => {
    const [a, b, c] = d.rows
    const rows = [{ ...a, pctSunlit: 81.107 }, { ...b, pctSunlit: 80.565 }, { ...c, pctSunlit: 60 }]
    const why = reasons(rows)
    expect(pctText(81.107)).toBe(pctText(80.565))
    expect(why[0]).toMatch(/^Most sunlight/)
    expect(why[1]).toMatch(/^Most sunlight/)
    expect(why[2]).toMatch(/least sunlight/i)
    // all printed alike: nobody leads or trails
    const same = reasons([{ ...a, pctSunlit: 81.1 }, { ...b, pctSunlit: 80.6 }])
    for (const r of same) expect(r).not.toMatch(/sunlight/i)
  })

  it('floors the longest dark spell and adds + at the edge of the chosen dates', () => {
    // 167.5 h, 449 h, 411.5 h: floored (never rounded up to 7 d / 17 d 4 h)
    expect(ranked(d).map(longestDarkText)).toEqual(['6 d 23 h', '18 d 17 h', '17 d 3 h'])
    expect(longestDarkText({ ...d.rows[0], longestDarkH: 168 })).toBe('7 d')
    expect(longestDarkText({ ...d.rows[0], longestDarkAtEdge: true })).toBe('6 d 23 h+')
    expect(longestDarkText({ ...d.rows[0], longestDarkH: 0 })).toBe('none')
    const f = buildCompareSimple({ ...d, rows: [{ ...d.rows[0], longestDarkAtEdge: true }, d.rows[1]] })
    const dark = (f.layout.annotations as Ann[]).find((a) => plain(a.text) === '6 d 23 h+')
    expect(dark?.hovertext).toMatch(/^Longest dark spell: at least 6 d 23 h/)
  })

  it('score line from the weights: power and comms are rest x share', () => {
    expect(scoreLine(d.weights)).toBe('Score (0–100) weighs 37.5% power, 37.5% comms, 25% Sun + Earth together. ' +
      'Power and comms are sub-scores, so the bars alone do not add up to the score.')
    expect(scoreLine({ power: 70, comms: 30, both: 60, rest: 40 })).toContain('28% power, 12% comms, 60% Sun + Earth together')
    expect(scoreLine(d.weights)).not.toMatch(/sunlight/i)
  })

  it('labels three bars per site directly, % at the bar end', () => {
    const f = buildCompareSimple(d)
    expect(f.data.map((t) => t.name)).toEqual(['Sunlight', 'Earth in view', 'Sun + Earth'])
    expect((f.data[1] as { text: string[] }).text).toEqual(['56%', '100%', '80%'])
    expect(f.layout.showlegend).toBe(false)
    const ticks = (f.layout.yaxis as { ticktext: string[] }).ticktext
    expect(ticks.filter((t) => t === 'Sunlight')).toHaveLength(3)
    expect(ticks.filter((t) => t === 'Longest dark')).toHaveLength(3)
    expect(String((f.data[0] as { hovertemplate: string }).hovertemplate)).toContain('%{x:.1f}%')
    expect(pctText(99.6)).toBe('99.6%')
    expect(pctText(100)).toBe('100%')
    expect(pctText(0.3)).toBe('0.3%')
    expect(pctText(0)).toBe('0%')
  })

  it('keeps the exact stars with the same decimals and the longest dark in the hover', () => {
    const f = buildCompare(d)
    const star = f.data[3] as { text: string[]; customdata: string[]; hovertemplate: string }
    expect(star.text).toEqual(['61.84', '61.83', '56.72'])
    expect(star.customdata).toEqual(['6 d 23 h', '18 d 17 h', '17 d 3 h'])
    expect(star.hovertemplate).toContain('%{x:.2f}')
    expect(texts(f).join(' ')).toContain(weightsText(d.weights))
  })

  it('PNG figures carry the headline and the score line (simple and exact)', () => {
    for (const [f, exact] of [[buildCompareSimple(d, { png: true }), false], [buildCompare(d, { png: true }), true]] as const) {
      const all = texts(f).map(plain).join('\n')
      expect(all).toContain(headline(d, exact))
      expect(all).toContain(scoreLine(d.weights))
    }
    // on screen the headline and score line are HTML around the figure
    expect(texts(buildCompareSimple(d)).map(plain).join('\n')).not.toContain(headline(d))
  })

  it('alt text keeps every number, the longest dark and the formula', () => {
    const alt = buildCompareSimple(d).alt
    for (const s of ['Malapert peak (MP1)', 'score 61.84', 'sunlight 80.6%', 'Earth in view 56.2%', 'Sun and Earth together 42.3%',
      'longest dark 6 d 23 h', '37.5% power', weightsText(d.weights)]) expect(alt).toContain(s)
    // each view's alt text opens with the headline that view shows; the numbers after it are the same
    expect(alt.startsWith(`${headline(d)}. `)).toBe(true)
    expect(buildCompare(d).alt).toBe(`${headline(d, true)}. ` + alt.slice(`${headline(d)}. `.length))
  })

  it('alt text never says "almost tied" under a visible "Tied"', () => {
    const t = { ...d, rows: [{ ...d.rows[0], name: 'A', score: 61.97 }, { ...d.rows[0], name: 'B', score: 61.96 }] }
    expect(buildCompareSimple(t).alt.startsWith('Tied: A and B, both 62. ')).toBe(true)
    expect(buildCompareSimple(t).alt).toContain('score 61.97')
  })

  it('wraps reason lines at the separators on phones', () => {
    expect(wrapAt('Most sunlight · most time with both · shortest longest-dark (6 d 23 h)', 62))
      .toEqual(['Most sunlight · most time with both ·', 'shortest longest-dark (6 d 23 h)'])
    const f = buildCompareSimple(d, { narrow: true })
    const cats = (f.layout.yaxis as { categoryarray: string[] }).categoryarray
    expect(cats).toContain('r0b') // one category row per reason line
    expect(texts(f)[0].split('<br>')).toHaveLength(3) // title + two reason lines in one block
    expect(cats).not.toContain('r2') // no reason row for IM-2
  })
})
