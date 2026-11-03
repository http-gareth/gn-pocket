include "lib/hardware.asm"

TILE_ALIEN  equ FIRST_TILE
TILE_BOOM   equ FIRST_TILE + 3
TILE_GROUND equ FIRST_TILE + 4
TILE_CANNON equ FIRST_TILE + 5
TILE_SHOT   equ FIRST_TILE + 7
TILE_BOMB   equ FIRST_TILE + 8
TILE_UFO    equ FIRST_TILE + 9
TILE_WRECK  equ FIRST_TILE + 11
TILE_LIFE   equ FIRST_TILE + 13
TILE_BOSS   equ FIRST_TILE + 14
TILE_BAR    equ FIRST_TILE + 22

STATE_TITLE equ 0
STATE_PLAY  equ 1
STATE_DYING equ 2
STATE_OVER  equ 3
STATE_WAVE  equ 4

LCDC_HUD   equ %11110011
COLS       equ 8
ROWS       equ 5
ALIENS     equ COLS * ROWS
FORM_TOP   equ 2
DROP       equ 2
FORM_SCX   equ 236
STEP       equ 2
EDGE_L     equ 4
EDGE_R     equ 156
PLAYER_Y   equ 112
PLAYER_MIN equ 8
PLAYER_MAX equ 136
GROUND_Y   equ 128
PANEL_Y    equ 64
PANEL      equ $9c00
SHOT_SPEED equ 4
UFO_Y      equ 4
MAX_BOMBS  equ 3
DIE_TIME   equ 90
BOOM_TIME  equ 10
BOSS_EVERY equ 3
BOSS_HP    equ 20
BOSS_Y     equ 24
BOSS_MIN   equ 8
BOSS_MAX   equ 120
BAR        equ $9800 + 6

hState     equ $ff80
hPlayerX   equ $ff81
hShotX     equ $ff82
hShotY     equ $ff83
hDir       equ $ff84
hStepTimer equ $ff85
hAlive     equ $ff86
hAnimFrame equ $ff87
hNote      equ $ff88
hBoomLo    equ $ff89
hBoomHi    equ $ff8a
hBoomTime  equ $ff8b
hScore0    equ $ff8c
hScore1    equ $ff8d
hScore2    equ $ff8e
hHi0       equ $ff8f
hHi1       equ $ff90
hHi2       equ $ff91
hLives     equ $ff92
hTimer     equ $ff93
hUfoX      equ $ff94
hUfoDir    equ $ff95
hWave      equ $ff96
hBoss      equ $ff97
hFrame     equ $ff98
hColL      equ $ff99
hColR      equ $ff9a
hRowB      equ $ff9b
hUfoTimer  equ $ff9c
hNoteTime  equ $ff9d
hTick      equ $ff9e
hBossX     equ $ff9f
hBossDir   equ $ffa6
hBossFlash equ $ffa7
hBombX     equ $ffa0
hBombY     equ $ffa3

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
    db "INVASION"

    org $150
Start:
    di
    ld sp, STACK_TOP
    call LcdOff
    call LoadFont
    ld de, Tiles
    ld hl, $8000 + TILE_BOOM * 16
    ld bc, TilesEnd - Tiles
    call MemCopy
    call Animate
    ld a, PALETTE
    ldh [rBGP], a
    ldh [rOBP0], a
    cpl
    ldh [rOBP1], a
    ld a, 7
    ldh [rWX], a
    call SoundOn
    call MusicStop
    call LoadWave
    call SeedRandom
    xor a
    ldh [hHi0], a
    ldh [hHi1], a
    ldh [hHi2], a
    ldh [hScore0], a
    ldh [hScore1], a
    ldh [hScore2], a
    ldh [hNoteTime], a
    call ShowTitle
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
    call NoteOff
    ld hl, hTick
    inc [hl]
    ldh a, [hState]
    cp STATE_PLAY
    jr z, .play
    cp STATE_DYING
    jr z, .dying
    cp STATE_WAVE
    jr z, .wave
    call WaitStart
    jr MainLoop
.play:
    call Play
    jr MainLoop
.dying:
    call Dying
    jr MainLoop
.wave:
    call WaveWait
    jr MainLoop

