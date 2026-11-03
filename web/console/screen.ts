import { HEIGHT, WIDTH } from '../../src/hardware/ppu.ts'

export type Palette = { name: string, bg: string[], obj?: string[], alt?: string[] }

export const PALETTES: Palette[] = [
  { name: 'CLASSIC', bg: ['#e0f8d0', '#88c070', '#346856', '#081820'] },
  { name: 'POCKET', bg: ['#e9ebe4', '#a9ab9f', '#5a5c53', '#1c1d19'] },
  { name: 'ARCADE', bg: ['#c8ecff', '#7bd36b', '#2f7a46', '#0b1a2a'], obj: ['#ffffff', '#ffd23f', '#e8432f', '#1a0a0a'], alt: ['#ffffff', '#8ad4ff', '#3a5fd8', '#0a1030'] },
  { name: 'SUNSET', bg: ['#fff1d6', '#ffb36b', '#b8476a', '#2b1638'], obj: ['#ffffff', '#fff27a', '#e8602c', '#2a0f12'], alt: ['#ffffff', '#a8e0ff', '#4a7ad8', '#141e3a'] },
  { name: 'NEON', bg: ['#0d0f1a', '#2d3a8c', '#9a5cf0', '#f2f2ff'], obj: ['#0d0f1a', '#39ff88', '#ff3d8b', '#ffffff'], alt: ['#0d0f1a', '#ffe14d', '#29d3ff', '#ffffff'] }
]

export const rgb = (hex: string) => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16))

export class Screen {
  colors = new Uint8Array(12 * 3)
  readonly #canvas: HTMLCanvasElement
  readonly #ctx: CanvasRenderingContext2D
  readonly #image: ImageData
  readonly #lcd: HTMLElement

  constructor(canvas: HTMLCanvasElement, lcd: HTMLElement) {
    this.#canvas = canvas
    this.#ctx = canvas.getContext('2d')!
    this.#image = this.#ctx.createImageData(WIDTH, HEIGHT)
    this.#lcd = lcd
    new ResizeObserver(() => this.#fit()).observe(lcd)
  }

  usePalette(palette: Palette) {
    const sets = [palette.bg, palette.obj ?? palette.bg, palette.alt ?? palette.obj ?? palette.bg]
    this.colors = new Uint8Array(sets.flatMap(set => set.flatMap(rgb)))
    this.#lcd.style.background = palette.bg[0]
  }

  draw(frame: Uint8Array, layer: Uint8Array) {
    const data = this.#image.data
    for (let i = 0; i < frame.length; i++) {
      const c = (layer[i] * 4 + frame[i]) * 3
      data[i * 4] = this.colors[c]
      data[i * 4 + 1] = this.colors[c + 1]
      data[i * 4 + 2] = this.colors[c + 2]
      data[i * 4 + 3] = 255
    }
    this.#ctx.putImageData(this.#image, 0, 0)
  }

  clear() {
    this.#ctx.clearRect(0, 0, WIDTH, HEIGHT)
  }

  #fit() {
    const dpr = devicePixelRatio || 1
    const fit = Math.min(this.#lcd.clientWidth * dpr / WIDTH, this.#lcd.clientHeight * dpr / HEIGHT)
    const scale = Math.floor(fit) >= fit * 0.9 ? Math.floor(fit) : fit
    this.#canvas.style.width = `${WIDTH * scale / dpr}px`
    this.#canvas.style.height = `${HEIGHT * scale / dpr}px`
  }
}
