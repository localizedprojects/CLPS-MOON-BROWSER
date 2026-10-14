/**
 * Hooks shared by the chart views (split out of views.tsx unchanged): the
 * newest host payload, the newest cursor-type message without re-renders,
 * the phone width class and the PNG export answer.
 */
import { useEffect, useRef, useState } from 'react'
import type { HostMessage } from './bridge'
import { subscribe } from './bridge'
import type { Fig } from './usePlot'
import { exportPng } from './usePlot'
import { C } from './theme'
import { viewportWidth } from './viewport'

export const box: React.CSSProperties = { width: '100%', height: '100%' }

export type Msg<T extends HostMessage['type']> = Extract<HostMessage, { type: T }>

/** The newest full payload of [type] (re-renders the view). */
export function useHost<T extends HostMessage['type']>(type: T) {
  const [msg, setMsg] = useState<Msg<T> | null>(null)
  useEffect(() => subscribe((m) => { if (m.type === type) setMsg(m as Msg<T>) }), [type])
  return msg
}

/**
 * The newest message of [type] in a ref (no re-render), and [apply] called
 * at most once per animation frame after one or more such messages.
 */
export function useLatest<T extends HostMessage['type']>(type: T, apply: () => void) {
  const ref = useRef<Msg<T> | null>(null)
  const fn = useRef(apply)
  fn.current = apply
  useEffect(() => {
    let raf = 0
    const run = () => { raf = 0; fn.current() }
    const off = subscribe((m) => {
      if (m.type !== type) return
      ref.current = m as Msg<T>
      if (!raf) raf = requestAnimationFrame(run)
    })
    return () => { off(); if (raf) cancelAnimationFrame(raf) }
  }, [type])
  return ref
}

/** True while the page is narrower than [px] (phones). */
/** The host's focus view: true while this chart is shown full screen (`{type:'focus', on}`, replayed). */
export function useFocusView(): boolean {
  const [on, setOn] = useState(false)
  useEffect(() => subscribe((m) => { if (m.type === 'focus') setOn(m.on) }), [])
  return on
}

export function useNarrow(px: number) {
  const [narrow, setNarrow] = useState(() => viewportWidth() < px)
  useEffect(() => {
    const f = () => setNarrow(viewportWidth() < px)
    window.addEventListener('resize', f)
    // moving to or from the app's full-screen view resizes the web view, and
    // a resize event does not always follow: watch the page itself too, or a
    // phone-width chart keeps the wide layout (squashed, overlapping labels)
    const ro = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(f)
    ro?.observe(document.documentElement)
    f()
    return () => {
      window.removeEventListener('resize', f)
      ro?.disconnect()
    }
  }, [px])
  return narrow
}

/**
 * Answer the host's PNG requests with a figure made by [make] at request time,
 * for the requested size (a file export, or the app's full-screen picture).
 */
export function useExport(make: (width: number, height: number) => Fig | null) {
  const mk = useRef(make)
  mk.current = make
  useEffect(() => subscribe((m) => {
    if (m.type !== 'exportPng') return
    const w = m.width ?? 1600, h = m.height ?? 1000
    void exportPng(mk.current(w, h), m.id, w, h, m.scale)
  }), [])
}

export function Waiting({ what }: { what: string }) {
  return <div style={{ ...box, display: 'grid', placeItems: 'center', color: C.muted, fontSize: 12.5, letterSpacing: 0.4 }}>Loading {what}…</div>
}

/**
 * The aria-live value for an answer or caption block (charts spec 2.0):
 * 'polite', but 'off' while messages of [types] arrive more than twice a
 * second (Play or scrubbing), back to 'polite' 1.5 s after the last one.
 */
export function useLiveMode(types: HostMessage['type'][]): 'polite' | 'off' {
  const [mode, setMode] = useState<'polite' | 'off'>('polite')
  const key = types.join(',')
  useEffect(() => {
    const want = new Set(key.split(','))
    const times: number[] = []
    let timer: ReturnType<typeof setTimeout> | undefined
    const off = subscribe((m) => {
      if (!want.has(m.type)) return
      const now = Date.now()
      times.push(now)
      while (times.length && now - times[0] > 1000) times.shift()
      if (times.length > 2) setMode('off')
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => { times.length = 0; setMode('polite') }, 1500)
    })
    return () => { off(); if (timer) clearTimeout(timer) }
  }, [key])
  return mode
}
