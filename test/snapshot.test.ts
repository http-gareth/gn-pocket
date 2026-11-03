import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { assemble, resolveFiles } from '../src/assembler.ts'
import { GameBoy } from '../src/gameboy.ts'
import { checksum } from '../src/netplay.ts'

const read = (path: string) => readFileSync(new URL(`../games/${path}`, import.meta.url), 'utf8')

test('a snapshot rewinds the whole machine, and replaying the same buttons repeats history exactly', async () => {
  const files = await resolveFiles('pip.asm', read, {})
  const gb = new GameBoy(assemble(files['pip.asm'], { files, name: 'pip.asm' }).rom)
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
