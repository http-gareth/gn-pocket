import { APU } from './apu.ts'
import { CPU } from './cpu.ts'
import { Memory } from './memory.ts'
import type { Button, MemoryState } from './memory.ts'
import { PPU } from './ppu.ts'
import type { PPUState } from './ppu.ts'
import { Timer } from './timer.ts'

export const CYCLES_PER_FRAME = 70224

export type Snapshot = { cpu: number[], mem: MemoryState, timer: number, ppu: PPUState }

export class GameBoy {
  readonly mem: Memory
  readonly cpu: CPU
  readonly ppu: PPU
  readonly timer: Timer
  readonly apu: APU

  constructor(rom: Uint8Array) {
    this.mem = new Memory(rom)
    this.cpu = new CPU(this.mem)
    this.ppu = new PPU(this.mem)
    this.timer = new Timer(this.mem)
    this.apu = new APU()
    this.mem.audio = this.apu
  }

  step() {
    const cycles = this.cpu.step()
    this.timer.tick(cycles)
    this.ppu.tick(cycles)
    this.apu.tick(cycles)
    return cycles
  }

  runFrame() {
    this.ppu.frameReady = false
    let spent = 0
    while (!this.ppu.frameReady && spent < CYCLES_PER_FRAME) spent += this.step()
    return this.ppu.frame
  }

  snapshot(into?: Snapshot): Snapshot {
    return { cpu: this.cpu.save(), mem: this.mem.save(into?.mem), timer: this.timer.save(), ppu: this.ppu.save(into?.ppu) }
  }

  restore(state: Snapshot) {
    this.cpu.load(state.cpu)
    this.mem.load(state.mem)
    this.timer.load(state.timer)
    this.ppu.load(state.ppu)
  }

  press(button: Button) { this.mem.setButton(button, true) }
  release(button: Button) { this.mem.setButton(button, false) }
}
