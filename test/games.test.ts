import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { assemble, resolveFiles } from '../src/assembler.ts'
import { GameBoy } from '../src/gameboy.ts'
import { LIBRARY, MENU, libraryAsm } from '../src/library.ts'
import type { Cart } from '../src/library.ts'
import type { Button } from '../src/memory.ts'

const read = (path: string) => readFileSync(new URL(`../games/${path}`, import.meta.url), 'utf8')
const carts: Cart[] = JSON.parse(read('games.json'))

const boot = async (entry: string) => {
  const files = await resolveFiles(entry, read, { [LIBRARY]: libraryAsm(carts) })
  return new GameBoy(assemble(files[entry], { files, name: entry }).rom)
}

const frames = (gb: GameBoy, count: number) => { for (let i = 0; i < count; i++) gb.runFrame() }
const tap = (gb: GameBoy, button: Button) => { gb.press(button); frames(gb, 2); gb.release(button); frames(gb, 2) }
const row = (gb: GameBoy, y: number) =>
  String.fromCharCode(...gb.mem.vram.slice(0x1800 + y * 32, 0x1800 + y * 32 + 20).map(t => t < 64 ? t + 32 : 35))
const hram = (gb: GameBoy, addr: number) => gb.mem.read(addr)
const panelRow = (gb: GameBoy, y: number) =>
  String.fromCharCode(...gb.mem.vram.slice(0x1c00 + y * 32, 0x1c00 + y * 32 + 20).map(t => t < 64 ? t + 32 : 35))

test('the menu slides in, scrolls through every cartridge and launches the one you pick', async () => {
  const gb = await boot(MENU)
  frames(gb, 60)
  const visible = Math.min(5, carts.length)
  const titles = (top: number) => carts.slice(top, top + visible).forEach((cart, i) =>
    assert.match(row(gb, 6 + i * 2), new RegExp(cart.title.toUpperCase())))
  const arrow = (y: number) => gb.mem.vram[0x1800 + y * 32 + 18]
  const cursor = (slot: number) => assert.equal(gb.mem.oam[0], 6 * 8 + 16 + 16 * slot)
  assert.match(row(gb, 1), /GN POCKET/)
  titles(0)
  cursor(0)
  assert.equal(arrow(5), 0, 'nothing above the first game')
  assert.equal(arrow(15), 67, 'an arrow shows more games below')

  tap(gb, 'up')
  cursor(0)
  for (let i = 0; i < carts.length + 2; i++) tap(gb, 'down')
  titles(carts.length - visible)
  cursor(visible - 1)
  assert.equal(arrow(5), 66, 'an arrow shows more games above')
  assert.equal(arrow(15), 0, 'nothing below the last game')

  for (let i = 0; i < carts.length + 2; i++) tap(gb, 'up')
  titles(0)
  cursor(0)

  let launched = -1
  gb.mem.onLaunch = index => { launched = index }
  for (let i = 0; i < carts.length - 2; i++) tap(gb, 'down')
  tap(gb, 'a')
  assert.equal(launched, -1, 'the launch jingle plays before the cartridge swaps')
  frames(gb, 30)
  assert.equal(launched, carts.length - 2)
})

test('snake moves, eats, grows and scores', async () => {
  const gb = await boot('snake.asm')
  frames(gb, 3)
  assert.match(row(gb, 0), /SCORE 00/)
  const food = gb.mem.vram.indexOf(67, 0x1800)
  gb.mem.vram[food] = 0
  gb.mem.vram[0x1800 + 9 * 32 + 9] = 67
  gb.mem.write(0xff84, 9)
  gb.mem.write(0xff85, 9)
  frames(gb, 20)
  assert.match(row(gb, 0), /SCORE 01/)
  assert.equal((hram(gb, 0xff80) - hram(gb, 0xff81)) & 0xff, 3, 'the snake is one segment longer')
})

test('snake dies at the wall, shows game over, and A starts again', async () => {
  const gb = await boot('snake.asm')
  frames(gb, 150)
  assert.equal(hram(gb, 0xff89), 1)
  assert.match(row(gb, 8), /GAME OVER!/)
  tap(gb, 'a')
  frames(gb, 2)
  assert.equal(hram(gb, 0xff89), 0)
  assert.doesNotMatch(row(gb, 8), /GAME OVER/)
})

test('snake will not reverse into itself', async () => {
  const gb = await boot('snake.asm')
  frames(gb, 3)
  tap(gb, 'left')
  frames(gb, 20)
  assert.equal(hram(gb, 0xff89), 0)
  assert.equal(hram(gb, 0xff82), 0, 'still heading right')
})

test('shootout: a kick flies, gets judged and is marked on the scoreboard', async () => {
  const gb = await boot('shootout.asm')
  frames(gb, 5)
  assert.match(row(gb, 0), /YOU 0/)
  assert.match(row(gb, 10), /PRESS A TO SHOOT/)
  tap(gb, 'a')
  assert.equal(hram(gb, 0xff80), 2)
  frames(gb, 36)
  assert.equal(hram(gb, 0xff80), 3)
  assert.match(row(gb, 10), /GOAL!|SAVED!|MISS!/)
  assert.match(row(gb, 1)[1], /[OX]/)
})

test('shootout: you control the keeper on the CPU kick', async () => {
  const gb = await boot('shootout.asm')
  frames(gb, 5)
  tap(gb, 'a')
  frames(gb, 120)
  assert.equal(hram(gb, 0xff82), 1, 'second kick is the CPU')
  while (hram(gb, 0xff80) !== 2) frames(gb, 1)
  gb.press('left')
  frames(gb, 20)
  gb.release('left')
  assert.ok(hram(gb, 0xff88) < 80, 'the keeper dived left')
})

test('shootout: a full ten-kick match ends with a result', async () => {
  const gb = await boot('shootout.asm')
  for (let i = 0; i < 60 * 60 && hram(gb, 0xff80) !== 4; i++) {
    if (hram(gb, 0xff80) === 0) tap(gb, 'a')
    else frames(gb, 1)
  }
  assert.equal(hram(gb, 0xff80), 4)
  assert.equal(hram(gb, 0xff82), 10)
  assert.ok(hram(gb, 0xff83) + hram(gb, 0xff84) <= 10)
  assert.match(row(gb, 10), /YOU WIN!|CPU WINS!|DRAW!/)
  assert.doesNotMatch(row(gb, 1), /-/)
})

const bcd = (gb: GameBoy, lo: number) => Number((hram(gb, lo + 1) << 8 | hram(gb, lo)).toString(16))

test('bricks: the wall is built, the ball launches and a player can clear a level', async () => {
  const gb = await boot('bricks.asm')
  frames(gb, 5)
  assert.match(row(gb, 11), /B R I C K S/)
  tap(gb, 'start')
  const bricks = () => gb.mem.vram.slice(0x1800 + 3 * 32, 0x1800 + 9 * 32).filter(t => t >= 65 && t <= 70).length
  assert.equal(bricks(), 108)
  assert.match(row(gb, 13), /A: LAUNCH/)
  tap(gb, 'a')
  assert.equal(hram(gb, 0xff80), 2)
  let held: Button | null = null
  for (let i = 0; i < 60 * 150 && hram(gb, 0xff8a) === 1; i++) {
    if (hram(gb, 0xff80) === 1) { tap(gb, 'a'); continue }
    const offset = hram(gb, 0xff82) - 10 - hram(gb, 0xff81) + ((i >> 7) % 3 - 1) * 8
    const want: Button | null = offset > 2 ? 'right' : offset < -2 ? 'left' : null
    if (want !== held) { if (held) gb.release(held); if (want) gb.press(want); held = want }
    gb.runFrame()
  }
  assert.equal(hram(gb, 0xff8a), 2, 'reached level 2')
  assert.equal(bcd(gb, 0xff87), 54)
})

test('bricks: losing every ball ends the game and keeps the best score', async () => {
  const gb = await boot('bricks.asm')
  frames(gb, 5)
  tap(gb, 'start')
  gb.press('left')
  for (let i = 0; i < 3000 && hram(gb, 0xff80) !== 3; i++) {
    if (hram(gb, 0xff80) === 1) tap(gb, 'a')
    frames(gb, 1)
  }
  gb.release('left')
  assert.equal(hram(gb, 0xff80), 3)
  assert.match(row(gb, 11), /GAME OVER/)
  assert.equal(bcd(gb, 0xff8b), bcd(gb, 0xff87))
  tap(gb, 'start')
  assert.equal(hram(gb, 0xff86), 3, 'a fresh game has three balls')
  assert.equal(bcd(gb, 0xff87), 0)
})

const flapTile = (gb: GameBoy, col: number, y: number) => gb.mem.vram[0x1800 + y * 32 + (col & 31)]

test('flap: the world scrolls, and doing nothing ends on the ground', async () => {
  const gb = await boot('flap.asm')
  frames(gb, 5)
  assert.match(row(gb, 5), /F L A P/)
  tap(gb, 'a')
  assert.equal(hram(gb, 0xff80), 1)
  assert.doesNotMatch(row(gb, 5), /F L A P/)
  frames(gb, 30)
  assert.ok(gb.mem.io[0x43] > 30, 'the background scrolls')
  frames(gb, 120)
  assert.equal(hram(gb, 0xff80), 3)
  assert.equal(hram(gb, 0xff81), 113, 'the bird lies on the ground')
})

test('flap: flying through the gaps scores a point per pipe', async () => {
  const gb = await boot('flap.asm')
  frames(gb, 5)
  tap(gb, 'a')
  const aim = () => {
    const col = (gb.mem.io[0x43] + 43) >> 3
    for (let c = col - 1; c < col + 20; c++) {
      if (flapTile(gb, c, 14) !== 69) continue
      let top = 0
      while (top < 15 && flapTile(gb, c, top) !== 0) top++
      return top * 8 + 24
    }
    return 60
  }
  for (let i = 0; i < 60 * 12 && hram(gb, 0xff80) === 1; i++) {
    const falling = hram(gb, 0xff83) < 0x80 && (hram(gb, 0xff83) | hram(gb, 0xff84)) > 0
    if (hram(gb, 0xff81) > aim() && falling) { gb.press('a'); gb.runFrame(); gb.release('a') }
    gb.runFrame()
  }
  assert.ok(bcd(gb, 0xff89) >= 5, `scored ${bcd(gb, 0xff89)}`)
})

const bcd3 = (gb: GameBoy, lo: number) => Number([2, 1, 0].map(i => hram(gb, lo + i).toString(16).padStart(2, '0')).join(''))

test('blocks: a filled row flashes, clears and scores', async () => {
  const gb = await boot('blocks.asm')
  frames(gb, 5)
  assert.match(row(gb, 4), /BLOCKS/)
  tap(gb, 'start')
  assert.equal(hram(gb, 0xff80), 1)
  for (let y = 14; y < 18; y++) for (let x = 1; x < 10; x++) gb.mem.vram[0x1800 + y * 32 + x] = 66
  gb.mem.vram[0x1800 + 13 * 32 + 3] = 66
  gb.mem.write(0xff81, 0)
  tap(gb, 'a')
  for (let i = 0; i < 5; i++) tap(gb, 'right')
  tap(gb, 'up')
  assert.equal(hram(gb, 0xff80), 2, 'the cleared rows flash first')
  frames(gb, 30)
  assert.equal(hram(gb, 0xff80), 1)
  assert.equal(bcd(gb, 0xff89), 4)
  assert.ok(bcd3(gb, 0xff8b) >= 1200, 'four rows at once is worth 1200')
  assert.equal(gb.mem.vram[0x1800 + 17 * 32 + 3], 66, 'the block above fell into the gap')
  assert.equal(gb.mem.vram.slice(0x1800 + 14 * 32 + 1, 0x1800 + 14 * 32 + 11).filter(Boolean).length, 0)
})

test('blocks: stacking to the top drops the curtain and keeps the best score', async () => {
  const gb = await boot('blocks.asm')
  frames(gb, 5)
  tap(gb, 'start')
  for (let i = 0; i < 200 && hram(gb, 0xff80) !== 3; i++) tap(gb, 'up')
  assert.equal(hram(gb, 0xff80), 3)
  frames(gb, 50)
  assert.match(row(gb, 6), /GAME/)
  assert.match(row(gb, 7), /OVER/)
  assert.equal(bcd3(gb, 0xff8e), bcd3(gb, 0xff8b))
  tap(gb, 'start')
  assert.equal(hram(gb, 0xff80), 1)
  assert.equal(bcd3(gb, 0xff8b), 0)
})

test('racer: gas speeds you up, and a driver who does nothing crashes', async () => {
  const gb = await boot('racer.asm')
  frames(gb, 5)
  assert.match(panelRow(gb, 3), /R A C E R/)
  tap(gb, 'start')
  assert.equal(hram(gb, 0xff80), 1)
  const scy = gb.mem.io[0x42]
  gb.press('up')
  frames(gb, 30)
  gb.release('up')
  assert.ok(hram(gb, 0xff82) > 24, 'faster')
  assert.notEqual(gb.mem.io[0x42], scy, 'the road scrolls')
  for (let i = 0; i < 60 * 60 && hram(gb, 0xff80) === 1; i++) frames(gb, 1)
  assert.equal(hram(gb, 0xff80), 2)
  frames(gb, 60)
  assert.equal(hram(gb, 0xff80), 3)
  assert.match(panelRow(gb, 3), /GAME OVER/)
  assert.equal(gb.mem.io[0x4a], 72, 'the results panel slid up')
  assert.equal(bcd3(gb, 0xff89), bcd3(gb, 0xff86))
})

test('racer: a driver who reads the traffic survives', async () => {
  const gb = await boot('racer.asm')
  frames(gb, 5)
  tap(gb, 'start')
  let held: Button | null = null
  for (let i = 0; i < 60 * 40 && hram(gb, 0xff80) === 1; i++) {
    let near = -1
    for (let r = 0; r < 3; r++) { const y = hram(gb, 0xff90 + r); if (y >= 20 && y <= 141 && (near < 0 || y > hram(gb, 0xff90 + near))) near = r }
    const x = hram(gb, 0xff81)
    let target = x
    if (near >= 0) {
      const blocked = [hram(gb, 0xff93 + near), hram(gb, 0xff96 + near)]
      const free = [0, 1, 2, 3].filter(lane => !blocked.includes(lane)).map(lane => 36 + lane * 24)
      target = free.reduce((a, b) => Math.abs(b - x) < Math.abs(a - x) ? b : a)
    }
    const want: Button | null = target > x + 1 ? 'right' : target < x - 1 ? 'left' : null
    if (want !== held) { if (held) gb.release(held); if (want) gb.press(want); held = want }
    gb.runFrame()
  }
  assert.equal(hram(gb, 0xff80), 1, 'still racing after 40 seconds')
  assert.ok(bcd3(gb, 0xff86) > 2000, `score ${bcd3(gb, 0xff86)}`)
})

test('blocks, racer and invasion play music on the wave channel once the game starts', async () => {
  for (const file of ['blocks.asm', 'racer.asm', 'invasion.asm']) {
    const gb = await boot(file)
    frames(gb, 5)
    assert.equal(gb.apu.wave.on, false, `${file} is quiet on the title screen`)
    tap(gb, 'start')
    const notes = new Set<number>()
    for (let i = 0; i < 120; i++) { gb.runFrame(); notes.add(gb.apu.wave.freq) }
    assert.ok(gb.apu.wave.dac, `${file} switched the wave channel on`)
    assert.ok(notes.size >= 4, `${file} played ${notes.size} different notes`)
  }
})

test('racer: cars disappear behind the score bar instead of drawing over it', async () => {
  const gb = await boot('racer.asm')
  frames(gb, 5)
  tap(gb, 'start')
  frames(gb, 20)
  gb.mem.write(0xff90, 146)
  gb.mem.write(0xff93, 2)
  gb.mem.write(0xff81, 36)
  gb.runFrame()
  const pixels = (y0: number, y1: number) => [...Array(y1 - y0)].flatMap((_, i) => [...gb.ppu.frame.slice((y0 + i) * 160 + 96, (y0 + i) * 160 + 100)])
  assert.ok(pixels(130, 136).some(shade => shade === 3), 'the car is drawn above the bar')
  assert.ok(pixels(136, 144).every(shade => shade === 0), 'nothing of the car shows on the bar')
})

test('invasion: a shot destroys the alien above it and scores by row', async () => {
  const gb = await boot('invasion.asm')
  frames(gb, 5)
  assert.match(row(gb, 3), /I N V A S I O N/)
  assert.match(row(gb, 6), /= 30 POINTS/)
  tap(gb, 'start')
  assert.equal(hram(gb, 0xff80), 1)
  assert.equal(hram(gb, 0xff86), 40)
  gb.mem.write(0xff81, 64)
  tap(gb, 'a')
  frames(gb, 10)
  assert.equal(hram(gb, 0xff86), 39)
  assert.equal(bcd3(gb, 0xff8c), 10, 'the bottom row is worth 10')
})

test('invasion: the formation marches down and lands if nobody stops it', async () => {
  const gb = await boot('invasion.asm')
  frames(gb, 5)
  tap(gb, 'start')
  const scy = gb.mem.io[0x42]
  for (let i = 0; i < 60 * 240 && hram(gb, 0xff80) !== 3; i++) {
    if (hram(gb, 0xff80) === 2) gb.mem.write(0xff92, 3)
    gb.runFrame()
  }
  assert.equal(hram(gb, 0xff80), 3)
  assert.notEqual(gb.mem.io[0x42], scy, 'the formation came down')
  frames(gb, 20)
  assert.equal(gb.mem.io[0x4a], 64, 'the results panel slid up')
  assert.match(panelRow(gb, 3), /GAME OVER/)
})

test('invasion: a player who aims and dodges clears the first wave', async () => {
  const gb = await boot('invasion.asm')
  frames(gb, 5)
  tap(gb, 'start')
  let held: Button | null = null
  for (let i = 0; i < 60 * 180 && hram(gb, 0xff96) < 2 && hram(gb, 0xff80) !== 3; i++) {
    if (hram(gb, 0xff80) !== 1) { gb.runFrame(); continue }
    const px = hram(gb, 0xff81), scx = gb.mem.io[0x43]
    let danger = 0
    for (let b = 0; b < 3; b++) {
      const x = hram(gb, 0xffa0 + b)
      if (hram(gb, 0xffa3 + b) > 60 && x >= px - 6 && x <= px + 20) danger = x < px + 7 ? 1 : -1
    }
    let target = px + 7
    for (let c = 0; c < 8; c++) for (let r = 0; r < 5; r++) {
      const t = gb.mem.vram[0x1800 + (2 + 2 * r) * 32 + 2 * c]
      const x = (c * 16 - scx + 4) & 255
      if (t >= 64 && t <= 66 && Math.abs(x - px - 7) < Math.abs(target - px - 7) + (target === px + 7 ? 999 : 0)) target = x
    }
    const want: Button | null = danger > 0 ? 'right' : danger < 0 ? 'left' : target > px + 8 ? 'right' : target < px + 6 ? 'left' : null
    if (want !== held) { if (held) gb.release(held); if (want) gb.press(want); held = want }
    if (!danger && Math.abs(target - px - 7) <= 2 && hram(gb, 0xff83) === 0) { gb.press('a'); gb.runFrame(); gb.release('a') }
    gb.runFrame()
  }
  assert.ok(hram(gb, 0xff96) >= 2, `reached wave ${hram(gb, 0xff96)} with ${hram(gb, 0xff86)} aliens left`)
})

test('invasion: every third wave is a mothership boss with a health bar', async () => {
  const gb = await boot('invasion.asm')
  frames(gb, 5)
  tap(gb, 'start')
  for (let wave = 0; wave < 2; wave++) {
    for (let i = 0x1800; i < 0x1c00; i++) if (gb.mem.vram[i] >= 64 && gb.mem.vram[i] <= 66) gb.mem.vram[i] = 0
    gb.mem.write(0xff86, 0)
    frames(gb, 70)
  }
  assert.equal(hram(gb, 0xff96), 3)
  assert.equal(hram(gb, 0xff97), 1, 'boss wave')
  assert.match(row(gb, 0), /BOSS/)
  const bar = () => [...gb.mem.vram.slice(0x1806, 0x1810)]
  assert.deepEqual(bar(), Array(10).fill(64 + 24), 'full health')
  for (let i = 0; i < 60 * 60 && hram(gb, 0xff86) > 0; i++) {
    if (hram(gb, 0xff80) === 2) gb.mem.write(0xff92, 3)
    gb.mem.write(0xff81, Math.min(136, Math.max(8, hram(gb, 0xff9f) + 9)))
    if (hram(gb, 0xff83) === 0 && hram(gb, 0xff80) === 1) { gb.press('a'); gb.runFrame(); gb.release('a') }
    gb.runFrame()
    if (hram(gb, 0xff86) === 19) assert.equal(bar()[9], 64 + 23, 'one hit shows as half a block')
  }
  assert.equal(hram(gb, 0xff86), 0)
  assert.ok(bcd3(gb, 0xff8c) >= 1200, 'twenty hits plus the 1000 bonus')
  frames(gb, 70)
  assert.equal(hram(gb, 0xff96), 4)
  assert.equal(hram(gb, 0xff97), 0, 'the formation is back on wave 4')
})

const pip = async () => {
  const gb = await boot('pip.asm')
  frames(gb, 30)
  tap(gb, 'start')
  frames(gb, 110)
  assert.equal(hram(gb, 0xff80), 2, 'playing after the world card')
  return gb
}
const placeHero = (gb: GameBoy, x: number, y: number, vy = 0) => {
  gb.mem.write(0xff8b, (x << 4) & 255); gb.mem.write(0xff8c, x >> 4)
  gb.mem.write(0xff8d, (y << 4) & 255); gb.mem.write(0xff8e, y >> 4)
  gb.mem.write(0xff90, vy & 255)
}
const heroX = (gb: GameBoy) => hram(gb, 0xffaa) + 256 * hram(gb, 0xffab)
const levelChar = (gb: GameBoy, col: number, row: number) => String.fromCharCode(gb.mem.read(0xc000 + row * 128 + col))
const putGrub = (gb: GameBoy, x: number, y: number) => {
  for (const [i, v] of [1, x & 255, x >> 8, y, 1, 0].entries()) gb.mem.write(0xc900 + i, v)
}

test('pip quest: the title, the world card, and running moves the camera', async () => {
  const gb = await boot('pip.asm')
  frames(gb, 30)
  assert.match(row(gb, 3), /P I P {3}Q U E S T/)
  tap(gb, 'start')
  assert.match(row(gb, 6), /WORLD 1-1/)
  frames(gb, 110)
  assert.equal(hram(gb, 0xff80), 2)
  assert.match(panelRow(gb, 0), /1-1/)
  gb.press('right')
  gb.press('b')
  frames(gb, 60)
  gb.release('right')
  gb.release('b')
  assert.ok(heroX(gb) > 100, 'ran right')
  assert.ok(hram(gb, 0xff94) > 0, 'the camera followed')
  assert.equal(gb.mem.io[0x43], hram(gb, 0xff94), 'the background scrolls with the camera')
})

test('pip quest: landing on a grub squishes it and bounces Pip', async () => {
  const gb = await pip()
  placeHero(gb, 40, 70, 16)
  putGrub(gb, 40, 104)
  for (let i = 0; i < 30 && gb.mem.read(0xc900) === 1; i++) gb.runFrame()
  assert.equal(gb.mem.read(0xc900), 2, 'squished')
  assert.ok(hram(gb, 0xff90) >= 128, 'bouncing up')
  assert.equal(bcd3(gb, 0xff84), 100)
  assert.equal(hram(gb, 0xff80), 2)
})

test('pip quest: walking into a grub costs a life', async () => {
  const gb = await pip()
  putGrub(gb, 60, 104)
  gb.press('right')
  for (let i = 0; i < 60 && hram(gb, 0xff80) === 2; i++) gb.runFrame()
  gb.release('right')
  assert.equal(hram(gb, 0xff80), 3, 'dying')
  frames(gb, 160)
  assert.equal(hram(gb, 0xff82), 4)
  assert.equal(hram(gb, 0xff80), 1, 'back to the world card')
})

test('pip quest: bumping a ? block from below pops a coin', async () => {
  const gb = await pip()
  assert.equal(levelChar(gb, 12, 10), '?')
  placeHero(gb, 92, 104)
  gb.runFrame()
  tap(gb, 'a')
  frames(gb, 30)
  assert.equal(levelChar(gb, 12, 10), 'U', 'the block is used up')
  assert.equal(hram(gb, 0xff83), 1, 'one coin')
  assert.equal(bcd3(gb, 0xff84), 200)
})

test('pip quest: falling into a pit costs a life', async () => {
  const gb = await pip()
  placeHero(gb, 290, 104)
  for (let i = 0; i < 120 && hram(gb, 0xff80) === 2; i++) gb.runFrame()
  assert.equal(hram(gb, 0xff80), 3)
})

test('pip quest: touching the flag clears the course and the next world starts', async () => {
  const gb = await pip()
  placeHero(gb, 900, 60)
  frames(gb, 2)
  placeHero(gb, 938, 60, 8)
  for (let i = 0; i < 60 && hram(gb, 0xff80) === 2; i++) gb.runFrame()
  assert.equal(hram(gb, 0xff80), 4, 'course clear')
  for (let i = 0; i < 400 && hram(gb, 0xff80) !== 1; i++) gb.runFrame()
  assert.equal(hram(gb, 0xff81), 1)
  assert.match(row(gb, 6), /WORLD 1-2/)
})

test('pip quest: worlds 1-1 and 1-2 can be crossed on foot', async () => {
  const gb = await pip()
  const solid = (c: string) => '#BU?PpX|!C'.includes(c)
  const pitBelow = (c: number) => [12, 13, 14, 15].every(r => !solid(levelChar(gb, c, r)))
  gb.press('right')
  gb.press('b')
  let hold = 0
  for (let i = 0; i < 60 * 60 && hram(gb, 0xff81) < 2 && hram(gb, 0xff80) !== 5; i++) {
    for (let e = 0; e < 4; e++) gb.mem.write(0xc900 + e * 8, 0)
    if (hram(gb, 0xff80) === 2) {
      const x = heroX(gb), col = (x + 8) >> 3, feet = (hram(gb, 0xffac) + 16) >> 3
      const vy = (hram(gb, 0xff90) << 24) >> 24
      let jump = false
      for (let d = 1; d <= 3; d++) {
        if (solid(levelChar(gb, col + d, feet - 1)) || solid(levelChar(gb, col + d, feet - 2))) jump = true
        if (!solid(levelChar(gb, col + d, feet)) && !solid(levelChar(gb, col + d, feet + 1))) jump = true
      }
      const brake = !hram(gb, 0xff91) && vy > 0 && pitBelow((x + 20) >> 3) && !pitBelow(x >> 3)
      if (brake) { gb.release('right'); gb.press('left') } else { gb.release('left'); gb.press('right') }
      if (jump && hram(gb, 0xff91) && hold === 0) { gb.press('a'); hold = 18 }
      if (hold > 0 && --hold === 0) gb.release('a')
    }
    gb.runFrame()
  }
  assert.equal(hram(gb, 0xff81), 2, 'reached the castle')
  assert.equal(hram(gb, 0xff82), 5, 'without losing a life')
})

test('pip quest: three stomps defeat Krag and win the game', async () => {
  const gb = await boot('pip.asm')
  frames(gb, 30)
  tap(gb, 'start')
  gb.mem.write(0xff81, 2)
  frames(gb, 110)
  placeHero(gb, 860, 104)
  frames(gb, 30)
  assert.equal(hram(gb, 0xffa2), 1, 'Krag is here')
  assert.deepEqual([...gb.mem.vram.slice(0x1c08, 0x1c0b)], [118, 118, 118], 'three hearts on the HUD')
  for (let stomp = 3; stomp > 0; stomp--) {
    for (let i = 0; i < 120 && hram(gb, 0xffa1) > 0; i++) {
      placeHero(gb, hram(gb, 0xff9c) + 256 * hram(gb, 0xff9d) + 4, 20)
      gb.runFrame()
    }
    const bx = hram(gb, 0xff9c) + 256 * hram(gb, 0xff9d)
    placeHero(gb, bx + 4, hram(gb, 0xff9e) - 18, 24)
    for (let i = 0; i < 20 && hram(gb, 0xff9b) === stomp; i++) gb.runFrame()
    assert.equal(hram(gb, 0xff9b), stomp - 1, `stomp ${4 - stomp} lands`)
    assert.equal(hram(gb, 0xff80), 2, 'Pip survives the stomp')
  }
  for (let i = 0; i < 120 && hram(gb, 0xff80) !== 6; i++) gb.runFrame()
  assert.equal(hram(gb, 0xff80), 6, 'you win')
  assert.ok(bcd3(gb, 0xff84) >= 6500, 'stomps and the victory bonus scored')
})

test('pip quest: passing the checkpoint means a fall restarts halfway', async () => {
  const gb = await pip()
  placeHero(gb, 520, 104)
  frames(gb, 10)
  assert.equal(hram(gb, 0xffb8), 1, 'checkpoint reached')
  placeHero(gb, 564, 104)
  for (let i = 0; i < 300 && hram(gb, 0xff80) === 2; i++) gb.runFrame()
  assert.equal(hram(gb, 0xff80), 3, 'fell into the pit')
  for (let i = 0; i < 400 && hram(gb, 0xff80) !== 2; i++) gb.runFrame()
  assert.equal(hram(gb, 0xff82), 4)
  assert.ok(heroX(gb) >= 500, `restarted at ${heroX(gb)}`)
})

test('knockout: punches land, fireballs fly, and a round ends in a K.O.', async () => {
  const gb = await boot('knockout.asm')
  frames(gb, 10)
  assert.match(row(gb, 4), /K N O C K O U T/)
  tap(gb, 'start')
  assert.match(row(gb, 5), /ROUND 1/)
  frames(gb, 100)
  assert.equal(hram(gb, 0xff80), 2, 'fighting')
  gb.mem.write(0xff86, 200)
  gb.mem.write(0xffa0, hram(gb, 0xff90) + 14)
  gb.mem.write(0xffa3, 0)
  tap(gb, 'a')
  frames(gb, 6)
  assert.ok(hram(gb, 0xffa6) < 64, 'the punch hurt Zed')
  for (let i = 0; i < 40; i++) gb.runFrame()
  gb.mem.write(0xffa0, 120)
  gb.press('down')
  tap(gb, 'a')
  gb.release('down')
  frames(gb, 12)
  assert.ok(hram(gb, 0xff9c) > 0, 'a fireball is flying')
  gb.mem.write(0xffa6, 1)
  for (let i = 0; i < 600 && hram(gb, 0xff80) === 2; i++) {
    gb.mem.write(0xffa0, hram(gb, 0xff90) + 18)
    if (hram(gb, 0xff93) === 0) tap(gb, 'a')
    else gb.runFrame()
  }
  assert.equal(hram(gb, 0xff80), 3, 'round over')
  assert.match(row(gb, 5), /K\.O\.!/)
  assert.equal(hram(gb, 0xff9b), 1, 'Kai takes the round')
})

test('knockout: holding away from an attack blocks it down to chip damage', async () => {
  const zedPunches = async (hold: boolean) => {
    const gb = await boot('knockout.asm')
    frames(gb, 10)
    tap(gb, 'start')
    frames(gb, 100)
    gb.mem.write(0xff90, 4)
    gb.mem.write(0xffa0, 22)
    gb.mem.write(0xff86, 200)
    if (hold) gb.press('left')
    frames(gb, 2)
    gb.mem.write(0xffa3, 2)
    gb.mem.write(0xffa8, 0)
    gb.mem.write(0xffa4, 0)
    gb.mem.write(0xffa7, 0)
    frames(gb, 10)
    return hram(gb, 0xff96)
  }
  assert.equal(await zedPunches(false), 64 - 5, 'an open punch does full damage')
  assert.equal(await zedPunches(true), 64 - 1, 'a blocked punch only chips')
})

test('with the link cable in, player 2 drives Pong\'s right paddle and Knockout\'s Zed', async () => {
  const pong = await boot('pong.asm')
  pong.mem.link = 1
  frames(pong, 5)
  const start = pong.mem.oam[3 * 4]
  pong.mem.pad2 = 1 << 3
  frames(pong, 10)
  pong.mem.pad2 = 0
  assert.ok(pong.mem.oam[3 * 4] - start >= 16, 'player 2 moved the right paddle down')

  const ko = await boot('knockout.asm')
  ko.mem.link = 1
  frames(ko, 40)
  assert.match(row(ko, 6), /2 PLAYERS LINKED/)
  tap(ko, 'start')
  frames(ko, 100)
  const zed = hram(ko, 0xffa0)
  ko.mem.pad2 = 1 << 1
  frames(ko, 20)
  ko.mem.pad2 = 0
  assert.ok(hram(ko, 0xffa0) < zed - 10, 'player 2 walked Zed forward')
  ko.mem.write(0xffa0, hram(ko, 0xff90) + 18)
  ko.mem.pad2 = 1 << 4
  frames(ko, 2)
  ko.mem.pad2 = 0
  frames(ko, 8)
  assert.ok(hram(ko, 0xff96) < 64, 'player 2 punched Kai')
})

test('hits, crashes and deaths buzz the phone through the rumble port', async () => {
  const gb = await boot('racer.asm')
  const buzz: number[] = []
  gb.mem.onRumble = length => buzz.push(length)
  frames(gb, 5)
  tap(gb, 'start')
  for (let i = 0; i < 60 * 60 && hram(gb, 0xff80) === 1; i++) gb.runFrame()
  assert.deepEqual(buzz, [30], 'one long buzz for the crash')
})

test('the Game Studio example builds and the smiley moves with the D-pad', async () => {
  const gb = await boot('examples/hello.asm')
  frames(gb, 5)
  assert.match(row(gb, 3), /HELLO GN POCKET!/)
  const x = gb.mem.oam[1]
  gb.press('right')
  frames(gb, 20)
  gb.release('right')
  assert.ok(gb.mem.oam[1] > x + 15, 'the smiley walked right')
})

test('a level from the editor drops into Pip Quest in place of World 1-1', async () => {
  const pip = read('pip.asm')
  const rows = Array.from({ length: 17 }, (_, r) => (r >= 15 ? '#' : r === 13 ? 'o' : ' ').repeat(128))
  const custom = pip.replace(/Level1:\r?\n(    db ".*"\r?\n){17}/, `Level1:\n${rows.map(row => `    db "${row}"\n`).join('')}`)
  assert.notEqual(custom, pip, 'the level rows were found and replaced')
  const files = await resolveFiles('my-level.asm', read, { 'my-level.asm': custom })
  const gb = new GameBoy(assemble(files['my-level.asm'], { files, name: 'my-level.asm' }).rom)
  frames(gb, 30)
  tap(gb, 'start')
  frames(gb, 110)
  gb.press('right')
  frames(gb, 60)
  gb.release('right')
  assert.ok(hram(gb, 0xff83) >= 3, `Pip collected the custom coin row (${hram(gb, 0xff83)})`)
})
