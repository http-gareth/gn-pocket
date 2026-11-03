include "lib/hardware.asm"

TILE_WALL equ FIRST_TILE
TILE_BODY equ FIRST_TILE + 1
TILE_HEAD equ FIRST_TILE + 2
TILE_FOOD equ FIRST_TILE + 3

FIELD_LEFT   equ 1
FIELD_RIGHT  equ 18
FIELD_TOP    equ 2
FIELD_BOTTOM equ 16

DIR_RIGHT equ 0
DIR_LEFT  equ 1
DIR_UP    equ 2
DIR_DOWN  equ 3

START_SPEED equ 8
MIN_SPEED   equ 3

wSnakeX equ $c000
wSnakeY equ $c100

hHead    equ $ff80
hTail    equ $ff81
hDir     equ $ff82
hNextDir equ $ff83
hFoodX   equ $ff84
hFoodY   equ $ff85
hScore   equ $ff86
hTick    equ $ff87
hSpeed   equ $ff88
hOver    equ $ff89
hNewX    equ $ff8a
hNewY    equ $ff8b

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "SNAKE"

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
    ld a, PALETTE
    ldh [rBGP], a
    ldh [rOBP0], a
    call SeedRandom
    call SoundOn
    call NewGame
    ld a, LCDC_ON
    ldh [rLCDC], a
    call EnableVBlank

MainLoop:
    halt
    nop
    call ReadJoypad
    ldh a, [hOver]
    and a
    jr nz, .over
    call Steer
    ld hl, hTick
    dec [hl]
    jr nz, MainLoop
    ldh a, [hSpeed]
    ld [hl], a
    call Step
    jr MainLoop
.over:
    ldh a, [hJoyPressed]
    and PAD_A | PAD_START
    jr z, MainLoop
    call LcdOff
    call NewGame
    ld a, LCDC_ON
    ldh [rLCDC], a
    jr MainLoop

NewGame:
    call ClearScreen
    ld hl, $9800 + 32 * (FIELD_TOP - 1)
    call WallRow
    ld hl, $9800 + 32 * (FIELD_BOTTOM + 1)
    call WallRow
    ld hl, $9800 + 32 * FIELD_TOP
    ld b, FIELD_BOTTOM - FIELD_TOP + 1
.sides:
    ld a, TILE_WALL
    ld [hl], a
    push hl
    ld de, FIELD_RIGHT + 1
    add hl, de
    ld [hl], a
    pop hl
    ld de, 32
    add hl, de
    dec b
    jr nz, .sides

    ld hl, $9800 + 1
    ld de, ScoreText
    call PrintText
    ld hl, $9800 + 12
    ld de, TitleText
    call PrintText

    xor a
    ldh [hTail], a
    ldh [hScore], a
    ldh [hOver], a
    ld a, 2
    ldh [hHead], a
    ld a, DIR_RIGHT
    ldh [hDir], a
    ldh [hNextDir], a
    ld a, START_SPEED
    ldh [hSpeed], a
    ldh [hTick], a

    ld hl, wSnakeX
    ld a, 5
    ld [hl+], a
    inc a
    ld [hl+], a
    inc a
    ld [hl], a
    ld hl, wSnakeY
    ld a, 9
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    ld bc, (5 << 8) | 9
    call CellAddr
    ld [hl], TILE_BODY
    inc hl
    ld [hl], TILE_BODY
    inc hl
    ld [hl], TILE_HEAD

    call PlaceFood
    jp DrawScore

WallRow:
    ld b, 20
    ld a, TILE_WALL
.tile:
    ld [hl+], a
    dec b
    jr nz, .tile
    ret

CellAddr:
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, l
    add b
    ld l, a
    ld a, h
    adc $98
    ld h, a
    ret

Steer:
    ldh a, [hJoyPressed]
    ld b, a
    ldh a, [hDir]
    ld c, a
    bit PADB_RIGHT, b
    jr z, .notRight
    ld a, c
    cp DIR_LEFT
    jr z, .notRight
    ld a, DIR_RIGHT
    ldh [hNextDir], a
.notRight:
    bit PADB_LEFT, b
    jr z, .notLeft
    ld a, c
    cp DIR_RIGHT
    jr z, .notLeft
    ld a, DIR_LEFT
    ldh [hNextDir], a
.notLeft:
    bit PADB_UP, b
    jr z, .notUp
    ld a, c
    cp DIR_DOWN
    jr z, .notUp
    ld a, DIR_UP
    ldh [hNextDir], a
.notUp:
    bit PADB_DOWN, b
    ret z
    ld a, c
    cp DIR_UP
    ret z
    ld a, DIR_DOWN
    ldh [hNextDir], a
    ret

