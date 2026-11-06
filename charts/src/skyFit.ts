/**
 * The "Where to look" plot's side (SkyView.tsx): from the frame's width,
 * and in a frame shorter than the plot and the rest, from its height.
 */

/** Side padding of the sky view, px. */
export const SKY_PAD_PX = 12

/** Largest plot side, px (charts spec 2.2). */
export const SKY_MAX_PX = 520
/** Plot side for a frame [width] px wide: the frame width minus padding, at most 520 px. */
export const skySide = (width: number) => Math.max(160, Math.min(SKY_MAX_PX, Math.floor(width - 2 * SKY_PAD_PX)))

/** Smallest plot side when the frame's height limits it, px: about a 320 px phone's plot (264). */
export const SKY_FIT_MIN_PX = 260
/** Room kept under the content when the frame's height limits the plot, px: a caption line that wraps during Play. */
export const SKY_FIT_RESERVE_PX = 17

/**
 * The plot side's limit in a frame [width] x [height] px whose content
 * besides the plot (header, caption lines, the "Paths over the period"
 * toggle, the key line and the padding) takes [rest] px: none (null) when the
 * frame holds it all with the plot at its width ([skySide]), as the single
 * column's frames on phones do (sky_time.dart skyFrameHeight); else the side
 * that leaves the rest in the frame with [SKY_FIT_RESERVE_PX] to spare, never
 * under [SKY_FIT_MIN_PX] (a shorter frame scrolls). The wide pane's frame is
 * what the timeline beside it and NowStatus under it leave (397 x 532 px at
 * 1440 x 900, 597 x 604 at 1920 x 1080), shorter than the plot at its width
 * plus the rest (1.13.3: the toggle and the key line were in a scroll area
 * the frame hid).
 */
export function skyFitLimit(width: number, height: number, rest: number): number | null {
  if (rest + skySide(width) <= height + 0.5) return null // sub-pixel rounding of the measured boxes
  return Math.max(SKY_FIT_MIN_PX, Math.floor(height - rest - SKY_FIT_RESERVE_PX))
}

/** Plot side in a frame [width] x [height] px whose content besides the plot takes [rest] px. */
export const skyFitSide = (width: number, height: number, rest: number) => Math.min(skySide(width), skyFitLimit(width, height, rest) ?? Infinity)
