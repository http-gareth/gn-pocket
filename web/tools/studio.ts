import { GameBoy } from '../../src/hardware/gameboy.ts'
import { HEIGHT, WIDTH } from '../../src/hardware/ppu.ts'
import type { Button } from '../../src/hardware/memory.ts'
import { assemble, resolveFiles } from '../../src/assembler/assembler.ts'
import { readGame, store, stored } from '../shared.ts'

const SHADES = [[0xe0, 0xf8, 0xd0], [0x88, 0xc0, 0x70], [0x34, 0x68, 0x56], [0x08, 0x18, 0x20]]
const FRAME_MS = 1000 / 59.7275
const KEYS: Record<string, Button> = {
  ArrowRight: 'right', ArrowLeft: 'left', ArrowUp: 'up', ArrowDown: 'down',
  KeyZ: 'a', KeyX: 'b', Enter: 'start', ShiftLeft: 'select', ShiftRight: 'select'
}

const code = document.querySelector('#code') as HTMLTextAreaElement
const status = document.querySelector('#status') as HTMLElement
const canvas = document.querySelector('#screen') as HTMLCanvasElement
const ctx = canvas.getContext('2d')!
const image = ctx.createImageData(WIDTH, HEIGHT)

const SOURCE_KEY = 'studio:source'
const remember = () => store(SOURCE_KEY, code.value)

let gb: GameBoy | null = null
let carry = 0
let last = performance.now()
let focused = false

const say = (text: string, bad = false) => {
  status.textContent = text
  status.classList.toggle('bad', bad)
}

const showLine = (line: number) => {
  const lines = code.value.split('\n')
  const start = lines.slice(0, line - 1).reduce((sum, text) => sum + text.length + 1, 0)
  code.focus()
  code.setSelectionRange(start, start + (lines[line - 1]?.length ?? 0))
}

const run = async () => {
  remember()
  try {
    const started = performance.now()
    const files = await resolveFiles('studio.asm', readGame, { 'studio.asm': code.value })
    const { rom } = assemble(files['studio.asm'], { files, name: 'studio.asm' })
    gb = new GameBoy(rom)
    canvas.focus()
    focused = true
    say(`Built ${rom.length / 1024} KB cartridge in ${(performance.now() - started).toFixed(1)} ms. Playing!`)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    say(message, true)
    const line = /^studio\.asm line (\d+)/.exec(message)
    if (line) showLine(Number(line[1]))
  }
}

const loop = (time: number) => {
  carry += Math.min(250, time - last)
  last = time
  if (gb) {
    try {
      while (carry >= FRAME_MS) {
        gb.runFrame()
        carry -= FRAME_MS
      }
      const data = image.data
      gb.ppu.frame.forEach((shade, i) => {
        const [r, g, b] = SHADES[shade]
        data[i * 4] = r
        data[i * 4 + 1] = g
        data[i * 4 + 2] = b
        data[i * 4 + 3] = 255
      })
      ctx.putImageData(image, 0, 0)
    } catch (error) {
      gb = null
      say(`Your game crashed: ${error instanceof Error ? error.message : error}`, true)
    }
  } else {
    carry = 0
  }
  requestAnimationFrame(loop)
}

const example = async () => {
  code.value = await readGame('examples/hello.asm')
  remember()
}

code.addEventListener('keydown', e => {
  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
    e.preventDefault()
    run()
  } else if (e.key === 'Tab') {
    e.preventDefault()
    code.setRangeText('    ', code.selectionStart, code.selectionEnd, 'end')
  }
})
code.addEventListener('input', remember)
code.addEventListener('focus', () => { focused = false })
canvas.tabIndex = 0
canvas.addEventListener('focus', () => { focused = true })
canvas.addEventListener('blur', () => { focused = false })
for (const type of ['keydown', 'keyup'] as const) {
  addEventListener(type, e => {
    const button = KEYS[e.code]
    if (!button || !focused || !gb) return
    e.preventDefault()
    if (type === 'keydown') gb.press(button)
    else gb.release(button)
  })
}
document.querySelector('#run')!.addEventListener('click', run)
document.querySelector('#example')!.addEventListener('click', example)
document.querySelector('#pocket')!.addEventListener('click', remember)

const saved = stored(SOURCE_KEY)
if (saved) code.value = saved
else await example()
requestAnimationFrame(loop)
run()