Step:
    ldh a, [hNextDir]
    ldh [hDir], a
    ldh a, [hHead]
    ld l, a
    ld h, high(wSnakeX)
    ld b, [hl]
    inc h
    ld c, [hl]
    ldh a, [hDir]
    and a
    jr nz, .notRight
    inc b
    jr .moved
.notRight:
    dec a
    jr nz, .notLeft
    dec b
    jr .moved
.notLeft:
    dec a
    jr nz, .notUp
    dec c
    jr .moved
.notUp:
    inc c
.moved:
    ld a, b
    ldh [hNewX], a
    ld a, c
    ldh [hNewY], a
    cp FIELD_TOP
    jr c, Die
    cp FIELD_BOTTOM + 1
    jr nc, Die
    ld a, b
    cp FIELD_LEFT
    jr c, Die
    cp FIELD_RIGHT + 1
    jr nc, Die

    ldh a, [hFoodX]
    cp b
    jr nz, .noFood
    ldh a, [hFoodY]
    cp c
    jr nz, .noFood
    call Eat
    jr .advance
.noFood:
    call DropTail
.advance:
    ldh a, [hNewX]
    ld b, a
    ldh a, [hNewY]
    ld c, a
    call CellAddr
    ld a, [hl]
    cp TILE_BODY
    jr z, Die
    push hl
    ldh a, [hHead]
    ld l, a
    ld h, high(wSnakeX)
    ld b, [hl]
    inc h
    ld c, [hl]
    call CellAddr
    ld [hl], TILE_BODY
    pop hl
    ld [hl], TILE_HEAD
    ldh a, [hHead]
    inc a
    ldh [hHead], a
    ld l, a
    ld h, high(wSnakeX)
    ldh a, [hNewX]
    ld [hl], a
    inc h
    ldh a, [hNewY]
    ld [hl], a
    ret

Die:
    ld hl, SfxCrash
    call PlayNoise
    ld a, 1
    ldh [hOver], a
    ld hl, $9800 + 32 * 8 + 5
    ld de, GameOverText
    call PrintText
    ld hl, $9800 + 32 * 10 + 6
    ld de, AgainText
    jp PrintText

DropTail:
    ldh a, [hTail]
    ld l, a
    ld h, high(wSnakeX)
    ld b, [hl]
    inc h
    ld c, [hl]
    call CellAddr
    ld [hl], TILE_SPACE
    ld hl, hTail
    inc [hl]
    ret

Eat:
    ld hl, SfxDing
    call PlayTone
    ldh a, [hScore]
    add 1
    daa
    ldh [hScore], a
    call DrawScore
    ldh a, [hScore]
    and 3
    jr nz, PlaceFood
    ldh a, [hSpeed]
    cp MIN_SPEED + 1
    jr c, PlaceFood
    dec a
    ldh [hSpeed], a

PlaceFood:
    call Random
    and $1f
    cp FIELD_RIGHT - FIELD_LEFT + 1
    jr nc, PlaceFood
    add FIELD_LEFT
    ld b, a
.row:
    call Random
    and $0f
    cp FIELD_BOTTOM - FIELD_TOP + 1
    jr nc, .row
    add FIELD_TOP
    ld c, a
    call CellAddr
    ld a, [hl]
    and a
    jr nz, PlaceFood
    ld [hl], TILE_FOOD
    ld a, b
    ldh [hFoodX], a
    ld a, c
    ldh [hFoodY], a
    ret

DrawScore:
    ldh a, [hScore]
    swap a
    and $0f
    add '0' - 32
    ld [$9800 + 7], a
    ldh a, [hScore]
    and $0f
    add '0' - 32
    ld [$9800 + 8], a
    ret

    include "lib/util.asm"
    include "lib/sound.asm"

ScoreText:
    db "SCORE", 0
TitleText:
    db "SNAKE", 0
GameOverText:
    db "GAME OVER!", 0
AgainText:
    db "A: AGAIN", 0

    include "lib/font.asm"

Tiles:
    dw `33333333
    dw `31113111
    dw `31113111
    dw `33333333
    dw `11311131
    dw `11311131
    dw `33333333
    dw `31113111

    dw `03333330
    dw `33333333
    dw `33322333
    dw `33322333
    dw `33333333
    dw `33333333
    dw `03333330
    dw `00000000

    dw `03333330
    dw `33333333
    dw `30333303
    dw `30333303
    dw `33333333
    dw `33333333
    dw `03333330
    dw `00000000

    dw `00003000
    dw `00030000
    dw `03322330
    dw `32222223
    dw `32222223
    dw `32222223
    dw `03222230
    dw `00333300
TilesEnd:
