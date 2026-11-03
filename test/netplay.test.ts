import { test } from 'node:test'
import assert from 'node:assert/strict'
import { GameBoy } from '../src/hardware/gameboy.ts'
import { DELAY, FRAME_MS, Lockstep, MAX_DELAY, checksum, delayFor } from '../src/netplay/lockstep.ts'
import { linkRole, newCode, parseClientMessage, parseServerMessage } from '../src/netplay/protocol.ts'
import type { LinkMessage } from '../src/netplay/protocol.ts'
import { build } from './carts.ts'

const seeded = (seed: number) => () => {
  seed = (seed * 1103515245 + 12345) >>> 0
  return seed / 2 ** 32
}

test('two linked consoles over a laggy, jittery network play the identical game', async () => {
  const { rom: knockout } = await build('knockout.asm')
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
  assert.deepEqual(parseClientMessage('{"t":"pong","x":1}'), { t: 'pong' })
  assert.deepEqual(linkRole('?join=abcd'), { host: false, code: 'ABCD' })
  assert.deepEqual(linkRole('?host'), { host: true })
  for (const bad of ['', '?join=AB', '?join=ABCDE', '?join=AB1D', '?join=%3Cb%3E']) assert.equal(linkRole(bad), null, bad)
  assert.match(newCode(), /^[A-HJ-NP-Z]{4}$/)
  for (const junk of ['', 'nope', '[]', 'null', '{"t":"in","f":-1,"b":1}', '{"t":"in","f":1,"b":256}',
    '{"t":"in","f":1.5,"b":1}', '{"t":"sum","f":"120","s":1}', '{"t":"join","code":"' + 'A'.repeat(99) + '"}', '{"t":"start","player":1}']) {
    assert.equal(parseClientMessage(junk), null, junk)
  }
  assert.equal(parseServerMessage('{"t":"start","player":3}'), null)
  assert.equal(parseServerMessage('{"t":"room","code":"<b>"}'), null)
  assert.deepEqual(parseServerMessage('{"t":"start","player":2,"delay":12}'), { t: 'start', player: 2, delay: 12 })
  assert.equal(parseServerMessage('{"t":"start","player":2,"delay":999}'), null)
  assert.equal(parseServerMessage('{"t":"start","player":2}'), null)
})

test('the lockstep ignores button presses for frames outside its window', () => {
  const lock = new Lockstep(1, () => {})
  lock.receive({ t: 'in', f: DELAY, b: 7 })
  lock.receive({ t: 'in', f: DELAY * 2 + 1, b: 9 })
  lock.receive({ t: 'in', f: 10 ** 12, b: 9 })
  for (let f = 0; f < DELAY; f++) {
    assert.deepEqual(lock.next(0), [0, 0])
    lock.advance(() => 0)
  }
  assert.deepEqual(lock.next(0), [0, 7])
  lock.advance(() => 0)
  for (let f = DELAY + 1; f <= DELAY * 2; f++) {
    lock.receive({ t: 'in', f, b: 1 })
    assert.deepEqual(lock.next(0), [0, 1])
    lock.advance(() => 0)
  }
  assert.equal(lock.next(0), null, 'the early press was dropped, not stored')
  lock.receive({ t: 'in', f: DELAY * 2 + 1, b: 9 })
  assert.deepEqual(lock.next(0), [0, 9])
})

const linkedFrames = (latency: number, delay: number, ticks: number) => {
  const wire: { at: number, to: number, message: LinkMessage }[] = []
  let clock = 0
  const locks = [1, 2].map(player => new Lockstep(player as 1 | 2, message => wire.push({ at: clock + latency, to: player === 1 ? 1 : 0, message }), delay))
  for (clock = 0; clock < ticks; clock++) {
    const arrived = wire.filter(item => item.at <= clock)
    wire.splice(0, wire.length, ...wire.filter(item => item.at > clock))
    for (const item of arrived) locks[item.to].receive(item.message)
    for (const lock of locks) if (lock.next(0)) lock.advance(() => 0)
  }
  return Math.min(...locks.map(lock => lock.frame))
}

test('the link delay grows with distance so a far-away player still gets full speed', () => {
  assert.equal(delayFor(1), DELAY, 'next door still uses the minimum')
  assert.equal(delayFor(10 * FRAME_MS), 12)
  assert.equal(delayFor(60_000), MAX_DELAY, 'capped')
  const latency = 19
  const ticks = 1200
  assert.ok(linkedFrames(latency, DELAY, ticks) < ticks / 3, 'a fixed 4-frame delay crawls over a 320 ms link')
  assert.ok(linkedFrames(latency, delayFor(latency * FRAME_MS), ticks) > ticks - 30, 'the adaptive delay keeps up')
})
