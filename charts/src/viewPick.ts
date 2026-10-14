/**
 * Which chart a page shows (views.tsx renders it): Sky & time shows the
 * CLASSIC sky plot and timeline by default; the host's "Simple view" switch
 * (`{type:'simple', on:true}`, kept for replay) shows the simple views.
 * Compare always shows its own chart. Kept free of React and Plotly so the
 * rule is unit-tested in node.
 */
import type { View } from './bridge'
import { latest } from './bridge'

export type ViewKind = 'classicSky' | 'sky' | 'classicTimeline' | 'timeline' | 'compare'

/** The newest "Simple view" switch received (false before any: the classic charts). */
export const simpleOn = (): boolean => latest('simple')?.on === true

/** The chart for [view]: the classic sky plot and timeline unless [simple]; Compare always its own. */
export function viewKind(view: View, simple: boolean): ViewKind {
  if (view === 'compare') return 'compare'
  if (view === 'timeline') return simple ? 'timeline' : 'classicTimeline'
  return simple ? 'sky' : 'classicSky'
}
