import { test } from 'node:test'
import assert from 'node:assert/strict'
import { CPU, FLAG_C, FLAG_H, FLAG_N, FLAG_Z } from '../src/cpu.ts'
import { Memory, REG } from '../src/memory.ts'
import { Timer } from '../src/timer.ts'

const boot = (...bytes: number[]) => {
  const rom = new Uint8Array(0x8000)
  rom.set(bytes, 0x100)
  const mem = new Memory(rom)
  return { mem, cpu: new CPU(mem) }
}

const run = (cpu: CPU, steps: number) => {
  let cycles = 0
  for (let i = 0; i < steps; i++) cycles += cpu.step()
  return cycles
}

test('8-bit add sets zero, half-carry and carry', () => {
  const { cpu } = boot(0x3e, 0x3a, 0xc6, 0xc6)
  run(cpu, 2)
  assert.equal(cpu.a, 0x00)
  assert.equal(cpu.f, FLAG_Z | FLAG_H | FLAG_C)
})

test('subtract borrows from bit 4 without a full carry', () => {
  const { cpu } = boot(0x3e, 0x10, 0xd6, 0x01)
  run(cpu, 2)
  assert.equal(cpu.a, 0x0f)
  assert.equal(cpu.f, FLAG_N | FLAG_H)
})

test('daa turns a binary sum into decimal', () => {
  const { cpu } = boot(0x3e, 0x15, 0xc6, 0x27, 0x27)
  run(cpu, 3)
  assert.equal(cpu.a, 0x42)
})

test('instruction timing matches the hardware', () => {
  const { cpu } = boot(0x00, 0x01, 0x34, 0x12, 0xc5, 0xd1)
  assert.deepEqual([cpu.step(), cpu.step(), cpu.step(), cpu.step()], [4, 12, 16, 12])
  assert.equal(cpu.de, 0x1234)
})

test('call and ret take 24 and 16 cycles and return to the next instruction', () => {
  const { cpu } = boot(0xcd, 0x10, 0x01, ...new Array(13).fill(0), 0xc9)
  assert.equal(cpu.step(), 24)
  assert.equal(cpu.pc, 0x0110)
  assert.equal(cpu.step(), 16)
  assert.equal(cpu.pc, 0x0103)
})

test('prefixed CB ops: swap, arithmetic shift, bit test', () => {
  const { cpu } = boot(0x3e, 0xf0, 0xcb, 0x37, 0x06, 0x81, 0xcb, 0x28, 0xcb, 0x78)
  run(cpu, 2)
  assert.equal(cpu.a, 0x0f)
  run(cpu, 2)
  assert.equal(cpu.b, 0xc0)
  assert.equal(cpu.f & FLAG_C, FLAG_C)
  run(cpu, 1)
  assert.equal(cpu.f & FLAG_Z, 0)
})

test('an interrupt pushes pc, jumps to its vector and costs 20 cycles', () => {
  const { cpu, mem } = boot(0x00)
  mem.ie = 0x01
  mem.request(0x01)
  cpu.ime = true
  assert.equal(cpu.step(), 20)
  assert.equal(cpu.pc, 0x40)
  assert.equal(cpu.sp, 0xfffc)
  assert.equal(mem.read(0xfffc) | (mem.read(0xfffd) << 8), 0x0100)
  assert.equal(mem.io[REG.IF] & 0x01, 0)
})

test('ei only takes effect after the next instruction', () => {
  const { cpu, mem } = boot(0xfb, 0x00, 0x00)
  mem.ie = 0x01
  mem.request(0x01)
  cpu.step()
  assert.equal(cpu.ime, false)
  cpu.step()
  assert.equal(cpu.pc, 0x0102)
  cpu.step()
  assert.equal(cpu.pc, 0x40)
})

test('the timer counts at the selected rate and fires on overflow', () => {
  const { mem } = boot()
  const timer = new Timer(mem)
  mem.io[REG.TAC] = 0x05
  mem.io[REG.TIMA] = 0
  timer.tick(64)
  assert.equal(mem.io[REG.TIMA], 4)
  mem.io[REG.TIMA] = 0xff
  mem.io[REG.TMA] = 0x80
  timer.tick(16)
  assert.equal(mem.io[REG.TIMA], 0x80)
  assert.equal(mem.io[REG.IF] & 0x04, 0x04)
})
