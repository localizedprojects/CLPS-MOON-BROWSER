/**
 * Site comparison (charts spec 2.3).
 *
 * Simple view (default, [buildCompareSimple]): a headline naming the best
 * site (and an "almost tied" note under a 1-point gap), then one block per
 * site, best first: rank, name and score; a factual reason line (what the
 * site leads or trails on among the shown sites); three labelled bars with
 * the share printed at the bar end; and the longest dark spell. A plain score
 * line says how the score weighs power, comms and Sun + Earth together.
 *
 * Exact view ([buildCompare]): the grouped bars plus the star score panel,
 * with the exact formula ([weightsText]) under it.
 *
 * Render-only: the scores, percentages and longest dark spells are the
 * host's. The bundle only sorts them, picks the largest or smallest of a sent
 * number and formats. No causal claims ("because", "mostly from").
 */
import type { CompareData, CompareRow } from './bridge'
import { edgePlus, fmtDur, HOUR_MS, scoreDecimals, sortedStable } from './format'
import { C, FONT, HOVER, MONO, TICK } from './theme'

export const DEFAULT_EARTH_LABEL = 'Earth in view'

type Fig = { data: Record<string, unknown>[]; layout: Record<string, unknown>; alt: string }

/** One line describing the score weights, as the formula box in the app shows them. */
export function weightsText(w: CompareData['weights']): string {
  return `Score = ${w.rest}% × [${w.power}% power + ${w.comms}% comms] + ${w.both}% × Sun and Earth together`
}

/** A share in percent without trailing zeros: 37.5, 25, 28. */
const pctNum = (x: number) => String(Number(x.toFixed(2)))

/**
 * The plain score line (always visible in the simple view): power% = rest x
 * power / 100, comms% = rest x comms / 100. "Power", never "sunlight".
 */
export function scoreLine(w: CompareData['weights']): string {
  return `Score (0–100) weighs ${pctNum((w.rest * w.power) / 100)}% power, ${pctNum((w.rest * w.comms) / 100)}% comms, ` +
    `${pctNum(w.both)}% Sun + Earth together. Power and comms are sub-scores, so the bars alone do not add up to the score.`
}

/** Rows best first (equal scores keep their order, on Chrome 69 too). */
export const ranked = (d: CompareData): CompareRow[] => sortedStable(d.rows, (a, b) => b.score - a.score)

/** Score text with the shared tie-aware decimals ([scoreDecimals] over every row). */
export function scoreTexts(rows: CompareRow[]): string[] {
  const dp = scoreDecimals(rows.map((r) => r.score))
  return rows.map((r) => r.score.toFixed(dp))
}

/**
 * Exact view: "Best: Malapert peak (MP1) · almost tied with IM-1 Odysseus (landed), 61.84 vs 61.83"
 * when the runner-up is under 1 point behind, otherwise "Best: Malapert peak (MP1), score 61.84".
 * Simple view (the default): whole scores only, like the Flutter WinnerCard. Sites at the top with
 * the same whole score read "Tied: A and B, both 62"; a near tie with different whole scores reads
 * "Best: A · almost tied with B, 62 vs 61"; otherwise "Best: A, score 62".
 */
export function headline(d: CompareData, exact = false): string {
  const rows = ranked(d)
  if (!rows.length) return 'No sites to compare'
  const [a, b] = rows
  if (exact) {
    const s = scoreTexts(rows)
    if (b && a.score - b.score < 1) return `Best: ${a.name} · almost tied with ${b.name}, ${s[0]} vs ${s[1]}`
    return `Best: ${a.name}, score ${s[0]}`
  }
  const top = Math.round(a.score)
  const tied = rows.filter((r) => Math.round(r.score) === top)
  if (tied.length > 1) {
    const n = tied.map((r) => r.name)
    return `Tied: ${n.slice(0, -1).join(', ')} and ${n[n.length - 1]}, ${tied.length > 2 ? 'all' : 'both'} ${top}`
  }
  if (b && a.score - b.score < 1) return `Best: ${a.name} · almost tied with ${b.name}, ${top} vs ${Math.round(b.score)}`
  return `Best: ${a.name}, score ${top}`
}

/** The longest dark spell in the shared duration format, "+" when it touches the edge of the chosen dates. */
export function longestDarkText(r: CompareRow): string {
  if (!Number.isFinite(r.longestDarkH)) return '–'
  if (r.longestDarkH <= 0) return 'none'
  return edgePlus(fmtDur(r.longestDarkH * HOUR_MS), !!r.longestDarkAtEdge)
}

/** Hover words for the longest dark spell ("at least …" at the edge of the period). */
function longestDarkTip(r: CompareRow): string {
  const t = longestDarkText(r).replace(/\+$/, '')
  return r.longestDarkAtEdge
    ? `Longest dark spell: at least ${t} (it touches the start or end of your chosen dates)`
    : `Longest dark spell: ${t}`
}

/** The Earth word for reasons: 'Earth contact' with the DSN rule, else 'Earth in view'. */
const earthWord = (earth: string) => (/contact/i.test(earth) ? 'Earth contact' : 'Earth in view')

/**
 * Factual reason line per site (same order as [rows]): what it leads or
 * trails on among the shown sites, from the sent numbers only. Empty when a
 * site leads or trails in nothing (and for a single site). "All the time"
 * needs >= 99.95 %. Leads and trails go by the numbers as the bars print
 * them (pctText, longestDarkText): two sites both printed "81%" share the
 * lead, and a metric where every site prints the same names nobody.
 */
export function reasons(rows: CompareRow[], earthLabel: string = DEFAULT_EARTH_LABEL): string[] {
  const many = rows.length > 1
  const ew = earthWord(earthLabel)
  const span = (k: 'pctSunlit' | 'pctEarth' | 'pctBoth' | 'longestDarkH') => {
    const shown = (v: number) => (k === 'longestDarkH' ? longestDarkText({ longestDarkH: v } as CompareRow) : pctText(v))
    const xs = rows.map((r) => r[k]).filter(Number.isFinite)
    const hi = shown(Math.max(...xs)), lo = shown(Math.min(...xs))
    const differ = hi !== lo
    return {
      isMax: (v: number) => differ && Number.isFinite(v) && shown(v) === hi,
      isMin: (v: number) => differ && Number.isFinite(v) && shown(v) === lo,
    }
  }
  const sun = span('pctSunlit'), earth = span('pctEarth'), both = span('pctBoth'), dark = span('longestDarkH')
  return rows.map((r) => {
    if (!many) return ''
    const out: string[] = []
    if (sun.isMax(r.pctSunlit)) out.push('most sunlight')
    if (r.pctEarth >= 99.95) out.push(`${ew} all the time`)
    else if (earth.isMax(r.pctEarth)) out.push(`most time with ${ew}`)
    if (both.isMax(r.pctBoth)) out.push('most time with both')
    if (dark.isMin(r.longestDarkH)) out.push(`shortest longest-dark (${longestDarkText(r)})`)
    if (sun.isMin(r.pctSunlit)) out.push('least sunlight')
    const s = out.join(' · ')
    return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''
  })
}

/**
 * A share at the bar end: whole percent, but never "100%" below 99.95 (the
 * "all the time" line) and never "0%" for a share above zero.
 */
export function pctText(v: number): string {
  if (!Number.isFinite(v)) return '–'
  const r = Math.round(v)
  if (v > 0 && v < 0.05) return '<0.1%'
  if ((r === 100 && v < 99.95) || (r === 0 && v > 0)) return `${v.toFixed(1)}%`
  return `${r}%`
}

/** Break [text] at ' · ' separators (else spaces) into lines of at most [max] characters. */
export function wrapAt(text: string, max: number): string[] {
  const parts = text.split(' · ')
  const sep = parts.length > 1 ? ' · ' : ' '
  const words = parts.length > 1 ? parts : text.split(' ')
  const lines: string[] = []
  let cur = ''
  for (const w of words) {
    if (cur && (cur + sep + w).length > max) {
      lines.push(cur + (sep === ' · ' ? ' ·' : ''))
      cur = w
    } else cur = cur ? cur + sep + w : w
  }
  if (cur) lines.push(cur)
  return lines
}

export interface CompareOptions {
  /** Narrow plot (phone): short axis titles, wrapped names and labels. */
  narrow?: boolean
  /**
   * PNG export: the headline (and, in the simple view, the "Bars" sub-line
   * and the score line) are drawn into the figure. On screen they are HTML
   * lines around the chart (they wrap and are read first).
   */
  png?: boolean
}

const mono = (s: string) => `<span style="font-family:${MONO}">${s}</span>`
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

/**
 * Plain alt text: the headline as this view shows it (so a screen reader never hears "almost tied" under a
 * visible "Tied"), then every row's exact numbers, the plain score line and the exact formula.
 */
function compareAlt(d: CompareData, rows: CompareRow[], earth: string, exact: boolean): string {
  const s = scoreTexts(rows)
  return `${headline(d, exact)}. ` + rows.map((r, i) => `${i + 1}. ${r.name}, score ${s[i]}, sunlight ${r.pctSunlit.toFixed(1)}%, ` +
    `${earth} ${r.pctEarth.toFixed(1)}%, Sun and Earth together ${r.pctBoth.toFixed(1)}%, longest dark ${longestDarkText(r)}`).join('; ') +
    `. ${scoreLine(d.weights)} ${weightsText(d.weights)}.`
}

/** Exact view: grouped bars (left) and the star score panel (right), best site first. */
export function buildCompare(d: CompareData, opts: CompareOptions = {}): Fig {
  const narrow = !!opts.narrow
  const earth = d.earthLabel || DEFAULT_EARTH_LABEL
  const rows = ranked(d)
  const st = scoreTexts(rows)
  const dp = scoreDecimals(rows.map((r) => r.score))
  const names = rows.map((r) => (narrow ? wrapAt(r.name, 14).join('<br>') : r.name))
  const bar = (key: 'pctSunlit' | 'pctEarth' | 'pctBoth', name: string, color: string, pattern?: string) => ({
    type: 'bar', orientation: 'h', y: names, x: rows.map((r) => r[key]), name,
    marker: { color, ...(pattern ? { pattern: { shape: pattern, fillmode: 'overlay', fgcolor: C.bg, solidity: 0.3 } } : {}) },
    hovertemplate: `${name} %{x:.1f}%<extra>%{y}</extra>`, xaxis: 'x', yaxis: 'y',
  })
  const ticks = { tickmode: 'array', tickvals: [0, 50, 100], ticktext: ['0', '50', '100'] }
  const wt = weightsText(d.weights)
  const annotations: Record<string, unknown>[] = [{
    xref: 'paper', yref: 'paper', x: 0, xanchor: 'left', y: 0, yanchor: 'top', yshift: narrow ? -38 : -36, showarrow: false, align: 'left',
    font: { size: 12, color: C.muted }, text: narrow ? wt.replace('] + ', ']<br>+ ') : wt,
  }]
  if (opts.png) {
    annotations.push(
      { xref: 'paper', yref: 'paper', x: 0, xanchor: 'left', y: 1, yanchor: 'bottom', yshift: 50, showarrow: false, align: 'left',
        font: { size: 15, color: C.text }, text: `<b>${esc(headline(d, true))}</b>` },
      { xref: 'paper', yref: 'paper', x: 0, xanchor: 'left', y: 0, yanchor: 'top', yshift: -58, showarrow: false, align: 'left',
        font: { size: 12, color: C.muted }, text: esc(scoreLine(d.weights)) })
  }
  return {
    alt: compareAlt(d, rows, earth, true),
    data: [
      bar('pctSunlit', 'Sunlit %', C.sun),
      bar('pctEarth', `${earth} %`, C.earth, '.'),
      bar('pctBoth', 'Sun and Earth %', C.both, '/'),
      { type: 'scatter', mode: 'markers+text', y: names, x: rows.map((r) => r.score), xaxis: 'x2', yaxis: 'y',
        text: st, customdata: rows.map((r) => longestDarkText(r)), textposition: 'middle right', name: 'Score',
        marker: { color: C.text, size: 11, symbol: 'star' }, textfont: { family: MONO, size: 12, color: C.text },
        cliponaxis: false, hovertemplate: `Score %{x:.${dp}f}<br>Longest dark %{customdata}<extra>%{y}</extra>` },
    ],
    layout: {
      paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER, barmode: 'group',
      margin: { l: narrow ? 8 : 20, r: narrow ? 34 : 40, t: opts.png ? 92 : 8, b: opts.png ? 96 : narrow ? 74 : 62 },
      // separate domains with a clear gap, end ticks inside the range: '100' and '0' never touch
      xaxis: { domain: narrow ? [0, 0.58] : [0, 0.64], range: [0, 110], ...ticks, automargin: true,
        title: { text: narrow ? '% of period' : '% of the chosen period', font: { size: 12, color: C.muted }, standoff: 4 }, gridcolor: C.grid, tickfont: TICK },
      xaxis2: { domain: narrow ? [0.7, 1] : [0.74, 1], range: [0, 115], ...ticks, automargin: true,
        title: { text: narrow ? 'Score' : 'Score (0–100)', font: { size: 12, color: C.muted }, standoff: 4 }, gridcolor: C.grid, tickfont: TICK },
      yaxis: { autorange: 'reversed', gridcolor: C.grid, automargin: true, tickfont: { size: narrow ? 11.5 : 12.5, color: C.text } },
      // above the plot area, in the top margin (Plotly grows the margin to fit it)
      legend: { orientation: 'h', x: 0, xanchor: 'left', y: 1.02, yanchor: 'bottom', font: { size: 12, color: C.muted } },
      annotations,
    },
  }
}

