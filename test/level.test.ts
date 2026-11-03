import { test } from 'node:test'
import assert from 'node:assert/strict'
import { LEVEL_HEIGHT, LEVEL_WIDTH, parseLevel, withLevel } from '../src/assembler/level.ts'
import { build, read } from './carts.ts'

const row = (text = '') => text.padEnd(LEVEL_WIDTH)
const level = (rows: string[]) => JSON.stringify(rows)

test('a saved level must be the right size and plain characters before it reaches the assembler', () => {
  const good = Array.from({ length: LEVEL_HEIGHT }, () => row('#'))
  assert.deepEqual(parseLevel(level(good)), good)
  for (const bad of [
    null, '', 'not json', '{}', level(good.slice(1)), level([...good.slice(1), row('#').slice(1)]),
    level([...good.slice(1), row('"\n    halt ;')]), level([...good.slice(1), row('\\')]), level([...good.slice(1), row('é')])
  ]) {
    assert.equal(parseLevel(bad), null, String(bad))
  }
})

test('a custom level is spliced into Pip Quest literally and still assembles', async () => {
  const rows = Array.from({ length: LEVEL_HEIGHT }, (_, r) => row(r === 16 ? '$&$1$`' : r >= 15 ? '#'.repeat(LEVEL_WIDTH) : ''))
  const source = withLevel(read('pip.asm'), rows)
  assert.ok(source.includes('    db "$&$1$`'), 'replacement patterns are not expanded')
  const { rom, symbols } = await build('pip.asm', { 'pip.asm': source })
  const start = symbols.get('Level1')!
  assert.equal(String.fromCharCode(...rom.subarray(start, start + 6)), ' '.repeat(6))
  assert.equal(String.fromCharCode(...rom.subarray(start + 16 * LEVEL_WIDTH, start + 16 * LEVEL_WIDTH + 6)), '$&$1$`')
})
