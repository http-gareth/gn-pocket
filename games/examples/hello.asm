include "lib/hardware.asm"

hX equ $ff80
hY equ $ff81

    org $40
    reti

    org $100
    nop
    jp Start

    org $150
Start:
    di
    ld sp, STACK_TOP
    call LcdOff
    call LoadFont
    ld de, Smiley
    ld hl, $8000 + FIRST_TILE * 16
    ld bc, 16
    call MemCopy
    call ClearScreen
    ld hl, $9800 + 32 * 3 + 2
    ld de, Hello
    call PrintText
    ld hl, $9800 + 32 * 5
    ld de, Hint
    call PrintText
    ld a, PALETTE
    ldh [rBGP], a
    ldh [rOBP0], a
    ld a, 84
    ldh [hX], a
    ld a, 96
    ldh [hY], a
    call SoundOn
    ld a, LCDC_ON
    ldh [rLCDC], a
    call EnableVBlank

Loop:
    halt
    nop
    call ReadJoypad
    ldh a, [hJoyHeld]
    ld b, a
    ld hl, hX
    bit PADB_RIGHT, b
    jr z, .left
    inc [hl]
.left:
    bit PADB_LEFT, b
    jr z, .up
    dec [hl]
.up:
    ld hl, hY
    bit PADB_UP, b
    jr z, .down
    dec [hl]
.down:
    bit PADB_DOWN, b
    jr z, .beep
    inc [hl]
.beep:
    ldh a, [hJoyPressed]
    and PAD_A
    jr z, .draw
    ld hl, SfxDing
    call PlayTone
.draw:
    ld hl, $fe00
    ldh a, [hY]
    ld [hl+], a
    ldh a, [hX]
    ld [hl+], a
    ld a, FIRST_TILE
    ld [hl+], a
    xor a
    ld [hl], a
    jr Loop

    include "lib/util.asm"
    include "lib/sound.asm"

Hello:
    db "HELLO GN POCKET!", 0
Hint:
    db "D-PAD: MOVE  A: BEEP", 0

    include "lib/font.asm"

Smiley:
    dw `00333300
    dw `03111130
    dw `31311313
    dw `31111113
    dw `31311313
    dw `31133113
    dw `03111130
    dw `00333300
