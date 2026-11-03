import { test } from 'node:test'
import assert from 'node:assert/strict'
import { APU } from '../src/apu.ts'

const RATE = 48000
const CPU_HZ = 4194304

const powered = () => {
  const apu = new APU()
  apu.sampleRate = RATE
  apu.capture = true
  apu.write(0x26, 0x80)
  apu.write(0x24, 0x77)
  apu.write(0x25, 0xff)
  return apu
}

const run = (apu: APU, seconds: number) => {
  for (let c = 0; c < CPU_HZ * seconds; c += 16) apu.tick(16)
  return apu.takeSamples()
}

const crossings = (samples: Float32Array) => {
  let count = 0
  for (let i = 1; i < samples.length; i++) if ((samples[i - 1] < 0) !== (samples[i] < 0)) count++
  return count
}

test('a pulse note plays at the pitch its frequency register asks for', () => {
  const apu = powered()
  apu.write(0x16, 0x80)
  apu.write(0x17, 0xf0)
  apu.write(0x18, 1750 & 0xff)
  apu.write(0x19, 0x80 | (1750 >> 8))
  const samples = run(apu, 0.25)
  assert.ok(Math.abs(samples.length - RATE / 4) < 2)
  const hz = crossings(samples.subarray(RATE / 20)) / 2 / 0.2
  assert.ok(Math.abs(hz - 440) < 12, `expected about 440 Hz, heard ${hz.toFixed(1)}`)
})

test('the envelope fades a note to silence and the channel can be read back as on', () => {
  const apu = powered()
  apu.write(0x16, 0x80)
  apu.write(0x17, 0xf1)
  apu.write(0x18, 0x00)
  apu.write(0x19, 0x87)
  assert.equal(apu.read(0x26) & 0x02, 0x02)
  const samples = run(apu, 0.5)
  const peak = (from: number, to: number) => samples.subarray(from, to).reduce((m, s) => Math.max(m, Math.abs(s)), 0)
  assert.ok(peak(0, RATE / 20) > 0.05)
  assert.ok(peak(RATE * 0.4, RATE * 0.5) < 0.01)
})

test('the length counter switches a channel off on time', () => {
  const apu = powered()
  apu.write(0x16, 0x3f)
  apu.write(0x17, 0xf0)
  apu.write(0x19, 0xc7)
  assert.equal(apu.read(0x26) & 0x02, 0x02)
  run(apu, 0.01)
  assert.equal(apu.read(0x26) & 0x02, 0)
})

test('the noise channel makes noise and the sweep bends pitch upward', () => {
  const apu = powered()
  apu.write(0x21, 0xf0)
  apu.write(0x22, 0x30)
  apu.write(0x23, 0x80)
  assert.ok(crossings(run(apu, 0.1)) > 200)

  const sweep = powered()
  sweep.write(0x10, 0x11)
  sweep.write(0x11, 0x80)
  sweep.write(0x12, 0xf0)
  sweep.write(0x13, 0x00)
  sweep.write(0x14, 0x82)
  const before = sweep.pulse1.freq
  run(sweep, 0.02)
  assert.ok(sweep.pulse1.freq > before, 'sweep raised the pitch')

  const overflow = powered()
  overflow.write(0x10, 0x11)
  overflow.write(0x12, 0xf0)
  overflow.write(0x14, 0x86)
  assert.equal(overflow.pulse1.on, false, 'a sweep that would pass 2047 mutes the channel, like the hardware')
})

test('switching the sound chip off silences every channel', () => {
  const apu = powered()
  apu.write(0x17, 0xf0)
  apu.write(0x19, 0x87)
  apu.write(0x26, 0x00)
  assert.equal(apu.read(0x26) & 0x0f, 0)
  apu.write(0x17, 0xf0)
  assert.equal(apu.read(0x17), 0x00)
})
