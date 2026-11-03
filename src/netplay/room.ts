import { delayFor } from './lockstep.ts'
import type { ClientMessage, ServerMessage } from './protocol.ts'

const PINGS = 3
const PING_TIMEOUT_MS = 3000
const MESSAGES_PER_SECOND = 300

export type Seat = { send: (message: ServerMessage) => void, rtt: number, pings: number, pingAt: number, sent: number, since: number }

export const seat = (send: Seat['send']): Seat => ({ send, rtt: 0, pings: 0, pingAt: 0, sent: 0, since: 0 })

export const withinRate = (from: Seat) => {
  const now = Date.now()
  if (now - from.since >= 1000) {
    from.since = now
    from.sent = 0
  }
  return ++from.sent <= MESSAGES_PER_SECOND
}

export class Room {
  readonly host: Seat
  guest: Seat | null = null
  #started = false
  #over = false

  constructor(host: Seat) {
    this.host = host
  }

  get open() {
    return !this.guest && !this.#over
  }

  join(guest: Seat) {
    this.guest = guest
    this.#ping(this.host)
    this.#ping(guest)
    setTimeout(() => this.#start(), PING_TIMEOUT_MS)
  }

  receive(from: Seat, message: ClientMessage) {
    if (message.t !== 'pong') return this.#other(from)?.send(message)
    if (!from.pingAt) return
    from.rtt = Math.max(from.rtt, Date.now() - from.pingAt)
    from.pingAt = 0
    if (++from.pings < PINGS) this.#ping(from)
    else if (this.host.pings >= PINGS && (this.guest?.pings ?? 0) >= PINGS) this.#start()
  }

  leave(from: Seat) {
    if (this.#over) return
    this.#over = true
    this.#other(from)?.send({ t: 'bye' })
  }

  #other(from: Seat) {
    return from === this.host ? this.guest : this.host
  }

  #ping(to: Seat) {
    to.pingAt = Date.now()
    to.send({ t: 'ping' })
  }

  #start() {
    const { host, guest } = this
    if (this.#started || this.#over || !guest) return
    this.#started = true
    const rtt = (s: Seat) => s.pings ? s.rtt : PING_TIMEOUT_MS
    const delay = delayFor((rtt(host) + rtt(guest)) / 2)
    host.send({ t: 'start', player: 1, delay })
    guest.send({ t: 'start', player: 2, delay })
  }
}