ShowTitle:
    call ClearScreen
    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [hState], a
    ldh [hLives], a
    call BuildPanel
    ld a, GROUND_Y
    ldh [rWY], a
    ld hl, $9800 + 32 + 5
    call ShowHi
    ld hl, $9800 + 32 * 3 + 2
    ld de, TitleText
    call PrintText
    ld a, TILE_ALIEN
    ld [$9800 + 32 * 6 + 4], a
    inc a
    ld [$9800 + 32 * 8 + 4], a
    inc a
    ld [$9800 + 32 * 10 + 4], a
    ld a, TILE_UFO
    ld [$9800 + 32 * 12 + 3], a
    inc a
    ld [$9800 + 32 * 12 + 4], a
    ld hl, $9800 + 32 * 6 + 6
    ld de, Points30Text
    call PrintText
    ld hl, $9800 + 32 * 8 + 6
    ld de, Points20Text
    call PrintText
    ld hl, $9800 + 32 * 10 + 6
    ld de, Points10Text
    call PrintText
    ld hl, $9800 + 32 * 12 + 6
    ld de, MysteryText
    call PrintText
    ld hl, $9800 + 32 * 15 + 4
    ld de, PressText
    jp PrintText

BuildPanel:
    ld hl, PANEL
    ld b, 20
    ld a, TILE_GROUND
.ground:
    ld [hl+], a
    dec b
    jr nz, .ground
    ld hl, PANEL + 32
    ld bc, 32 * 8
    ld d, TILE_SPACE
    call MemFill
    ld hl, PANEL + 32
    ld de, HudText
    jp PrintText

ShowHi:
    ld de, HiText
    call PrintText
    ldh a, [hHi2]
    call PrintBCD
    ldh a, [hHi1]
    call PrintBCD
    ldh a, [hHi0]
    jp PrintBCD

WaitStart:
    ldh a, [hState]
    and a
    jr nz, .blink
    ldh a, [hTick]
    and 31
    call z, Animate
.blink:
    call Blink
    ldh a, [hState]
    cp STATE_OVER
    jr nz, .ready
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
    ld hl, SfxRise
    call PlaySweep

NewGame:
    call LcdOff
    xor a
    ldh [hScore0], a
    ldh [hScore1], a
    ldh [hScore2], a
    ldh [hWave], a
    ld a, 3
    ldh [hLives], a
    call BuildPanel
    ld a, GROUND_Y
    ldh [rWY], a
    call NextWave
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ret

Blink:
    ldh a, [hTick]
    and 31
    ret nz
    ldh a, [hTick]
    and 32
    ld de, PressText
    jr z, .show
    ld de, PressBlank
.show:
    ld hl, $9800 + 32 * 15 + 4
    ldh a, [hState]
    and a
    jr z, .print
    ld hl, PANEL + 32 * 5 + 4
.print:
    jp PrintText

NextWave:
    ld hl, hWave
    inc [hl]
    call ClearScreen
    xor a
    ldh [hBoss], a
    ldh [hBossFlash], a
    ldh a, [hWave]
.mod:
    sub BOSS_EVERY
    jr z, BossWave
    jr nc, .mod
    ld hl, $9800 + 32 * FORM_TOP
    ld c, 0
.row:
    ld e, c
    ld d, 0
    push hl
    ld hl, RowTiles
    add hl, de
    ld a, [hl]
    pop hl
    push hl
    ld b, COLS
.col:
    ld [hl+], a
    inc hl
    dec b
    jr nz, .col
    pop hl
    ld de, 64
    add hl, de
    inc c
    ld a, c
    cp ROWS
    jr nz, .row
    ld a, ALIENS
    ldh [hAlive], a
    ld a, FORM_SCX
    ldh [rSCX], a
    ldh a, [hWave]
    dec a
    cp 3
    jr c, .depth
    ld a, 2
.depth:
    add a
    add a
    cpl
    inc a
    ldh [rSCY], a
    call ResetPlay
    jp Bounds

BossWave:
    ld a, 1
    ldh [hBoss], a
    ld a, BOSS_HP
    ldh [hAlive], a
    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [hBossDir], a
    ld a, (BOSS_MIN + BOSS_MAX) / 2
    ldh [hBossX], a
    ld hl, $9800 + 1
    ld de, BossText
    call PrintText
    call DrawBar

