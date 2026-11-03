import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checksum } from '../src/netplay/lockstep.ts'
import { boot } from './carts.ts'

test('a snapshot rewinds the whole machine, and replaying the same buttons repeats history exactly', async () => {
  const gb = await boot('pip.asm')
  for (let i = 0; i < 40; i++) gb.runFrame()
  gb.press('start')
  for (let i = 0; i < 3; i++) gb.runFrame()
  gb.release('start')
  for (let i = 0; i < 150; i++) gb.runFrame()
  const saved = gb.snapshot()
  const play = () => {
    const trail: number[] = []
    for (let i = 0; i < 120; i++) {
      if (i === 10) gb.press('right')
      if (i === 40) gb.press('a')
      if (i === 60) gb.release('a')
      gb.runFrame()
      trail.push(checksum(gb))
    }
    gb.release('right')
    return trail
  }
  const first = play()
  assert.notEqual(first[0], first[119], 'Pip moved')
  gb.restore(saved)
  assert.deepEqual(play(), first, 'the replay is identical frame by frame')
  const copy = JSON.parse(JSON.stringify(saved, (_, v) => v instanceof Uint8Array ? [...v] : v))
  assert.equal(copy.mem.wram.length, 0x2000, 'a snapshot survives being written to storage')
})
