import { IRQ_STAT, IRQ_VBLANK, REG } from './memory.ts'
import type { Memory } from './memory.ts'

export const WIDTH = 160
export const HEIGHT = 144

const LINE_DOTS = 456
const OAM_DOTS = 80
const DRAW_END = 252
const MODE_HBLANK = 0
const MODE_VBLANK = 1
const MODE_OAM = 2
const MODE_DRAW = 3

export type PPUState = { dot: number, windowLine: number, frame: Uint8Array, layer: Uint8Array }

export class PPU {
  readonly frame = new Uint8Array(WIDTH * HEIGHT)
  readonly layer = new Uint8Array(WIDTH * HEIGHT)
  frameReady = false
  #dot = 0
  #windowLine = 0
  #bgColor = new Uint8Array(WIDTH)
  #mem: Memory

  save(into?: PPUState): PPUState {
    if (!into) return { dot: this.#dot, windowLine: this.#windowLine, frame: this.frame.slice(), layer: this.layer.slice() }
    into.dot = this.#dot
    into.windowLine = this.#windowLine
    into.frame.set(this.frame)
    into.layer.set(this.layer)
    return into
  }

  load(state: PPUState) {
    this.#dot = state.dot
    this.#windowLine = state.windowLine
    this.frame.set(state.frame)
    this.layer.set(state.layer)
  }

  constructor(mem: Memory) {
    this.#mem = mem
  }

  tick(cycles: number) {
    const io = this.#mem.io
    if (!(io[REG.LCDC] & 0x80)) {
      this.#dot = 0
      this.#windowLine = 0
      io[REG.LY] = 0
      io[REG.STAT] &= ~0x03
      return
    }
    this.#dot += cycles
    for (;;) {
      const mode = io[REG.STAT] & 0x03
      if (mode === MODE_OAM && this.#dot >= OAM_DOTS) this.#setMode(MODE_DRAW)
      else if (mode === MODE_DRAW && this.#dot >= DRAW_END) {
        this.#renderLine(io[REG.LY])
        this.#setMode(MODE_HBLANK)
      } else if (this.#dot >= LINE_DOTS) {
        this.#dot -= LINE_DOTS
        this.#nextLine()
      } else return
    }
  }

  #nextLine() {
    const io = this.#mem.io
    const ly = io[REG.LY] + 1
    if (ly === HEIGHT) {
      io[REG.LY] = ly
      this.#setMode(MODE_VBLANK)
      this.#mem.request(IRQ_VBLANK)
      this.frameReady = true
    } else if (ly > 153) {
      io[REG.LY] = 0
      this.#windowLine = 0
      this.#setMode(MODE_OAM)
    } else {
      io[REG.LY] = ly
      if (ly < HEIGHT) this.#setMode(MODE_OAM)
    }
    this.#compareLY()
  }

  #setMode(mode: number) {
    const io = this.#mem.io
    io[REG.STAT] = (io[REG.STAT] & ~0x03) | mode
    const source = mode === MODE_HBLANK ? 0x08 : mode === MODE_VBLANK ? 0x10 : mode === MODE_OAM ? 0x20 : 0
    if (io[REG.STAT] & source) this.#mem.request(IRQ_STAT)
  }

  #compareLY() {
    const io = this.#mem.io
    const match = io[REG.LY] === io[REG.LYC]
    io[REG.STAT] = (io[REG.STAT] & ~0x04) | (match ? 0x04 : 0)
    if (match && io[REG.STAT] & 0x40) this.#mem.request(IRQ_STAT)
  }

  #tilePixel(tileAddr: number, row: number, col: number) {
    const vram = this.#mem.vram
    const lo = vram[tileAddr + row * 2]
    const hi = vram[tileAddr + row * 2 + 1]
    const bit = 7 - col
    return (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
  }

  #bgTile(index: number, unsigned: boolean) {
    return unsigned ? index * 16 : 0x1000 + ((index ^ 0x80) - 0x80) * 16
  }

  #renderLine(ly: number) {
    const io = this.#mem.io
    const vram = this.#mem.vram
    const lcdc = io[REG.LCDC]
    const bgp = io[REG.BGP]
    const row = ly * WIDTH
    const unsigned = (lcdc & 0x10) !== 0
    this.layer.fill(0, row, row + WIDTH)

    if (lcdc & 0x01) {
      const map = lcdc & 0x08 ? 0x1c00 : 0x1800
      const y = (ly + io[REG.SCY]) & 0xff
      for (let x = 0; x < WIDTH; x++) {
        const px = (x + io[REG.SCX]) & 0xff
        const tile = vram[map + (y >> 3) * 32 + (px >> 3)]
        const color = this.#tilePixel(this.#bgTile(tile, unsigned), y & 7, px & 7)
        this.#bgColor[x] = color
        this.frame[row + x] = (bgp >> (color * 2)) & 3
      }

      const wx = io[REG.WX] - 7
      if (lcdc & 0x20 && io[REG.WY] <= ly && wx < WIDTH) {
        const wmap = lcdc & 0x40 ? 0x1c00 : 0x1800
        const wy = this.#windowLine++
        for (let x = Math.max(0, wx); x < WIDTH; x++) {
          const px = x - wx
          const tile = vram[wmap + (wy >> 3) * 32 + (px >> 3)]
          const color = this.#tilePixel(this.#bgTile(tile, unsigned), wy & 7, px & 7)
          this.#bgColor[x] = color
          this.frame[row + x] = (bgp >> (color * 2)) & 3
        }
      }
    } else {
      this.#bgColor.fill(0)
      this.frame.fill(0, row, row + WIDTH)
    }

    if (lcdc & 0x02) this.#renderSprites(ly, row, lcdc & 0x04 ? 16 : 8)
  }

  #renderSprites(ly: number, row: number, height: number) {
    const oam = this.#mem.oam
    const io = this.#mem.io
    const visible: number[] = []
    for (let i = 0; i < 40 && visible.length < 10; i++) {
      const top = oam[i * 4] - 16
      if (ly >= top && ly < top + height) visible.push(i)
    }
    visible.sort((a, b) => oam[b * 4 + 1] - oam[a * 4 + 1] || b - a)
    for (const i of visible) {
      const top = oam[i * 4] - 16
      const left = oam[i * 4 + 1] - 8
      const tile = height === 16 ? oam[i * 4 + 2] & 0xfe : oam[i * 4 + 2]
      const attr = oam[i * 4 + 3]
      const palette = attr & 0x10 ? io[REG.OBP1] : io[REG.OBP0]
      const line = attr & 0x40 ? height - 1 - (ly - top) : ly - top
      for (let col = 0; col < 8; col++) {
        const x = left + col
        if (x < 0 || x >= WIDTH) continue
        const color = this.#tilePixel(tile * 16, line, attr & 0x20 ? 7 - col : col)
        if (color === 0) continue
        if (attr & 0x80 && this.#bgColor[x] !== 0) continue
        this.frame[row + x] = (palette >> (color * 2)) & 3
        this.layer[row + x] = attr & 0x10 ? 2 : 1
      }
    }
  }
}
