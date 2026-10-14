/**
 * The page's width now: the smaller of the window's and the page's own. The
 * web view can change size without a window resize event (moving a chart to
 * and from the app's full-screen view), and then only the page's width is
 * current. A side that reports nothing (0) is ignored.
 */
export function viewportWidth(
  win: { innerWidth: number } = window,
  doc: { documentElement?: { clientWidth: number } | null } = document,
): number {
  const a = win.innerWidth || Infinity, b = doc.documentElement?.clientWidth || Infinity
  return Math.min(a, b)
}
