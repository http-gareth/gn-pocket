import type { GameBoy } from '../../src/hardware/gameboy.ts'

type Part = string | { bold: string }
export type NerdStats = { cart: string, fps: number, msPerFrame: number, colors: Uint8Array }

const h2 = (n: number) => n.toString(16).padStart(2, '0').toUpperCase()
const h4 = (n: number) => n.toString(16).padStart(4, '0').toUpperCase()

const render = (target: HTMLElement, lines: Part[][]) => {
  const nodes: Node[] = []
  lines.forEach((parts, i) => {
    if (i) nodes.push(document.createTextNode('\n'))
    for (const part of parts) {
      if (typeof part === 'string') {
        nodes.push(document.createTextNode(part))
      } else {
        const bold = document.createElement('b')
        bold.textContent = part.bold
        nodes.push(bold)
      }
    }
  })
  target.replaceChildren(...nodes)
}

export const routinesOf = (symbols: Map<string, number>) => [...symbols]
  .filter(([label, address]) => address >= 0x150 && address < 0x8000 && !/^[A-Z0-9_]+$/.test(label) && !/^[hrw][A-Z]/.test(label))
  .sort((a, b) => a[1] - b[1])

export class NerdPanel {
  routines: [string, number][] = []
  readonly #root: HTMLElement
  readonly #cpu: HTMLElement
  readonly #ram: HTMLElement
  readonly #tiles: CanvasRenderingContext2D
  readonly #image: ImageData
  #previousRam = new Uint8Array(128)

  constructor(root: HTMLElement) {
    this.#root = root
    this.#cpu = root.querySelector('#nerd-cpu')!
    this.#ram = root.querySelector('#nerd-ram')!
    this.#tiles = root.querySelector<HTMLCanvasElement>('#nerd-tiles')!.getContext('2d')!
    this.#image = this.#tiles.createImageData(128, 128)
  }

  get open() {
    return !this.#root.hidden
  }

  toggle() {
    this.#root.hidden = !this.#root.hidden
    return this.open
  }

  draw(device: GameBoy, stats: NerdStats) {
    this.#drawCpu(device, stats)
    this.#drawRam(device.mem.hram)
    this.#drawTiles(device.mem.vram, stats.colors)
  }

  #routineAt(pc: number) {
    let name = '?'
    for (const [label, address] of this.routines) {
      if (address > pc) break
      name = label
    }
    return name
  }

  #drawCpu(device: GameBoy, stats: NerdStats) {
    const c = device.cpu
    const flags = ['Z', 'N', 'H', 'C'].map((flag, i) => c.f & (0x80 >> i) ? flag : '-').join('')
    render(this.#cpu, [
      [`AF ${h2(c.a)}${h2(c.f)}  BC ${h2(c.b)}${h2(c.c)}  ${flags}`],
      [`DE ${h2(c.d)}${h2(c.e)}  HL ${h2(c.h)}${h2(c.l)}  ${c.ime ? 'IME' : 'ime'}`],
      [`SP ${h4(c.sp)}  PC `, { bold: h4(c.pc) }, `  ${c.halted ? 'HALT' : 'RUN '}`],
      ['in ', { bold: this.#routineAt(c.pc) }],
      [`scanline ${device.mem.io[0x44].toString().padStart(3)}  cart ${stats.cart}`],
      [{ bold: String(stats.fps) }, ' fps  ', { bold: stats.msPerFrame.toFixed(1) }, ' ms per frame']
    ])
  }

  #drawRam(ram: Uint8Array) {
    const lines: Part[][] = []
    for (let row = 0; row < 8; row++) {
      const parts: Part[] = [h2(0x80 + row * 16)]
      for (let col = 0; col < 16; col++) {
        const i = row * 16 + col
        const text = h2(ram[i] ?? 0)
        parts.push(' ', i < ram.length && ram[i] !== this.#previousRam[i] ? { bold: text } : text)
      }
      lines.push(parts)
    }
    this.#previousRam = ram.slice()
    render(this.#ram, lines)
  }

  #drawTiles(vram: Uint8Array, colors: Uint8Array) {
    const data = this.#image.data
    for (let tile = 0; tile < 256; tile++) {
      for (let y = 0; y < 8; y++) {
        const lo = vram[tile * 16 + y * 2]
        const hi = vram[tile * 16 + y * 2 + 1]
        for (let x = 0; x < 8; x++) {
          const shade = ((hi >> (7 - x)) & 1) << 1 | ((lo >> (7 - x)) & 1)
          const o = (((tile >> 4) * 8 + y) * 128 + (tile & 15) * 8 + x) * 4
          data[o] = colors[shade * 3]
          data[o + 1] = colors[shade * 3 + 1]
          data[o + 2] = colors[shade * 3 + 2]
          data[o + 3] = 255
        }
      }
    }
    this.#tiles.putImageData(this.#image, 0, 0)
  }
}
