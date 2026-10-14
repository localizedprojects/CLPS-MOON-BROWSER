/**
 * Router of the chart views. Sky & time shows the CLASSIC sky plot and
 * timeline by default (ClassicViews.tsx, restored at the user's request on
 * 2026-10-12); the host's `{type:'simple', on:true}` ("Simple view", off by
 * default) swaps in the simple views (SkyView.tsx "Where to look",
 * TimelineView.tsx "When"). Compare always shows CompareView.tsx. Shared
 * hooks are in viewHooks.tsx. Each draws its Plotly figure only when a full
 * payload arrives (or the width class changes). What follows the time cursor
 * is cheap: the sky plot's markers and labels live in an SVG overlay
 * (skyOverlay.ts) and the timeline's cursor is a DOM line, both moved at most
 * once per animation frame with the newest message, so scrubbing and Play
 * never queue Plotly redraws.
 *
 * A cursor message that arrives before the figure exists (the host replays
 * its buffer as soon as the page reports ready) is kept and applied after
 * the first draw; the newer of payload and cursor message always wins.
 */
import { useEffect, useState } from 'react'
import type { View } from './bridge'
import { post, subscribe } from './bridge'
import type { ViewKind } from './viewPick'
import { simpleOn, viewKind } from './viewPick'
import { ClassicSkyView, ClassicTimelineView } from './ClassicViews'
import { SkyView } from './SkyView'
import { TimelineView } from './TimelineView'
import { CompareView } from './CompareView'

const VIEWS: Record<ViewKind, () => React.JSX.Element> = {
  classicSky: ClassicSkyView, sky: SkyView, classicTimeline: ClassicTimelineView, timeline: TimelineView, compare: CompareView,
}

/** The host's "Simple view" switch: false (classic charts) until a `{type:'simple', on:true}` arrives. */
export function useSimple(): boolean {
  // the replayed switch is read at once, so a page that reloads in simple mode never draws the classic chart first
  const [simple, setSimple] = useState(() => simpleOn())
  useEffect(() => subscribe((m) => { if (m.type === 'simple') setSimple(m.on) }), [])
  return simple
}

export function App({ view: initial }: { view: View }) {
  // The host may switch views by message (Android loadFlutterAsset cannot pass a #hash).
  const [view, setView] = useState<View>(initial)
  const simple = useSimple()
  useEffect(() => subscribe((m) => { if (m.type === 'setView') setView(m.view) }), [])
  useEffect(() => {
    document.title = { sky: 'Sky plot', timeline: 'Visibility timeline', compare: 'Site comparison' }[view]
    post({ type: 'ready', view })
  }, [view])
  const V = VIEWS[viewKind(view, simple)]
  return <V />
}
