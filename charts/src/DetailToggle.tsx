/**
 * "Exact numbers" switch shared by the three charts (charts spec 2.0).
 *
 * The app's expert mode is the source of truth: Flutter sends
 * `{type:'detail', exact}` (kept for replay). A tap here changes this chart
 * only and posts `{type:'detail', exact}` back, so the host replays this
 * chart's own state after a reload. No localStorage.
 */
import { useEffect, useState } from 'react'
import { post, subscribe } from './bridge'

/** [exact, setExact]: follows the host's detail messages; setExact is a local toggle reported to the host. */
export function useDetail(): [boolean, (exact: boolean) => void] {
  const [exact, setExact] = useState(false)
  useEffect(() => subscribe((m) => { if (m.type === 'detail') setExact(m.exact) }), [])
  const set = (v: boolean) => {
    setExact(v)
    post({ type: 'detail', exact: v })
  }
  return [exact, set]
}

/**
 * A quiet text button, top right of a chart: "Exact numbers", or
 * "Simple view" while exact. A real <button> with aria-pressed and a 48 px
 * hit area (styles.css `.ph-detail`).
 */
export function DetailToggle({ exact, onChange, className }: { exact: boolean; onChange: (exact: boolean) => void; className?: string }) {
  return (
    <button
      type="button"
      className={className ? `ph-detail ${className}` : 'ph-detail'}
      aria-pressed={exact}
      onClick={() => onChange(!exact)}
    >
      {exact ? 'Simple view' : 'Exact numbers'}
    </button>
  )
}
