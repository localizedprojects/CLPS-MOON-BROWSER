// first: what Chrome 69 (Android 7.0's WebView) lacks, before any library runs
import './polyfills'
import '@fontsource/ibm-plex-sans/latin-400.css'
import '@fontsource/ibm-plex-sans/latin-500.css'
import '@fontsource/ibm-plex-sans/latin-600.css'
import '@fontsource/ibm-plex-mono/latin-400.css'
import '@fontsource/ibm-plex-mono/latin-500.css'
import './styles.css'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { installBridge, subscribe, viewFromLocation } from './bridge'
import { App } from './views'
import { installFocusHandoff } from './focusHandoff'

installBridge()
installFocusHandoff()
// The app's full-screen view moves this page to a new size and back: settle
// the layout once the move is done (on Android a resize event does not
// always follow), so a chart never keeps the other size's layout.
// 'ph-settle' makes every chart redraw at its size then, unconditionally: during
// the move the web view can be hidden or briefly another size, and a chart
// drawn then stayed tiny or blank (seen on a OnePlus phone, 2026-10-14).
subscribe((m) => {
  if (m.type !== 'focus') return
  for (const ms of [150, 500, 1000]) {
    setTimeout(() => {
      window.dispatchEvent(new Event('resize'))
      window.dispatchEvent(new Event('ph-settle'))
    }, ms)
  }
})
const view = viewFromLocation()

// Standalone dev only: feed a clearly-labelled SYNTHETIC payload when no host
// answers. Excluded from production builds by the DEV guard.
if (import.meta.env.DEV) {
  setTimeout(() => { void import('./devSample').then((m) => m.feedDevSample(view)) }, 800)
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App view={view} />
  </StrictMode>,
)