/** Left margin of the simple blocks (the bar row labels sit in it), px. */
const simpleLeft = (narrow: boolean) => (narrow ? 104 : 136)

/**
 * Simple view: one block per site, best first, on a category axis. Per site:
 * a title row, a reason row (two rows when it wraps; none when empty), the
 * Sunlight / Earth / Sun + Earth bars with their share at the end, the
 * longest dark row, and a spacer before the next site.
 */
export function buildCompareSimple(d: CompareData, opts: CompareOptions = {}): Fig {
  const narrow = !!opts.narrow
  const earth = d.earthLabel || DEFAULT_EARTH_LABEL
  const rows = ranked(d)
  // whole scores, like the simple headline ("Tied: A and B, both 62") and the app's rank cards (62 / 100);
  // the exact view keeps the tie-aware decimals (pre-ux-4)
  const st = rows.map((r) => String(Math.round(r.score)))
  const why = reasons(rows, earth)
  const left = simpleLeft(narrow)
  const wrapLabel = (s: string) => (narrow && s.length > 14 ? wrapAt(s, 14).join('<br>') : s)
  const metrics: { key: 'pctSunlit' | 'pctEarth' | 'pctBoth'; label: string; color: string; pattern?: string }[] = [
    { key: 'pctSunlit', label: 'Sunlight', color: C.sun },
    { key: 'pctEarth', label: earth, color: C.earth, pattern: '.' },
    { key: 'pctBoth', label: 'Sun + Earth', color: C.both, pattern: '/' },
  ]
  const cats: string[] = [], ticks: string[] = []
  const at = (cat: string, tick = '') => { cats.push(cat); ticks.push(tick); return cats.length - 1 }
  const annotations: Record<string, unknown>[] = []
  const reasonMax = narrow ? 62 : 96
  rows.forEach((r, i) => {
    // title line, then the reason line(s) under it in one text block (natural line spacing),
    // given one category row per line so the bars never move under it
    const why1 = why[i] ? wrapAt(why[i], reasonMax) : []
    const t = at(`t${i}`)
    why1.forEach((_, k) => at(`r${i}${k ? 'b' : ''}`))
    annotations.push({ xref: 'paper', x: 0, xshift: -left + 4, y: t + why1.length / 2, yref: 'y', xanchor: 'left', showarrow: false, align: 'left',
      text: `<b>${i + 1} ${esc(r.name)}</b> <span style="color:${C.muted}">score</span> ${mono(st[i])}` +
        why1.map((l) => `<br><span style="font-size:12.5px;color:${C.muted}">${esc(l)}</span>`).join(''),
      font: { size: 14, color: C.text } })
    for (const m of metrics) at(`${m.key}${i}`, wrapLabel(m.label))
    const dk = at(`d${i}`, 'Longest dark')
    annotations.push({ xref: 'x', x: 0, y: dk, yref: 'y', xanchor: 'left', showarrow: false,
      text: mono(esc(longestDarkText(r))), font: { size: 13, color: C.text }, hovertext: longestDarkTip(r) })
    if (i < rows.length - 1) at(`s${i}`)
  })
  const data = metrics.map((m) => ({
    type: 'bar', orientation: 'h', name: m.label,
    y: rows.map((_, i) => `${m.key}${i}`), x: rows.map((r) => r[m.key]),
    text: rows.map((r) => pctText(r[m.key])), textposition: 'outside', cliponaxis: false,
    textfont: { family: MONO, size: 13, color: C.text },
    marker: { color: m.color, line: { width: 0 }, ...(m.pattern ? { pattern: { shape: m.pattern, fillmode: 'overlay', fgcolor: C.bg, solidity: 0.3 } } : {}) },
    customdata: rows.map((r) => r.name),
    hovertemplate: `${m.label} %{x:.1f}% of your chosen dates<extra>%{customdata}</extra>`,
  }))
  if (opts.png) {
    annotations.push(
      { xref: 'paper', yref: 'paper', x: 0, xshift: -left + 4, y: 1, yanchor: 'bottom', yshift: 26, xanchor: 'left', showarrow: false, align: 'left',
        text: `<b>${esc(headline(d))}</b>`, font: { size: 15, color: C.text } },
      { xref: 'paper', yref: 'paper', x: 0, xshift: -left + 4, y: 1, yanchor: 'bottom', yshift: 6, xanchor: 'left', showarrow: false, align: 'left',
        text: 'Bars: share of your chosen dates', font: { size: 12.5, color: C.muted } },
      { xref: 'paper', yref: 'paper', x: 0, xshift: -left + 4, y: 0, yanchor: 'top', yshift: -10, xanchor: 'left', showarrow: false, align: 'left',
        text: esc(scoreLine(d.weights)), font: { size: 12.5, color: C.muted } })
  }
  return {
    alt: compareAlt(d, rows, earth, false),
    data,
    layout: {
      paper_bgcolor: C.bg, plot_bgcolor: C.bg, font: FONT, hoverlabel: HOVER, barmode: 'overlay', bargap: 0.26, showlegend: false,
      margin: { l: left, r: narrow ? 52 : 60, t: opts.png ? 70 : 4, b: opts.png ? 44 : 4 },
      xaxis: { range: [0, 100], visible: false, fixedrange: true },
      yaxis: { type: 'category', categoryorder: 'array', categoryarray: cats, autorange: false, range: [cats.length - 0.5, -0.5],
        tickmode: 'array', tickvals: cats, ticktext: ticks, showgrid: false, zeroline: false, fixedrange: true, automargin: false, ticks: '',
        ticklabelstandoff: 6, tickfont: { size: narrow ? 12 : 12.5, color: C.muted } },
      annotations, dragmode: false,
    },
  }
}
