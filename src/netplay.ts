import type { GameBoy } from './gameboy.ts'

export const DELAY = 4
export const SUM_EVERY = 120

export type LinkMessage = { t: 'in', f: number, b: number } | { t: 'sum', f: number, s: number }

export class Lockstep {
  frame = 0
  desynced = false
  readonly #mine = new Map<number, number>()
  readonly #theirs = new Map<number, number>()
  readonly #sums = new Map<number, number>()
  readonly #theirSums = new Map<number, number>()
  readonly player: 1 | 2
  readonly #send: (message: LinkMessage) => void

  constructor(player: 1 | 2, send: (message: LinkMessage) => void) {
    this.player = player
    this.#send = send
    for (let f = 0; f < DELAY; f++) {
      this.#mine.set(f, 0)
      this.#theirs.set(f, 0)
    }
  }

  receive(message: LinkMessage) {
    if (message.t === 'in') this.#theirs.set(message.f, message.b)
    else {
      this.#theirSums.set(message.f, message.s)
      this.#compare(message.f)
    }
  }

  next(local: number): [number, number] | null {
    const ahead = this.frame + DELAY
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
