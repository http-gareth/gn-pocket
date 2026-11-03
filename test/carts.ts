import { readFileSync } from 'node:fs'
import { assemble, resolveFiles } from '../src/assembler/assembler.ts'
import { LIBRARY, libraryAsm } from '../src/assembler/library.ts'
import type { Cart } from '../src/assembler/library.ts'
import { GameBoy } from '../src/hardware/gameboy.ts'

export const read = (path: string) => readFileSync(new URL(`../games/${path}`, import.meta.url), 'utf8')
export const carts: Cart[] = JSON.parse(read('games.json'))

export const build = async (entry: string, overrides: Record<string, string> = {}) => {
  const files = await resolveFiles(entry, read, { [LIBRARY]: libraryAsm(carts), ...overrides })
  return assemble(files[entry], { files, name: entry })
}

export const boot = async (entry: string, overrides?: Record<string, string>) => new GameBoy((await build(entry, overrides)).rom)
