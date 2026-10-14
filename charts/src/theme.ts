/**
 * Design tokens (mirror app/lib/theme.dart and src/styles.css): calm deep navy,
 * depth from tone rather than hairlines. The chart background equals the
 * Flutter card colour (PH.panel) so embedded views read as part of the card.
 * Colour encodes meaning only (Sun amber, Earth blue, both teal) and is never
 * the only encoding.
 */
export const C = {
  bg: '#0C1528', // = PH.panel (cards)
  page: '#060B16', // = PH.bg
  panel: '#12203A', // = PH.panelHi (raised)
  selected: '#1C3358', // = PH.selected / PH.tonal (neutral selection, tonal buttons)
  sunken: '#08101F',
  grid: '#1E3050', // = PH.line / --line (hairlines), as the cards around the charts (charts-2)
  gridStrong: '#2C4470',
  text: '#E6EEF9',
  muted: '#8DA1C3',
  ice: '#A9CCFF',
  sun: '#FFB000',
  earth: '#3D8BFD',
  both: '#2EC4B6',
  terrain: 'rgba(52,72,110,0.92)',
  terrainEdge: '#7D93BA',
  /** slate fill of a dark spell / out-of-view gap (= --dark); text on it is C.text */
  dark: '#33445F',
  /** 1 px dashed outline of those gaps (= --dark-line; >= 3:1 on C.bg) */
  darkLine: '#6B7FA3',
  halo: 'rgba(12,21,40,0.92)',
} as const

/** Corner radii, px (= PH.radius, radiusInner, radiusCard, radiusSheet). */
export const RADIUS = { small: 6, inner: 12, card: 16, sheet: 24 } as const

/** The one motion: 250 ms fades (none when the viewer asks for reduced motion). */
export const FADE_MS = 250

export const SANS = "'IBM Plex Sans', system-ui, -apple-system, 'Segoe UI', sans-serif"
export const MONO = "'IBM Plex Mono', ui-monospace, 'Cascadia Mono', monospace"

/**
 * Type: Plex Sans, nothing below 12 px inside plots (13 in the Flutter UI).
 * Axis and value labels use Sans with tabular figures (= statStyle; the
 * figures are fixed-width in Plex Sans and styles.css enforces tabular-nums).
 * Mono (= numStyle) is kept for exact readouts: hover labels and UTC stamps.
 */
export const FONT = { family: SANS, color: C.text, size: 13 }
export const TICK = { family: SANS, color: C.muted, size: 12 }
export const STAT = { family: SANS, color: C.text, size: 16 }
export const HOVER = { bgcolor: C.panel, bordercolor: C.gridStrong, font: { family: MONO, size: 13, color: C.text } }

/** Unix ms -> 'YYYY-MM-DD HH:MM:SS' in UTC (Plotly date axes have no time zones). */
export function utcIso(ms: number): string {
  return new Date(ms).toISOString().replace('T', ' ').slice(0, 19)
}
