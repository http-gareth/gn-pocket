import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { assemble, includesOf } from '../src/assembler/assembler.ts'
import { GameBoy } from '../src/hardware/gameboy.ts'
import { REG } from '../src/hardware/memory.ts'

const files: Record<string, string> = {}
const load = (path: string) => {
  if (path in files) return
  files[path] = readFileSync(new URL(`../games/${path}`, import.meta.url), 'utf8')
  includesOf(files[path]).forEach(load)
}
load('pong.asm')
const rom = assemble(files['pong.asm'], { files, name: 'pong.asm' }).rom

const boot = () => new GameBoy(rom)
const frames = (gb: GameBoy, count: number) => { for (let i = 0; i < count; i++) gb.runFrame() }

test('pong boots, turns the screen on and draws the court', () => {
  const gb = boot()
  frames(gb, 5)
  assert.equal(gb.mem.io[REG.LCDC], 0x93)
  assert.equal(gb.mem.vram[0x1800 + 2 * 32 + 9], 3)
  assert.equal(gb.mem.vram[0x1800 + 32 + 7], 4)
  assert.ok(gb.ppu.frame.some(shade => shade === 3), 'paddles and ball are drawn in black')
})

test('the ball waits for the serve, then moves', () => {
  const gb = boot()
  frames(gb, 30)
  const ballX = gb.mem.oam[6 * 4 + 1]
  frames(gb, 20)
  assert.equal(gb.mem.oam[6 * 4 + 1], ballX)
  frames(gb, 30)
  assert.notEqual(gb.mem.oam[6 * 4 + 1], ballX)
})

test('holding down moves the player paddle down, and it stops at the wall', () => {
  const gb = boot()
  frames(gb, 5)
  const top = gb.mem.oam[0]
  gb.press('down')
  frames(gb, 10)
  const moved = gb.mem.oam[0] - top
  assert.ok(moved >= 16 && moved <= 20 && moved % 2 === 0, `moved ${moved}px in 10 frames at 2px per frame`)
  frames(gb, 100)
  assert.equal(gb.mem.oam[0], 120 + 16)
  gb.release('down')
})

test('a paddle parked in a corner cannot lock the rally into an endless loop', () => {
  for (const corner of ['down', 'up'] as const) {
    const gb = boot()
    gb.press(corner)
    let last = 0
    let longest = 0
    let previous = 0
    for (let frame = 0; frame < 60 * 180; frame++) {
      gb.runFrame()
      const score = gb.mem.read(0xff86) + gb.mem.read(0xff87)
      if (score !== previous) { longest = Math.max(longest, frame - last); last = frame; previous = score }
    }
    longest = Math.max(longest, 60 * 180 - last)
    assert.ok(longest < 60 * 30, `paddle held ${corner}: longest rally ${(longest / 60).toFixed(1)}s`)
  }
})

test('a full match plays out without crashing and somebody scores', () => {
  const gb = boot()
  frames(gb, 60 * 60)
  assert.ok(gb.mem.read(0xff86) + gb.mem.read(0xff87) > 0)
})