ResetPlay:
    xor a
    ldh [hDir], a
    ldh [hShotY], a
    ldh [hUfoX], a
    ldh [hBoomTime], a
    ldh [hBombY], a
    ldh [hBombY + 1], a
    ldh [hBombY + 2], a
    inc a
    ldh [hStepTimer], a
    ld a, 200
    ldh [hUfoTimer], a
    ld a, (PLAYER_MIN + PLAYER_MAX) / 2
    ldh [hPlayerX], a
    ld a, STATE_PLAY
    ldh [hState], a
    ret

DrawBar:
    ld hl, BAR
    ldh a, [hAlive]
    ld b, a
    ld c, BOSS_HP / 2
.cell:
    ld a, b
    cp 2
    ld a, TILE_BAR + 2
    jr nc, .put
    ld a, b
    add TILE_BAR
.put:
    ld [hl+], a
    ld a, b
    sub 2
    jr nc, .left
    xor a
.left:
    ld b, a
    dec c
    jr nz, .cell
    ret

BossMove:
    ld hl, hBossFlash
    ld a, [hl]
    and a
    jr z, .move
    dec [hl]
.move:
    ldh a, [hAlive]
    cp BOSS_HP / 2
    ld c, 1
    jr nc, .speed
    inc c
.speed:
    ldh a, [hBossDir]
    and a
    ldh a, [hBossX]
    jr nz, .left
    add c
    cp BOSS_MAX
    jr c, .store
    ld a, BOSS_MAX
    jr .turn
.left:
    sub c
    cp BOSS_MIN
    jr nc, .store
    ld a, BOSS_MIN
.turn:
    ld b, a
    ldh a, [hBossDir]
    xor 1
    ldh [hBossDir], a
    ld a, b
.store:
    ldh [hBossX], a
    ret

HitBoss:
    ldh a, [hShotY]
    cp BOSS_Y + 16
    ret nc
    ldh a, [hBossX]
    ld b, a
    ldh a, [hShotX]
    sub b
    cp 32
    ret nc
    xor a
    ldh [hShotY], a
    ld a, 8
    ldh [hBossFlash], a
    ld de, $0010
    call AddScore
    ld hl, hAlive
    dec [hl]
    call DrawBar
    ldh a, [hAlive]
    and a
    jr z, .destroyed
    ld hl, SfxKick
    jp PlayNoise
.destroyed:
    ld de, $1000
    call AddScore
    ldh a, [hBossX]
    srl a
    srl a
    srl a
    add low($9800 + 32 * (BOSS_Y / 8))
    ld l, a
    ld h, high($9800 + 32 * (BOSS_Y / 8))
    ld a, TILE_BOOM
    ld b, 4
.boom:
    ld [hl+], a
    dec b
    jr nz, .boom
    ld hl, SfxCrash
    call PlayNoise
    ld hl, SfxRise
    jp PlaySweep

BossBomb:
    ld hl, hBombY
    ld b, MAX_BOMBS
.find:
    ld a, [hl]
    and a
    jr z, .slot
    inc l
    dec b
    jr nz, .find
    ret
.slot:
    ld [hl], BOSS_Y + 14
    ld a, l
    sub MAX_BOMBS
    ld l, a
    call Random
    and 15
    add 8
    ld b, a
    ldh a, [hBossX]
    add b
    ld [hl], a
    ret

Play:
    call MovePlayer
    call Fire
    call MoveShot
    call Boom
    ldh a, [hBoss]
    and a
    jr nz, .boss
    call Ufo
    call March
    jr .bombs
.boss:
    call BossMove
.bombs:
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    call Bombs
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    ldh a, [hAlive]
    and a
    ret nz
    ld a, STATE_WAVE
    ldh [hState], a
    ld a, 60
    ldh [hTimer], a
    ld hl, SfxDing
    jp PlayTone

WaveWait:
    call Boom
    ld hl, hTimer
    dec [hl]
    ret nz
    call LcdOff
    call NextWave
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ret

MovePlayer:
    ldh a, [hJoyHeld]
    ld b, a
    ldh a, [hTick]
    and 1
    inc a
    ld c, a
    ldh a, [hPlayerX]
    bit PADB_LEFT, b
    jr z, .right
    sub c
    cp PLAYER_MIN
    jr nc, .store
    ld a, PLAYER_MIN
    jr .store
.right:
    bit PADB_RIGHT, b
    ret z
    add c
    cp PLAYER_MAX + 1
    jr c, .store
    ld a, PLAYER_MAX
.store:
    ldh [hPlayerX], a
    ret

Fire:
    ldh a, [hShotY]
    and a
    ret nz
    ldh a, [hJoyPressed]
    and PAD_A | PAD_B | PAD_UP
    ret z
    ldh a, [hPlayerX]
    add 7
    ldh [hShotX], a
    ld a, PLAYER_Y - 6
    ldh [hShotY], a
    ld hl, SfxShoot
    jp PlaySweep

MoveShot:
    ldh a, [hShotY]
    and a
    ret z
    sub SHOT_SPEED
    jr c, .gone
    cp 8
    jr c, .gone
    ldh [hShotY], a
    ldh a, [hBoss]
    and a
    jp nz, HitBoss
    call HitUfo
    ret c
    ldh a, [hShotX]
    ld d, a
    ldh a, [hShotY]
    ld e, a
    call AlienAt
    ret nc
    ld b, a
    push hl
    push bc
    call ClearBoom
    pop bc
    pop hl
    ld [hl], TILE_BOOM
    ld a, l
    ldh [hBoomLo], a
    ld a, h
    ldh [hBoomHi], a
    ld a, BOOM_TIME
    ldh [hBoomTime], a
    ld e, b
    ld d, 0
    ld hl, AlienPoints
    add hl, de
    ld e, [hl]
    call AddScore
    ld hl, hAlive
    dec [hl]
    call Bounds
    ld hl, SfxKick
    call PlayNoise
.gone:
    xor a
    ldh [hShotY], a
    ret

AlienAt:
    ldh a, [rSCY]
    add e
    and $f8
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ldh a, [rSCX]
    add d
    srl a
    srl a
    srl a
    or l
    ld l, a
    ld a, h
    add high($9800)
    ld h, a
    ld a, [hl]
    sub TILE_ALIEN
    cp 3
    ret

HitUfo:
    ldh a, [hUfoX]
    and a
    ret z
    ldh a, [hShotY]
    cp UFO_Y + 8
    ret nc
    ldh a, [hUfoX]
    sub 8
    ld b, a
    ldh a, [hShotX]
    sub b
    cp 16
    ret nc
    xor a
    ldh [hUfoX], a
    ldh [hShotY], a
    ld a, 200
    ldh [hUfoTimer], a
    call Random
    and 3
    add a
    add low(UfoPoints)
    ld l, a
    ld a, high(UfoPoints)
    adc 0
    ld h, a
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    call AddScore
    ld hl, SfxRise
    call PlaySweep
    scf
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

ClearBoom:
    ldh a, [hBoomTime]
    and a
    ret z
    xor a
    ldh [hBoomTime], a
    jr EraseBoom

Boom:
    ldh a, [hBoomTime]
    and a
    ret z
    dec a
    ldh [hBoomTime], a
    ret nz

EraseBoom:
    ldh a, [hBoomLo]
    ld l, a
    ldh a, [hBoomHi]
    ld h, a
    ld [hl], TILE_SPACE
    ret

ColumnAlive:
    ld hl, $9800 + 32 * FORM_TOP
    ld a, c
    add a
    add l
    ld l, a
    ld b, ROWS
.row:
    ld a, [hl]
    sub TILE_ALIEN
    cp 3
    jr c, .yes
    ld a, l
    add 64
    ld l, a
    jr nc, .next
    inc h
.next:
    dec b
    jr nz, .row
    xor a
    ret
.yes:
    or 1
    ret

RowAddr:
    ld a, c
    add a
    add FORM_TOP
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, h
    add high($9800)
    ld h, a
    ret

RowAlive:
    call RowAddr
    ld b, COLS
.col:
    ld a, [hl]
    sub TILE_ALIEN
    cp 3
    jr c, .yes
    inc hl
    inc hl
    dec b
    jr nz, .col
    xor a
    ret
.yes:
    or 1
    ret

Bounds:
    ld c, 0
.left:
    call ColumnAlive
    jr nz, .foundLeft
    inc c
    ld a, c
    cp COLS
    jr nz, .left
    ret
.foundLeft:
    ld a, c
    ldh [hColL], a
    ld c, COLS - 1
.right:
    call ColumnAlive
    jr nz, .foundRight
    dec c
    jr .right
.foundRight:
    ld a, c
    ldh [hColR], a
    ld c, ROWS - 1
.bottom:
    call RowAlive
    jr nz, .foundBottom
    dec c
    jr .bottom
.foundBottom:
    ld a, c
    ldh [hRowB], a
    ret

ColumnBottom:
    ld b, ROWS - 1
.row:
    push bc
    ld a, c
    ld c, b
    ld b, a
    call RowAddr
    ld a, b
    add a
    add l
    ld l, a
    pop bc
    ld a, [hl]
    sub TILE_ALIEN
    cp 3
    jr c, .found
    dec b
    bit 7, b
    jr z, .row
    and a
    ret
.found:
    ld a, b
    scf
    ret

March:
    ld hl, hStepTimer
    dec [hl]
    ret nz
    ldh a, [hAlive]
    srl a
    inc a
    ld [hl], a
    call Animate
    call MarchNote
    ldh a, [hDir]
    and a
    jr nz, .left
    ldh a, [hColR]
    swap a
    add 8 + STEP
    ld b, a
    ldh a, [rSCX]
    ld c, a
    ld a, b
    sub c
    cp EDGE_R + 1
    jr nc, .drop
    ldh a, [rSCX]
    sub STEP
    ldh [rSCX], a
    ret
.left:
    ldh a, [hColL]
    swap a
    ld b, a
    ldh a, [rSCX]
    ld c, a
    ld a, b
    sub c
    cp EDGE_L + STEP
    jr c, .drop
    ldh a, [rSCX]
    add STEP
    ldh [rSCX], a
    ret
.drop:
    ldh a, [hDir]
    xor 1
    ldh [hDir], a
    ldh a, [rSCY]
    sub DROP
    ldh [rSCY], a
    ldh a, [hRowB]
    add a
    add FORM_TOP + 1
    add a
    add a
    add a
    ld b, a
    ldh a, [rSCY]
    ld c, a
    ld a, b
    sub c
    cp PLAYER_Y
    ret c
    xor a
    ldh [hLives], a
    jp GameOver

Animate:
    ldh a, [hAnimFrame]
    xor 1
    ldh [hAnimFrame], a
    ld de, AlienFrames
    jr z, .copy
    ld de, AlienFrames + 48
.copy:
    ld hl, $8000 + TILE_ALIEN * 16
    ld bc, 48
    jp MemCopy

MarchNote:
    ldh a, [hNote]
    inc a
    and 3
    ldh [hNote], a
    add low(MarchNotes)
    ld l, a
    ld a, high(MarchNotes)
    adc 0
    ld h, a
    ld a, [hl]
    call PlayNote
    ld a, 6
    ldh [hNoteTime], a
    ret

NoteOff:
    ldh a, [hNoteTime]
    and a
    ret z
    dec a
    ldh [hNoteTime], a
    ret nz
    ldh [rNR32], a
    ret

Bombs:
    ldh a, [hBoss]
    and a
    jr z, .formation
    call Random
    and 31
    ld b, a
    ldh a, [hAlive]
    cp BOSS_HP / 2
    ld a, 1
    jr nc, .rate
    ld a, 3
.rate:
    cp b
    call nc, BossBomb
    jr .move
.formation:
    call Random
    and 127
    ld b, a
    ldh a, [hWave]
    inc a
    cp b
    call nc, SpawnBomb
.move:
    ld c, 0
.loop:
    ld a, c
    add low(hBombY)
    ld l, a
    ld h, $ff
    ld a, [hl]
    and a
    jr z, .next
    inc a
    ld b, a
    ldh a, [hWave]
    cp 3
    ld a, 0
    jr c, .slow
    ldh a, [hTick]
    and 1
.slow:
    add b
    cp GROUND_Y - 6
    jr c, .falling
    xor a
.falling:
    ld [hl], a
    cp PLAYER_Y - 6
    jr c, .next
    cp PLAYER_Y + 8
    jr nc, .next
    ld a, l
    sub MAX_BOMBS
    ld l, a
    ldh a, [hPlayerX]
    ld b, a
    ld a, [hl]
    sub b
    cp 15
    jr c, PlayerHit
.next:
    inc c
    ld a, c
    cp MAX_BOMBS
    jr nz, .loop
    ret

PlayerHit:
    ld a, 25
    ldh [rRUMBLE], a
    ld a, STATE_DYING
    ldh [hState], a
    ld a, DIE_TIME
    ldh [hTimer], a
    xor a
    ldh [hBombY], a
    ldh [hBombY + 1], a
    ldh [hBombY + 2], a
    ldh [hShotY], a
    ld hl, hLives
    dec [hl]
    ld hl, SfxCrash
    jp PlayNoise

SpawnBomb:
    ld hl, hBombY
    ld b, MAX_BOMBS
.find:
    ld a, [hl]
    and a
    jr z, .slot
    inc l
    dec b
    jr nz, .find
    ret
.slot:
    push hl
    call Random
    and COLS - 1
    ld c, a
    call ColumnBottom
    pop hl
    ret nc
    add a
    add FORM_TOP + 1
    add a
    add a
    add a
    ld b, a
    ldh a, [rSCY]
    ld d, a
    ld a, b
    sub d
    ld [hl], a
    ld a, l
    sub MAX_BOMBS
    ld l, a
    ld a, c
    swap a
    ld b, a
    ldh a, [rSCX]
    ld d, a
    ld a, b
    sub d
    add 3
    ld [hl], a
    ret

Ufo:
    ldh a, [hUfoX]
    and a
    jr nz, .fly
    ldh a, [hTick]
    and 3
    ret nz
    ld hl, hUfoTimer
    dec [hl]
    ret nz
    call Random
    and 1
    ldh [hUfoDir], a
    ld a, 1
    jr z, .spawn
    ld a, 167
.spawn:
    ldh [hUfoX], a
    ret
.fly:
    ldh a, [hTick]
    and 1
    ret nz
    ldh a, [hUfoDir]
    and a
    ldh a, [hUfoX]
    jr nz, .left
    inc a
    cp 168
    jr c, .store
    xor a
    jr .store
.left:
    dec a
.store:
    ldh [hUfoX], a
    and a
    ret nz
    ld a, 200
    ldh [hUfoTimer], a
    ret

Dying:
    call Boom
    ld hl, hTimer
    dec [hl]
    ret nz
    ldh a, [hLives]
    and a
    jr z, GameOver
    ld a, STATE_PLAY
    ldh [hState], a
    ret

GameOver:
    ld a, STATE_OVER
    ldh [hState], a
    ld a, 40
    ldh [hTimer], a
    xor a
    ldh [rNR32], a
    ld hl, SfxFall
    call PlaySweep
    ldh a, [hHi2]
    ld b, a
    ldh a, [hScore2]
    cp b
    jr c, .text
    jr nz, .best
    ldh a, [hHi1]
    ld b, a
    ldh a, [hScore1]
    cp b
    jr c, .text
    jr nz, .best
    ldh a, [hHi0]
    ld b, a
    ldh a, [hScore0]
    cp b
    jr c, .text
.best:
    ldh a, [hScore0]
    ldh [hHi0], a
    ldh a, [hScore1]
    ldh [hHi1], a
    ldh a, [hScore2]
    ldh [hHi2], a
.text:
    ld hl, PANEL + 32 * 3 + 5
    ld de, GameOverText
    call PrintText
    ld hl, PANEL + 32 * 5 + 4
    ld de, PressText
    call PrintText
    ld hl, PANEL + 32 * 7 + 5
    jp ShowHi

Draw:
    ldh a, [rLCDC]
    or 2
    ldh [rLCDC], a
    ld hl, PANEL + 32 + 6
    ldh a, [hScore2]
    call PrintBCD
    ldh a, [hScore1]
    call PrintBCD
    ldh a, [hScore0]
    call PrintBCD
    ld hl, PANEL + 32 + 15
    ldh a, [hLives]
    ld b, a
    ld c, 3
.life:
    ld a, b
    and a
    ld a, TILE_SPACE
    jr z, .put
    dec b
    ld a, TILE_LIFE
.put:
    ld [hl+], a
    dec c
    jr nz, .life

    ldh a, [hState]
    cp STATE_OVER
    jr nz, .lyc
    ldh a, [rWY]
    cp PANEL_Y
    jr z, .lyc
    sub 8
    ldh [rWY], a
.lyc:
    ldh a, [rWY]
    ldh [rLYC], a

    ld hl, $fe00
    ldh a, [hState]
    and a
    jp z, .hide
    cp STATE_OVER
    jp z, .hide
    ld c, TILE_CANNON
    cp STATE_DYING
    jr nz, .cannon
    ld c, TILE_WRECK
.cannon:
    ldh a, [hPlayerX]
    add 8
    ld b, a
    ld a, PLAYER_Y + 16
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld a, c
    ld [hl+], a
    xor a
    ld [hl+], a
    ld a, PLAYER_Y + 16
    ld [hl+], a
    ld a, b
    add 8
    ld [hl+], a
    ld a, c
    inc a
    ld [hl+], a
    xor a
    ld [hl+], a

    ldh a, [hShotY]
    and a
    jr z, .noShot
    add 16
.noShot:
    ld [hl+], a
    ldh a, [hShotX]
    add 8 - 3
    ld [hl+], a
    ld a, TILE_SHOT
    ld [hl+], a
    xor a
    ld [hl+], a

    ld c, 0
.bomb:
    ld a, c
    add low(hBombY)
    ld e, a
    ld d, $ff
    ld a, [de]
    and a
    jr z, .noBomb
    add 16
.noBomb:
    ld [hl+], a
    ld a, e
    sub MAX_BOMBS
    ld e, a
    ld a, [de]
    add 8 - 3
    ld [hl+], a
    ld a, TILE_BOMB
    ld [hl+], a
    xor a
    ld [hl+], a
    inc c
    ld a, c
    cp MAX_BOMBS
    jr nz, .bomb

    ldh a, [hUfoX]
    ld b, a
    and a
    ld a, UFO_Y + 16
    jr nz, .ufo
    xor a
.ufo:
    ld c, a
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld a, TILE_UFO
    ld [hl+], a
    xor a
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, b
    add 8
    ld [hl+], a
    ld a, TILE_UFO + 1
    ld [hl+], a
    xor a
    ld [hl+], a

    ldh a, [hBoss]
    and a
    jr z, .noBoss
    ldh a, [hAlive]
    and a
    jr z, .noBoss
    ldh a, [hBossFlash]
    and 2
    jr z, .attr
    ld a, $10
.attr:
    ld e, a
    ldh a, [hBossX]
    add 8
    ld d, a
    ld c, TILE_BOSS
    ld b, BOSS_Y + 16
    call BossRow
    ld b, BOSS_Y + 24
    jp BossRow
.noBoss:
    xor a
    ld b, 8 * 4
.clearBoss:
    ld [hl+], a
    dec b
    jr nz, .clearBoss
    ret
.hide:
    xor a
    ld b, 16 * 4
.clear:
    ld [hl+], a
    dec b
    jr nz, .clear
    ret

BossRow:
    push de
    ld a, 4
.sprite:
    push af
    ld a, b
    ld [hl+], a
    ld a, d
    ld [hl+], a
    add 8
    ld d, a
    ld a, c
    ld [hl+], a
    inc c
    ld a, e
    ld [hl+], a
    pop af
    dec a
    jr nz, .sprite
    pop de
    ret

    include "lib/util.asm"
    include "lib/sound.asm"
    include "lib/music.asm"

SfxShoot:
    db $1b, $80, $a1, low(1950), $80 | high(1950)

RowTiles:
    db TILE_ALIEN, TILE_ALIEN + 1, TILE_ALIEN + 1, TILE_ALIEN + 2, TILE_ALIEN + 2

AlienPoints:
    db $30, $20, $10

UfoPoints:
    dw $0050, $0100, $0150, $0300

MarchNotes:
    db N_C3, N_AS2, N_GS2, N_G2

TitleText:
    db "I N V A S I O N", 0
Points30Text:
    db "= 30 POINTS", 0
Points20Text:
    db "= 20 POINTS", 0
Points10Text:
    db "= 10 POINTS", 0
MysteryText:
    db "= MYSTERY", 0
