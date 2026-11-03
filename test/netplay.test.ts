import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { assemble, resolveFiles } from '../src/assembler.ts'
import { GameBoy } from '../src/gameboy.ts'
import { LIBRARY, libraryAsm } from '../src/library.ts'
import type { Cart } from '../src/library.ts'
import { Lockstep, checksum } from '../src/netplay.ts'
import type { LinkMessage } from '../src/netplay.ts'

const read = (path: string) => readFileSync(new URL(`../games/${path}`, import.meta.url), 'utf8')
const carts: Cart[] = JSON.parse(read('games.json'))
const rom = async (entry: string) => {
  const files = await resolveFiles(entry, read, { [LIBRARY]: libraryAsm(carts) })
  return assemble(files[entry], { files, name: entry }).rom
}

const seeded = (seed: number) => () => {
  seed = (seed * 1103515245 + 12345) >>> 0
  return seed / 2 ** 32
}

test('two linked consoles over a laggy, jittery network play the identical game', async () => {
  const knockout = await rom('knockout.asm')
  const random = seeded(7)
  const wire: { at: number, to: 0 | 1, message: LinkMessage }[] = []
  let clock = 0
  const consoles = [1, 2].map(player => {
    const gb = new GameBoy(knockout)
    gb.mem.link = 1
    const lock = new Lockstep(player as 1 | 2, message => {
      wire.push({ at: clock + 2 + Math.floor(random() * 6), to: player === 1 ? 1 : 0, message })
    })
    return { gb, lock, frames: 0, history: [] as string[] }
  })
  const mash = () => [0, 1 << 4, 1 << 5, 1 << 0, 1 << 1, 1 << 2, 1 << 7, (1 << 3) | (1 << 4)][Math.floor(random() * 8)]

  for (clock = 0; clock < 60 * 40; clock++) {
    for (let i = wire.length - 1; i >= 0; i--) {
      if (wire[i].at > clock) continue
      consoles[wire[i].to].lock.receive(wire[i].message)
      wire.splice(i, 1)
    }
    for (const c of consoles) {
      if (random() < 0.15) continue
      const pads = c.lock.next(mash())
      if (!pads) continue
      c.gb.mem.setPad(pads[0])
      c.gb.mem.pad2 = pads[1]
      c.gb.runFrame()
      c.lock.advance(() => checksum(c.gb))
      c.history.push(`${checksum(c.gb)}:${[...c.gb.mem.hram].join(',')}`)
      c.frames++
    }
  }
  const [a, b] = consoles
  assert.ok(Math.min(a.frames, b.frames) > 1500, `both kept playing (${a.frames} / ${b.frames} frames)`)
  assert.ok(Math.abs(a.frames - b.frames) <= 8, 'neither console ran ahead of the other')
  assert.equal(a.lock.desynced || b.lock.desynced, false, 'the periodic checksums always matched')
  const shared = Math.min(a.history.length, b.history.length)
  const first = a.history.findIndex((state, i) => i < shared && state !== b.history[i])
  assert.equal(first, -1, `identical on every one of ${shared} frames`)
  assert.ok(a.gb.mem.read(0xff80) >= 2, 'the match actually started')
})
