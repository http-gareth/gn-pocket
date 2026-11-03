include "lib/hardware.asm"

TILE_GRASS equ FIRST_TILE
TILE_TREE  equ FIRST_TILE + 1
TILE_KERB  equ FIRST_TILE + 2
TILE_ROAD  equ FIRST_TILE + 3
TILE_DASH  equ FIRST_TILE + 4
TILE_CAR   equ FIRST_TILE + 5
TILE_RIVAL equ FIRST_TILE + 7
TILE_FLAG  equ FIRST_TILE + 9

STATE_TITLE equ 0
STATE_PLAY  equ 1
STATE_CRASH equ 2
STATE_OVER  equ 3

LCDC_HUD    equ %11110011
PANEL_Y     equ 72
HUD_Y       equ 136
PANEL       equ $9c00
PLAYER_Y    equ 112
ROAD_L      equ 33
ROAD_R      equ 111
LANE_X      equ 36
MIN_SPEED   equ 16
START_SPEED equ 24
MAX_SPEED   equ 64
RIVAL_SPEED equ 12
LOOP        equ 240
CRASH_TIME  equ 48
NO_CAR      equ $ff

hState   equ $ff80
hCarX    equ $ff81
hSpeed   equ $ff82
hSub     equ $ff83
hTraffic equ $ff84
hPassed  equ $ff85
hScore0  equ $ff86
hScore1  equ $ff87
hScore2  equ $ff88
hBest0   equ $ff89
hBest1   equ $ff8a
hBest2   equ $ff8b
hTimer   equ $ff8c
hBlink   equ $ff8d
hFrame   equ $ff8e
hRowY    equ $ff90
hLaneA   equ $ff93
hLaneB   equ $ff96

    org $40
    push af
    ld a, 1
    ldh [hFrame], a
    pop af
    reti

    org $48
    push af
    ldh a, [rLCDC]
    res 1, a
    ldh [rLCDC], a
    pop af
    reti

    org $100
    nop
    jp Start

    org $134
    db "RACER"

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
    ld a, PANEL_Y
    ldh [rWY], a
    ld a, 7
    ldh [rWX], a
    call SoundOn
    call MusicStop
    call SeedRandom
    xor a
    ldh [hBest0], a
    ldh [hBest1], a
    ldh [hBest2], a
    call NewRace
    ld hl, PANEL + 32 * 3 + 5
    ld de, TitleText
    call PrintText
    ld hl, PANEL + 32 * 5 + 4
    ld de, PressText
    call PrintText
    call ShowBest
    xor a
    ldh [hState], a
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ld a, $40
    ldh [rSTAT], a
    call EnableVBlank
    ld a, 3
    ldh [rIE], a

MainLoop:
    halt
    nop
    ldh a, [hFrame]
    and a
    jr z, MainLoop
    xor a
    ldh [hFrame], a
    call Draw
    call ReadJoypad
    call MusicTick
    ldh a, [hState]
    cp STATE_PLAY
    jr z, .play
    cp STATE_CRASH
    jr z, .crash
    call WaitStart
    jr MainLoop
.play:
    call Play
    jr MainLoop
.crash:
    call Crashing
    jr MainLoop

NewRace:
    call ClearScreen
    xor a
    ldh [rSCY], a
    ldh [hSub], a
    ldh [hTraffic], a
    ldh [hPassed], a
    ldh [hScore0], a
    ldh [hScore1], a
    ldh [hScore2], a
    ld a, (ROAD_L + ROAD_R) / 2
    ldh [hCarX], a
    ld a, START_SPEED
    ldh [hSpeed], a
    ld hl, hRowY
    xor a
    ld [hl+], a
    ld a, LOOP / 3
    ld [hl+], a
    ld a, LOOP / 3 * 2
    ld [hl+], a
    ld a, NO_CAR
    ld b, 6
.empty:
    ld [hl+], a
    dec b
    jr nz, .empty

    ld hl, $9800
    ld b, 0
.row:
    ld de, PlainRow
    ld a, b
    and 2
    jr nz, .copy
    ld de, DashRow
.copy:
    push hl
    ld c, 20
.cell:
    ld a, [de]
    inc de
    cp TILE_GRASS
    jr nz, .put
    call Random
    and 7
    ld a, TILE_GRASS
    jr nz, .put
    ld a, TILE_TREE
.put:
    ld [hl+], a
    dec c
    jr nz, .cell
    pop hl
    ld de, 32
    add hl, de
    inc b
    ld a, b
    cp 32
    jr nz, .row

    ld hl, PANEL + 32
    ld bc, 32 * 8
    ld d, TILE_SPACE
    call MemFill
    ld hl, PANEL + 32
    ld b, 20
    ld a, TILE_FLAG
.flag:
    ld [hl+], a
    dec b
    jr nz, .flag
    ld hl, PANEL
    ld de, HudText
    jp PrintText

ShowBest:
    ld hl, PANEL + 32 * 7 + 4
    ld de, BestText
    call PrintText
    ldh a, [hBest2]
    call PrintBCD
    ldh a, [hBest1]
    call PrintBCD
    ldh a, [hBest0]
    jp PrintBCD

WaitStart:
    call BlinkPrompt
    ldh a, [hState]
    cp STATE_OVER
    jr z, .wait
    ld hl, rSCY
    dec [hl]
    jr .ready
.wait:
    ld hl, hTimer
    ld a, [hl]
    and a
    jr z, .ready
    dec [hl]
    ret
.ready:
    ldh a, [hJoyPressed]
    and PAD_START | PAD_A
    ret z
    call LcdOff
    call NewRace
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ld a, STATE_PLAY
    ldh [hState], a
    ld hl, SfxRise
    call PlaySweep
    ld hl, Theme
    jp MusicPlay

BlinkPrompt:
    ld hl, hBlink
    inc [hl]
    ld a, [hl]
    and 31
    ret nz
    ld a, [hl]
    and 32
    ld de, PressText
    jr z, .show
    ld de, PressBlank
.show:
    ld hl, PANEL + 32 * 5 + 4
    jp PrintText

Play:
    ldh a, [hJoyHeld]
    ld b, a
    ldh a, [hCarX]
    bit PADB_LEFT, b
    jr z, .notLeft
    sub 2
    cp ROAD_L
    jr nc, .notLeft
    ld a, ROAD_L
.notLeft:
    bit PADB_RIGHT, b
    jr z, .notRight
    add 2
    cp ROAD_R + 1
    jr c, .notRight
    ld a, ROAD_R
.notRight:
    ldh [hCarX], a

    ldh a, [hSpeed]
    ld c, a
    ld a, b
    and PAD_UP | PAD_A
    ld a, c
    jr z, .noGas
    cp MAX_SPEED
    jr nc, .noGas
    inc a
.noGas:
    ld c, a
    ld a, b
    and PAD_DOWN | PAD_B
    ld a, c
    jr z, .noBrake
    sub 2
    cp MIN_SPEED
    jr nc, .noBrake
    ld a, MIN_SPEED
.noBrake:
    ldh [hSpeed], a

    ld c, a
    ld hl, hSub
    call Advance
    ldh a, [rSCY]
    sub d
    ldh [rSCY], a
    ld a, d
    call AddScore

    ldh a, [hSpeed]
    sub RIVAL_SPEED
    ld c, a
    ld hl, hTraffic
    call Advance
    call MoveTraffic
    call Collide
    ret nc
    ld a, STATE_CRASH
    ldh [hState], a
    ld a, CRASH_TIME
    ldh [hTimer], a
    ld a, 30
    ldh [rRUMBLE], a
    call MusicStop
    ld hl, SfxCrash
    call PlayNoise
    ld hl, SfxFall
    jp PlaySweep

Advance:
    ld a, [hl]
    add c
    ld d, a
    and 15
    ld [hl], a
    ld a, d
    swap a
    and 15
    ld d, a
    ret

AddScore:
    ld b, a
    ldh a, [hScore0]
    add b
    daa
    ldh [hScore0], a
    ldh a, [hScore1]
    adc 0
    daa
    ldh [hScore1], a
    ldh a, [hScore2]
    adc 0
    daa
    ldh [hScore2], a
    ret

MoveTraffic:
    ld hl, hRowY
    ld b, 3
.row:
    ld a, [hl]
    add d
    cp LOOP
    jr c, .store
    sub LOOP
    ld [hl], a
    call NewRow
    jr .next
.store:
    ld [hl], a
.next:
    inc hl
    dec b
    jr nz, .row
    ret

NewRow:
    push bc
    push hl
    inc hl
    inc hl
    inc hl
    call Random
    and 3
    ld [hl], a
    ld c, a
    ldh a, [hPassed]
    inc a
    ldh [hPassed], a
    srl a
    srl a
    srl a
    cp 7
    jr c, .level
    ld a, 7
.level:
    ld b, a
    call Random
    and 7
    cp b
    jr nc, .single
    call Random
    and 3
    cp c
    jr nz, .second
    xor 2
.second:
    jr .setB
.single:
    ld a, NO_CAR
.setB:
    inc hl
    inc hl
    inc hl
    ld [hl], a
    pop hl
    pop bc
    ret

Collide:
    ld hl, hRowY
    ld b, 3
.row:
    ld a, [hl]
    sub PLAYER_Y + 16 - 13
    cp 27
    jr nc, .next
    push hl
    inc hl
    inc hl
    inc hl
    ld a, [hl]
    call HitLane
    jr c, .hit
    inc hl
    inc hl
    inc hl
    ld a, [hl]
    call HitLane
.hit:
    pop hl
    ret c
.next:
    inc hl
    dec b
    jr nz, .row
    and a
    ret

HitLane:
    cp NO_CAR
    ret z
    call LaneX
    ld c, a
    ldh a, [hCarX]
    sub c
    jr nc, .apart
    cpl
    inc a
.apart:
    cp 14
    ret

LaneX:
    ld c, a
    add a
    add c
    add a
    add a
    add a
    add LANE_X
    ret

Crashing:
    ld hl, hTimer
    dec [hl]
    jr z, .over
    ld a, [hl]
    and 4
    ld a, PALETTE
    jr z, .palette
    cpl
.palette:
    ldh [rBGP], a
    ret
.over:
    ld a, PALETTE
    ldh [rBGP], a
    ld a, STATE_OVER
    ldh [hState], a
    ld a, 40
    ldh [hTimer], a
    ldh a, [hBest2]
    ld b, a
    ldh a, [hScore2]
    cp b
    jr c, .text
    jr nz, .best
    ldh a, [hBest1]
    ld b, a
    ldh a, [hScore1]
    cp b
    jr c, .text
    jr nz, .best
    ldh a, [hBest0]
    ld b, a
    ldh a, [hScore0]
    cp b
    jr c, .text
.best:
    ldh a, [hScore0]
    ldh [hBest0], a
    ldh a, [hScore1]
    ldh [hBest1], a
    ldh a, [hScore2]
    ldh [hBest2], a
.text:
    ld hl, PANEL + 32 * 3 + 5
    ld de, GameOverText
    call PrintText
    jp ShowBest

Draw:
    ld hl, $9c00 + 6
    ldh a, [hScore2]
    call PrintBCD
    ldh a, [hScore1]
    call PrintBCD
    ldh a, [hScore0]
    call PrintBCD
    ldh a, [hSpeed]
    swap a
    and 15
    add '0' - 32
    ld [$9c00 + 18], a

    ld b, HUD_Y
    ldh a, [hState]
    and a
    jr z, .panel
    cp STATE_OVER
    jr nz, .slide
.panel:
    ld b, PANEL_Y
.slide:
    ldh a, [rWY]
    cp b
    jr z, .sprites
    ld a, 8
    jr c, .down
    ld a, -8
.down:
    ld c, a
    ldh a, [rWY]
    add c
    ldh [rWY], a
.sprites:
    ldh a, [rWY]
    ldh [rLYC], a
    ldh a, [rLCDC]
    or 2
    ldh [rLCDC], a
    ld hl, $fe00
    ld a, b
    cp PANEL_Y
    jr nz, .cars
    xor a
    ld c, 7 * 16
.hideAll:
    ld [hl+], a
    dec c
    jr nz, .hideAll
    ret
.cars:
    ld b, PLAYER_Y + 16
    ldh a, [hCarX]
    add 8
    ld c, a
    ld d, TILE_CAR
    call DrawCar
    ld de, hRowY
.rows:
    ld a, [de]
    ld b, a
    push de
    inc e
    inc e
    inc e
    ld a, [de]
    call DrawRival
    inc e
    inc e
    inc e
    ld a, [de]
    call DrawRival
    pop de
    inc e
    ld a, e
    cp low(hRowY) + 3
    jr nz, .rows
    ret

DrawRival:
    cp NO_CAR
    jr z, .hide
    push de
    call LaneX
    add 8
    ld c, a
    ld d, TILE_RIVAL
    call DrawCar
    pop de
    ret
.hide:
    xor a
    ld c, 16
.clear:
    ld [hl+], a
    dec c
    jr nz, .clear
    ret

DrawCar:
    ld e, 0
    call .half
    ld a, c
    add 8
    ld c, a
    ld e, $20
    call .half
    ld a, c
    sub 8
    ld c, a
    ret
.half:
    ld a, b
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, d
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, b
    add 8
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, d
    inc a
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ret

    include "lib/util.asm"
    include "lib/sound.asm"
    include "lib/music.asm"

GRS equ TILE_GRASS
KRB equ TILE_KERB
ROD equ TILE_ROAD
DSH equ TILE_DASH

DashRow:
    db GRS, GRS, GRS, KRB, ROD, ROD, ROD, DSH, ROD, ROD, DSH, ROD, ROD, DSH, ROD, ROD, KRB, GRS, GRS, GRS
PlainRow:
    db GRS, GRS, GRS, KRB, ROD, ROD, ROD, ROD, ROD, ROD, ROD, ROD, ROD, ROD, ROD, ROD, KRB, GRS, GRS, GRS

HudText:
    db "SCORE         SPD", 0
TitleText:
    db "R A C E R", 0
PressText:
    db "PRESS START", 0
PressBlank:
    db "           ", 0
GameOverText:
    db "GAME OVER", 0
BestText:
    db "BEST ", 0

Theme:
    db N_A2, 8, N_A2, 8, N_A3, 8, N_A2, 8, N_G2, 8, N_A2, 8, N_C3, 8, N_A2, 8
    db N_F2, 8, N_F2, 8, N_F3, 8, N_F2, 8, N_E2, 8, N_F2, 8, N_A2, 8, N_F2, 8
    db N_G2, 8, N_G2, 8, N_G3, 8, N_G2, 8, N_F2, 8, N_G2, 8, N_B2, 8, N_G2, 8
    db N_E2, 8, N_E2, 8, N_E3, 8, N_E2, 8, N_G2, 8, N_B2, 8, N_D3, 8, N_E3, 8
    db $ff

    include "lib/font.asm"

Tiles:
    dw `11111111
    dw `11121111
    dw `11111111
    dw `11111121
    dw `11111111
    dw `12111111
    dw `11111111
    dw `11111211

    dw `11333311
    dw `13222231
    dw `32222223
    dw `32322223
    dw `32222323
    dw `13222231
    dw `11333311
    dw `11111111

    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `22222222
    dw `22222222
    dw `22222222
    dw `22222122
    dw `22222222
    dw `22222222
    dw `22222222
    dw `21222222

    dw `00222222
    dw `00222222
    dw `00222222
    dw `00222222
    dw `00222222
    dw `00222222
    dw `00222222
    dw `00222222

    dw `00033333
    dw `00311111
    dw `03111111
    dw `33111111
    dw `33133333
    dw `03133333
    dw `03111111
    dw `03111111

    dw `03111111
    dw `03111111
    dw `03133333
    dw `33133333
    dw `33111111
    dw `03111111
    dw `00311111
    dw `00033333

    dw `00033333
    dw `00333333
    dw `03333333
    dw `11333333
    dw `11311111
    dw `03311111
    dw `03333333
    dw `03333333

    dw `03333333
    dw `03333333
    dw `03311111
    dw `11311111
    dw `11333333
    dw `03333333
    dw `00333333
    dw `00033333

    dw `33330000
    dw `33330000
    dw `33330000
    dw `33330000
    dw `00003333
    dw `00003333
    dw `00003333
    dw `00003333
TilesEnd:
