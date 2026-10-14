/**
 * The newer of a full payload and the latest cursor message wins. The host
 * replays its buffer (payload, then cursor) as soon as a page reports ready,
 * often before the figure exists; the views keep the newest cursor message
 * and apply it after every draw, so an early cursor is never lost and a
 * cursor that belongs to an older payload (another site) is never applied.
 */
import type { HostMessage, SkyData } from './bridge'
import { seqOf } from './bridge'

type Msg<T extends HostMessage['type']> = Extract<HostMessage, { type: T }>

/** The sky payload's data with the newer of its own "now" and the latest skyNow message. */
export function skyNowData(m: Msg<'sky'>, now: Msg<'skyNow'> | null): SkyData {
  return now && seqOf(now) > seqOf(m) ? { ...m.data, now: now.now, timeLabel: now.timeLabel } : m.data
}

/** The timeline payload's cursor, or the latest cursor message when it is newer. */
export function timelineCursor(m: Msg<'timeline'>, cur: Msg<'cursor'> | null): number {
  return cur && seqOf(cur) > seqOf(m) ? cur.t : m.data.cursor
}
