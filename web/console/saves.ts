import type { GameBoy, Snapshot } from '../../src/hardware/gameboy.ts'

const pack = (state: Snapshot) =>
  JSON.stringify(state, (_, v) => v instanceof Uint8Array ? { bytes: btoa(String.fromCharCode(...v)) } : v)

const unpack = (text: string) =>
  JSON.parse(text, (_, v) => v && typeof v === 'object' && typeof v.bytes === 'string' ? Uint8Array.from(atob(v.bytes), c => c.charCodeAt(0)) : v) as Snapshot

export const saveGame = (device: GameBoy) => pack(device.snapshot())

export const loadGame = (device: GameBoy, text: string) => {
  const backup = device.snapshot()
  try {
    device.restore(unpack(text))
    return true
  } catch {
    device.restore(backup)
    return false
  }
}
