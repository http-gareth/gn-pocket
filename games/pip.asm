include "lib/hardware.asm"

TILE_GRASS    equ FIRST_TILE
TILE_DIRT     equ FIRST_TILE + 1
TILE_BRICK    equ FIRST_TILE + 2
TILE_QUESTION equ FIRST_TILE + 3
SOLID_TILES   equ 11
TILE_COIN     equ FIRST_TILE + 11
TILE_POLE     equ FIRST_TILE + 16
TILE_FLAGTOP  equ FIRST_TILE + 17
TILE_LAVA     equ FIRST_TILE + 18
TILE_HERO     equ FIRST_TILE + 20
FRAME_WALK    equ 4
FRAME_JUMP    equ 12
FRAME_DEAD    equ 16
TILE_GRUB     equ FIRST_TILE + 40
TILE_SQUISH   equ TILE_GRUB + 4
TILE_BOSS     equ FIRST_TILE + 45
TILE_FIRE     equ FIRST_TILE + 51
TILE_LIFE     equ FIRST_TILE + 52
TILE_COINICON equ FIRST_TILE + 53
TILE_HEART    equ FIRST_TILE + 54

STATE_TITLE equ 0
STATE_INTRO equ 1
STATE_PLAY  equ 2
STATE_DYING equ 3
STATE_CLEAR equ 4
STATE_OVER  equ 5
STATE_WIN   equ 6

LCDC_HUD   equ %11110011
HUD_Y      equ 136
HUD        equ $9c00
LEVEL_W    equ 128
LEVEL_H    equ 17
LEVELS     equ 3
CASTLE     equ LEVELS - 1
MAX_CAM    equ LEVEL_W * 8 - 160
HERO_MAX_X equ LEVEL_W * 8 - 16
START_X    equ 24
FLOOR_Y    equ 104
CAM_LEAD   equ 64

WALK_MAX   equ 24
RUN_MAX    equ 40
ACCEL      equ 1
FRICTION   equ 2
SKID       equ 3
JUMP_V     equ 72
RUN_JUMP_V equ 80
GRAV_HOLD  equ 4
GRAV       equ 12
MAX_FALL   equ 64
BOUNCE_V   equ 56

ENEMIES    equ 4
ENEMY_SIZE equ 8

BOSS_HP    equ 3
BOSS_Y     equ 96
BOSS_LEFT  equ MAX_CAM + 16
BOSS_RIGHT equ LEVEL_W * 8 - 8 - 24 - 4
BOSS_INV   equ 60
FIRE_EVERY equ 150
LIVES      equ 5

wLevel   equ $c000
wEnemies equ $c900

hState    equ $ff80
hLevel    equ $ff81
hLives    equ $ff82
hCoins    equ $ff83
hScore0   equ $ff84
hScore1   equ $ff85
hScore2   equ $ff86
hTop0     equ $ff87
hTop1     equ $ff88
hTop2     equ $ff89
hTimer    equ $ff8a
hXL       equ $ff8b
hXH       equ $ff8c
hYL       equ $ff8d
hYH       equ $ff8e
hVX       equ $ff8f
hVY       equ $ff90
hGround   equ $ff91
hFacing   equ $ff92
hAnim     equ $ff93
hCamL     equ $ff94
hCamH     equ $ff95
hNextCol  equ $ff96
hPopXL    equ $ff97
hPopXH    equ $ff98
hPopY     equ $ff99
hPopT     equ $ff9a
hBossHP   equ $ff9b
hBossXL   equ $ff9c
hBossXH   equ $ff9d
hBossY    equ $ff9e
hBossDir  equ $ff9f
hBossVY   equ $ffa0
hBossInv  equ $ffa1
hBossOn   equ $ffa2
hFireXL   equ $ffa3
hFireXH   equ $ffa4
hFireY    equ $ffa5
hFireDir  equ $ffa6
hFireOn   equ $ffa7
hFrame    equ $ffa8
hTick     equ $ffa9
hPXL      equ $ffaa
hPXH      equ $ffab
hPY       equ $ffac
hBossTime equ $ffad
hTmp      equ $ffae
hCol      equ $ffaf
hEState   equ $ffb0
hEXL      equ $ffb1
hEXH      equ $ffb2
hEY       equ $ffb3
hEDir     equ $ffb4
hETimer   equ $ffb5
hCheck    equ $ffb8

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
    db "PIP QUEST"

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
    cpl
    ldh [rOBP1], a
    ld a, HUD_Y
    ldh [rWY], a
    ldh [rLYC], a
    ld a, 7
    ldh [rWX], a
    call SoundOn
    call MusicStop
    call SeedRandom
    xor a
    ldh [hTop0], a
    ldh [hTop1], a
    ldh [hTop2], a
    call ResetRun
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
    call MusicTick
    ld hl, hTick
    inc [hl]
    ldh a, [hState]
    cp STATE_PLAY
    jr z, .play
    cp STATE_DYING
    jr z, .dying
    cp STATE_CLEAR
    jr z, .clear
    cp STATE_INTRO
    jr z, .intro
    and a
    jr z, .title
    call Ending
    jr MainLoop
.play:
    call Play
    jr MainLoop
.dying:
    call Dying
    jr MainLoop
.clear:
    call Clear
    jr MainLoop
.intro:
    call Intro
    jr MainLoop
.title:
    call Title
    jr MainLoop

ResetRun:
    xor a
    ldh [hScore0], a
    ldh [hScore1], a
    ldh [hScore2], a
    ldh [hCoins], a
    ldh [hLevel], a
    ldh [hCheck], a
    ld a, LIVES
    ldh [hLives], a
    ret

ShowTitle:
    xor a
    ldh [hLevel], a
    ldh [hCheck], a
    call LoadLevel
    xor a
    ldh [hState], a
    call MusicStop
    ld hl, $9800 + 32 * 3 + 1
    ld de, TitleText
    call PrintText
    ld hl, $9800 + 32 * 5 + 1
    ld de, SubtitleText
    call PrintText
    ld hl, $9800 + 32 * 9 + 5
    ld de, TopText
    call PrintText
    ldh a, [hTop2]
    call PrintBCD
    ldh a, [hTop1]
    call PrintBCD
    ldh a, [hTop0]
    jp PrintBCD

Title:
    ldh a, [hTick]
    and 31
    jr nz, .input
    ldh a, [hTick]
    and 32
    ld de, PressText
    jr z, .show
    ld de, PressBlank
.show:
    ld hl, $9800 + 32 * 7 + 4
    call PrintText
.input:
    ldh a, [hJoyPressed]
    and PAD_START | PAD_A
    ret z
    ld hl, SfxRise
    call PlaySweep
    call ResetRun

ShowIntro:
    call LcdOff
    call ClearScreen
    call MusicStop
    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [hBossOn], a
    ldh [hFireOn], a
    ldh [hPopT], a
    call DrawHud
    ld hl, $9800 + 32 * 6 + 5
    ld de, WorldText
    call PrintText
    ldh a, [hLevel]
    add '1' - 32
    ld [hl], a
    ld a, TILE_LIFE
    ld [$9800 + 32 * 9 + 7], a
    ld hl, $9800 + 32 * 9 + 9
    ld de, TimesText
    call PrintText
    ldh a, [hLives]
    add '0' - 32
    ld [hl], a
    ldh a, [hLevel]
    cp CASTLE
    jr nz, .plain
    ld hl, $9800 + 32 * 12 + 1
    ld de, CastleText
    call PrintText
.plain:
    ld a, 100
    ldh [hTimer], a
    ld a, STATE_INTRO
    ldh [hState], a
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ret

Intro:
    ld hl, hTimer
    dec [hl]
    ret nz
    call LcdOff
    call LoadLevel
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ld hl, OverworldTheme
    ldh a, [hLevel]
    cp CASTLE
    jr nz, .music
    ld hl, CastleTheme
.music:
    jp MusicPlay

LoadLevel:
    ldh a, [hLevel]
    add a
    add low(LevelTable)
    ld l, a
    ld a, high(LevelTable)
    adc 0
    ld h, a
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ld hl, wLevel
    ld bc, LEVEL_W * LEVEL_H
    call MemCopy
    ld hl, wEnemies
    ld bc, ENEMIES * ENEMY_SIZE
    ld d, 0
    call MemFill
    call ClearScreen
    xor a
    ldh [hCamL], a
    ldh [hCamH], a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [hNextCol], a
    ldh [hVX], a
    ldh [hVY], a
    ldh [hFacing], a
    ldh [hBossOn], a
    ldh [hFireOn], a
    ldh [hPopT], a
    ldh [hYL], a
    ld a, low(START_X << 4)
    ldh [hXL], a
    ld a, high(START_X << 4)
    ldh [hXH], a
    ldh a, [hCheck]
    and a
    jr z, .fresh
    call CheckX
    ld h, d
    ld l, e
    call Shl4
    ld a, l
    ldh [hXL], a
    ld a, h
    ldh [hXH], a
    ld a, e
    sub CAM_LEAD
    ld e, a
    ld a, d
    sbc 0
    ld d, a
    ld a, e
    ldh [hCamL], a
    ldh [rSCX], a
    ld a, d
    ldh [hCamH], a
    ld a, e
    srl d
    rra
    srl d
    rra
    srl d
    rra
    ldh [hNextCol], a
.fresh:
    ld a, FLOOR_Y >> 4
    ldh [hYH], a
    ld a, (FLOOR_Y & 15) << 4
    ldh [hYL], a
    ld a, 1
    ldh [hGround], a
    call HeroPixels
    call StreamColumns
    call DrawHud
    ld a, STATE_PLAY
    ldh [hState], a
    ret

DrawHud:
    ld hl, HUD
    ld bc, 32
    ld d, TILE_SPACE
    call MemFill
    ld a, TILE_LIFE
    ld [HUD], a
    ld a, TILE_COINICON
    ld [HUD + 4], a
    ld hl, HUD + 8
    ld de, LevelName
    call PrintText
    ldh a, [hLevel]
    add '1' - 32
    ld [hl], a
    ret

Play:
    call HeroInput
    call Gravity
    call MoveX
    call MoveY
    call Camera
    call Pickups
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    call Checkpoint
    call Enemies
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    call Boss
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    call Fireball
    call CoinPop
    ld hl, hAnim
    ldh a, [hVX]
    bit 7, a
    jr z, .speed
    cpl
    inc a
.speed:
    add [hl]
    ld [hl], a
    ret

HeroInput:
    ldh a, [hJoyPressed]
    bit PADB_A, a
    jr z, .run
    ldh a, [hGround]
    and a
    jr z, .run
    ld c, 256 - JUMP_V
    ldh a, [hVX]
    bit 7, a
    jr z, .fast
    cpl
    inc a
.fast:
    cp WALK_MAX + 4
    jr c, .jump
    ld c, 256 - RUN_JUMP_V
.jump:
    ld a, c
    ldh [hVY], a
    xor a
    ldh [hGround], a
    ld hl, SfxFlap
    call PlaySweep
.run:
    ldh a, [hJoyHeld]
    ld b, a
    ld c, WALK_MAX
    bit PADB_B, b
    jr z, .direction
    ld c, RUN_MAX
.direction:
    bit PADB_RIGHT, b
    jr nz, .right
    bit PADB_LEFT, b
    jr nz, .left
    ldh a, [hGround]
    and a
    ret z
    ldh a, [hVX]
    bit 7, a
    jr nz, .slowLeft
    sub FRICTION
    jr nc, .store
    xor a
    jr .store
.slowLeft:
    add FRICTION
    jr nc, .store
    xor a
    jr .store
.right:
    xor a
    ldh [hFacing], a
    ldh a, [hVX]
    bit 7, a
    jr z, .speedRight
    add SKID
    jr .store
.speedRight:
    add ACCEL
    cp c
    jr c, .store
    ld a, c
    jr .store
.left:
    ld a, $20
    ldh [hFacing], a
    ldh a, [hVX]
    and a
    jr z, .speedLeft
    bit 7, a
    jr nz, .speedLeft
    sub SKID
    jr .store
.speedLeft:
    sub ACCEL
    ld d, a
    cpl
    inc a
    cp c
    ld a, d
    jr c, .store
    jr z, .store
    ld a, c
    cpl
    inc a
.store:
    ldh [hVX], a
    ret

Gravity:
    ld c, GRAV
    ldh a, [hVY]
    bit 7, a
    jr z, .apply
    ldh a, [hJoyHeld]
    bit PADB_A, a
    ldh a, [hVY]
    jr z, .apply
    ld c, GRAV_HOLD
.apply:
    add c
    bit 7, a
    jr nz, .store
    cp MAX_FALL
    jr c, .store
    ld a, MAX_FALL
.store:
    ldh [hVY], a
    ret

HeroPixels:
    ldh a, [hXL]
    ld l, a
    ldh a, [hXH]
    ld h, a
    call Shr4
    ld a, l
    ldh [hPXL], a
    ld a, h
    ldh [hPXH], a
    ldh a, [hYL]
    ld l, a
    ldh a, [hYH]
    ld h, a
    call Shr4
    ld a, l
    ldh [hPY], a
    ret

Shr4:
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ret

Shl4:
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ret

MoveX:
    ldh a, [hVX]
    and a
    jp z, .clamp
    ld e, a
    ld d, 0
    bit 7, a
    jr z, .add
    dec d
.add:
    ldh a, [hXL]
    add e
    ld l, a
    ldh a, [hXH]
    adc d
    ld h, a
    push hl
    call Shr4
    ld bc, 13
    ldh a, [hVX]
    bit 7, a
    jr z, .edge
    ld bc, 2
.edge:
    add hl, bc
    ld d, h
    ld e, l
    ldh a, [hPY]
    inc a
    ld c, a
    call SolidAt
    jr c, .blocked
    ldh a, [hPY]
    add 8
    ld c, a
    call SolidAt
    jr c, .blocked
    ldh a, [hPY]
    add 14
    ld c, a
    call SolidAt
    jr c, .blocked
    pop hl
    jr .store
.blocked:
    pop hl
    ld a, e
    and $f8
    ld e, a
    ldh a, [hVX]
    bit 7, a
    jr nz, .snapLeft
    ld a, e
    sub 14
    ld l, a
    ld a, d
    sbc 0
    ld h, a
    jr .snap
.snapLeft:
    ld hl, 6
    add hl, de
.snap:
    call Shl4
    xor a
    ldh [hVX], a
.store:
    ld a, l
    ldh [hXL], a
    ld a, h
    ldh [hXH], a
    call HeroPixels
.clamp:
    ldh a, [hCamL]
    ld e, a
    ldh a, [hCamH]
    ld d, a
    ldh a, [hPXH]
    cp d
    jr c, .toCamera
    jr nz, .right
    ldh a, [hPXL]
    cp e
    jr nc, .right
.toCamera:
    ld h, d
    ld l, e
    jr .pin
.right:
    ldh a, [hPXH]
    cp high(HERO_MAX_X)
    ret c
    ldh a, [hPXL]
    cp low(HERO_MAX_X) + 1
    ret c
    ld hl, HERO_MAX_X
.pin:
    call Shl4
    ld a, l
    ldh [hXL], a
    ld a, h
    ldh [hXH], a
    xor a
    ldh [hVX], a
    jp HeroPixels

MoveY:
    xor a
    ldh [hGround], a
    ldh a, [hVY]
    ld e, a
    ld d, 0
    bit 7, a
    jr z, .add
    dec d
.add:
    ldh a, [hYL]
    add e
    ld l, a
    ldh a, [hYH]
    adc d
    ld h, a
    bit 7, h
    jr z, .inside
    ld hl, 0
    xor a
    ldh [hVY], a
.inside:
    push hl
    call Shr4
    ld a, l
    ldh [hTmp], a
    ldh a, [hVY]
    bit 7, a
    jr nz, .up
    ldh a, [hTmp]
    add 16
    ld c, a
    call FeetSolid
    jr c, .land
    pop hl
    jr .store
.land:
    pop hl
    ld a, c
    and $f8
    sub 16
    ld l, a
    ld h, 0
    call Shl4
    xor a
    ldh [hVY], a
    inc a
    ldh [hGround], a
    jr .store
.up:
    ldh a, [hTmp]
    ld c, a
    call FeetSolid
    jr c, .bonk
    pop hl
    jr .store
.bonk:
    pop hl
    call HeadBump
    ldh a, [hTmp]
    and $f8
    add 8
    ld l, a
    ld h, 0
    call Shl4
    xor a
    ldh [hVY], a
.store:
    ld a, l
    ldh [hYL], a
    ld a, h
    ldh [hYH], a
    jp HeroPixels

FeetSolid:
    ldh a, [hPXL]
    add 3
    ld e, a
    ldh a, [hPXH]
    adc 0
    ld d, a
    call SolidAt
    ret c
    ldh a, [hPXL]
    add 8
    ld e, a
    ldh a, [hPXH]
    adc 0
    ld d, a
    call SolidAt
    ret c
    ldh a, [hPXL]
    add 12
    ld e, a
    ldh a, [hPXH]
    adc 0
    ld d, a

SolidAt:
    call LevelAt
    sub FIRST_TILE
    cp SOLID_TILES
    ret

LevelAt:
    ld a, d
    cp high(LEVEL_W * 8)
    jr nc, LevelEmpty
    ld a, c
    cp LEVEL_H * 8
    jr nc, LevelEmpty
    and $f8
    ld b, a
    swap a
    and $0f
    add high(wLevel)
    ld h, a
    ld a, b
    and 8
    swap a
    ld l, a
    ld a, e
    srl a
    srl a
    srl a
    ld b, a
    ld a, d
    swap a
    add a
    or b
    or l
    ld l, a
    ld a, [hl]

TileOf:
    push hl
    add low(CharTile)
    ld l, a
    ld a, high(CharTile)
    adc 0
    ld h, a
    ld a, [hl]
    pop hl
    ret

LevelEmpty:
    xor a
    ret

VramAt:
    ld a, c
    and $f8
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld a, e
    srl a
    srl a
    srl a
    or l
    ld l, a
    ld a, h
    add high($9800)
    ld h, a
    ret

SetCell:
    ld [hl], b
    ld a, b
    call TileOf
    push af
    call VramAt
    pop af
    ld [hl], a
    ret

HeadBump:
    ldh a, [hPXL]
    add 8
    ld e, a
    ldh a, [hPXH]
    adc 0
    ld d, a
    ldh a, [hTmp]
    ld c, a
    call LevelAt
    cp TILE_QUESTION
    jr z, .question
    cp TILE_BRICK
    jr z, .brick
    ld hl, SfxThud
    jp PlayTone
.question:
    ld b, 'U'
    call SetCell
    ld a, e
    and $f8
    ldh [hPopXL], a
    ld a, d
    ldh [hPopXH], a
    ld a, c
    and $f8
    sub 8
    ldh [hPopY], a
    ld a, 16
    ldh [hPopT], a
    jp GetCoin
.brick:
    ld b, ' '
    call SetCell
    ld de, $0050
    call AddScore
    ld hl, SfxKick
    jp PlayNoise

GetCoin:
    ldh a, [hCoins]
    add 1
    daa
    ldh [hCoins], a
    jr nz, .score
    ld hl, hLives
    inc [hl]
.score:
    ld de, $0200
    call AddScore
    ld hl, SfxDing
    jp PlayTone

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

Pickups:
    ldh a, [hPY]
    cp LEVEL_H * 8 + 8
    jp nc, HeroDies
    ldh a, [hPY]
    add 4
    ld c, a
    call TouchAt
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    ldh a, [hPY]
    add 14
    ld c, a

TouchAt:
    ldh a, [hPXL]
    add 8
    ld e, a
    ldh a, [hPXH]
    adc 0
    ld d, a
    call LevelAt
    cp TILE_COIN
    jr z, .coin
    cp TILE_LAVA
    jp z, HeroDies
    cp TILE_POLE
    jr z, .flag
    cp TILE_FLAGTOP
    jr z, .flag
    ret
.coin:
    ld b, ' '
    call SetCell
    jp GetCoin
.flag:
    ld a, STATE_CLEAR
    ldh [hState], a
    xor a
    ldh [hVX], a
    ldh [hVY], a
    ldh [hTimer], a
    ldh [hFacing], a
    ld a, e
    and $f8
    sub 10
    ld l, a
    ld a, d
    sbc 0
    ld h, a
    call Shl4
    ld a, l
    ldh [hXL], a
    ld a, h
    ldh [hXH], a
    call HeroPixels
    call MusicStop
    ld de, $1000
    call AddScore
    ld hl, SfxRise
    jp PlaySweep

Camera:
    ldh a, [hPXL]
    sub CAM_LEAD
    ld e, a
    ldh a, [hPXH]
    sbc 0
    ld d, a
    jr c, .scroll
    ldh a, [hCamH]
    cp d
    jr c, .move
    jr nz, .scroll
    ldh a, [hCamL]
    cp e
    jr nc, .scroll
.move:
    ld a, d
    cp high(MAX_CAM)
    jr c, .set
    jr nz, .limit
    ld a, e
    cp low(MAX_CAM) + 1
    jr c, .set
.limit:
    ld de, MAX_CAM
.set:
    ld a, e
    ldh [hCamL], a
    ld a, d
    ldh [hCamH], a
.scroll:
    ldh a, [hCamL]
    ldh [rSCX], a

StreamColumns:
    ldh a, [hCamL]
    ld e, a
    ldh a, [hCamH]
    ld d, a
    ld a, e
    srl d
    rra
    srl d
    rra
    srl d
    rra
    add 21
    ld b, a
.next:
    ldh a, [hNextCol]
    cp LEVEL_W
    ret nc
    cp b
    ret nc
    push bc
    call WriteColumn
    pop bc
    ld hl, hNextCol
    inc [hl]
    jr .next

WriteColumn:
    ldh [hCol], a
    ld e, a
    ld d, high(wLevel)
    and 31
    ld l, a
    ld h, high($9800)
    ld b, 0
    ld c, ' '
.row:
    ld a, [de]
    cp 'g'
    jr nz, .notGrub
    call SpawnGrub
    ld a, ' '
.notGrub:
    cp '@'
    jr nz, .notBoss
    call SpawnBoss
    ld a, ' '
.notBoss:
    push af
    cp '#'
    jr nz, .tile
    ld a, c
    cp '#'
    ld a, TILE_DIRT
    jr z, .put
    ld a, '#'
.tile:
    call TileOf
.put:
    ld [hl], a
    pop af
    ld c, a
    ld a, e
    add LEVEL_W
    ld e, a
    jr nc, .vram
    inc d
.vram:
    ld a, l
    add 32
    ld l, a
    jr nc, .count
    inc h
.count:
    inc b
    ld a, b
    cp LEVEL_H
    jr nz, .row
    ret

ColumnX:
    ldh a, [hCol]
    ld e, a
    ld d, 0
    sla e
    rl d
    sla e
    rl d
    sla e
    rl d
    ret

SpawnGrub:
    push hl
    push de
    push bc
    ld hl, wEnemies
    ld c, ENEMIES
.find:
    ld a, [hl]
    and a
    jr z, .slot
    ld a, l
    add ENEMY_SIZE
    ld l, a
    dec c
    jr nz, .find
    jr .done
.slot:
    ld [hl], 1
    inc hl
    call ColumnX
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    ld a, b
    dec a
    add a
    add a
    add a
    ld [hl+], a
    ld a, 1
    ld [hl+], a
    xor a
    ld [hl], a
.done:
    pop bc
    pop de
    pop hl
    ret

SpawnBoss:
    push de
    call ColumnX
    ld a, e
    sub 8
    ldh [hBossXL], a
    ld a, d
    sbc 0
    ldh [hBossXH], a
    pop de
    ld a, BOSS_Y
    ldh [hBossY], a
    ld a, 1
    ldh [hBossOn], a
    ldh [hBossDir], a
    ld a, BOSS_HP
    ldh [hBossHP], a
    xor a
    ldh [hBossVY], a
    ldh [hBossInv], a
    ld a, FIRE_EVERY
    ldh [hBossTime], a
    ret

Enemies:
    ld hl, wEnemies
    ld b, ENEMIES
.each:
    ld a, [hl]
    and a
    jr z, .skip
    push bc
    push hl
    ld c, low(hEState)
    ld b, ENEMY_SIZE
.load:
    ld a, [hl+]
    ldh [c], a
    inc c
    dec b
    jr nz, .load
    call Enemy
    pop hl
    push hl
    ld c, low(hEState)
    ld b, ENEMY_SIZE
.save:
    ldh a, [c]
    ld [hl+], a
    inc c
    dec b
    jr nz, .save
    pop hl
    pop bc
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
.skip:
    ld a, l
    add ENEMY_SIZE
    ld l, a
    dec b
    jr nz, .each
    ret

Enemy:
    ldh a, [hEState]
    cp 2
    jr nz, .walk
    ld hl, hETimer
    dec [hl]
    ret nz
    xor a
    ldh [hEState], a
    ret
.walk:
    ldh a, [hEY]
    cp LEVEL_H * 8
    jp nc, .remove
    ldh a, [hCamL]
    ld c, a
    ldh a, [hCamH]
    ld b, a
    ldh a, [hEXL]
    sub c
    ld e, a
    ldh a, [hEXH]
    sbc b
    bit 7, a
    jr z, .move
    ld a, e
    cp 256 - 16
    jr c, .remove
.move:
    ldh a, [hTick]
    and 1
    jr nz, .fall
    ldh a, [hEXL]
    ld e, a
    ldh a, [hEXH]
    ld d, a
    ldh a, [hEY]
    add 8
    ld c, a
    ldh a, [hEDir]
    and a
    jr nz, .goLeft
    push de
    ld hl, 16
    add hl, de
    ld d, h
    ld e, l
    call SolidAt
    pop de
    jr c, .turn
    inc de
    jr .moved
.goLeft:
    push de
    dec de
    call SolidAt
    pop de
    jr c, .turn
    dec de
.moved:
    ld a, e
    ldh [hEXL], a
    ld a, d
    ldh [hEXH], a
    jr .fall
.turn:
    ldh a, [hEDir]
    xor 1
    ldh [hEDir], a
.fall:
    ldh a, [hEY]
    add 16
    ld c, a
    ldh a, [hEXL]
    add 4
    ld e, a
    ldh a, [hEXH]
    adc 0
    ld d, a
    call SolidAt
    jr c, .grounded
    ldh a, [hEXL]
    add 11
    ld e, a
    ldh a, [hEXH]
    adc 0
    ld d, a
    call SolidAt
    jr c, .grounded
    ldh a, [hEY]
    add 2
    ldh [hEY], a
    jr HeroVsEnemy
.grounded:
    ld a, c
    and $f8
    sub 16
    ldh [hEY], a
    jr HeroVsEnemy
.remove:
    xor a
    ldh [hEState], a
    ret

HeroVsEnemy:
    ldh a, [hPXL]
    ld c, a
    ldh a, [hPXH]
    ld b, a
    ldh a, [hEXL]
    sub c
    ld e, a
    ldh a, [hEXH]
    sbc b
    ld d, a
    ld a, e
    add 10
    ld e, a
    ld a, d
    adc 0
    ret nz
    ld a, e
    cp 21
    ret nc
    ldh a, [hPY]
    ld b, a
    ldh a, [hEY]
    sub b
    ld c, a
    add 14
    cp 29
    ret nc
    bit 7, c
    jp nz, HeroDies
    ld a, c
    cp 5
    jp c, HeroDies
    ld a, 2
    ldh [hEState], a
    ld a, 30
    ldh [hETimer], a
    ld a, 256 - BOUNCE_V
    ldh [hVY], a
    ld de, $0100
    call AddScore
    ld hl, SfxKick
    jp PlayNoise

HeroDies:
    ld a, 25
    ldh [rRUMBLE], a
    ld a, STATE_DYING
    ldh [hState], a
    ld a, 150
    ldh [hTimer], a
    ld a, 256 - 64
    ldh [hVY], a
    call MusicStop
    ld hl, SfxFall
    jp PlaySweep

Dying:
    ld hl, hTimer
    dec [hl]
    jr z, .done
    ld a, [hl]
    cp 120
    ret nc
    ldh a, [hYH]
    cp 11
    ret nc
    ldh a, [hVY]
    add 3
    ldh [hVY], a
    ld e, a
    ld d, 0
    bit 7, a
    jr z, .add
    dec d
.add:
    ldh a, [hYL]
    add e
    ldh [hYL], a
    ldh a, [hYH]
    adc d
    bit 7, a
    jr z, .keep
    xor a
.keep:
    ldh [hYH], a
    jp HeroPixels
.done:
    ld hl, hLives
    dec [hl]
    jp nz, ShowIntro

GameOver:
    call UpdateTop
    call LcdOff
    call ClearScreen
    xor a
    ldh [rSCX], a
    ld hl, $9800 + 32 * 7 + 5
    ld de, GameOverText
    call PrintText
    ld a, 150
    ldh [hTimer], a
    ld a, STATE_OVER
    ldh [hState], a
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ret

UpdateTop:
    ldh a, [hTop2]
    ld b, a
    ldh a, [hScore2]
    cp b
    ret c
    jr nz, .best
    ldh a, [hTop1]
    ld b, a
    ldh a, [hScore1]
    cp b
    ret c
    jr nz, .best
    ldh a, [hTop0]
    ld b, a
    ldh a, [hScore0]
    cp b
    ret c
.best:
    ldh a, [hScore0]
    ldh [hTop0], a
    ldh a, [hScore1]
    ldh [hTop1], a
    ldh a, [hScore2]
    ldh [hTop2], a
    ret

Ending:
    ld hl, hTimer
    dec [hl]
    ret nz
    call UpdateTop
    call LcdOff
    call ShowTitle
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ret

Clear:
    ldh a, [hTimer]
    and a
    jr z, .slide
    ld hl, hTimer
    dec [hl]
    ret nz
    ld hl, hLevel
    inc [hl]
    xor a
    ldh [hCheck], a
    jp ShowIntro
.slide:
    ldh a, [hPY]
    cp FLOOR_Y - 8
    jr nc, .landed
    ldh a, [hYL]
    add 16
    ldh [hYL], a
    ldh a, [hYH]
    adc 0
    ldh [hYH], a
    jp HeroPixels
.landed:
    ld b, 5
    ld c, 3
    ld de, ClearText
    call PrintCam
    ld a, 150
    ldh [hTimer], a
    ret

PrintCam:
    ldh a, [hCamL]
    srl a
    srl a
    srl a
    add c
    ld c, a
    ld l, b
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, h
    add high($9800)
    ld h, a
    ld b, l
.char:
    ld a, [de]
    and a
    ret z
    sub 32
    push af
    ld a, c
    and 31
    or b
    ld l, a
    pop af
    ld [hl], a
    inc c
    inc de
    jr .char

Checkpoint:
    ldh a, [hCheck]
    and a
    ret nz
    call CheckX
    ldh a, [hPXL]
    sub e
    ldh a, [hPXH]
    sbc d
    ret c
    ld a, 1
    ldh [hCheck], a
    ld b, 3
    ld c, 5
    ld de, CheckText
    call PrintCam
    ld hl, SfxDing
    jp PlayTone

CheckX:
    ldh a, [hLevel]
    add a
    add low(CheckXs)
    ld l, a
    ld a, high(CheckXs)
    adc 0
    ld h, a
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ret

CoinPop:
    ldh a, [hPopT]
    and a
    ret z
    dec a
    ldh [hPopT], a
    ldh a, [hPopY]
    sub 2
    ldh [hPopY], a
    ret

Boss:
    ldh a, [hBossOn]
    and a
    ret z
    cp 2
    jp z, .defeated
    ld hl, hBossInv
    ld a, [hl]
    and a
    jr z, .move
    dec [hl]
.move:
    ldh a, [hBossXL]
    ld e, a
    ldh a, [hBossXH]
    ld d, a
    ldh a, [hBossDir]
    and a
    jr nz, .left
    inc de
    ld a, e
    sub low(BOSS_RIGHT)
    ld a, d
    sbc high(BOSS_RIGHT)
    jr c, .storeX
    ld a, 1
    ldh [hBossDir], a
    jr .storeX
.left:
    dec de
    ld a, e
    sub low(BOSS_LEFT)
    ld a, d
    sbc high(BOSS_LEFT)
    jr nc, .storeX
    xor a
    ldh [hBossDir], a
.storeX:
    ld a, e
    ldh [hBossXL], a
    ld a, d
    ldh [hBossXH], a
    ldh a, [hBossY]
    cp BOSS_Y
    jr c, .air
    call Random
    and 127
    jr nz, .attack
    ld a, 256 - 5
    ldh [hBossVY], a
.air:
    ldh a, [hTick]
    and 3
    jr nz, .apply
    ld hl, hBossVY
    inc [hl]
.apply:
    ldh a, [hBossVY]
    ld b, a
    ldh a, [hBossY]
    add b
    cp BOSS_Y
    jr c, .setY
    xor a
    ldh [hBossVY], a
    ld a, BOSS_Y
.setY:
    ldh [hBossY], a
.attack:
    ld hl, hBossTime
    dec [hl]
    jr nz, HeroVsBoss
    ld [hl], FIRE_EVERY
    call ShootFire
    jr HeroVsBoss
.defeated:
    ldh a, [hBossY]
    add 2
    ldh [hBossY], a
    cp 150
    ret c
    xor a
    ldh [hBossOn], a
    jp Win

HeroVsBoss:
    ldh a, [hBossInv]
    and a
    ret nz
    ldh a, [hPXL]
    ld c, a
    ldh a, [hPXH]
    ld b, a
    ldh a, [hBossXL]
    sub c
    ld e, a
    ldh a, [hBossXH]
    sbc b
    ld d, a
    ld a, e
    add 19
    ld e, a
    ld a, d
    adc 0
    ret nz
    ld a, e
    cp 31
    ret nc
    ldh a, [hPY]
    ld b, a
    ldh a, [hBossY]
    sub b
    ld c, a
    add 21
    cp 35
    ret nc
    bit 7, c
    jp nz, HeroDies
    ld a, c
    cp 8
    jp c, HeroDies
    ld a, BOSS_INV
    ldh [hBossInv], a
    ld a, 256 - BOUNCE_V - 16
    ldh [hVY], a
    ld de, $0500
    call AddScore
    ld hl, SfxCrash
    call PlayNoise
    ld hl, hBossHP
    dec [hl]
    ret nz
    ld a, 2
    ldh [hBossOn], a
    xor a
    ldh [hFireOn], a
    call MusicStop
    ld de, $5000
    call AddScore
    ld hl, SfxRise
    jp PlaySweep

ShootFire:
    ldh a, [hFireOn]
    and a
    ret nz
    ld a, 1
    ldh [hFireOn], a
    ldh a, [hBossY]
    add 10
    ldh [hFireY], a
    ldh a, [hBossXL]
    add 8
    ldh [hFireXL], a
    ldh a, [hBossXH]
    adc 0
    ldh [hFireXH], a
    ld b, a
    ldh a, [hFireXL]
    ld c, a
    ldh a, [hPXL]
    sub c
    ldh a, [hPXH]
    sbc b
    ld a, 0
    jr nc, .aim
    inc a
.aim:
    ldh [hFireDir], a
    ld hl, SfxKick
    jp PlayNoise

Fireball:
    ldh a, [hFireOn]
    and a
    ret z
    ldh a, [hFireXL]
    ld e, a
    ldh a, [hFireXH]
    ld d, a
    ldh a, [hFireDir]
    and a
    jr nz, .left
    inc de
    inc de
    jr .moved
.left:
    dec de
    dec de
.moved:
    ld a, e
    ldh [hFireXL], a
    ld a, d
    ldh [hFireXH], a
    ld a, e
    sub low(MAX_CAM)
    ld a, d
    sbc high(MAX_CAM)
    jr c, .gone
    ld a, d
    cp high(LEVEL_W * 8)
    jr nc, .gone
    ldh a, [hPXL]
    ld c, a
    ldh a, [hPXH]
    ld b, a
    ld a, e
    sub c
    ld e, a
    ld a, d
    sbc b
    ld d, a
    ld a, e
    add 6
    ld e, a
    ld a, d
    adc 0
    ret nz
    ld a, e
    cp 20
    ret nc
    ldh a, [hPY]
    ld b, a
    ldh a, [hFireY]
    sub b
    add 6
    cp 21
    ret nc
    jp HeroDies
.gone:
    xor a
    ldh [hFireOn], a
    ret

Win:
    ld a, STATE_WIN
    ldh [hState], a
    ld a, 255
    ldh [hTimer], a
    ld b, 4
    ld c, 3
    ld de, WinText
    call PrintCam
    ld b, 6
    ld c, 1
    ld de, ThanksText
    call PrintCam
    ld hl, SfxCrowd
    jp PlayNoise

Draw:
    ldh a, [rLCDC]
    or 2
    ldh [rLCDC], a
    ldh a, [hLives]
    cp 10
    jr c, .lives
    ld a, 9
.lives:
    add '0' - 32
    ld [HUD + 1], a
    ld hl, HUD + 5
    ldh a, [hCoins]
    call PrintBCD
    ld hl, HUD + 13
    ldh a, [hScore2]
    call PrintBCD
    ldh a, [hScore1]
    call PrintBCD
    ldh a, [hScore0]
    call PrintBCD
    ldh a, [hBossOn]
    cp 1
    jr nz, .sprites
    ld hl, HUD + 8
    ldh a, [hBossHP]
    ld b, a
    ld c, BOSS_HP
.heart:
    ld a, b
    and a
    ld a, TILE_SPACE
    jr z, .put
    dec b
    ld a, TILE_HEART
.put:
    ld [hl+], a
    dec c
    jr nz, .heart
.sprites:
    ld hl, $fe00
    ldh a, [hState]
    cp STATE_INTRO
    jp z, HideAll
    cp STATE_OVER
    jp z, HideAll
    call DrawHero
    call DrawEnemies
    call DrawPop
    call DrawBoss
    jp DrawFire

HideAll:
    xor a
    ld b, 40
.clear:
    ld [hl+], a
    inc l
    inc l
    inc l
    dec b
    jr nz, .clear
    ret

ScreenX:
    ldh a, [hCamL]
    ld c, a
    ldh a, [hCamH]
    ld b, a
    ld a, e
    sub c
    ld e, a
    ld a, d
    sbc b
    ld d, a
    ld a, e
    add 16
    ld e, a
    ld a, d
    adc 0
    jr nz, .off
    ld a, e
    cp 176
    jr nc, .off
    sub 8
    ret
.off:
    scf
    ret

DrawHero:
    ldh a, [hPY]
    cp 150
    jr nc, .hide
    ldh a, [hPXL]
    ld e, a
    ldh a, [hPXH]
    ld d, a
    call ScreenX
    jr c, .hide
    ld c, a
    ldh a, [hPY]
    add 16
    ld b, a
    ld d, TILE_HERO + FRAME_DEAD
    ldh a, [hState]
    cp STATE_DYING
    jr z, .frame
    ld d, TILE_HERO + FRAME_JUMP
    ldh a, [hGround]
    and a
    jr z, .frame
    ld d, TILE_HERO
    ldh a, [hVX]
    and a
    jr z, .frame
    ld d, TILE_HERO + FRAME_WALK
    ldh a, [hAnim]
    bit 7, a
    jr z, .frame
    ld d, TILE_HERO + FRAME_WALK + 4
.frame:
    ldh a, [hFacing]
    ld e, a
    jp Sprite16
.hide:
    jp Hide4

Hide4:
    xor a
    ld [hl+], a
    inc l
    inc l
    inc l
    ld [hl+], a
    inc l
    inc l
    inc l
    ld [hl+], a
    inc l
    inc l
    inc l
    ld [hl+], a
    inc l
    inc l
    inc l
    ret

Sprite16:
    ld a, e
    and $20
    ld a, d
    jr z, .top
    xor 1
.top:
    call .pair
    ld a, b
    add 8
    ld b, a
    ld a, e
    and $20
    ld a, d
    jr z, .bottom
    xor 1
.bottom:
    add 2
.pair:
    push af
    ld [hl], b
    inc l
    ld [hl], c
    inc l
    ld [hl+], a
    ld [hl], e
    inc l
    ld [hl], b
    inc l
    ld a, c
    add 8
    ld [hl+], a
    pop af
    xor 1
    ld [hl+], a
    ld [hl], e
    inc l
    ret

Mirror16:
    call MirrorRow
    ld a, b
    add 8
    ld b, a
    inc d

MirrorRow:
    ld [hl], b
    inc l
    ld [hl], c
    inc l
    ld [hl], d
    inc l
    ld [hl], e
    inc l
    ld [hl], b
    inc l
    ld a, c
    add 8
    ld [hl+], a
    ld [hl], d
    inc l
    ld a, e
    or $20
    ld [hl+], a
    ret

DrawEnemies:
    ld de, wEnemies
    ld b, ENEMIES
.each:
    push bc
    push de
    ld a, [de]
    ldh [hTmp], a
    and a
    jr z, .hide
    inc e
    ld a, [de]
    ld c, a
    inc e
    ld a, [de]
    ld b, a
    inc e
    ld a, [de]
    ldh [hCol], a
    ld d, b
    ld e, c
    call ScreenX
    jr c, .hide
    ld c, a
    ldh a, [hCol]
    add 16
    ld b, a
    ld e, 0
    ldh a, [hTmp]
    cp 2
    jr z, .squished
    ld d, TILE_GRUB
    ldh a, [hTick]
    and 16
    jr z, .walk
    ld d, TILE_GRUB + 2
.walk:
    call Mirror16
    jr .next
.squished:
    ld a, b
    add 8
    ld b, a
    ld d, TILE_SQUISH
    call MirrorRow
    call Hide2
    jr .next
.hide:
    call Hide4
.next:
    pop de
    pop bc
    ld a, e
    add ENEMY_SIZE
    ld e, a
    dec b
    jr nz, .each
    ret

Hide2:
    xor a
    ld [hl+], a
    inc l
    inc l
    inc l
    ld [hl+], a
    inc l
    inc l
    inc l
    ret

DrawPop:
    ldh a, [hPopT]
    and a
    jr z, .hide
    ldh a, [hPopXL]
    ld e, a
    ldh a, [hPopXH]
    ld d, a
    call ScreenX
    jr c, .hide
    ld c, a
    ldh a, [hPopY]
    add 16
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, TILE_COIN
    ld [hl+], a
    xor a
    ld [hl+], a
    ret
.hide:
    xor a
    ld [hl+], a
    inc l
    inc l
    inc l
    ret

DrawBoss:
    ldh a, [hBossOn]
    and a
    jr z, .hide
    ldh a, [hBossXL]
    ld e, a
    ldh a, [hBossXH]
    ld d, a
    call ScreenX
    jr c, .hide
    ld c, a
    ldh a, [hBossY]
    add 16
    ld b, a
    ld e, 0
    ldh a, [hBossOn]
    cp 2
    jr nz, .flash
    ld e, $10
.flash:
    ldh a, [hBossInv]
    and 4
    jr z, .draw
    ld a, e
    or $10
    ld e, a
.draw:
    ld d, TILE_BOSS
    call .column
    ld a, c
    add 8
    ld c, a
    ld d, TILE_BOSS + 3
    call .column
    ld a, c
    add 8
    ld c, a
    ld d, TILE_BOSS
    ld a, e
    or $20
    ld e, a
.column:
    push bc
    ld a, 3
.cell:
    push af
    ld [hl], b
    inc l
    ld [hl], c
    inc l
    ld [hl], d
    inc l
    ld [hl], e
    inc l
    inc d
    ld a, b
    add 8
    ld b, a
    pop af
    dec a
    jr nz, .cell
    pop bc
    ret
.hide:
    ld b, 9
.clear:
    xor a
    ld [hl+], a
    inc l
    inc l
    inc l
    dec b
    jr nz, .clear
    ret

DrawFire:
    ldh a, [hFireOn]
    and a
    jr z, .hide
    ldh a, [hFireXL]
    ld e, a
    ldh a, [hFireXH]
    ld d, a
    call ScreenX
    jr c, .hide
    ld c, a
    ldh a, [hFireY]
    add 16
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, TILE_FIRE
    ld [hl+], a
    ldh a, [hTick]
    and 4
    swap a
    ld [hl+], a
    ret
.hide:
    xor a
    ld [hl+], a
    ret

    include "lib/util.asm"
    include "lib/sound.asm"
    include "lib/music.asm"

TitleText:
    db "P I P   Q U E S T", 0
SubtitleText:
    db "SAVE THE KINGDOM!", 0
PressText:
    db "PRESS START", 0
PressBlank:
    db "           ", 0
TopText:
    db "TOP ", 0
WorldText:
    db "WORLD 1-", 0
TimesText:
    db "X ", 0
CastleText:
    db "KRAG'S CASTLE AHEAD", 0
LevelName:
    db "1-", 0
ClearText:
    db "COURSE CLEAR!", 0
CheckText:
    db "CHECKPOINT!", 0

CheckXs:
    dw 64 * 8, 60 * 8, 68 * 8
GameOverText:
    db "GAME OVER", 0
WinText:
    db "YOU BEAT KRAG!", 0
ThanksText:
    db "THANKS FOR PLAYING", 0

OverworldTheme:
    db N_C4, 8, N_E4, 8, N_G4, 8, N_C5, 8, N_G4, 8, N_E4, 8, N_G4, 16
    db N_A4, 8, N_F4, 8, N_A4, 8, N_C5, 8, N_A4, 8, N_F4, 8, N_A4, 16
    db N_G4, 8, N_B4, 8, N_D5, 8, N_B4, 8, N_G4, 8, N_F4, 8, N_D4, 16
    db N_E4, 8, N_G4, 8, N_C5, 8, N_G4, 8, N_E4, 8, N_D4, 8, N_C4, 16
    db $ff

CastleTheme:
    db N_A2, 10, N_C3, 10, N_E3, 10, N_A3, 10, N_E3, 10, N_C3, 10
    db N_G2, 10, N_B2, 10, N_D3, 10, N_G3, 10, N_D3, 10, N_B2, 10
    db N_F2, 10, N_A2, 10, N_C3, 10, N_F3, 10, N_C3, 10, N_A2, 10
    db N_E2, 10, N_GS2, 10, N_B2, 10, N_E3, 10, N_B2, 10, N_GS2, 10
    db $ff

CharTile:
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 72, 0, 64, 0, 0, 0, 0, 120, 121, 0, 0, 0, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 123, 0, 0, 122, 0, 67
    db 0, 0, 66, 74, 127, 0, 80, 0, 0, 0, 0, 0, 82, 126, 0, 0
    db 69, 0, 0, 0, 129, 68, 0, 125, 73, 124, 0, 0, 0, 0, 119, 0
    db 0, 0, 78, 76, 77, 0, 81, 0, 0, 0, 0, 0, 0, 0, 79, 75
    db 70, 0, 0, 0, 0, 0, 0, 128, 0, 0, 0, 0, 71, 0, 0, 0

LevelTable:
    dw Level1, Level2, Level3

Level1:
    db "                                                                                                                                "
    db "                                                                                                                                "
    db "        cd                     cd                        cd                       cd                      cd          f         "
    db "                   cd                                               cd                                                F cd      "
    db "                                            cd                                               cd                       F         "
    db "                                                                              ooo                                     F         "
    db "                  ?                     oo                                   BB?BB         B                          F         "
    db "                                                                                                                      F         "
    db "                                                                                                                      F         "
    db "                        ooo                                                                                      X    F  M M M  "
    db "            ?   B?B?B                 B?B                       ooooo       BBB?BBB     ?  ?                    XX    F  WWWWWW "
    db "                                                          Pp                                             X     XXX    F  WwWWwW "
    db "  ^                              ^            Pp          |!       ^                          ^         XX    XXXX    F  WWWWWW "
    db " (:)                ^       Pp  (=)           |!  ^       |!      (=)                 ^      (=)       XXX   XXXXX    F  WWDDWW "
    db "(:==)bn YYYY    bn (=)  g   |! (==:)    g bnYY|! (=)g g   |!   bn(=:=)    YYYY  g   g(=)bn  (=:=)  g  XXXX  XXXXXXn   X  WWDDWW "
    db "####################################  ################################   #######################  ##############################"
    db "####################################  ################################   #######################  ##############################"

Level2:
    db "                                                                                                                                "
    db "                                                                                                                                "
    db "                      cd                          cd                           cd                       cd            f         "
    db "      cd                                                        cd                                                    F         "
    db "                                     cd                                                     cd                        F         "
    db "                                                                                                                      F         "
    db "         ooo            B??B                          BBB                o                                            F         "
    db "                                                                                                                      F         "
    db "                                                                                                                X     F         "
    db "                                   oooo                                                ooo                     XX     F  M M M  "
    db "        ?B?           BBBB                     ?                        B?B                       XX          XXX     F  WWWWWW "
    db "                                                                              Pp                 XXXX        XXXX     F  WwWWwW "
    db "    ^                          ^    BB      Pp              ooo     BB        |!       BB       XXXXXX      XXXXX     F  WWWWWW "
    db "   (=)                  ^     (=)           |!     ^         (:)            ^ |!               XXXXXXXX    XXXXXX     F  WWDDWW "
    db "  (=:=)   bnYYg        (=)g  (g:=)        g |!bng (=)     g (:g=)         g(bn|!  g         g XXXXXXXXXX  XXXXXXX     X  WWDDWW "
    db "##################   #############      ##############   #########      ##############     #####################################"
    db "##################   #############      ##############   #########      ##############     #####################################"

Level3:
    db "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
    db "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
    db "                              CCCCC                                   CCCCCCC                                                  C"
    db "                              CCCCC                                   CCCCCCC                                                  C"
    db "                              CCCCC                                                                                            C"
    db "          w                 w                 w                 w                 w                 w                 w        C"
    db "          w                 w                 w                 w                 w                 w                 w        C"
    db "      T        T        T        T        T        o        T        T        T        T        T        T        T            C"
    db "                                                                                                                               C"
    db "                                                                                                                               C"
    db "            ?                                     ?B?                                                                          C"
    db "                                                                                                                               C"
    db "                          ooo                                                               ooo                                C"
    db "                                                                                                CC                             C"
    db "                g           g       g               g   g                 g   g               g CC                    @        C"
    db "CCCCCCCCCCCCCCCCCCCCLLLLCCCCCCCCCCCCCCCCLLLLLCCCCCCCCCCCCCCCLLLLLCCCCCCCCCCCCCCCCCLLLLLCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
    db "CCCCCCCCCCCCCCCCCCCCLLLLCCCCCCCCCCCCCCCCLLLLLCCCCCCCCCCCCCCCLLLLLCCCCCCCCCCCCCCCCCLLLLLCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"

    include "lib/font.asm"

Tiles:
    dw `33333333
    dw `12121212
    dw `21212121
    dw `22222222
    dw `22322222
    dw `22222232
    dw `23222222
    dw `22222222

    dw `22222222
    dw `22322222
    dw `22222232
    dw `23222222
    dw `22222222
    dw `22232222
    dw `32222222
    dw `22222322

    dw `33333333
    dw `22223222
    dw `22223222
    dw `22223222
    dw `33333333
    dw `32222232
    dw `32222232
    dw `32222232

    dw `33333333
    dw `31111113
    dw `31133113
    dw `31113113
    dw `31131113
    dw `31111113
    dw `31131113
    dw `33333333

    dw `33333333
    dw `32222223
    dw `32322323
    dw `32222223
    dw `32222223
    dw `32322323
    dw `32222223
    dw `33333333

    dw `33333333
    dw `31122222
    dw `31122222
    dw `31122222
    dw `33333333
    dw `03112222
    dw `03112222
    dw `03112222

    dw `33333333
    dw `22222223
    dw `22222223
    dw `22222223
    dw `33333333
    dw `22222230
    dw `22222230
    dw `22222230

    dw `03112222
    dw `03112222
    dw `03112222
    dw `03112222
    dw `03112222
    dw `03112222
    dw `03112222
    dw `03112222

    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230

    dw `33333333
    dw `31111123
    dw `31111123
    dw `31111123
    dw `31111123
    dw `31111123
    dw `32222223
    dw `33333333

    dw `22232222
    dw `22232222
    dw `33333333
    dw `22222223
    dw `22222223
    dw `33333333
    dw `22232222
    dw `22232222

    dw `00033000
    dw `00322300
    dw `03211230
    dw `03211230
    dw `03211230
    dw `03211230
    dw `00322300
    dw `00033000

    dw `00000000
    dw `00000033
    dw `00003311
    dw `00031111
    dw `00311111
    dw `03111111
    dw `03111111
    dw `00333333

    dw `00000000
    dw `33000000
    dw `11330000
    dw `11113000
    dw `11111300
    dw `11111130
    dw `11111130
    dw `33333300

    dw `00000000
    dw `00000033
    dw `00003322
    dw `00032222
    dw `00322222
    dw `03222222
    dw `32222222
    dw `32222222

    dw `00000000
    dw `33000000
    dw `22330000
    dw `22223000
    dw `22222300
    dw `22222230
    dw `22222223
    dw `22222223

    dw `00032000
    dw `00032000
    dw `00032000
    dw `00032000
    dw `00032000
    dw `00032000
    dw `00032000
    dw `00032000

    dw `00033000
    dw `00311300
    dw `00311300
    dw `00033000
    dw `00032000
    dw `00032000
    dw `00032000
    dw `00032000

    dw `00100010
    dw `01110111
    dw `11111111
    dw `12111211
    dw `11121112
    dw `11111111
    dw `21112111
    dw `11211121

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000333
    dw `00033111
    dw `00311111
    dw `03111111
    dw `03111111
    dw `31111111

    dw `33000000
    dw `30000000
    dw `33300000
    dw `11133000
    dw `11111300
    dw `31131130
    dw `31131130
    dw `11111113

    dw `31111111
    dw `31111111
    dw `03111111
    dw `00311111
    dw `00033111
    dw `00000333
    dw `00002220
    dw `00033330

    dw `12111213
    dw `11133113
    dw `11111130
    dw `11111300
    dw `11133000
    dw `33300000
    dw `00222000
    dw `03333000

    dw `00000000
    dw `00000000
    dw `00000333
    dw `00033111
    dw `00311111
    dw `03111111
    dw `03111111
    dw `31111111

    dw `33000000
    dw `30000000
    dw `33300000
    dw `11133000
    dw `11111300
    dw `31131130
    dw `31131130
    dw `11111113

    dw `31111111
    dw `31111111
    dw `03111111
    dw `00311111
    dw `00033111
    dw `00000333
    dw `00222000
    dw `03333000

    dw `12111213
    dw `11133113
    dw `11111130
    dw `11111300
    dw `11133000
    dw `33300000
    dw `00002220
    dw `00033330

    dw `00000000
    dw `00000000
    dw `00000333
    dw `00033111
    dw `00311111
    dw `03111111
    dw `03111111
    dw `31111111

    dw `33000000
    dw `30000000
    dw `33300000
    dw `11133000
    dw `11111300
    dw `31131130
    dw `31131130
    dw `11111113

    dw `31111111
    dw `31111111
    dw `03111111
    dw `00311111
    dw `00033111
    dw `00000333
    dw `00000022
    dw `00000333

    dw `12111213
    dw `11133113
    dw `11111130
    dw `11111300
    dw `11133000
    dw `33300000
    dw `22000000
    dw `33300000

    dw `00000000
    dw `00000000
    dw `00000333
    dw `00033111
    dw `00311111
    dw `03111111
    dw `03111111
    dw `31111111

    dw `33000000
    dw `30000000
    dw `33300000
    dw `11133000
    dw `31131300
    dw `31131130
    dw `31131130
    dw `11111113

    dw `31111111
    dw `31111111
    dw `03111111
    dw `00311111
    dw `00033111
    dw `00000333
    dw `00222000
    dw `00000000

    dw `12111213
    dw `11133113
    dw `11111130
    dw `11111300
    dw `11133000
    dw `33300000
    dw `00222000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000333
    dw `00033111
    dw `00311111
    dw `03111131
    dw `03111113
    dw `31111111

    dw `33000000
    dw `30000000
    dw `33300000
    dw `11133000
    dw `11111300
    dw `31313130
    dw `13131130
    dw `11111113

    dw `31111111
    dw `31111111
    dw `03111111
    dw `00311111
    dw `00033111
    dw `00000333
    dw `00002220
    dw `00033330

    dw `12111213
    dw `13333113
    dw `11111130
    dw `11111300
    dw `11133000
    dw `33300000
    dw `00222000
    dw `03333000

    dw `00000000
    dw `00000000
    dw `00000033
    dw `00003322
    dw `00032222
    dw `00322222
    dw `03221132
    dw `03221332

    dw `32222222
    dw `32222333
    dw `32222222
    dw `03222222
    dw `00333333
    dw `00033330
    dw `00333300
    dw `03333000

    dw `00000000
    dw `00000000
    dw `00000033
    dw `00003322
    dw `00032222
    dw `00322222
    dw `03221132
    dw `03221332

    dw `32222222
    dw `32222333
    dw `32222222
    dw `03222222
    dw `00333333
    dw `00003330
    dw `00033330
    dw `00333300

    dw `00000000
    dw `00000000
    dw `00033333
    dw `03322222
    dw `32211322
    dw `32222222
    dw `03333333
    dw `00000000

    dw `00000030
    dw `00000330
    dw `00000333
    dw `00000033
    dw `00000322
    dw `00003222
    dw `00032211
    dw `00322133

    dw `00322111
    dw `03222222
    dw `03222222
    dw `32222333
    dw `32223131
    dw `32222333
    dw `03222222
    dw `03222222

    dw `00322222
    dw `00332222
    dw `00033322
    dw `00000333
    dw `00003333
    dw `00033333
    dw `00333333
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `22222222
    dw `22222222
    dw `12222221
    dw `12222221

    dw `12222221
    dw `22222222
    dw `22222222
    dw `33333333
    dw `31311313
    dw `33333333
    dw `22222222
    dw `22222222

    dw `22222222
    dw `22222222
    dw `22222222
    dw `33333333
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00033000
    dw `00322300
    dw `03211230
    dw `32111123
    dw `32111123
    dw `03211230
    dw `00322300
    dw `00033000

    dw `00033000
    dw `00311300
    dw `03111130
    dw `31131131
    dw `31111111
    dw `31111113
    dw `03111130
    dw `00333300

    dw `00000000
    dw `00033000
    dw `00311300
    dw `03111130
    dw `03111130
    dw `00311300
    dw `00033000
    dw `00000000

    dw `03300330
    dw `31133113
    dw `31111113
    dw `31111113
    dw `03111130
    dw `00311300
    dw `00033000
    dw `00000000

    dw `00033000
    dw `00311300
    dw `03111130
    dw `31111113
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111

    dw `00000003
    dw `00000031
    dw `00000311
    dw `00003111
    dw `00031111
    dw `00311111
    dw `03111111
    dw `31111111

    dw `30000000
    dw `13000000
    dw `11300000
    dw `11130000
    dw `11113000
    dw `11111300
    dw `11111130
    dw `11111113

    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111

    dw `11111111
    dw `11211111
    dw `11111111
    dw `11111121
    dw `11111111
    dw `11111111
    dw `12111111
    dw `11111111

    dw `00000000
    dw `20020020
    dw `22222222
    dw `20020020
    dw `20020020
    dw `22222222
    dw `20020020
    dw `20020020

    dw `22232222
    dw `22232222
    dw `33333333
    dw `22222322
    dw `22222322
    dw `33333333
    dw `22232222
    dw `22232222

    dw `33300333
    dw `32300323
    dw `32300323
    dw `33333333
    dw `22232222
    dw `22232222
    dw `33333333
    dw `22222322

    dw `22333322
    dw `23333332
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333

    dw `22232222
    dw `22333322
    dw `23333332
    dw `23333332
    dw `23333332
    dw `22333322
    dw `22232222
    dw `33333333

    dw `00020000
    dw `00212000
    dw `02111200
    dw `00212000
    dw `00333000
    dw `00030000
    dw `00030000
    dw `00030000
TilesEnd:
