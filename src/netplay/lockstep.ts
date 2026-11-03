import type { GameBoy } from '../hardware/gameboy.ts'
import type { LinkMessage } from './protocol.ts'

export const DELAY = 4
export const MAX_DELAY = 30
export const SUM_EVERY = 120
export const FRAME_MS = 1000 / 59.7275

export const delayFor = (oneWayMs: number) => Math.min(MAX_DELAY, Math.max(DELAY, Math.ceil(oneWayMs / FRAME_MS) + 2))

export class Lockstep {
  frame = 0
  desynced = false
  readonly #mine = new Map<number, number>()
  readonly #theirs = new Map<number, number>()
  readonly #sums = new Map<number, number>()
  readonly #theirSums = new Map<number, number>()
  readonly player: 1 | 2
  readonly delay: number
  readonly #send: (message: LinkMessage) => void

  constructor(player: 1 | 2, send: (message: LinkMessage) => void, delay = DELAY) {
    this.player = player
    this.delay = delay
    this.#send = send
    for (let f = 0; f < delay; f++) {
      this.#mine.set(f, 0)
      this.#theirs.set(f, 0)
    }
  }

  receive(message: LinkMessage) {
    const ahead = message.f - this.frame
    const window = this.delay * 2
    if (message.t === 'in') {
      if (ahead >= 0 && ahead <= window) this.#theirs.set(message.f, message.b)
    } else if (Math.abs(ahead) <= window && message.f % SUM_EVERY === 0) {
      this.#theirSums.set(message.f, message.s)
      this.#compare(message.f)
    }
  }

  next(local: number): [number, number] | null {
    const ahead = this.frame + this.delay
    if (!this.#mine.has(ahead)) {
      this.#mine.set(ahead, local)
      this.#send({ t: 'in', f: ahead, b: local })
    }
    const theirs = this.#theirs.get(this.frame)
    if (theirs === undefined) return null
    const mine = this.#mine.get(this.frame)!
    this.#mine.delete(this.frame)
    this.#theirs.delete(this.frame)
    return this.player === 1 ? [mine, theirs] : [theirs, mine]
  }

  advance(sum: () => number) {
    this.frame++
    if (this.frame % SUM_EVERY) return
    const s = sum()
    this.#sums.set(this.frame, s)
    this.#send({ t: 'sum', f: this.frame, s })
    this.#compare(this.frame)
  }

  #compare(frame: number) {
    const mine = this.#sums.get(frame)
    const theirs = this.#theirSums.get(frame)
    if (mine === undefined || theirs === undefined) return
    if (mine !== theirs) this.desynced = true
    this.#sums.delete(frame)
    this.#theirSums.delete(frame)
  }
}

export const checksum = (gb: GameBoy) => {
  let hash = 0
  for (const block of [gb.mem.wram, gb.mem.hram, gb.mem.vram, gb.mem.oam]) {
    for (const byte of block) hash = (hash * 31 + byte) >>> 0
  }
  return hash
}
