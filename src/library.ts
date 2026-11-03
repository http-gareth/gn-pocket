export interface Cart {
  id: string
  title: string
  file: string
  blurb: string
}

export const MENU = 'menu.asm'
export const LIBRARY = 'generated/library.asm'

export const libraryAsm = (carts: Cart[]) => [
  `GAME_COUNT equ ${carts.length}`,
  'GameTitles:',
  ...carts.map(cart => `    db "${cart.title.toUpperCase().padEnd(15).slice(0, 15)}", 0`)
].join('\n')
