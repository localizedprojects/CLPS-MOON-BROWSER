// qa-1: the "Where to look" header wraps between its parts on a phone instead
// of squeezing the site name to a dot; charts-3: its time carries the year.
// @ts-expect-error node's types are not installed; vitest runs these tests in node
import { readFileSync } from 'node:fs'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { skyHeader } from './sky'
import { SkyHeader } from './SkyHeader'

const css: string = readFileSync(new URL('./styles.css', import.meta.url), 'utf8')
const rule = (sel: string) => {
  const i = css.indexOf(`${sel} {`)
  return i < 0 ? '' : css.slice(i, css.indexOf('}', i))
}

describe('sky header (qa-1, charts-3)', () => {
  const h = skyHeader({ siteName: 'Malapert peak (MP1)', timeLabel: '2026-10-20 19:00 UTC' })
  const html = renderToStaticMarkup(createElement(SkyHeader, { ...h }))

  it('names the site in full and shows the year', () => {
    expect(h.time).toBe('20 Oct 2026 19:00 UTC')
    expect(html).toContain('Malapert peak (MP1)')
    expect(html).toContain('20 Oct 2026 19:00 UTC')
  })

  it('is three parts in a wrapping row, with no squeezing nowrap container', () => {
    expect(html).toMatch(/^<div data-header="true" class="ph-seps"/)
    expect(html).not.toMatch(/data-header[^>]*white-space:\s*nowrap/)
    expect((html.match(/<span>|<span data-site/g) ?? []).length).toBe(3)
    // the separators are CSS, never text (so a wrapped line never starts with one)
    expect(html).not.toContain('·')
    expect(rule('.ph-seps > div')).toMatch(/flex-wrap:\s*wrap/)
    expect(rule('.ph-seps > div')).toMatch(/margin-left:\s*-1\.2em/)
    expect(rule('.ph-seps > div > span')).toMatch(/padding-left:\s*1\.2em/)
    expect(rule('.ph-seps > div > span::before')).toMatch(/position:\s*absolute/)
    // never cut off: a part wider than the line wraps inside itself
    expect(rule('.ph-seps > div > span')).not.toMatch(/nowrap|ellipsis/)
    expect(rule('.ph-seps')).toMatch(/overflow:\s*hidden/)
  })
})
