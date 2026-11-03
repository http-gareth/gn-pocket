import { GameBoy } from '../../src/hardware/gameboy.ts'
import type { Snapshot } from '../../src/hardware/gameboy.ts'
import { BUTTONS } from '../../src/hardware/memory.ts'
import type { Button } from '../../src/hardware/memory.ts'
import { assemble, resolveFiles } from '../../src/assembler/assembler.ts'
import { LIBRARY, MENU, libraryAsm } from '../../src/assembler/library.ts'
import type { Cart } from '../../src/assembler/library.ts'
import { parseLevel, withLevel } from '../../src/assembler/level.ts'
import { FRAME_MS, Lockstep, checksum } from '../../src/netplay/lockstep.ts'
import { parseServerMessage } from '../../src/netplay/protocol.ts'
import type { ClientMessage } from '../../src/netplay/protocol.ts'
import { readGame, store, stored } from '../shared.ts'
import { PALETTES, Screen } from './screen.ts'
import { Speaker } from './speaker.ts'
import { NerdPanel, routinesOf } from './nerd.ts'
import { bindTouch, hold } from './touch.ts'
import { loadGame, saveGame } from './saves.ts'

type Built = { rom: Uint8Array, symbols: Map<string, number> }
type Link = {
  ws: WebSocket
  lock: Lockstep | null
  roms: { menu: Built, carts: Built[] } | null
  pending: number | null
  previous: number
}

const REWIND_EVERY = 4
const REWIND_DEPTH = 300
const NERD_EVERY = 6
const LINK_INVITE = 'Play with a friend on the same Wi-Fi.'
const MENU_COMBO = (1 << BUTTONS.indexOf('start')) | (1 << BUTTONS.indexOf('select'))
const KEYS: Record<string, Button> = {
  ArrowRight: 'right', ArrowLeft: 'left', ArrowUp: 'up', ArrowDown: 'down',
  KeyZ: 'a', KeyX: 'b', Enter: 'start', ShiftLeft: 'select', ShiftRight: 'select'
}

const $ = <T extends Element>(selector: string) => document.querySelector(selector) as T
const device = $<HTMLElement>('.device')
const insertHint = $<HTMLElement>('#insert')
const toast = $<HTMLElement>('#toast')
const led = $<HTMLElement>('#led')
const colorButton = $<HTMLButtonElement>('#color')
const speakerButton = $<HTMLButtonElement>('#speaker')
const menuButton = $<HTMLButtonElement>('#menu')
const rewindButton = $<HTMLButtonElement>('#rewind')
const dialog = $<HTMLDialogElement>('#menu-dialog')
const linkStatus = $<HTMLElement>('#link-status')
const linkChoices = $<HTMLElement>('#link-choices')
const linkCode = $<HTMLElement>('#link-code')
const codeInput = $<HTMLInputElement>('#link-input')
const unplug = $<HTMLButtonElement>('#link-unplug')

const screen = new Screen($<HTMLCanvasElement>('#screen'), $<HTMLElement>('#lcd'))
const speaker = new Speaker()
const nerd = new NerdPanel($<HTMLElement>('#nerd'))
const carts: Cart[] = JSON.parse(await readGame('games.json'))
const known: Record<string, string> = { [LIBRARY]: libraryAsm(carts) }
const roms = new Map<string, Built>()
const held = new Set<Button>()
const history: Snapshot[] = []

let gb: GameBoy | null = null
let entry = MENU
let pending: Cart | null = null
let link: Link | null = null
let carry = 0
let last = performance.now()
let frames = 0
let rewinding = false
let emulated = 0
let busy = 0
let fps = 0
let msPerFrame = 0
let statsAt = performance.now()
let paletteIndex = Math.max(0, PALETTES.findIndex(p => p.name === stored('palette')))
let toastTimer = 0

const say = (text: string) => {
  toast.textContent = text
  toast.hidden = false
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => { toast.hidden = true }, 2200)
}

const usePalette = (index: number) => {
  paletteIndex = (index + PALETTES.length) % PALETTES.length
  const palette = PALETTES[paletteIndex]
  screen.usePalette(palette)
  insertHint.style.color = palette.bg[2]
  const swatches = colorButton.querySelectorAll<HTMLElement>('i')
  ;[palette.bg[1], (palette.obj ?? palette.bg)[2], (palette.alt ?? palette.bg)[2]].forEach((c, i) => { swatches[i].style.background = c })
  store('palette', palette.name)
}

const setMuted = (muted: boolean) => {
  speaker.muted = muted
  speakerButton.classList.toggle('muted', muted)
  store('muted', muted ? '1' : '0')
}

const listen = (machine: GameBoy) => {
  machine.mem.onRumble = length => navigator.vibrate?.(length * 10)
  if (speaker.sampleRate === null) return
  machine.apu.sampleRate = speaker.sampleRate
  machine.apu.capture = true
}

const power = (on: boolean, message = 'LOADING') => {
  led.classList.toggle('on', on)
  insertHint.hidden = on
  insertHint.textContent = message
  if (!on) screen.clear()
}

const customSource = async (name: string) => {
  if (name === 'studio.asm') return stored('studio:source') ?? ''
  if (name === 'my-level.asm') {
    const rows = parseLevel(stored('editor:level'))
    if (!rows) throw new Error('no saved level')
    return withLevel(await readGame('pip.asm'), rows)
  }
  return null
}

const build = async (name: string): Promise<Built> => {
  const cached = roms.get(name)
  if (cached) return cached
  const custom = await customSource(name)
  const files = await resolveFiles(name, readGame, custom === null ? known : { ...known, [name]: custom })
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
  nerd.routines = routinesOf(built.symbols)
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

const saveState = () => {
  if (!gb || link) return say(link ? 'NOT WHILE LINKED' : 'NOTHING TO SAVE')
  say(store(`state:${entry}`, saveGame(gb)) ? 'SAVED' : 'COULD NOT SAVE')
}

const loadState = () => {
  if (!gb || link) return say(link ? 'NOT WHILE LINKED' : 'NOTHING TO LOAD')
  const saved = stored(`state:${entry}`)
  if (!saved) return say('NO SAVE FOR THIS GAME')
  if (!loadGame(gb, saved)) return say('THAT SAVE IS DAMAGED')
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
  nerd.routines = routinesOf(built.symbols)
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
  showLink(LINK_INVITE, 'choose')
  say(message)
  if (old.lock) menu()
}

const openLink = (first: ClientMessage) => {
  link?.ws.close()
  const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/link`)
  const current: Link = { ws, lock: null, roms: null, pending: null, previous: 0 }
  const send = (message: ClientMessage) => ws.send(JSON.stringify(message))
  link = current
  setRewind(false)
  ws.addEventListener('open', () => send(first))
  ws.addEventListener('close', () => {
    if (link !== current) return
    endLink(current.lock ? 'LINK LOST' : 'NO LINK SERVER')
    if (!current.lock) linkStatus.textContent = 'No link server here. Run GN Pocket on a PC (npm start) and open it on the same Wi-Fi.'
  })
  ws.addEventListener('message', async event => {
    const message = link === current ? parseServerMessage(String(event.data)) : null
    if (!message) return
    if (message.t === 'ping') {
      send({ t: 'pong' })
    } else if (message.t === 'room') {
      linkCode.textContent = message.code
      showLink('Ask player 2 to open MENU, then JOIN with this code:', 'code')
    } else if (message.t === 'nope') {
      showLink('No game with that code. Check it and try again.', 'choose')
    } else if (message.t === 'start') {
      current.lock = new Lockstep(message.player, send, message.delay)
      const lag = Math.round(message.delay * FRAME_MS)
      showLink(`Linked! You are player ${message.player}.${message.player === 2 ? ' Player 1 picks the game.' : ' Pick a game.'} Button lag ${lag} ms.`, 'linked')
      menuButton.classList.add('on')
      const built = { menu: await build(MENU), carts: await Promise.all(carts.map(cart => build(cart.file))) }
      if (link !== current) return
      current.roms = built
      gb = linkedConsole(built.menu)
      carry = 0
      dialog.close()
      say(`LINKED: PLAYER ${message.player}`)
    } else if (message.t === 'bye') {
      endLink('PLAYER LEFT')
    } else {
      current.lock?.receive(message)
    }
  })
}

const stepLinked = (current: Link, due: number) => {
  const { lock, roms: built } = current
  if (!lock || !built || !gb) return 0
  for (let ran = 0; ran < due; ran++) {
    const pads = lock.next(localPad())
    if (!pads) {
      carry = Math.min(carry + (due - ran) * FRAME_MS, FRAME_MS * 4)
      return ran
    }
    const [p1, p2] = pads
    if ((p1 & MENU_COMBO) === MENU_COMBO && (current.previous & MENU_COMBO) !== MENU_COMBO) gb = linkedConsole(built.menu)
    current.previous = p1
    gb.mem.setPad(p1)
    gb.mem.pad2 = p2
    gb.runFrame()
    if (current.pending !== null) {
      const cart = built.carts[current.pending]
      current.pending = null
      if (cart) gb = linkedConsole(cart)
    }
    const machine = gb
    lock.advance(() => checksum(machine))
    if (lock.desynced) {
      endLink('OUT OF SYNC')
      return ran
    }
  }
  return due
}

const stepLocal = (machine: GameBoy, due: number) => {
  if (rewinding) {
    if (!due) return 0
    const state = history.pop()
    if (state) machine.restore(state)
    else say('THAT IS AS FAR BACK AS IT GOES')
    return 1
  }
  for (let i = 0; i < due; i++) {
    if (frames++ % REWIND_EVERY === 0) {
      const spare = history.length >= REWIND_DEPTH ? history.shift() : undefined
      history.push(machine.snapshot(spare))
    }
    machine.runFrame()
  }
  return due
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
      msPerFrame = emulated ? busy / emulated : 0
      emulated = 0
      busy = 0
      statsAt = time
    }
    if (gb && ran) {
      screen.draw(gb.ppu.frame, gb.ppu.layer)
      const samples = gb.apu.takeSamples()
      if (!rewinding) speaker.play(samples)
      if (nerd.open && frames % NERD_EVERY === 0) drawNerd()
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

const drawNerd = () => {
  if (gb) nerd.draw(gb, { cart: entry, fps, msPerFrame, colors: screen.colors })
}

const toggleNerd = () => {
  if (nerd.toggle()) drawNerd()
}

const SHORTCUTS: Record<string, () => void> = {
  KeyM: () => {
    setMuted(!speaker.muted)
    say(speaker.muted ? 'SOUND OFF' : 'SOUND ON')
  },
  KeyC: () => {
    usePalette(paletteIndex + 1)
    say(`COLOR: ${PALETTES[paletteIndex].name}`)
  },
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
for (const type of ['pointerdown', 'pointerup', 'keydown']) {
  addEventListener(type, () => {
    speaker.wake()
    if (gb) listen(gb)
  }, true)
}

bindTouch(device, press, button => held.has(button))
hold(rewindButton, () => setRewind(true), () => setRewind(false))
colorButton.addEventListener('click', SHORTCUTS.KeyC)
speakerButton.addEventListener('click', SHORTCUTS.KeyM)
menuButton.addEventListener('click', () => {
  if (!link) showLink(LINK_INVITE, 'choose')
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
  if (!/^[A-Z]{4}$/.test(code)) return showLink('The code is 4 letters.', 'choose')
  showLink('Joining...', 'code')
  linkCode.textContent = code
  openLink({ t: 'join', code })
})
unplug.addEventListener('click', () => {
  if (link) endLink('UNPLUGGED')
  else showLink(LINK_INVITE, 'choose')
})
$<HTMLButtonElement>('#save').addEventListener('click', () => { dialog.close(); saveState() })
$<HTMLButtonElement>('#load').addEventListener('click', () => { dialog.close(); loadState() })
$<HTMLButtonElement>('#nerd-toggle').addEventListener('click', () => { dialog.close(); toggleNerd() })
$<HTMLButtonElement>('#nerd-close').addEventListener('click', toggleNerd)

usePalette(paletteIndex)
setMuted(stored('muted') === '1')
requestAnimationFrame(loop)
const play = new URLSearchParams(location.search).get('play')
if (play === 'studio') boot('studio.asm', 'Your game')
else if (play === 'level') boot('my-level.asm', 'Your level')
else menu()
