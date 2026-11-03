import { test } from 'node:test'
import assert from 'node:assert/strict'
import { AsmError, assemble, resolveFiles } from '../src/assembler.ts'

const bytes = (source: string, length: number, at = 0) => [...assemble(source).rom.slice(at, at + length)]

test('encodes every addressing form to the right opcodes', () => {
  const cases: [string, number[]][] = [
    ['ld a, b', [0x78]],
    ['ld [hl], a', [0x77]],
    ['ld a, $42', [0x3e, 0x42]],
    ['ld hl, $c000', [0x21, 0x00, 0xc0]],
    ['ld [hl+], a', [0x22]],
    ['ld a, [hld]', [0x3a]],
    ['ld [$c000], sp', [0x08, 0x00, 0xc0]],
    ['ld hl, sp+2', [0xf8, 0x02]],
    ['ld a, [$c123]', [0xfa, 0x23, 0xc1]],
    ['ldh [$ff40], a', [0xe0, 0x40]],
    ['ldh a, [$ff44]', [0xf0, 0x44]],
    ['add a, $10', [0xc6, 0x10]],
    ['add 16', [0xc6, 0x10]],
    ['add hl, de', [0x19]],
    ['add sp, -2', [0xe8, 0xfe]],
    ['sub c', [0x91]],
    ['xor a', [0xaf]],
    ['cp 144', [0xfe, 0x90]],
    ['inc [hl]', [0x34]],
    ['dec bc', [0x0b]],
    ['bit 2, a', [0xcb, 0x57]],
    ['res 0, [hl]', [0xcb, 0x86]],
    ['swap a', [0xcb, 0x37]],
    ['push af', [0xf5]],
    ['pop bc', [0xc1]],
    ['jp $0150', [0xc3, 0x50, 0x01]],
    ['jp hl', [0xe9]],
    ['call z, $1234', [0xcc, 0x34, 0x12]],
    ['ret nz', [0xc0]],
    ['ret c', [0xd8]],
    ['rst $38', [0xff]],
    ['ld a, -1', [0x3e, 0xff]]
  ]
  for (const [source, expected] of cases) assert.deepEqual(bytes(source, expected.length), expected, source)
})

test('labels, local labels and relative jumps resolve in both directions', () => {
  const source = `
Start:
    jr .later
.back:
    nop
.later:
    jr .back
Other:
.back:
    jr Start`
  assert.deepEqual(bytes(source, 7), [0x18, 0x01, 0x00, 0x18, 0xfd, 0x18, 0xf9])
})

test('constants, expressions, strings and pixel-art rows', () => {
  const source = `
BASE equ $9800
    ld hl, BASE + 2 * 32 + 9
    db "OK", low($1234), high($1234)
    dw \`01230123`
  const out = bytes(source, 9)
  assert.deepEqual(out.slice(0, 3), [0x21, 0x49, 0x98])
  assert.deepEqual(out.slice(3, 7), [0x4f, 0x4b, 0x34, 0x12])
  assert.deepEqual(out.slice(7), [0b01010101, 0b00110011])
})

test('errors name the line and the problem', () => {
  assert.throws(() => assemble('nop\n    ld a, missing'), (e: unknown) => e instanceof AsmError && /line 2: unknown symbol "missing"/.test(e.message))
  assert.throws(() => assemble('    frob a'), /line 1: can't encode "frob a"/)
  assert.throws(() => assemble('x:\n    ds 200\n    jr x'), /jr distance/)
})

test('include pulls in other files and names them in errors', () => {
  const files = { 'lib/a.asm': 'VALUE equ 7\n    include "lib/b.asm"', 'lib/b.asm': '    ld a, VALUE' }
  assert.deepEqual([...assemble('    include "lib/a.asm"', { files }).rom.slice(0, 2)], [0x3e, 0x07])
  assert.throws(() => assemble('    include "nope.asm"', { files }), /can't find "nope.asm"/)
  assert.throws(() => assemble('    include "x.asm"', { files: { 'x.asm': 'include "x.asm"' } }), /include loop/)
  assert.throws(() => assemble('    include "bad.asm"', { files: { 'bad.asm': 'nop\n    frob' } }), /bad\.asm line 2: can't encode "frob"/)
})

test('the cartridge header checksum is filled in', () => {
  const { rom } = assemble('    org $134\n    db "PONG"')
  let x = 0
  for (let i = 0x134; i <= 0x14c; i++) x = (x - rom[i] - 1) & 0xff
  assert.equal(rom[0x14d], x)
})

test('a source handed in directly still pulls in the files it includes', async () => {
  const library: Record<string, string> = { 'lib/a.asm': 'A equ 1\n include "lib/b.asm"', 'lib/b.asm': 'B equ 2' }
  const files = await resolveFiles('mine.asm', path => library[path], { 'mine.asm': 'include "lib/a.asm"\n db A, B' })
  assert.deepEqual(Object.keys(files).sort(), ['lib/a.asm', 'lib/b.asm', 'mine.asm'])
  assert.deepEqual([...assemble(files['mine.asm'], { files, name: 'mine.asm', size: 2 }).rom], [1, 2])
})
