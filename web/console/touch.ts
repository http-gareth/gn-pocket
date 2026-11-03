import type { Button } from '../../src/hardware/memory.ts'

type Press = (button: Button, down: boolean) => void

const DIRECTIONS: Button[] = ['up', 'down', 'left', 'right']
const DEAD_ZONE = 0.2
const DIAGONAL = 0.414

export const hold = (el: HTMLElement, down: () => void, up: () => void) => {
  el.addEventListener('pointerdown', e => {
    e.preventDefault()
    el.setPointerCapture(e.pointerId)
    down()
  })
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) el.addEventListener(type, up)
}

const bindDpad = (dpad: HTMLElement, press: Press, isHeld: (button: Button) => boolean) => {
  let pointer: number | null = null
  const aim = (e: PointerEvent) => {
    const r = dpad.getBoundingClientRect()
    const dx = (e.clientX - r.left - r.width / 2) / (r.width / 2)
    const dy = (e.clientY - r.top - r.height / 2) / (r.height / 2)
    const want = new Set<Button>()
    if (Math.hypot(dx, dy) > DEAD_ZONE) {
      if (Math.abs(dx) > Math.abs(dy) * DIAGONAL) want.add(dx > 0 ? 'right' : 'left')
      if (Math.abs(dy) > Math.abs(dx) * DIAGONAL) want.add(dy > 0 ? 'down' : 'up')
    }
    for (const direction of DIRECTIONS) {
      if (want.has(direction) !== isHeld(direction)) press(direction, want.has(direction))
    }
  }
  dpad.addEventListener('pointerdown', e => {
    e.preventDefault()
    dpad.setPointerCapture(e.pointerId)
    pointer = e.pointerId
    aim(e)
  })
  dpad.addEventListener('pointermove', e => { if (e.pointerId === pointer) aim(e) })
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture'] as const) {
    dpad.addEventListener(type, e => {
      if (e.pointerId !== pointer) return
      pointer = null
      for (const direction of DIRECTIONS) if (isHeld(direction)) press(direction, false)
    })
  }
}

export const bindTouch = (root: HTMLElement, press: Press, isHeld: (button: Button) => boolean) => {
  bindDpad(root.querySelector('.dpad')!, press, isHeld)
  for (const el of root.querySelectorAll<HTMLElement>('[data-button]')) {
    if (el.closest('.dpad')) continue
    const button = el.dataset.button as Button
    hold(el, () => press(button, true), () => { if (isHeld(button)) press(button, false) })
  }
}