PressText:
    db "PRESS START", 0
PressBlank:
    db "           ", 0
HudText:
    db "SCORE", 0
HiText:
    db "HI ", 0
GameOverText:
    db "GAME OVER", 0
BossText:
    db "BOSS", 0

    include "lib/font.asm"

AlienFrames:
    dw `00033000
    dw `00333300
    dw `03333330
    dw `33033033
    dw `03333330
    dw `00300300
    dw `03000030
    dw `00300300

    dw `03000030
    dw `00300300
    dw `03333330
    dw `33033033
    dw `33333333
    dw `30333303
    dw `30300303
    dw `00033000

    dw `00333300
    dw `03333330
    dw `33333333
    dw `33033033
    dw `33333333
    dw `00300300
    dw `03033030
    dw `30300303

    dw `00033000
    dw `00333300
    dw `03333330
    dw `33033033
    dw `03333330
    dw `03033030
    dw `30000003
    dw `03000030

    dw `03000030
    dw `30300303
    dw `33333333
    dw `33033033
    dw `33333333
    dw `03333330
    dw `00300300
    dw `03000030

    dw `00333300
    dw `03333330
    dw `33333333
    dw `33033033
    dw `33333333
    dw `03033030
    dw `30000003
    dw `03000030

Tiles:
    dw `30030030
    dw `03030300
    dw `00000000
    dw `33000330
    dw `00000000
    dw `03030300
    dw `30030030
    dw `00000000

    dw `33333333
    dw `22222222
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000003
    dw `00000033
    dw `00000033
    dw `03333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333

    dw `30000000
    dw `33000000
    dw `33000000
    dw `33333330
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333

    dw `00030000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `00000000
    dw `00000000

    dw `00030000
    dw `00003000
    dw `00030000
    dw `00003000
    dw `00030000
    dw `00003000
    dw `00030000
    dw `00000000

    dw `00000333
    dw `00033333
    dw `00333333
    dw `03303303
    dw `33333333
    dw `00333003
    dw `00030000
    dw `00000000

    dw `33300000
    dw `33333000
    dw `33333300
    dw `30330330
    dw `33333333
    dw `30033300
    dw `00003000
    dw `00000000

    dw `00300000
    dw `30003000
    dw `00300030
    dw `03030300
    dw `00333330
    dw `03333333
    dw `33333333
    dw `00000000

    dw `00000300
    dw `00030003
    dw `03000300
    dw `00303030
    dw `03333300
    dw `33333330
    dw `33333333
    dw `00000000

    dw `00000000
    dw `00033000
    dw `00033000
    dw `03333330
    dw `33333333
    dw `33333333
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000033
    dw `00003333
    dw `00333333
    dw `03322333
    dw `33322333

    dw `00003333
    dw `00331111
    dw `33111111
    dw `11111111
    dw `33333333
    dw `33333333
    dw `22332223
    dw `22332223

    dw `33330000
    dw `11113300
    dw `11111133
    dw `11111111
    dw `33333333
    dw `33333333
    dw `33223332
    dw `33223332

    dw `00000000
    dw `00000000
    dw `00000000
    dw `33000000
    dw `33330000
    dw `33333300
    dw `23322330
    dw `23322333

    dw `33333333
    dw `03333333
    dw `00333300
    dw `00033000
    dw `00030000
    dw `00300000
    dw `00000000
    dw `00000000

    dw `33333333
    dw `33333333
    dw `00333300
    dw `00033000
    dw `00030000
    dw `00300000
    dw `00000000
    dw `00000000

    dw `33333333
    dw `33333333
    dw `00333300
    dw `00033000
    dw `00003000
    dw `00000300
    dw `00000000
    dw `00000000

    dw `33333333
    dw `33333330
    dw `00333300
    dw `00033000
    dw `00003000
    dw `00000300
    dw `00000000
    dw `00000000

    dw `33333333
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `00000000
    dw `00000000

    dw `33333333
    dw `22220000
    dw `22220000
    dw `22220000
    dw `22220000
    dw `33333333
    dw `00000000
    dw `00000000

    dw `33333333
    dw `22222222
    dw `22222222
    dw `22222222
    dw `22222222
    dw `33333333
    dw `00000000
    dw `00000000
TilesEnd:
