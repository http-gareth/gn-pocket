import { MAX_DELAY } from './lockstep.ts'

export type LinkMessage = { t: 'in', f: number, b: number } | { t: 'sum', f: number, s: number }
export type ClientMessage = { t: 'pong' } | LinkMessage
export type ServerMessage = { t: 'room', code: string } | { t: 'nope' } | { t: 'start', player: 1 | 2, delay: number } | { t: 'bye' } | { t: 'ping' } | LinkMessage

export const CODE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
export const CODE_LENGTH = 4
export const CODE = /^[A-Z]{4}$/
export const MAX_MESSAGE_BYTES = 256

export const newCode = () => {
  let code = ''
  while (code.length < CODE_LENGTH) {
    const [byte] = crypto.getRandomValues(new Uint8Array(1))
    if (byte < 240) code += CODE_LETTERS[byte % CODE_LETTERS.length]
  }
  return code
}

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
  if (value.t === 'pong') return { t: 'pong' }
  return linkMessage(value)
}

export const parseServerMessage = (text: string): ServerMessage | null => {
  const value = object(text)
  if (!value) return null
  const { t, code, player, delay } = value
  if (t === 'room' && typeof code === 'string' && CODE.test(code)) return { t, code }
  if (t === 'nope' || t === 'bye' || t === 'ping') return { t }
  if (t === 'start' && (player === 1 || player === 2) && isWhole(delay, MAX_DELAY) && delay > 0) return { t, player, delay }
  return linkMessage(value)
}

export const linkRole = (search: string) => {
  const params = new URLSearchParams(search)
  if (params.has('host')) return { host: true as const }
  const code = (params.get('join') ?? '').toUpperCase()
  return CODE.test(code) ? { host: false as const, code } : null
}
