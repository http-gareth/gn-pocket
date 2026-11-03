include "lib/hardware.asm"

TILE_WALL    equ FIRST_TILE
TILE_BLOCK   equ FIRST_TILE + 1
TILE_FLASH   equ FIRST_TILE + 8
TILE_CURTAIN equ FIRST_TILE + 10

STATE_TITLE equ 0
STATE_PLAY  equ 1
STATE_CLEAR equ 2
STATE_OVER  equ 3

ROWS       equ 18
SPAWN_X    equ 4
NEXT_X     equ 14
NEXT_Y     equ 12
FLASH_TIME equ 24
DAS_DELAY  equ 12
DAS_RATE   equ 3

hState      equ $ff80
hPiece      equ $ff81
hRot        equ $ff82
hX          equ $ff83
hY          equ $ff84
hNext       equ $ff85
hDrop       equ $ff86
hLevel      equ $ff87
hLevelLines equ $ff88
hLinesL     equ $ff89
hLinesH     equ $ff8a
hScore0     equ $ff8b
hScore1     equ $ff8c
hScore2     equ $ff8d
hBest0      equ $ff8e
hBest1      equ $ff8f
hBest2      equ $ff90
hRepeat     equ $ff91
hTimer      equ $ff92
hTestRot    equ $ff93
hDrawX      equ $ff94
hDrawY      equ $ff95
hBlink      equ $ff96

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "BLOCKS"

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
    call SoundOn
    call MusicStop
    call SeedRandom
    xor a
    ldh [hBest0], a
    ldh [hBest1], a
    ldh [hBest2], a
    call ResetStats
    call BuildBoard
    ld hl, $9800 + 32 * 4 + 3
    ld de, TitleText
    call PrintText
    ld hl, $9800 + 32 * 9 + 3
    ld de, PressText
    call PrintText
    ld hl, $9800 + 32 * 10 + 3
    ld de, StartText
    call PrintText
    xor a
    ldh [hState], a
    ld a, LCDC_ON
    ldh [rLCDC], a
    call EnableVBlank

MainLoop:
    halt
    nop
    call Draw
    call ReadJoypad
    call MusicTick
    ldh a, [hState]
    cp STATE_PLAY
    jr z, .play
    cp STATE_CLEAR
    jr z, .clear
    cp STATE_OVER
    jr z, .over
    call WaitStart
    jr MainLoop
.play:
    call Play
    jr MainLoop
.clear:
    call Clearing
    jr MainLoop
.over:
    call Curtain
    jr MainLoop

BuildBoard:
    ld hl, $9800
    ld bc, 32 * 32
    ld d, TILE_WALL
    call MemFill
    ld hl, $9800 + 1
    ld b, ROWS
.board:
    push hl
    ld c, 10
    xor a
.cell:
    ld [hl+], a
    dec c
    jr nz, .cell
    inc hl
    ld c, 8
.panel:
    ld [hl+], a
    dec c
    jr nz, .panel
    pop hl
    ld de, 32
    add hl, de
    dec b
    jr nz, .board
    ld hl, $fe00
    ld bc, 160
    ld d, 0
    call MemFill
    ld hl, $9800 + 32 * 1 + 13
    ld de, ScoreText
    call PrintText
    ld hl, $9800 + 32 * 4 + 13
    ld de, LevelText
    call PrintText
    ld hl, $9800 + 32 * 7 + 13
    ld de, LinesText
    call PrintText
    ld hl, $9800 + 32 * 10 + 13
    ld de, NextText
    call PrintText
    ld hl, $9800 + 32 * 15 + 13
    ld de, BestText
    jp PrintText

ResetStats:
    xor a
    ldh [hScore0], a
    ldh [hScore1], a
    ldh [hScore2], a
    ldh [hLinesL], a
    ldh [hLinesH], a
    ldh [hLevel], a
    ldh [hLevelLines], a
    ldh [hRepeat], a
    ret

WaitStart:
    ldh a, [hJoyPressed]
    and PAD_START | PAD_A
    ret z
    ld hl, SfxRise
    call PlaySweep
    call LcdOff
    call BuildBoard
    ld a, LCDC_ON
    ldh [rLCDC], a
    call ResetStats
    call RandomPiece
    ldh [hNext], a
    ld hl, Theme
    call MusicPlay
    jp Spawn

RandomPiece:
    call Random
    and 7
    cp 7
    jr z, RandomPiece
    ld b, a
    ldh a, [hNext]
    cp b
    ld a, b
    ret nz
    call Random
    and 7
    cp 7
    jr z, RandomPiece
    ret

Spawn:
    ldh a, [hNext]
    ldh [hPiece], a
    call RandomPiece
    ldh [hNext], a
    xor a
    ldh [hRot], a
    ldh [hY], a
    ld a, SPAWN_X
    ldh [hX], a
    call ResetDrop
    ld a, STATE_PLAY
    ldh [hState], a
    ld b, 0
    ld d, SPAWN_X
    ld e, 0
    call Fits
    ret nc

GameOver:
    ld a, STATE_OVER
    ldh [hState], a
    xor a
    ldh [hTimer], a
    call MusicStop
    ld hl, SfxCrash
    call PlayNoise
    ldh a, [hBest2]
    ld b, a
    ldh a, [hScore2]
    cp b
    ret c
    jr nz, .best
    ldh a, [hBest1]
    ld b, a
    ldh a, [hScore1]
    cp b
    ret c
    jr nz, .best
    ldh a, [hBest0]
    ld b, a
    ldh a, [hScore0]
    cp b
    ret c
.best:
    ldh a, [hScore0]
    ldh [hBest0], a
    ldh a, [hScore1]
    ldh [hBest1], a
    ldh a, [hScore2]
    ldh [hBest2], a
    ret

Curtain:
    ldh a, [hTimer]
    cp ROWS * 2
    jr nc, .done
    inc a
    ldh [hTimer], a
    srl a
    ret c
    ld d, a
    dec d
    call RowAddr
    ld b, 10
    ld a, TILE_CURTAIN
.fill:
    ld [hl+], a
    dec b
    jr nz, .fill
    ldh a, [hTimer]
    cp ROWS * 2
    ret nz
    ld hl, $9800 + 32 * 5 + 1
    ld de, OverPanel
    ld b, 10
.panel:
    push hl
    call PrintText
    inc de
    pop hl
    ld a, l
    add 32
    ld l, a
    jr nc, .line
    inc h
.line:
    dec b
    jr nz, .panel
    ret
.done:
    jp WaitStart

ResetDrop:
    ldh a, [hLevel]
    cp 15
    jr c, .speed
    ld a, 15
.speed:
    ld e, a
    ld d, 0
    ld hl, Speeds
    add hl, de
    ld a, [hl]
    ldh [hDrop], a
    ret

Play:
    ldh a, [hJoyPressed]
    bit PADB_A, a
    jr z, .notA
    ld c, 1
    call Rotate
.notA:
    ldh a, [hJoyPressed]
    bit PADB_B, a
    jr z, .notB
    ld c, 3
    call Rotate
.notB:
    call Shift
    ldh a, [hJoyPressed]
    bit PADB_UP, a
    jr nz, HardDrop
    ldh a, [hJoyHeld]
    bit PADB_DOWN, a
    jr z, .gravity
    ld hl, hDrop
    ld a, [hl]
    cp 3
    jr c, .gravity
    ld [hl], 2
.gravity:
    ld hl, hDrop
    dec [hl]
    ret nz
    call ResetDrop
    call LoadPos
    inc e
    call Fits
    jr c, Landed
    ld a, e
    ldh [hY], a
    ret

HardDrop:
    call LoadPos
    inc e
    call Fits
    jr c, Landed
    ld a, e
    ldh [hY], a
    ld de, $0002
    call AddScore
    jr HardDrop

LoadPos:
    ldh a, [hRot]
    ld b, a
    ldh a, [hX]
    ld d, a
    ldh a, [hY]
    ld e, a
    ret

Landed:
    call Lock
    ld hl, SfxThud
    call PlayTone
    call FindLines
    and a
    jp z, Spawn
    ld c, a
    push bc
    call ScoreLines
    pop bc
    ld a, c
    cp 4
    ld hl, SfxDing
    jr nz, .sound
    ld hl, SfxCrowd
    call PlayNoise
    ld hl, SfxRise
    call PlaySweep
    jr .flash
.sound:
    call PlayTone
.flash:
    ld a, FLASH_TIME
    ldh [hTimer], a
    ld a, STATE_CLEAR
    ldh [hState], a
    ret

Rotate:
    ldh a, [hRot]
    add c
    and 3
    ldh [hTestRot], a
    ldh a, [hY]
    ld e, a
    ldh a, [hX]
    ld d, a
    call TryRot
    jr nc, .turn
    dec d
    call TryRot
    jr nc, .turn
    inc d
    inc d
    call TryRot
    ret c
.turn:
    ldh a, [hTestRot]
    ldh [hRot], a
    ld a, d
    ldh [hX], a
    ld hl, SfxBlip
    jp PlayTone

TryRot:
    ldh a, [hTestRot]
    ld b, a
    jp Fits

Shift:
    ldh a, [hJoyHeld]
    and PAD_LEFT | PAD_RIGHT
    ret z
    ld c, a
    ldh a, [hJoyPressed]
    and PAD_LEFT | PAD_RIGHT
    jr nz, .fresh
    ld hl, hRepeat
    dec [hl]
    ret nz
    ld [hl], DAS_RATE
    jr .try
.fresh:
    ld a, DAS_DELAY
    ldh [hRepeat], a
.try:
    call LoadPos
    bit PADB_LEFT, c
    jr z, .right
    dec d
    jr .check
.right:
    inc d
.check:
    call Fits
    ret c
    ld a, d
    ldh [hX], a
    ret

CellsOf:
    add a
    add a
    add b
    add a
    add a
    add low(Shapes)
    ld l, a
    ld a, high(Shapes)
    adc 0
    ld h, a
    ret

CellAddr:
    ld c, a
    rrca
    rrca
    and 3
    add e
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, c
    and 3
    add d
    and 31
    or l
    ld l, a
    ld a, h
    add high($9800)
    ld h, a
    ret

Fits:
    ldh a, [hPiece]
    call CellsOf
    ld b, 4
.cell:
    ld a, [hl+]
    push hl
    call CellAddr
    ld a, [hl]
    pop hl
    and a
    jr nz, .blocked
    dec b
    jr nz, .cell
    ret
.blocked:
    scf
    ret

Lock:
    call LoadPos
    ldh a, [hPiece]
    call CellsOf
    ld b, 4
.cell:
    ld a, [hl+]
    push hl
    call CellAddr
    ldh a, [hPiece]
    add TILE_BLOCK
    ld [hl], a
    pop hl
    dec b
    jr nz, .cell
    ret

RowAddr:
    ld l, d
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    inc l
    ld a, h
    add high($9800)
    ld h, a
    ret

FindLines:
    ld c, 0
    ld d, 0
.row:
    call RowAddr
    ld b, 10
.col:
    ld a, [hl+]
    and a
    jr z, .next
    dec b
    jr nz, .col
    call RowAddr
    ld b, 10
    ld a, TILE_FLASH
.fill:
    ld [hl+], a
    dec b
    jr nz, .fill
    inc c
.next:
    inc d
    ld a, d
    cp ROWS
    jr nz, .row
    ld a, c
    ret

ScoreLines:
    ldh a, [hLinesL]
    add c
    daa
    ldh [hLinesL], a
    ldh a, [hLinesH]
    adc 0
    daa
    ldh [hLinesH], a
    ldh a, [hLevelLines]
    add c
    cp 10
    jr c, .same
    sub 10
    ld hl, hLevel
    inc [hl]
.same:
    ldh [hLevelLines], a
    ld a, c
    dec a
    add a
    add low(LinePoints)
    ld l, a
    ld a, high(LinePoints)
    adc 0
    ld h, a
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ldh a, [hLevel]
    inc a
    ld b, a
.times:
    call AddScore
    dec b
    jr nz, .times
    ret

