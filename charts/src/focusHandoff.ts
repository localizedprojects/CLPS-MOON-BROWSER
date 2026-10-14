/**
 * Keyboard focus between the Flutter web app and a chart iframe (a11y-1).
 *
 * The host sends `{type:'focusFirst'}` when Tab reaches the chart frame: the
 * page then focuses its first control (its last with `last`, on Shift+Tab). Tab past the last control (or
 * Shift+Tab before the first) posts `{type:'focusExit', dir}` so the host
 * moves its own focus on, instead of the browser leaving the iframe for the
 * page body. Until a focusFirst arrives (the Android WebView never sends one)
 * Tab is left to the browser.
 */
import { post, subscribe } from './bridge'

const FOCUSABLE = 'button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'

/** Whether Tab ([shift]: Shift+Tab) from [active] leaves the page's focus order ([order] in DOM order). */
export function tabLeaves<T>(order: T[], active: T | null, shift: boolean): boolean {
  const i = active == null ? -1 : order.indexOf(active)
  if (i < 0) return true
  return shift ? i === 0 : i === order.length - 1
}

/** The page's keyboard stops, in DOM order (hidden ones left out). */
export function focusOrder(doc: Document = document): HTMLElement[] {
  return [...doc.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.tabIndex >= 0 && el.getClientRects().length > 0)
}

export function installFocusHandoff(doc: Document = document) {
  let hosted = false
  subscribe((m) => {
    if (m.type !== 'focusFirst') return
    hosted = true
    const order = focusOrder(doc)
    ;(m.last ? order[order.length - 1] : order[0])?.focus()
  })
  doc.addEventListener('keydown', (e) => {
    if (!hosted || e.key !== 'Tab' || e.altKey || e.ctrlKey || e.metaKey) return
    if (!tabLeaves(focusOrder(doc), doc.activeElement as HTMLElement | null, e.shiftKey)) return
    e.preventDefault()
    post({ type: 'focusExit', dir: e.shiftKey ? -1 : 1 })
  })
}
