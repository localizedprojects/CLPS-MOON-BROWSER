import { C, MONO } from './theme'

/**
 * "Where to look · <site> · <time> UTC". A narrow frame wraps it between the
 * parts instead of squeezing the site name (qa-1: on a phone it shrank to a
 * dot). Each part carries its " · " in front and `.ph-seps` hides the one of
 * the part that starts a line (styles.css), so no line starts with a dot.
 */
export function SkyHeader({ title, site, time, tip }: { title: string; site: string; time: string; tip?: string }) {
  return (
    <div data-header className="ph-seps" style={{ flex: 1 }} title={tip}>
      <div>
        <span><b style={{ fontWeight: 600 }}>{title}</b></span>
        <span data-site style={{ color: C.muted }}>{site}</span>
        <span><span data-time style={{ fontFamily: MONO, color: C.text }}>{time}</span></span>
      </div>
    </div>
  )
}
