include "lib/hardware.asm"

TILE_RULE  equ FIRST_TILE
TILE_DOT   equ FIRST_TILE + 1
TILE_UP    equ FIRST_TILE + 2
TILE_DOWN  equ FIRST_TILE + 3
VISIBLE    equ 5
TITLE_ROW  equ 6
TITLE_COL  equ 5
CURSOR_X   equ 12
FOOTER     equ $9800 + 32 * 16 + 6

hSel   equ $ff80
hSlide equ $ff81
hBlink equ $ff82
hTop   equ $ff83

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "GN POCKET"

    org $150
Start:
    di
    ld sp, STACK_TOP
    call LcdOff
    call LoadFont
    ld de, Tiles
    ld hl, $8000 + FIRST_TILE * 16
    ld bc, TilesEnd - Tiles
    call MemCopy
    call ClearScreen

    ld hl, $9800 + 32 + 5
    ld de, Logo
    call PrintText
    ld hl, $9800 + 32 * 3 + 4
    ld de, Tagline
    call PrintText

    ld hl, $9800 + 32 * 4 + 1
    ld b, 18
    ld a, TILE_RULE
.rule:
    ld [hl+], a
    dec b
    jr nz, .rule

    xor a
    ldh [hSel], a
    ldh [hTop], a
    call DrawList

    ld hl, FOOTER
    ld de, Footer
    call PrintText

    xor a
    ldh [hBlink], a
    ld a, 144
    ldh [hSlide], a
    ldh [rSCY], a
    ld a, PALETTE
    ldh [rBGP], a
    ldh [rOBP0], a
    ld a, LCDC_ON
    ldh [rLCDC], a
    call SoundOn
    call EnableVBlank

MainLoop:
    halt
    nop
    ldh a, [hSlide]
    and a
    jr z, .ready
    sub 4
    ldh [hSlide], a
    ldh [rSCY], a
    jr MainLoop
.ready:
    call DrawCursor
    call Blink
    call ReadJoypad
    ldh a, [hJoyPressed]
    ld b, a
    bit PADB_UP, b
    jr z, .notUp
    ldh a, [hSel]
    and a
    jr z, .notUp
    dec a
    ldh [hSel], a
    call Blip
    ldh a, [hTop]
    ld c, a
    ldh a, [hSel]
    cp c
    jr nc, .notUp
    ldh [hTop], a
    call Redraw
.notUp:
    bit PADB_DOWN, b
    jr z, .notDown
    ldh a, [hSel]
    inc a
    cp GAME_COUNT
    jr nc, .notDown
    ldh [hSel], a
    call Blip
    ldh a, [hTop]
    ld c, a
    ldh a, [hSel]
    sub c
    cp VISIBLE
    jr c, .notDown
    ld hl, hTop
    inc [hl]
    call Redraw
.notDown:
    ld a, b
    and PAD_A | PAD_START
    jr z, MainLoop
    ld hl, SfxRise
    call PlaySweep
    ld b, 24
.fanfare:
    halt
    dec b
    jr nz, .fanfare
    ldh a, [hSel]
    ldh [rLAUNCH], a
.wait:
    halt
    jr .wait

Redraw:
    push bc
    call DrawList
    pop bc
    ret

DrawList:
    ldh a, [hTop]
    and a
    ld a, TILE_SPACE
    jr z, .up
    ld a, TILE_UP
.up:
    ld [$9800 + 32 * (TITLE_ROW - 1) + 18], a
    ldh a, [hTop]
    add VISIBLE
    cp GAME_COUNT
    ld a, TILE_SPACE
    jr nc, .down
    ld a, TILE_DOWN
.down:
    ld [$9800 + 32 * (TITLE_ROW + VISIBLE * 2 - 1) + 18], a
    ld hl, $9800 + 32 * TITLE_ROW + TITLE_COL - 2
    ldh a, [hTop]
    ld c, a
    ld b, VISIBLE
.slot:
    ld a, c
    cp GAME_COUNT
    ret nc
    push hl
    ld a, TILE_DOT
    ld [hl+], a
    inc hl
    ld a, c
    swap a
    add low(GameTitles)
    ld e, a
    ld a, high(GameTitles)
    adc 0
    ld d, a
    call PrintText
    pop hl
    ld de, 64
    add hl, de
    inc c
    dec b
    jr nz, .slot
    ret

Blip:
    push bc
    ld hl, SfxBlip
    call PlayTone
    pop bc
    ret

DrawCursor:
    ldh a, [hTop]
    ld c, a
    ldh a, [hSel]
    sub c
    swap a
    add TITLE_ROW * 8 + 16
    ld [$fe00], a
    ld a, CURSOR_X + 8
    ld [$fe01], a
    ld a, '>' - 32
    ld [$fe02], a
    xor a
    ld [$fe03], a
    ret

Blink:
    ld hl, hBlink
    inc [hl]
    ld a, [hl]
    and 31
    ret nz
    ld a, [hl]
    and 32
    ld hl, FOOTER
    ld de, Footer
    jr z, .show
    ld de, FooterBlank
.show:
    jp PrintText

    include "lib/util.asm"
    include "lib/sound.asm"

Logo:
    db "GN POCKET", 0
Tagline:
    db "GAME LIBRARY", 0
Footer:
    db "A: PLAY", 0
FooterBlank:
    db "       ", 0

    include "generated/library.asm"

    include "lib/font.asm"

Tiles:
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `22222222
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00022000
    dw `00222200
    dw `00222200
    dw `00022000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00033000
    dw `00333300
    dw `03333330
    dw `33333333
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `03333330
    dw `00333300
    dw `00033000
    dw `00000000
TilesEnd:
