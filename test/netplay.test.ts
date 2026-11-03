import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { assemble, resolveFiles } from '../src/assembler/assembler.ts'
import { GameBoy } from '../src/hardware/gameboy.ts'
import { LIBRARY, libraryAsm } from '../src/assembler/library.ts'
import type { Cart } from '../src/assembler/library.ts'
import { DELAY, Lockstep, WINDOW, checksum } from '../src/netplay/lockstep.ts'
import { parseClientMessage, parseServerMessage } from '../src/netplay/protocol.ts'
import type { LinkMessage } from '../src/netplay/protocol.ts'

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

test('link messages are checked field by field and anything else is dropped', () => {
  assert.deepEqual(parseClientMessage('{"t":"in","f":4,"b":16,"evil":"<img src=x>"}'), { t: 'in', f: 4, b: 16 })
  assert.deepEqual(parseClientMessage('{"t":"join","code":"abcd"}'), { t: 'join', code: 'ABCD' })
  for (const junk of ['', 'nope', '[]', 'null', '{"t":"in","f":-1,"b":1}', '{"t":"in","f":1,"b":256}',
    '{"t":"in","f":1.5,"b":1}', '{"t":"sum","f":"120","s":1}', '{"t":"join","code":"' + 'A'.repeat(99) + '"}', '{"t":"start","player":1}']) {
    assert.equal(parseClientMessage(junk), null, junk)
  }
  assert.equal(parseServerMessage('{"t":"start","player":3}'), null)
  assert.equal(parseServerMessage('{"t":"room","code":"<b>"}'), null)
  assert.deepEqual(parseServerMessage('{"t":"start","player":2}'), { t: 'start', player: 2 })
})

test('the lockstep ignores button presses for frames outside its window', () => {
  const lock = new Lockstep(1, () => {})
  lock.receive({ t: 'in', f: DELAY, b: 7 })
  lock.receive({ t: 'in', f: WINDOW + 1, b: 9 })
  lock.receive({ t: 'in', f: 10 ** 12, b: 9 })
  for (let f = 0; f < DELAY; f++) {
    assert.deepEqual(lock.next(0), [0, 0])
    lock.advance(() => 0)
  }
  assert.deepEqual(lock.next(0), [0, 7])
  lock.advance(() => 0)
  for (let f = DELAY + 1; f <= WINDOW; f++) {
    lock.receive({ t: 'in', f, b: 1 })
    assert.deepEqual(lock.next(0), [0, 1])
    lock.advance(() => 0)
  }
  assert.equal(lock.next(0), null, 'the early press was dropped, not stored')
  lock.receive({ t: 'in', f: WINDOW + 1, b: 9 })
  assert.deepEqual(lock.next(0), [0, 9])
})
