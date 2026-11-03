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
    const tac = this.#mem.io[REG.TAC]
    const period = TAC_BITS[tac & 3] * 2
    const edges = tac & 4 ? Math.floor((this.#counter + cycles) / period) - Math.floor(this.#counter / period) : 0
    this.#counter = (this.#counter + cycles) & 0xffff
    for (let i = 0; i < edges; i++) this.#incrementTima()
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
