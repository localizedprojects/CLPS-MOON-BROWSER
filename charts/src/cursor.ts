/**
 * The newer of a full payload and the latest cursor message wins. The host
 * replays its buffer (payload, then cursor) as soon as a page reports ready,
 * often before the figure exists; the views keep the newest cursor message
 * and apply it after every draw, so an early cursor is never lost and a
 * cursor that belongs to an older payload (another site) is never applied.
 */
import type { HostMessage, SkyData } from './bridge'
import { latest, seqOf } from './bridge'

type Msg<T extends HostMessage['type']> = Extract<HostMessage, { type: T }>

/** The sky payload's data with the newer of its own "now" and the latest skyNow message. */
export function skyNowData(m: Msg<'sky'>, now: Msg<'skyNow'> | null): SkyData {
  return now && seqOf(now) > seqOf(m) ? { ...m.data, now: now.now, timeLabel: now.timeLabel } : m.data
}

/** The timeline payload's cursor, or the latest cursor message when it is newer. */
export function timelineCursor(m: Msg<'timeline'>, cur: Msg<'cursor'> | null): number {
  return cur && seqOf(cur) > seqOf(m) ? cur.t : m.data.cursor
}

/**
 * The cursor the page holds for payload [m]: the newer of its own and the
 * latest cursor message the page has received (the replay buffer). A view
 * that mounts after the time moved (Simple view switched on later) anchors
 * its first window here: its own cursor ref fills only once its
 * subscription has run, after that first draw (F1, 2026-11-03).
 */
export function heldTimelineCursor(m: Msg<'timeline'>): number {
  return timelineCursor(m, latest('cursor'))
}