AddScore:
    ldh a, [hScore0]
    add e
    daa
    ldh [hScore0], a
    ldh a, [hScore1]
    adc d
    daa
    ldh [hScore1], a
    ldh a, [hScore2]
    adc 0
    daa
    ldh [hScore2], a
    ret

Clearing:
    ld hl, hTimer
    dec [hl]
    jr z, Collapse
    ld a, [hl]
    and 3
    ret nz
    ld d, 0
.row:
    call RowAddr
    ld a, [hl]
    cp TILE_FLASH
    jr z, .toggle
    cp TILE_FLASH + 1
    jr nz, .next
.toggle:
    xor 1
    ld b, 10
.fill:
    ld [hl+], a
    dec b
    jr nz, .fill
.next:
    inc d
    ld a, d
    cp ROWS
    jr nz, .row
    ret

Collapse:
    ld d, ROWS - 1
.check:
    call RowAddr
    ld a, [hl]
    and $fe
    cp TILE_FLASH
    jr z, .remove
    dec d
    bit 7, d
    jr z, .check
    jp Spawn
.remove:
    push de
.shift:
    ld a, d
    and a
    jr z, .top
    call RowAddr
    ld a, l
    sub 32
    ld c, a
    ld a, h
    sbc 0
    ld b, a
    ld e, 10
.copy:
    ld a, [bc]
    ld [hl+], a
    inc bc
    dec e
    jr nz, .copy
    dec d
    jr .shift
.top:
    call RowAddr
    ld b, 10
    xor a
.clear:
    ld [hl+], a
    dec b
    jr nz, .clear
    pop de
    jr .check

Draw:
    ld hl, $9800 + 32 * 2 + 13
    ldh a, [hScore2]
    call PrintBCD
    ldh a, [hScore1]
    call PrintBCD
    ldh a, [hScore0]
    call PrintBCD
    ld hl, $9800 + 32 * 16 + 13
    ldh a, [hBest2]
    call PrintBCD
    ldh a, [hBest1]
    call PrintBCD
    ldh a, [hBest0]
    call PrintBCD
    ld hl, $9800 + 32 * 8 + 13
    ldh a, [hLinesH]
    call PrintBCD
    ldh a, [hLinesL]
    call PrintBCD
    ldh a, [hLevel]
    ld b, 0
.tens:
    cp 10
    jr c, .level
    sub 10
    inc b
    jr .tens
.level:
    ld c, a
    ld a, b
    swap a
    or c
    ld hl, $9800 + 32 * 5 + 13
    call PrintBCD

    ld de, $fe00
    ldh a, [hState]
    cp STATE_PLAY
    jr nz, .hide
    ldh a, [hX]
    ldh [hDrawX], a
    ldh a, [hY]
    ldh [hDrawY], a
    ldh a, [hRot]
    ld b, a
    ldh a, [hPiece]
    call DrawCells
    jr .next
.hide:
    xor a
    ld b, 16
.clear:
    ld [de], a
    inc de
    dec b
    jr nz, .clear
.next:
    ldh a, [hState]
    and a
    jr z, .noNext
    ld a, NEXT_X
    ldh [hDrawX], a
    ld a, NEXT_Y
    ldh [hDrawY], a
    ld b, 0
    ldh a, [hNext]
    jp DrawCells
.noNext:
    xor a
    ld [de], a
    ld e, 20
    ld [de], a
    ld e, 24
    ld [de], a
    ld e, 28
    ld [de], a
    ret

DrawCells:
    ld c, a
    call CellsOf
    ld b, 4
.cell:
    ld a, [hl]
    rrca
    rrca
    and 3
    push hl
    ld hl, hDrawY
    add [hl]
    pop hl
    add a
    add a
    add a
    add 16
    ld [de], a
    inc de
    ld a, [hl+]
    and 3
    push hl
    ld hl, hDrawX
    add [hl]
    pop hl
    add a
    add a
    add a
    add 8
    ld [de], a
    inc de
    ld a, c
    add TILE_BLOCK
    ld [de], a
    inc de
    xor a
    ld [de], a
    inc de
    dec b
    jr nz, .cell
    ret

    include "lib/util.asm"
    include "lib/sound.asm"
    include "lib/music.asm"

Speeds:
    db 48, 40, 34, 28, 23, 19, 16, 13, 11, 9, 8, 7, 6, 5, 4, 3

LinePoints:
    dw $0040, $0100, $0300, $1200

TitleText:
    db "BLOCKS", 0
PressText:
    db "PRESS", 0
StartText:
    db "START", 0
OverPanel:
    db "          ", 0
    db "   GAME   ", 0
    db "   OVER   ", 0
    db "          ", 0
    db "          ", 0
    db "          ", 0
    db "  PRESS   ", 0
    db "  START   ", 0
    db "          ", 0
    db "          ", 0
ScoreText:
    db "SCORE", 0
LevelText:
    db "LEVEL", 0
LinesText:
    db "LINES", 0
NextText:
    db "NEXT", 0
BestText:
    db "BEST", 0

Theme:
    db N_E4, 24, N_B3, 12, N_C4, 12, N_D4, 24, N_C4, 12, N_B3, 12
    db N_A3, 24, N_A3, 12, N_C4, 12, N_E4, 24, N_D4, 12, N_C4, 12
    db N_B3, 36, N_C4, 12, N_D4, 24, N_E4, 24
    db N_C4, 24, N_A3, 24, N_A3, 24, 0, 24
    db N_D4, 36, N_F4, 12, N_A4, 24, N_G4, 12, N_F4, 12
    db N_E4, 36, N_C4, 12, N_E4, 24, N_D4, 12, N_C4, 12
    db N_B3, 24, N_B3, 12, N_C4, 12, N_D4, 24, N_E4, 24
    db N_C4, 24, N_A3, 24, N_A3, 24, 0, 24
    db $ff

Shapes:
    db 4, 5, 6, 7, 2, 6, 10, 14, 8, 9, 10, 11, 1, 5, 9, 13
    db 1, 2, 5, 6, 1, 2, 5, 6, 1, 2, 5, 6, 1, 2, 5, 6
    db 1, 4, 5, 6, 1, 5, 6, 9, 4, 5, 6, 9, 1, 4, 5, 9
    db 1, 2, 4, 5, 1, 5, 6, 10, 5, 6, 8, 9, 0, 4, 5, 9
    db 0, 1, 5, 6, 2, 5, 6, 9, 4, 5, 9, 10, 1, 4, 5, 8
    db 0, 4, 5, 6, 1, 2, 5, 9, 4, 5, 6, 10, 1, 5, 8, 9
    db 2, 4, 5, 6, 1, 5, 9, 10, 4, 5, 6, 8, 0, 1, 5, 9

    include "lib/font.asm"

Tiles:
    dw `22222223
    dw `22222223
    dw `22222223
    dw `33333333
    dw `22232222
    dw `22232222
    dw `22232222
    dw `33333333

    dw `33333333
    dw `31111113
    dw `31000013
    dw `31000013
    dw `31000013
    dw `31000013
    dw `31111113
    dw `33333333

    dw `33333333
    dw `32222223
    dw `32222223
    dw `32222223
    dw `32222223
    dw `32222223
    dw `32222223
    dw `33333333

    dw `33333333
    dw `31212123
    dw `32121213
    dw `31212123
    dw `32121213
    dw `31212123
    dw `32121213
    dw `33333333

    dw `33333333
    dw `30000003
    dw `30333303
    dw `30300303
    dw `30300303
    dw `30333303
    dw `30000003
    dw `33333333

    dw `33333333
    dw `33333333
    dw `33000033
    dw `33000033
    dw `33000033
    dw `33000033
    dw `33333333
    dw `33333333

    dw `33333333
    dw `31111113
    dw `32222223
    dw `31111113
    dw `32222223
    dw `31111113
    dw `32222223
    dw `33333333

    dw `33333333
    dw `30000003
    dw `30011003
    dw `30122103
    dw `30122103
    dw `30011003
    dw `30000003
    dw `33333333

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333

    dw `33333333
    dw `31111111
    dw `31111111
    dw `31111111
    dw `33333333
    dw `11113111
    dw `11113111
    dw `11113111
TilesEnd:
