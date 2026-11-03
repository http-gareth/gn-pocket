import { GameBoy } from '../src/gameboy.ts'
import type { Snapshot } from '../src/gameboy.ts'
import { assemble, resolveFiles } from '../src/assembler.ts'
import { HEIGHT, WIDTH } from '../src/ppu.ts'
import { LIBRARY, MENU, libraryAsm } from '../src/library.ts'
import type { Cart } from '../src/library.ts'
import { BUTTONS } from '../src/memory.ts'
import type { Button } from '../src/memory.ts'
import { Lockstep, checksum } from '../src/netplay.ts'
import type { LinkMessage } from '../src/netplay.ts'
import { Ring } from './ring.js'

type Palette = { name: string, bg: string[], obj?: string[], alt?: string[] }
type Built = { rom: Uint8Array, symbols: Map<string, number> }
type Link = {
  ws: WebSocket
  lock: Lockstep | null
  roms: { menu: Built, carts: Built[] } | null
  pending: number | null
  previous: number
}

const PALETTES: Palette[] = [
  { name: 'CLASSIC', bg: ['#e0f8d0', '#88c070', '#346856', '#081820'] },
  { name: 'POCKET', bg: ['#e9ebe4', '#a9ab9f', '#5a5c53', '#1c1d19'] },
  { name: 'ARCADE', bg: ['#c8ecff', '#7bd36b', '#2f7a46', '#0b1a2a'], obj: ['#ffffff', '#ffd23f', '#e8432f', '#1a0a0a'], alt: ['#ffffff', '#8ad4ff', '#3a5fd8', '#0a1030'] },
  { name: 'SUNSET', bg: ['#fff1d6', '#ffb36b', '#b8476a', '#2b1638'], obj: ['#ffffff', '#fff27a', '#e8602c', '#2a0f12'], alt: ['#ffffff', '#a8e0ff', '#4a7ad8', '#141e3a'] },
  { name: 'NEON', bg: ['#0d0f1a', '#2d3a8c', '#9a5cf0', '#f2f2ff'], obj: ['#0d0f1a', '#39ff88', '#ff3d8b', '#ffffff'], alt: ['#0d0f1a', '#ffe14d', '#29d3ff', '#ffffff'] }
]
const FRAME_MS = 1000 / 59.7275
const REWIND_EVERY = 4
const REWIND_DEPTH = 300
const MENU_COMBO = (1 << BUTTONS.indexOf('start')) | (1 << BUTTONS.indexOf('select'))
const KEYS: Record<string, Button> = {
  ArrowRight: 'right', ArrowLeft: 'left', ArrowUp: 'up', ArrowDown: 'down',
  KeyZ: 'a', KeyX: 'b', Enter: 'start', ShiftLeft: 'select', ShiftRight: 'select'
}

const $ = <T extends Element>(selector: string) => document.querySelector(selector) as T
const canvas = $<HTMLCanvasElement>('#screen')
const ctx = canvas.getContext('2d')!
const image = ctx.createImageData(WIDTH, HEIGHT)
const lcd = $<HTMLElement>('#lcd')
const insertHint = $<HTMLElement>('#insert')
const toast = $<HTMLElement>('#toast')
const led = $<HTMLElement>('#led')
const colorButton = $<HTMLButtonElement>('#color')
const speaker = $<HTMLButtonElement>('#speaker')
const menuButton = $<HTMLButtonElement>('#menu')
const rewindButton = $<HTMLButtonElement>('#rewind')
const dialog = $<HTMLDialogElement>('#menu-dialog')
const linkStatus = $<HTMLElement>('#link-status')
const linkChoices = $<HTMLElement>('#link-choices')
const linkCode = $<HTMLElement>('#link-code')
const codeInput = $<HTMLInputElement>('#link-input')
const unplug = $<HTMLButtonElement>('#link-unplug')
const nerd = $<HTMLElement>('#nerd')
const nerdCpu = $<HTMLElement>('#nerd-cpu')
const nerdRam = $<HTMLElement>('#nerd-ram')
const nerdTiles = $<HTMLCanvasElement>('#nerd-tiles')
const tileCtx = nerdTiles.getContext('2d')!
const tileImage = tileCtx.createImageData(128, 128)

const read = async (path: string) => {
  const res = await fetch(new URL(`../games/${path}`, import.meta.url), { cache: 'no-store' })
  if (!res.ok) throw new Error(`can't load ${path}`)
  return res.text()
}

const carts: Cart[] = await (await fetch(new URL('../games/games.json', import.meta.url))).json()
const known: Record<string, string> = { [LIBRARY]: libraryAsm(carts) }
const held = new Set<Button>()
const history: Snapshot[] = []
const remember = (key: string, value?: string) => {
  try {
    if (value === undefined) return localStorage.getItem(key)
    localStorage.setItem(key, value)
  } catch {}
  return null
}

let gb: GameBoy | null = null
let entry = MENU
let symbols: [string, number][] = []
let pending: Cart | null = null
let link: Link | null = null
let carry = 0
let last = performance.now()
let frames = 0
let rewinding = false
let audio: AudioContext | null = null
let sink: ((samples: Float32Array) => void) | null = null
let emulated = 0
let busy = 0
let fps = 0
let emuMs = 0
let statsAt = performance.now()
const roms = new Map<string, Built>()
let muted = remember('muted') === '1'
let paletteIndex = Math.max(0, PALETTES.findIndex(p => p.name === remember('palette')))
let colors = new Uint8Array(12 * 3)
let toastTimer = 0
let previousRam = new Uint8Array(128)

const hex = (value: string) => [1, 3, 5].map(i => parseInt(value.slice(i, i + 2), 16))
const h2 = (n: number) => n.toString(16).padStart(2, '0').toUpperCase()
const h4 = (n: number) => n.toString(16).padStart(4, '0').toUpperCase()

const usePalette = (index: number) => {
  paletteIndex = (index + PALETTES.length) % PALETTES.length
  const p = PALETTES[paletteIndex]
  colors = new Uint8Array([p.bg, p.obj ?? p.bg, p.alt ?? p.obj ?? p.bg].flatMap(set => set.flatMap(hex)))
  lcd.style.background = p.bg[0]
  insertHint.style.color = p.bg[2]
  const swatches = colorButton.querySelectorAll('i')
  ;[p.bg[1], (p.obj ?? p.bg)[2], (p.alt ?? p.bg)[2]].forEach((c, i) => { (swatches[i] as HTMLElement).style.background = c })
  remember('palette', p.name)
}

const say = (text: string) => {
  toast.textContent = text
  toast.hidden = false
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.hidden = true }, 2200)
}

const listen = (device: GameBoy) => {
  device.mem.onRumble = length => navigator.vibrate?.(length * 10)
  if (!audio) return
  device.apu.sampleRate = audio.sampleRate
  device.apu.capture = true
}

const startAudio = () => {
  if (!audio) {
    const context = new AudioContext({ latencyHint: 'interactive' })
    audio = context
    if (context.audioWorklet) {
      context.audioWorklet.addModule(new URL('audio.js', import.meta.url)).then(() => {
        const node = new AudioWorkletNode(context, 'pocket-audio', { outputChannelCount: [2] })
        node.connect(context.destination)
        sink = samples => node.port.postMessage(samples, [samples.buffer])
      }).catch(error => console.error(error))
    } else {
      const ring = new Ring(context.sampleRate)
      const node = context.createScriptProcessor(1024, 0, 1)
      node.onaudioprocess = e => ring.pull(e.outputBuffer.getChannelData(0))
      node.connect(context.destination)
      sink = samples => ring.push(samples)
    }
  }
  if (audio.state === 'suspended') audio.resume()
  if (gb) listen(gb)
}

const playAudio = (device: GameBoy) => {
  const samples = device.apu.takeSamples()
  if (!sink || !audio || muted || rewinding || audio.state !== 'running' || !samples.length) return
  sink(samples)
}

const setMuted = (value: boolean) => {
  muted = value
  speaker.classList.toggle('muted', muted)
  remember('muted', muted ? '1' : '0')
  say(muted ? 'SOUND OFF' : 'SOUND ON')
}

const power = (on: boolean, message = 'LOADING') => {
  led.classList.toggle('on', on)
  insertHint.hidden = on
  insertHint.textContent = message
  if (!on) ctx.clearRect(0, 0, WIDTH, HEIGHT)
}

const draw = (frame: Uint8Array, layer: Uint8Array) => {
  const data = image.data
  for (let i = 0; i < frame.length; i++) {
    const c = (layer[i] * 4 + frame[i]) * 3
    data[i * 4] = colors[c]
    data[i * 4 + 1] = colors[c + 1]
    data[i * 4 + 2] = colors[c + 2]
    data[i * 4 + 3] = 255
  }
  ctx.putImageData(image, 0, 0)
}

const customSource = async (name: string) => {
  if (name === 'studio.asm') return remember('studio:source') ?? ''
  if (name === 'my-level.asm') {
    const rows: string[] = JSON.parse(remember('editor:level') ?? '[]')
    const pip = await read('pip.asm')
    return pip.replace(/Level1:\r?\n(    db ".*"\r?\n){17}/, `Level1:\n${rows.map(row => `    db "${row}"\n`).join('')}`)
  }
  return null
}

const build = async (name: string): Promise<Built> => {
  const cached = roms.get(name)
  if (cached) return cached
  const custom = await customSource(name)
  const files = await resolveFiles(name, read, custom === null ? known : { ...known, [name]: custom })
  const built = assemble(files[name], { files, name })
  if (custom === null) roms.set(name, built)
  return built
}

const start = (built: Built, name: string) => {
  const next = new GameBoy(built.rom)
  next.mem.onLaunch = index => { pending = carts[index] ?? null }
  listen(next)
  gb = next
  entry = name
  symbols = [...built.symbols]
    .filter(([label, address]) => address >= 0x150 && address < 0x8000 && !/^[A-Z0-9_]+$/.test(label) && !/^[hrw][A-Z]/.test(label))
    .sort((a, b) => a[1] - b[1])
  history.length = 0
  power(true)
}

const boot = async (name: string, label: string) => {
  try {
    const built = await build(name)
    if (!link) start(built, name)
  } catch (error) {
    console.error(error)
    if (name !== MENU) {
      await menu()
      say(`${label.toUpperCase()} WON'T START`)
      return
    }
    gb = null
    power(false, 'CARTRIDGE ERROR')
  }
}

const menu = () => boot(MENU, 'Menu')

const stateKey = () => `state:${entry}`
const pack = (state: Snapshot) => JSON.stringify(state, (_, v) => v instanceof Uint8Array ? { bytes: btoa(String.fromCharCode(...v)) } : v)
const unpack = (text: string) => JSON.parse(text, (_, v) => v && typeof v === 'object' && 'bytes' in v ? Uint8Array.from(atob(v.bytes), c => c.charCodeAt(0)) : v) as Snapshot

const saveState = () => {
  if (!gb || link) return say(link ? 'NOT WHILE LINKED' : 'NOTHING TO SAVE')
  remember(stateKey(), pack(gb.snapshot()))
  say(remember(stateKey()) ? 'SAVED' : 'COULD NOT SAVE')
}

const loadState = () => {
  if (!gb || link) return say(link ? 'NOT WHILE LINKED' : 'NOTHING TO LOAD')
  const saved = remember(stateKey())
  if (!saved) return say('NO SAVE FOR THIS GAME')
  gb.restore(unpack(saved))
  history.length = 0
  say('LOADED')
}

const setRewind = (on: boolean) => {
  if (on && link) return say('NO REWIND WHEN LINKED')
  rewinding = on
  rewindButton.classList.toggle('on', on)
}

const localPad = () => BUTTONS.reduce((bits, button, i) => held.has(button) ? bits | 1 << i : bits, 0)

const linkedConsole = (built: Built) => {
  const next = new GameBoy(built.rom)
  next.mem.link = 1
  next.mem.onLaunch = index => { if (link) link.pending = index }
  listen(next)
  power(true)
  return next
}

const showLink = (status: string, mode: 'choose' | 'code' | 'linked') => {
  linkStatus.textContent = status
  linkChoices.hidden = mode !== 'choose'
  linkCode.hidden = mode !== 'code'
  unplug.hidden = mode === 'choose'
  unplug.textContent = mode === 'linked' ? 'UNPLUG' : 'CANCEL'
}

const endLink = (message: string) => {
  if (!link) return
  const old = link
  link = null
  old.ws.close()
  menuButton.classList.remove('on')
  showLink('Play with a friend on the same Wi-Fi.', 'choose')
  say(message)
  if (old.lock) menu()
}

const openLink = (first: object) => {
  link?.ws.close()
  const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/link`)
  const current: Link = { ws, lock: null, roms: null, pending: null, previous: 0 }
  link = current
  setRewind(false)
  ws.addEventListener('open', () => ws.send(JSON.stringify(first)))
  ws.addEventListener('close', () => {
    if (link !== current) return
    endLink(current.lock ? 'LINK LOST' : 'NO LINK SERVER')
    if (!current.lock) linkStatus.textContent = 'No link server here. Run GN Pocket on a PC (npm start) and open it on the same Wi-Fi.'
  })
  ws.addEventListener('message', async event => {
    if (link !== current) return
    const message = JSON.parse(String(event.data))
    if (message.t === 'room') {
      linkCode.textContent = message.code
      showLink('Ask player 2 to open MENU, then JOIN with this code:', 'code')
    } else if (message.t === 'nope') {
      showLink('No game with that code. Check it and try again.', 'choose')
    } else if (message.t === 'start') {
      current.lock = new Lockstep(message.player, (m: LinkMessage) => ws.send(JSON.stringify(m)))
      showLink(`Linked! You are player ${message.player}.${message.player === 2 ? ' Player 1 picks the game.' : ' Pick a game.'}`, 'linked')
      menuButton.classList.add('on')
      const roms = { menu: await build(MENU), carts: await Promise.all(carts.map(cart => build(cart.file))) }
      if (link !== current) return
      current.roms = roms
      gb = linkedConsole(roms.menu)
      carry = 0
      dialog.close()
      say(`LINKED: PLAYER ${message.player}`)
    } else if (message.t === 'in' || message.t === 'sum') {
      current.lock?.receive(message)
    } else if (message.t === 'bye') {
      endLink('PLAYER LEFT')
    }
  })
}

const stepLinked = (current: Link, due: number) => {
  const { lock, roms } = current
  if (!lock || !roms || !gb) return 0
  for (let ran = 0; ran < due; ran++) {
    const pads = lock.next(localPad())
    if (!pads) {
      carry = Math.min(carry + (due - ran) * FRAME_MS, FRAME_MS * 4)
      return ran
    }
    const [p1, p2] = pads
    if ((p1 & MENU_COMBO) === MENU_COMBO && (current.previous & MENU_COMBO) !== MENU_COMBO) gb = linkedConsole(roms.menu)
    current.previous = p1
    gb.mem.setPad(p1)
    gb.mem.pad2 = p2
    gb.runFrame()
    if (current.pending !== null) {
      const built = roms.carts[current.pending]
      current.pending = null
      if (built) gb = linkedConsole(built)
    }
    const device = gb
    lock.advance(() => checksum(device))
    if (lock.desynced) {
      endLink('OUT OF SYNC')
      return ran
    }
  }
  return due
}

const stepLocal = (device: GameBoy, due: number) => {
  if (rewinding) {
    if (!due) return 0
    const state = history.pop()
    if (state) device.restore(state)
    else say('THAT IS AS FAR BACK AS IT GOES')
    return 1
  }
  for (let i = 0; i < due; i++) {
    if (frames++ % REWIND_EVERY === 0) {
      const spare = history.length >= REWIND_DEPTH ? history.shift() : undefined
      history.push(device.snapshot(spare))
    }
    device.runFrame()
  }
  return due
}

const routineAt = (pc: number) => {
  let name = '?'
  for (const [label, address] of symbols) {
    if (address > pc) break
    name = label
  }
  return name
}

const drawNerd = (device: GameBoy) => {
  const c = device.cpu
  const f = c.f
  const flags = ['Z', 'N', 'H', 'C'].map((flag, i) => f & (0x80 >> i) ? flag : '-').join('')
  nerdCpu.innerHTML = [
    `AF ${h2(c.a)}${h2(f)}  BC ${h2(c.b)}${h2(c.c)}  ${flags}`,
    `DE ${h2(c.d)}${h2(c.e)}  HL ${h2(c.h)}${h2(c.l)}  ${c.ime ? 'IME' : 'ime'}`,
    `SP ${h4(c.sp)}  PC <b>${h4(c.pc)}</b>  ${c.halted ? 'HALT' : 'RUN '}`,
    `in <b>${routineAt(c.pc)}</b>`,
    `scanline ${device.mem.io[0x44].toString().padStart(3)}  cart ${entry}`,
    `<b>${fps}</b> fps  <b>${emuMs.toFixed(1)}</b> ms per frame`
  ].join('\n')
  const ram = device.mem.hram
  const lines: string[] = []
  for (let row = 0; row < 8; row++) {
    const cells: string[] = []
    for (let col = 0; col < 16; col++) {
      const i = row * 16 + col
      const text = h2(ram[i] ?? 0)
      cells.push(i < ram.length && ram[i] !== previousRam[i] ? `<b>${text}</b>` : text)
    }
    lines.push(`${h2(0x80 + row * 16)} ${cells.join(' ')}`)
  }
  previousRam = ram.slice()
  nerdRam.innerHTML = lines.join('\n')
  const vram = device.mem.vram
  const data = tileImage.data
  for (let tile = 0; tile < 256; tile++) {
    for (let y = 0; y < 8; y++) {
      const lo = vram[tile * 16 + y * 2]
      const hi = vram[tile * 16 + y * 2 + 1]
      for (let x = 0; x < 8; x++) {
        const shade = ((hi >> (7 - x)) & 1) << 1 | ((lo >> (7 - x)) & 1)
        const o = (((tile >> 4) * 8 + y) * 128 + (tile & 15) * 8 + x) * 4
        data[o] = colors[shade * 3]
        data[o + 1] = colors[shade * 3 + 1]
        data[o + 2] = colors[shade * 3 + 2]
        data[o + 3] = 255
      }
    }
  }
  tileCtx.putImageData(tileImage, 0, 0)
}

const press = (button: Button, down: boolean) => {
  const combo = held.has('start') && held.has('select')
  if (down) held.add(button)
  else held.delete(button)
  for (const el of document.querySelectorAll(`[data-button="${button}"]`)) el.classList.toggle('down', down)
  if (link) return
  if (down) gb?.press(button)
  else gb?.release(button)
  if (!combo && held.has('start') && held.has('select')) menu()
}

const loop = (time: number) => {
  carry = Math.max(-FRAME_MS, carry + Math.min(100, time - last))
  last = time
  const due = Math.max(0, Math.min(3, Math.floor(carry / FRAME_MS + 0.3)))
  carry -= due * FRAME_MS
  if (carry < 0 && carry > -FRAME_MS * 0.1) carry = 0
  try {
    const started = performance.now()
    const ran = link ? stepLinked(link, due) : gb ? stepLocal(gb, due) : 0
    busy += performance.now() - started
    emulated += ran
    if (time - statsAt >= 1000) {
      fps = Math.round(emulated * 1000 / (time - statsAt))
      emuMs = emulated ? busy / emulated : 0
      emulated = 0
      busy = 0
      statsAt = time
    }
    if (gb && ran) {
      draw(gb.ppu.frame, gb.ppu.layer)
      playAudio(gb)
      if (!nerd.hidden && frames % 6 === 0) drawNerd(gb)
    }
  } catch (error) {
    console.error(error)
    gb = null
    power(false, 'CRASHED')
  }
  if (pending && !link) {
    const cart = pending
    pending = null
    boot(cart.file, cart.title)
  }
  requestAnimationFrame(loop)
}

const toggleNerd = () => {
  nerd.hidden = !nerd.hidden
  if (!nerd.hidden && gb) drawNerd(gb)
}

const SHORTCUTS: Record<string, () => void> = {
  KeyM: () => setMuted(!muted),
  KeyC: () => { usePalette(paletteIndex + 1); say(`COLOR: ${PALETTES[paletteIndex].name}`) },
  KeyS: saveState,
  KeyL: loadState,
  KeyN: toggleNerd
}

addEventListener('keydown', e => {
  if (dialog.open) return
  if (e.code === 'KeyR') {
    if (!e.repeat) setRewind(true)
    return
  }
  if (e.repeat) return
  const shortcut = SHORTCUTS[e.code]
  if (shortcut) return shortcut()
  const button = KEYS[e.code]
  if (!button) return
  e.preventDefault()
  press(button, true)
})
addEventListener('keyup', e => {
  if (e.code === 'KeyR') return setRewind(false)
  const button = KEYS[e.code]
  if (button) press(button, false)
})
addEventListener('blur', () => {
  setRewind(false)
  for (const button of [...held]) press(button, false)
})
addEventListener('contextmenu', e => e.preventDefault())
for (const type of ['pointerdown', 'pointerup', 'keydown']) addEventListener(type, startAudio, true)

const fitScreen = () => {
  const dpr = devicePixelRatio || 1
  const fit = Math.min(lcd.clientWidth * dpr / WIDTH, lcd.clientHeight * dpr / HEIGHT)
  const scale = Math.floor(fit) >= fit * 0.9 ? Math.floor(fit) : fit
  canvas.style.width = `${WIDTH * scale / dpr}px`
  canvas.style.height = `${HEIGHT * scale / dpr}px`
}
new ResizeObserver(fitScreen).observe(lcd)

const dpad = $<HTMLElement>('.dpad')
const DIRECTIONS: Button[] = ['up', 'down', 'left', 'right']
let dpadPointer: number | null = null
const aim = (e: PointerEvent) => {
  const r = dpad.getBoundingClientRect()
  const dx = (e.clientX - r.left - r.width / 2) / (r.width / 2)
  const dy = (e.clientY - r.top - r.height / 2) / (r.height / 2)
  const want = new Set<Button>()
  if (Math.hypot(dx, dy) > 0.2) {
    if (Math.abs(dx) > Math.abs(dy) * 0.414) want.add(dx > 0 ? 'right' : 'left')
    if (Math.abs(dy) > Math.abs(dx) * 0.414) want.add(dy > 0 ? 'down' : 'up')
  }
  for (const direction of DIRECTIONS) {
    if (want.has(direction) !== held.has(direction)) press(direction, want.has(direction))
  }
}
dpad.addEventListener('pointerdown', e => {
  e.preventDefault()
  dpad.setPointerCapture(e.pointerId)
  dpadPointer = e.pointerId
  aim(e)
})
dpad.addEventListener('pointermove', e => { if (e.pointerId === dpadPointer) aim(e) })
for (const type of ['pointerup', 'pointercancel', 'lostpointercapture'] as const) {
  dpad.addEventListener(type, e => {
    if (e.pointerId !== dpadPointer) return
    dpadPointer = null
    for (const direction of DIRECTIONS) if (held.has(direction)) press(direction, false)
  })
}

for (const el of document.querySelectorAll<HTMLElement>('[data-button]')) {
  if (el.closest('.dpad')) continue
  const button = el.dataset.button as Button
  el.addEventListener('pointerdown', e => {
    e.preventDefault()
    el.setPointerCapture(e.pointerId)
    press(button, true)
  })
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    el.addEventListener(type, () => { if (held.has(button)) press(button, false) })
  }
}

rewindButton.addEventListener('pointerdown', e => {
  e.preventDefault()
  rewindButton.setPointerCapture(e.pointerId)
  setRewind(true)
})
for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
  rewindButton.addEventListener(type, () => setRewind(false))
}
colorButton.addEventListener('click', SHORTCUTS.KeyC)
speaker.addEventListener('click', () => setMuted(!muted))
menuButton.addEventListener('click', () => {
  if (!link) showLink('Play with a friend on the same Wi-Fi.', 'choose')
  dialog.showModal()
})
$<HTMLButtonElement>('#menu-close').addEventListener('click', () => dialog.close())
$<HTMLButtonElement>('#link-host').addEventListener('click', () => {
  showLink('Opening a game...', 'code')
  linkCode.textContent = '....'
  openLink({ t: 'host' })
})
$<HTMLFormElement>('#link-join').addEventListener('submit', e => {
  e.preventDefault()
  const code = codeInput.value.trim().toUpperCase()
  if (code.length !== 4) return showLink('The code is 4 letters.', 'choose')
  showLink('Joining...', 'code')
  linkCode.textContent = code
  openLink({ t: 'join', code })
})
unplug.addEventListener('click', () => {
  if (link) endLink('UNPLUGGED')
  else showLink('Play with a friend on the same Wi-Fi.', 'choose')
})
$<HTMLButtonElement>('#save').addEventListener('click', () => { dialog.close(); saveState() })
$<HTMLButtonElement>('#load').addEventListener('click', () => { dialog.close(); loadState() })
$<HTMLButtonElement>('#nerd-toggle').addEventListener('click', () => { dialog.close(); toggleNerd() })
$<HTMLButtonElement>('#nerd-close').addEventListener('click', toggleNerd)

usePalette(paletteIndex)
speaker.classList.toggle('muted', muted)
requestAnimationFrame(loop)
const play = new URLSearchParams(location.search).get('play')
if (play === 'studio') boot('studio.asm', 'Your game')
else if (play === 'level') boot('my-level.asm', 'Your level')
else menu()
