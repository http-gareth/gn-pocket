import { IRQ_TIMER, REG } from './memory.ts'
import type { Memory } from './memory.ts'

const TAC_BITS = [512, 8, 32, 128]

export class Timer {
  #counter = 0xabcc
  #mem: Memory

  constructor(mem: Memory) {
    this.#mem = mem
    mem.onDivWrite = () => {
      if (this.#selectedBit()) this.#incrementTima()
      this.#counter = 0
      this.#sync()
    }
    this.#sync()
  }

  save() { return this.#counter }
  load(counter: number) { this.#counter = counter }

  tick(cycles: number) {
    for (let i = 0; i < cycles; i += 4) {
      const before = this.#selectedBit()
      this.#counter = (this.#counter + 4) & 0xffff
      if (before && !this.#selectedBit()) this.#incrementTima()
    }
    this.#sync()
  }

  #selectedBit() {
    const tac = this.#mem.io[REG.TAC]
    return (tac & 4) !== 0 && (this.#counter & TAC_BITS[tac & 3]) !== 0
  }

  #incrementTima() {
    const io = this.#mem.io
    if (io[REG.TIMA] === 0xff) {
      io[REG.TIMA] = io[REG.TMA]
      this.#mem.request(IRQ_TIMER)
    } else {
      io[REG.TIMA]++
    }
  }

  #sync() {
    this.#mem.io[REG.DIV] = this.#counter >> 8
  }
}
