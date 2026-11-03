import { assemble, resolveFiles } from '../src/assembler.ts'

const W = 128
const H = 17
const FIRST_TILE = 64
const TILE_DIRT = FIRST_TILE + 1
const TILE_GRUB = FIRST_TILE + 40
const SHADES = [[0xe0, 0xf8, 0xd0], [0x88, 0xc0, 0x70], [0x34, 0x68, 0x56], [0x08, 0x18, 0x20]]
const TOOLS = [
  { ch: '#', name: 'Ground' },
  { ch: 'B', name: 'Brick' },
  { ch: '?', name: '? Block' },
  { ch: 'X', name: 'Hard block' },
  { ch: 'o', name: 'Coin' },
  { ch: 'g', name: 'Grub' },
  { ch: 'P', name: 'Pipe' },
  { ch: 'L', name: 'Lava' },
  { ch: '^', name: 'Hill' },
  { ch: ' ', name: 'Eraser' }
]

const read = async (path: string) => {
  const res = await fetch(new URL(`../games/${path}`, import.meta.url), { cache: 'no-store' })
  if (!res.ok) throw new Error(`can't load ${path}`)
  return res.text()
}
const remember = (value?: string) => {
  try {
    if (value === undefined) return localStorage.getItem('editor:level')
    localStorage.setItem('editor:level', value)
  } catch {}
  return null
}

const files = await resolveFiles('pip.asm', read)
const { rom, symbols } = assemble(files['pip.asm'], { files, name: 'pip.asm' })
const tiles = rom.subarray(symbols.get('Tiles')!, symbols.get('TilesEnd')!)
const charTile = rom.subarray(symbols.get('CharTile')!, symbols.get('CharTile')! + 128)
const original = () => {
  const start = symbols.get('Level1')!
  return Array.from({ length: H }, (_, r) => String.fromCharCode(...rom.subarray(start + r * W, start + (r + 1) * W)).split(''))
}

const map = document.querySelector('#map') as HTMLCanvasElement
const ctx = map.getContext('2d')!
const palette = document.querySelector('#palette') as HTMLElement
const saved = remember()
let grid: string[][] = saved ? (JSON.parse(saved) as string[]).map(row => row.split('')) : original()
let tool = '#'

const paintTile = (target: CanvasRenderingContext2D, id: number, px: number, py: number, flip = false) => {
  const pixels = target.createImageData(8, 8)
  const base = (id - FIRST_TILE) * 16
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      const bit = flip ? x : 7 - x
      const shade = id < FIRST_TILE ? 0 : ((tiles[base + y * 2 + 1] >> bit) & 1) << 1 | ((tiles[base + y * 2] >> bit) & 1)
      const o = (y * 8 + x) * 4
      ;[pixels.data[o], pixels.data[o + 1], pixels.data[o + 2]] = SHADES[shade]
      pixels.data[o + 3] = id >= TILE_GRUB && shade === 0 ? 0 : 255
    }
  }
  if (id >= TILE_GRUB) {
    const scratch = new OffscreenCanvas(8, 8)
    scratch.getContext('2d')!.putImageData(pixels, 0, 0)
    target.drawImage(scratch, px, py)
  } else {
    target.putImageData(pixels, px, py)
  }
}

const tileFor = (row: number, col: number) => {
  const ch = grid[row][col]
  if (ch === '#' && row > 0 && grid[row - 1][col] === '#') return TILE_DIRT
  return charTile[ch.charCodeAt(0)] ?? 0
}

const drawCell = (row: number, col: number) => {
  paintTile(ctx, tileFor(row, col), col * 8, row * 8)
}

const drawAll = () => {
  for (let row = 0; row < H; row++) for (let col = 0; col < W; col++) drawCell(row, col)
  for (let row = 0; row < H; row++) {
    for (let col = 0; col < W; col++) {
      if (grid[row][col] !== 'g') continue
      paintTile(ctx, TILE_GRUB + 1, col * 8, row * 8)
      if (col + 1 < W) paintTile(ctx, TILE_GRUB + 1, col * 8 + 8, row * 8, true)
      if (row > 0) {
        paintTile(ctx, TILE_GRUB, col * 8, row * 8 - 8)
        if (col + 1 < W) paintTile(ctx, TILE_GRUB, col * 8 + 8, row * 8 - 8, true)
      }
    }
  }
}

const save = () => remember(JSON.stringify(grid.map(row => row.join(''))))

const place = (row: number, col: number) => {
  if (row < 0 || row >= H || col < 0 || col >= W) return
  if (tool === 'P') {
    if (row > 13 || col + 1 >= W) return
    grid[row][col] = 'P'
    grid[row][col + 1] = 'p'
    for (let r = row + 1; r < 15; r++) {
      grid[r][col] = '|'
      grid[r][col + 1] = '!'
    }
  } else if (tool === '^') {
    for (let i = 0; i < 3; i++) {
      const r = row + i
      if (r >= 15) break
      for (let c = col - i; c <= col + i; c++) {
        if (c < 0 || c >= W || grid[r][c] !== ' ') continue
        grid[r][c] = i === 0 ? '^' : c === col - i ? '(' : c === col + i ? ')' : '='
      }
    }
  } else {
    grid[row][col] = tool
  }
  save()
  drawAll()
}

const cellAt = (e: PointerEvent) => {
  const rect = map.getBoundingClientRect()
  return [Math.floor((e.clientY - rect.top) / rect.height * H), Math.floor((e.clientX - rect.left) / rect.width * W)]
}

let painting = false
map.addEventListener('pointerdown', e => {
  painting = tool !== 'P' && tool !== '^'
  map.setPointerCapture(e.pointerId)
  const [row, col] = cellAt(e)
  place(row, col)
})
map.addEventListener('pointermove', e => {
  if (!painting) return
  const [row, col] = cellAt(e)
  if (grid[row]?.[col] !== undefined && grid[row][col] !== tool) place(row, col)
})
for (const type of ['pointerup', 'pointercancel']) map.addEventListener(type, () => { painting = false })

for (const item of TOOLS) {
  const button = document.createElement('button')
  button.type = 'button'
  button.setAttribute('aria-pressed', String(item.ch === tool))
  const swatch = document.createElement('canvas')
  swatch.width = 8
  swatch.height = 8
  const id = item.ch === 'g' ? TILE_GRUB : item.ch === '^' ? charTile['^'.charCodeAt(0)] : charTile[item.ch.charCodeAt(0)]
  paintTile(swatch.getContext('2d')!, id, 0, 0)
  button.append(swatch, item.name)
  button.addEventListener('click', () => {
    tool = item.ch
    for (const other of palette.querySelectorAll('button')) other.setAttribute('aria-pressed', String(other === button))
  })
  palette.append(button)
}

document.querySelector('#play')!.addEventListener('click', () => {
  save()
  location.href = '../?play=level'
})
document.querySelector('#reset')!.addEventListener('click', () => {
  grid = original()
  save()
  drawAll()
})
document.querySelector('#clear')!.addEventListener('click', () => {
  grid = original().map((row, r) => row.map((ch, c) => r >= 15 ? '#' : 'Ff'.includes(ch) || (r === 14 && c === 118) ? ch : ' '))
  save()
  drawAll()
})

drawAll()
