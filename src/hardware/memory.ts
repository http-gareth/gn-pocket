export const BUTTONS = ['right', 'left', 'up', 'down', 'a', 'b', 'select', 'start'] as const
export type Button = typeof BUTTONS[number]

export const IRQ_VBLANK = 0x01
export const IRQ_STAT = 0x02
export const IRQ_TIMER = 0x04
export const IRQ_JOYPAD = 0x10

export const REG = {
  JOYP: 0x00, DIV: 0x04, TIMA: 0x05, TMA: 0x06, TAC: 0x07, IF: 0x0f,
  LCDC: 0x40, STAT: 0x41, SCY: 0x42, SCX: 0x43, LY: 0x44, LYC: 0x45, DMA: 0x46,
  BGP: 0x47, OBP0: 0x48, OBP1: 0x49, WY: 0x4a, WX: 0x4b, RUMBLE: 0x7c, LINK: 0x7d, PAD2: 0x7e, LAUNCH: 0x7f
} as const

export type MemoryState = { vram: Uint8Array, wram: Uint8Array, oam: Uint8Array, hram: Uint8Array, io: Uint8Array, ie: number, pressed: number }

export class Memory {
  readonly vram = new Uint8Array(0x2000)
  readonly wram = new Uint8Array(0x2000)
  readonly oam = new Uint8Array(0xa0)
  readonly hram = new Uint8Array(0x7f)
  readonly io = new Uint8Array(0x80)
  ie = 0
  link = 0
  pad2 = 0
  onDivWrite: () => void = () => {}
  onLaunch: (index: number) => void = () => {}
  onRumble: (length: number) => void = () => {}
  audio: { read(reg: number): number; write(reg: number, value: number): void } | null = null
  #rom: Uint8Array
  #pressed = 0

  constructor(rom: Uint8Array) {
    this.#rom = rom
    this.io[REG.JOYP] = 0xcf
    this.io[REG.IF] = 0xe1
    this.io[REG.LCDC] = 0x91
    this.io[REG.STAT] = 0x86
    this.io[REG.BGP] = 0xfc
    this.io[REG.OBP0] = 0xff
    this.io[REG.OBP1] = 0xff
  }

  request(irq: number) {
    this.io[REG.IF] |= irq
  }

  setButton(button: Button, down: boolean) {
    const bit = 1 << BUTTONS.indexOf(button)
    if (down && !(this.#pressed & bit)) this.request(IRQ_JOYPAD)
    this.#pressed = down ? this.#pressed | bit : this.#pressed & ~bit
  }

  save(into?: MemoryState): MemoryState {
    if (!into) return { vram: this.vram.slice(), wram: this.wram.slice(), oam: this.oam.slice(), hram: this.hram.slice(), io: this.io.slice(), ie: this.ie, pressed: this.#pressed }
    into.vram.set(this.vram)
    into.wram.set(this.wram)
    into.oam.set(this.oam)
    into.hram.set(this.hram)
    into.io.set(this.io)
    into.ie = this.ie
    into.pressed = this.#pressed
    return into
  }

  load(state: MemoryState) {
    this.vram.set(state.vram)
    this.wram.set(state.wram)
    this.oam.set(state.oam)
    this.hram.set(state.hram)
    this.io.set(state.io)
    this.ie = state.ie
    this.#pressed = state.pressed
  }

  setPad(bits: number) {
    if (bits & ~this.#pressed) this.request(IRQ_JOYPAD)
    this.#pressed = bits
  }

  read(addr: number): number {
    if (addr < 0x8000) return this.#rom[addr] ?? 0xff
    if (addr < 0xa000) return this.vram[addr - 0x8000]
    if (addr < 0xc000) return 0xff
    if (addr < 0xe000) return this.wram[addr - 0xc000]
    if (addr < 0xfe00) return this.wram[addr - 0xe000]
    if (addr < 0xfea0) return this.oam[addr - 0xfe00]
    if (addr < 0xff00) return 0xff
    if (addr < 0xff80) return this.#readIO(addr - 0xff00)
    if (addr < 0xffff) return this.hram[addr - 0xff80]
    return this.ie
  }

  write(addr: number, value: number) {
    if (addr < 0x8000) return
    if (addr < 0xa000) { this.vram[addr - 0x8000] = value; return }
    if (addr < 0xc000) return
    if (addr < 0xe000) { this.wram[addr - 0xc000] = value; return }
    if (addr < 0xfe00) { this.wram[addr - 0xe000] = value; return }
    if (addr < 0xfea0) { this.oam[addr - 0xfe00] = value; return }
    if (addr < 0xff00) return
    if (addr < 0xff80) return this.#writeIO(addr - 0xff00, value)
    if (addr < 0xffff) { this.hram[addr - 0xff80] = value; return }
    this.ie = value
  }

  #readIO(reg: number) {
    if (reg >= 0x10 && reg < 0x40 && this.audio) return this.audio.read(reg)
    if (reg === REG.JOYP) {
      const select = this.io[REG.JOYP] & 0x30
      let low = 0x0f
      if (!(select & 0x10)) low &= ~(this.#pressed & 0x0f)
      if (!(select & 0x20)) low &= ~(this.#pressed >> 4)
      return 0xc0 | select | low
    }
    if (reg === REG.LINK) return this.link
    if (reg === REG.PAD2) return this.pad2
    if (reg === REG.IF) return this.io[reg] | 0xe0
    if (reg === REG.STAT) return this.io[reg] | 0x80
    return this.io[reg]
  }

  #writeIO(reg: number, value: number) {
    if (reg >= 0x10 && reg < 0x40 && this.audio) return this.audio.write(reg, value)
    switch (reg) {
      case REG.JOYP: this.io[reg] = (this.io[reg] & 0xcf) | (value & 0x30); return
      case REG.DIV: this.onDivWrite(); return
      case REG.LAUNCH: this.onLaunch(value); return
      case REG.RUMBLE: this.onRumble(value); return
      case REG.LY: return
      case REG.STAT: this.io[reg] = (this.io[reg] & 0x07) | (value & 0x78); return
      case REG.DMA: {
        const source = value << 8
        for (let i = 0; i < 0xa0; i++) this.oam[i] = this.read(source + i)
        this.io[reg] = value
        return
      }
      default: this.io[reg] = value
    }
  }
}
