import { MAX_DELAY } from './lockstep.ts'

export type LinkMessage = { t: 'in', f: number, b: number } | { t: 'sum', f: number, s: number }
export type ClientMessage = { t: 'host' } | { t: 'join', code: string } | LinkMessage
export type ServerMessage = { t: 'room', code: string } | { t: 'nope' } | { t: 'start', player: 1 | 2, delay: number } | { t: 'bye' } | LinkMessage

export const CODE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
export const CODE_LENGTH = 4
export const MAX_MESSAGE_BYTES = 256

const CODE = /^[A-Z]{4}$/

const isWhole = (value: unknown, max: number): value is number =>
  Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= max

const object = (text: string): Record<string, unknown> | null => {
  try {
    const value: unknown = JSON.parse(text)
    return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null
  } catch {
    return null
  }
}

const linkMessage = (value: Record<string, unknown>): LinkMessage | null => {
  const { t, f, b, s } = value
  if (t === 'in' && isWhole(f, Number.MAX_SAFE_INTEGER) && isWhole(b, 0xff)) return { t, f, b }
  if (t === 'sum' && isWhole(f, Number.MAX_SAFE_INTEGER) && isWhole(s, 0xffffffff)) return { t, f, s }
  return null
}

export const parseClientMessage = (text: string): ClientMessage | null => {
  const value = object(text)
  if (!value) return null
  if (value.t === 'host') return { t: 'host' }
  if (value.t === 'join' && typeof value.code === 'string' && value.code.length <= CODE_LENGTH * 2) {
    return { t: 'join', code: value.code.toUpperCase() }
  }
  return linkMessage(value)
}

export const parseServerMessage = (text: string): ServerMessage | null => {
  const value = object(text)
  if (!value) return null
  const { t, code, player, delay } = value
  if (t === 'room' && typeof code === 'string' && CODE.test(code)) return { t, code }
  if (t === 'nope' || t === 'bye') return { t }
  if (t === 'start' && (player === 1 || player === 2) && isWhole(delay, MAX_DELAY) && delay > 0) return { t, player, delay }
  return linkMessage(value)
}
