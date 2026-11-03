include "lib/hardware.asm"

TILE_CLOUD  equ FIRST_TILE
TILE_ROOF   equ FIRST_TILE + 1
TILE_TOWER  equ FIRST_TILE + 2
TILE_WINDOW equ FIRST_TILE + 3
TILE_PIPE_L equ FIRST_TILE + 4
TILE_PIPE_R equ FIRST_TILE + 5
TILE_GROUND equ FIRST_TILE + 8
TILE_DIRT   equ FIRST_TILE + 9
TILE_BIRD   equ FIRST_TILE + 10
TILE_RULE   equ FIRST_TILE + 14

STATE_TITLE equ 0
STATE_PLAY  equ 1
STATE_FALL  equ 2
STATE_OVER  equ 3

LCDC_HUD   equ %11110011
PANEL_Y    equ 72
HUD_Y      equ 136
PANEL      equ $9c00
BIRD_X     equ 40
BIRD_START equ 64
GROUND_Y   equ 113
GRAVITY    equ $0026
FLAP       equ $fd80
MAX_FALL   equ $0400
GROUND_ROW equ 15
PIPE_EVERY equ 8
TITLE_ROW  equ 5
PROMPT_ROW equ 10

hState    equ $ff80
hBirdY    equ $ff81
hBirdYL   equ $ff82
hVelH     equ $ff83
hVelL     equ $ff84
hNextCol  equ $ff85
hColCount equ $ff86
hGap      equ $ff87
hCloud    equ $ff88
hScoreL   equ $ff89
hScoreH   equ $ff8a
hBestL    equ $ff8b
hBestH    equ $ff8c
hTimer    equ $ff8d
hAnim     equ $ff8e
hTower    equ $ff8f
hTowerRun equ $ff90

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "FLAP"

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
    ld a, HUD_Y
    ldh [rWY], a
    ld a, 7
    ldh [rWX], a
    call SoundOn
    call SeedRandom
    xor a
    ldh [hBestL], a
    ldh [hBestH], a
    call NewWorld
    call EnableVBlank

MainLoop:
    halt
    nop
    call Draw
    call ReadJoypad
    ld hl, hAnim
    inc [hl]
    ldh a, [hState]
    cp STATE_PLAY
    jr z, .play
    cp STATE_FALL
    jr z, .fall
    cp STATE_OVER
    jr z, .over
    call Title
    jr MainLoop
.play:
    call Play
    jr MainLoop
.fall:
    call Falling
    jr MainLoop
.over:
    call Over
    jr MainLoop

NewWorld:
    call ClearScreen
    xor a
    ldh [rSCX], a
    ldh [hState], a
    ldh [hNextCol], a
    ldh [hScoreL], a
    ldh [hScoreH], a
    ldh [hVelH], a
    ldh [hVelL], a
    ld a, PIPE_EVERY - 1
    ldh [hColCount], a
    ld b, 32
.column:
    push bc
    call WriteColumn
    pop bc
    dec b
    jr nz, .column
    ld a, 21
    ldh [hNextCol], a
    ld hl, PANEL + 32
    ld bc, 32 * 8
    ld d, TILE_SPACE
    call MemFill
    ld hl, PANEL + 32
    ld b, 20
    ld a, TILE_RULE
.rule:
    ld [hl+], a
    dec b
    jr nz, .rule
    ld a, HUD_Y
    ldh [rWY], a
    ld hl, PANEL
    ld de, HudText
    call PrintText
    ld hl, $9800 + 32 * TITLE_ROW + 6
    ld de, TitleText
    call PrintText
    ld hl, $9800 + 32 * PROMPT_ROW + 6
    ld de, PressText
    call PrintText
    ld a, BIRD_START
    ldh [hBirdY], a
    ld a, LCDC_HUD
    ldh [rLCDC], a
    ret

Title:
    ldh a, [hAnim]
    rrca
    rrca
    rrca
    and 7
    ld e, a
    ld d, 0
    ld hl, Bob
    add hl, de
    ld a, [hl]
    add BIRD_START
    ldh [hBirdY], a
    call BlinkPrompt
    ldh a, [hJoyPressed]
    and PAD_A | PAD_START
    ret z
    ld hl, $9800 + 32 * TITLE_ROW + 6
    ld de, Blank
    call PrintText
    ld hl, $9800 + 32 * PROMPT_ROW + 6
    ld de, Blank
    call PrintText
    ld a, STATE_PLAY
    ldh [hState], a
    jp Flap

Play:
    ldh a, [hJoyPressed]
    and PAD_A | PAD_UP
    call nz, Flap
    call Fall
    ld hl, rSCX
    inc [hl]
    ld a, [hl]
    and 7
    call z, WriteColumn
    call CheckPass
    call Collide
    ret z
    ld a, STATE_FALL
    ldh [hState], a
    xor a
    ldh [hVelH], a
    ldh [hVelL], a
    ld hl, SfxCrash
    jp PlayNoise

Flap:
    ld a, high(FLAP)
    ldh [hVelH], a
    ld a, low(FLAP)
    ldh [hVelL], a
    ld hl, SfxFlap
    jp PlaySweep

Fall:
    ldh a, [hVelL]
    add low(GRAVITY)
    ld l, a
    ldh a, [hVelH]
    adc high(GRAVITY)
    ld h, a
    bit 7, h
    jr nz, .move
    cp high(MAX_FALL)
    jr c, .move
    ld hl, MAX_FALL
.move:
    ld a, l
    ldh [hVelL], a
    ld a, h
    ldh [hVelH], a
    ldh a, [hBirdYL]
    add l
    ldh [hBirdYL], a
    ldh a, [hBirdY]
    adc h
    cp $c0
    jr c, .store
    xor a
    ldh [hBirdYL], a
    ldh [hVelH], a
    ldh [hVelL], a
.store:
    ldh [hBirdY], a
    ret

Falling:
    call Fall
    ldh a, [hBirdY]
    cp GROUND_Y
    ret c
    ld a, GROUND_Y
    ldh [hBirdY], a
    ld hl, SfxThud
    call PlayTone

GameOver:
    ld a, STATE_OVER
    ldh [hState], a
    ld a, 40
    ldh [hTimer], a
    ld hl, PANEL + 32 * 3 + 5
    ld de, GameOverText
    call PrintText
    ld hl, PANEL + 32 * 7 + 6
    ld de, PressText
    call PrintText
    ldh a, [hBestH]
    ld b, a
    ldh a, [hScoreH]
    cp b
    ret c
    jr nz, .best
    ldh a, [hBestL]
    ld b, a
    ldh a, [hScoreL]
    cp b
    ret c
    ret z
.best:
    ldh a, [hScoreL]
    ldh [hBestL], a
    ldh a, [hScoreH]
    ldh [hBestH], a
    ld hl, PANEL + 32 * 5 + 5
    ld de, NewBestText
    call PrintText
    ld hl, SfxRise
    jp PlaySweep

Over:
    call BlinkPrompt
    ld hl, hTimer
    ld a, [hl]
    and a
    jr z, .ready
    dec [hl]
    ret
.ready:
    ldh a, [hJoyPressed]
    and PAD_A | PAD_START
    ret z
    call LcdOff
    jp NewWorld

WriteColumn:
    ld c, 0
    ldh a, [hState]
    cp STATE_PLAY
    jr nz, .sky
    ld hl, hColCount
    ld a, [hl]
    inc a
    and PIPE_EVERY - 1
    ld [hl], a
    cp 2
    jr nc, .sky
    inc a
    ld c, a
    cp 1
    jr nz, .pick
    call Random
    and 7
    cp 6
    jr c, .gap
    sub 4
.gap:
    add 3
    ldh [hGap], a
    jr .pick
.sky:
    ld hl, hTowerRun
    ld a, [hl]
    and a
    jr nz, .sameTower
    call Random
    and 3
    add 2
    ld [hl], a
    call Random
    and 7
    add 2
    cp 8
    jr c, .height
    xor a
.height:
    ldh [hTower], a
.sameTower:
    dec [hl]
    call Random
    and 15
    cp 3
    jr c, .cloud
    ld a, $ff
    jr .setCloud
.cloud:
    inc a
.setCloud:
    ldh [hCloud], a
.pick:
    ld a, c
    add TILE_PIPE_L - 1
    ld d, a
    ldh a, [hNextCol]
    ld l, a
    ld h, high($9800)
    ld b, 0
.row:
    ld a, b
    cp GROUND_ROW
    jr c, .air
    ld a, TILE_GROUND
    jr z, .put
    ld a, TILE_DIRT
    jr .put
.air:
    ld a, c
    and a
    jr nz, .pipe
    ldh a, [hTower]
    and a
    jr z, .skyTile
    ld e, a
    ld a, GROUND_ROW
    sub e
    cp b
    jr z, .roof
    jr nc, .skyTile
    ldh a, [hNextCol]
    xor b
    and 1
    ld a, TILE_TOWER
    jr z, .put
    ld a, TILE_WINDOW
    jr .put
.roof:
    ld a, TILE_ROOF
    jr .put
.skyTile:
    ldh a, [hCloud]
    cp b
    ld a, TILE_CLOUD
    jr z, .put
    ld a, TILE_SPACE
    jr .put
.pipe:
    ldh a, [hGap]
    ld e, a
    ld a, b
    sub e
    jr c, .upper
    cp 5
    jr c, .open
    jr z, .cap
    jr .body
.upper:
    inc a
    jr z, .cap
.body:
    ld a, d
    jr .put
.cap:
    ld a, d
    add 2
    jr .put
.open:
    ld a, TILE_SPACE
.put:
    ld [hl], a
    ld a, l
    add 32
    ld l, a
    jr nc, .next
    inc h
.next:
    inc b
    ld a, b
    cp 18
    jr nz, .row
    ldh a, [hNextCol]
    inc a
    and 31
    ldh [hNextCol], a
    ret

Solid:
    ld a, e
    and $f8
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld a, d
    srl a
    srl a
    srl a
    or l
    ld l, a
    ld a, h
    add high($9800)
    ld h, a
    ld a, [hl]
    cp TILE_PIPE_L
    sbc a
    inc a
    ret

Collide:
    ldh a, [rSCX]
    add BIRD_X + 3
    ld d, a
    ldh a, [hBirdY]
    inc a
    ld e, a
    call Solid
    ret nz
    ld a, d
    add 9
    ld d, a
    call Solid
    ret nz
    ld a, e
    add 5
    ld e, a
    call Solid
    ret nz
    ld a, d
    sub 9
    ld d, a
    jp Solid

CheckPass:
    ldh a, [rSCX]
    add BIRD_X + 3
    ld d, a
    and 7
    ret nz
    ld a, d
    srl a
    srl a
    srl a
    dec a
    and 31
    add low($9800 + 32 * (GROUND_ROW - 1))
    ld l, a
    ld h, high($9800 + 32 * (GROUND_ROW - 1))
    ld a, [hl]
    cp TILE_PIPE_R
    ret nz
    ldh a, [hScoreL]
    add 1
    daa
    ldh [hScoreL], a
    jr nc, .ding
    ldh a, [hScoreH]
    add 1
    daa
    ldh [hScoreH], a
.ding:
    ld hl, SfxDing
    jp PlayTone

BlinkPrompt:
    ldh a, [hAnim]
    and 31
    ret nz
    ldh a, [hAnim]
    and 32
    ld de, PressText
    jr z, .show
    ld de, Blank
.show:
    ld hl, $9800 + 32 * PROMPT_ROW + 6
    ldh a, [hState]
    cp STATE_OVER
    jr nz, .print
    ld hl, PANEL + 32 * 7 + 6
.print:
    jp PrintText

Draw:
    ld hl, $9c00 + 6
    ldh a, [hScoreH]
    call PrintBCD
    ldh a, [hScoreL]
    call PrintBCD
    ld hl, $9c00 + 16
    ldh a, [hBestH]
    call PrintBCD
    ldh a, [hBestL]
    call PrintBCD

    ldh a, [hState]
    cp STATE_OVER
    jr nz, .bird
    ldh a, [rWY]
    cp PANEL_Y
    jr z, .hide
    sub 8
    ldh [rWY], a
.hide:
    xor a
    ld [$fe00], a
    ld [$fe04], a
    ret
.bird:
    ld c, TILE_BIRD
    ld e, 0
    ldh a, [hState]
    and a
    jr nz, .moving
    ldh a, [hAnim]
    and 8
    jr nz, .wingDown
    jr .sprite
.moving:
    cp STATE_PLAY
    jr z, .alive
    ld e, $40
    jr .sprite
.alive:
    ldh a, [hVelH]
    bit 7, a
    jr z, .sprite
.wingDown:
    ld c, TILE_BIRD + 2
.sprite:
    ld hl, $fe00
    ldh a, [hBirdY]
    add 16
    ld b, a
    ld [hl+], a
    ld a, BIRD_X + 8
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld a, BIRD_X + 16
    ld [hl+], a
    ld a, c
    inc a
    ld [hl+], a
    ld [hl], e
    ret

    include "lib/util.asm"
    include "lib/sound.asm"

Bob:
    db 0, 1, 2, 1, 0, -1, -2, -1

HudText:
    db "SCORE      BEST", 0
TitleText:
    db "F L A P", 0
PressText:
    db "PRESS A", 0
Blank:
    db "       ", 0
GameOverText:
    db "GAME OVER", 0
NewBestText:
    db "NEW BEST!", 0

    include "lib/font.asm"

Tiles:
    dw `00000000
    dw `00011100
    dw `01111110
    dw `11111111
    dw `11111111
    dw `01111110
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `22222222
    dw `21111112
    dw `11111111
    dw `11111111
    dw `11111111

    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111

    dw `11111111
    dw `10011001
    dw `10011001
    dw `11111111
    dw `11111111
    dw `10011001
    dw `10011001
    dw `11111111

    dw `31122222
    dw `31122222
    dw `31122222
    dw `31122222
    dw `31122222
    dw `31122222
    dw `31122222
    dw `31122222

    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222233

    dw `33333333
    dw `31111222
    dw `31122222
    dw `31122222
    dw `31122222
    dw `31122222
    dw `31111222
    dw `33333333

    dw `33333333
    dw `22222223
    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222233
    dw `22222223
    dw `33333333

    dw `33333333
    dw `21212121
    dw `12121212
    dw `22222222
    dw `22322232
    dw `22222222
    dw `23222322
    dw `22222222

    dw `22222222
    dw `22322232
    dw `22222222
    dw `32223222
    dw `22222222
    dw `22322232
    dw `22222222
    dw `32223222

    dw `00000333
    dw `03303222
    dw `31132221
    dw `31113221
    dw `03113222
    dw `00332222
    dw `00032222
    dw `00003333

    dw `33000000
    dw `11300000
    dw `13130000
    dw `13130000
    dw `11133330
    dw `23111113
    dw `22333330
    dw `33000000

    dw `00000333
    dw `00003222
    dw `00032221
    dw `03332221
    dw `31113222
    dw `31132222
    dw `03332222
    dw `00003333

    dw `33000000
    dw `11300000
    dw `13130000
    dw `13130000
    dw `11133330
    dw `23111113
    dw `22333330
    dw `33000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `22222222
    dw `00000000
    dw `00000000
    dw `00000000
TilesEnd:
