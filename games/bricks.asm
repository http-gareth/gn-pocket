include "lib/hardware.asm"

TILE_WALL   equ FIRST_TILE
TILE_BRICK  equ FIRST_TILE + 1
TILE_PADDLE equ FIRST_TILE + 7
TILE_BALL   equ FIRST_TILE + 10
TILE_LIFE   equ FIRST_TILE + 11

STATE_TITLE equ 0
STATE_SERVE equ 1
STATE_PLAY  equ 2
STATE_OVER  equ 3

BRICK_TOP  equ 3
BRICK_ROWS equ 6
BRICK_COLS equ 9
BRICKS     equ BRICK_ROWS * BRICK_COLS
PADDLE_Y   equ 136
PADDLE_W   equ 24
PADDLE_SPEED equ 3
FIELD_L    equ 8
FIELD_R    equ 152
FIELD_T    equ 16
BALL_SIZE  equ 4
LOST_Y     equ 150
MSG_ROW    equ $9800 + 32 * 13

hState  equ $ff80
hPadX   equ $ff81
hBallX  equ $ff82
hBallY  equ $ff83
hVX     equ $ff84
hVY     equ $ff85
hLives  equ $ff86
hScoreL equ $ff87
hScoreH equ $ff88
hBricks equ $ff89
hLevel  equ $ff8a
hBestL  equ $ff8b
hBestH  equ $ff8c
hBlink  equ $ff8d

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "BRICKS"

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
    call SeedRandom
    xor a
    ldh [hBestL], a
    ldh [hBestH], a
    ldh [hScoreL], a
    ldh [hScoreH], a
    ld a, 3
    ldh [hLives], a
    ld a, 1
    ldh [hLevel], a
    call ShowTitle
    ld a, LCDC_ON
    ldh [rLCDC], a
    call EnableVBlank

MainLoop:
    halt
    nop
    call Draw
    call ReadJoypad
    ldh a, [hState]
    cp STATE_TITLE
    jr nz, .notTitle
    call WaitForStart
    jr MainLoop
.notTitle:
    cp STATE_SERVE
    jr nz, .notServe
    call Serve
    jr MainLoop
.notServe:
    cp STATE_PLAY
    jr nz, .over
    call Play
    jr MainLoop
.over:
    call WaitForStart
    jr MainLoop

ShowTitle:
    ld a, STATE_TITLE
    ldh [hState], a
    ld a, (FIELD_L + FIELD_R - PADDLE_W) / 2
    ldh [hPadX], a
    call BuildLevel
    ld hl, $9800 + 32 * 11 + 4
    ld de, TitleText
    call PrintText
    jp DrawBest

WaitForStart:
    call BlinkPrompt
    ldh a, [hJoyPressed]
    and PAD_START | PAD_A
    ret z
    ld hl, SfxRise
    call PlaySweep
    xor a
    ldh [hScoreL], a
    ldh [hScoreH], a
    ld a, 3
    ldh [hLives], a
    ld a, 1
    ldh [hLevel], a
    call LcdOff
    call BuildLevel
    ld a, LCDC_ON
    ldh [rLCDC], a
    jp ToServe

BuildLevel:
    call ClearScreen
    ld hl, $9800 + 1
    ld de, ScoreText
    call PrintText
    ld hl, $9800 + 12
    ld de, LevelText
    call PrintText

    ld hl, $9800 + 32
    ld b, 20
    ld a, TILE_WALL
.top:
    ld [hl+], a
    dec b
    jr nz, .top

    ld hl, $9800 + 32 * 2
    ld b, 16
.sides:
    ld a, TILE_WALL
    ld [hl], a
    push hl
    ld de, 19
    add hl, de
    ld [hl], a
    pop hl
    ld de, 32
    add hl, de
    dec b
    jr nz, .sides

    ld hl, $9800 + 32 * BRICK_TOP + 1
    ld c, 0
.row:
    ld a, c
    srl a
    add a
    add TILE_BRICK
    ld d, a
    ld b, BRICK_COLS
.brick:
    ld a, d
    ld [hl+], a
    inc a
    ld [hl+], a
    dec b
    jr nz, .brick
    ld de, 32 - BRICK_COLS * 2
    add hl, de
    inc c
    ld a, c
    cp BRICK_ROWS
    jr nz, .row
    ld a, BRICKS
    ldh [hBricks], a
    ret

ToServe:
    ld a, STATE_SERVE
    ldh [hState], a
    ld hl, MSG_ROW + 5
    ld de, LaunchText
    jp PrintText

Serve:
    call MovePaddle
    ldh a, [hPadX]
    add PADDLE_W / 2 - BALL_SIZE / 2
    ldh [hBallX], a
    ld a, PADDLE_Y - BALL_SIZE
    ldh [hBallY], a
    ldh a, [hJoyPressed]
    and PAD_A | PAD_START
    ret z
    ld hl, MSG_ROW + 5
    ld de, LaunchBlank
    call PrintText
    call Random
    and 1
    ld a, 1
    jr z, .aim
    ld a, -1
.aim:
    ldh [hVX], a
    call BallSpeed
    ldh [hVY], a
    ld a, STATE_PLAY
    ldh [hState], a
    ld hl, SfxHit
    jp PlayTone

BallSpeed:
    ldh a, [hLevel]
    cp 2
    jr nc, .fast
    ldh a, [hBricks]
    cp BRICKS / 2 + 1
    jr c, .fast
    ld a, -1
    ret
.fast:
    ld a, -2
    ret

Play:
    call MovePaddle
    call MoveBallX
    call MoveBallY
    ldh a, [hState]
    cp STATE_PLAY
    ret nz
    ldh a, [hBricks]
    and a
    ret nz
    ld hl, SfxRise
    call PlaySweep
    ld hl, hLevel
    ld a, [hl]
    cp 9
    jr nc, .rebuild
    inc [hl]
.rebuild:
    call LcdOff
    call BuildLevel
    ld a, LCDC_ON
    ldh [rLCDC], a
    jp ToServe

MovePaddle:
    ldh a, [hJoyHeld]
    ld b, a
    ldh a, [hPadX]
    bit PADB_LEFT, b
    jr z, .notLeft
    sub PADDLE_SPEED
    cp FIELD_L
    jr nc, .notLeft
    ld a, FIELD_L
.notLeft:
    bit PADB_RIGHT, b
    jr z, .store
    add PADDLE_SPEED
    cp FIELD_R - PADDLE_W + 1
    jr c, .store
    ld a, FIELD_R - PADDLE_W
.store:
    ldh [hPadX], a
    ret

MoveBallX:
    ldh a, [hVX]
    ld b, a
    ldh a, [hBallX]
    add b
    cp FIELD_L
    jr c, .wallLeft
    cp FIELD_R - BALL_SIZE + 1
    jr nc, .wallRight
    ld c, a
    bit 7, b
    jr nz, .probe
    add BALL_SIZE - 1
.probe:
    ld d, a
    ldh a, [hBallY]
    add BALL_SIZE / 2
    ld e, a
    call HitBrick
    jr z, .free
    jp FlipX
.free:
    ld a, c
    ldh [hBallX], a
    ret
.wallLeft:
    ld a, FIELD_L
    jr .bounce
.wallRight:
    ld a, FIELD_R - BALL_SIZE
.bounce:
    ldh [hBallX], a
    call FlipX
    ld hl, SfxThud
    jp PlayTone

FlipX:
    ldh a, [hVX]
    cpl
    inc a
    ldh [hVX], a
    ret

FlipY:
    ldh a, [hVY]
    cpl
    inc a
    ldh [hVY], a
    ret

MoveBallY:
    ldh a, [hVY]
    ld b, a
    ldh a, [hBallY]
    add b
    cp FIELD_T
    jp c, .ceiling
    cp LOST_Y
    jp nc, .lost
    ld c, a
    bit 7, b
    jr nz, .bricks
    add BALL_SIZE
    cp PADDLE_Y
    jr c, .bricks
    cp PADDLE_Y + 5
    jr nc, .bricks
    ldh a, [hPadX]
    ld d, a
    ldh a, [hBallX]
    add BALL_SIZE
    cp d
    jr c, .bricks
    jr z, .bricks
    ld a, d
    add PADDLE_W
    ld e, a
    ldh a, [hBallX]
    cp e
    jr nc, .bricks
    add BALL_SIZE / 2
    sub d
    jr nc, .zone
    xor a
.zone:
    ld e, 0
    cp 5
    jr c, .angle
    inc e
    cp 10
    jr c, .angle
    inc e
    cp 16
    jr c, .angle
    inc e
    cp 21
    jr c, .angle
    inc e
.angle:
    ld d, 0
    ld hl, Angles
    add hl, de
    ld a, [hl]
    and a
    jr nz, .setVX
    ldh a, [hVX]
    bit 7, a
    ld a, 1
    jr z, .setVX
    ld a, -1
.setVX:
    ldh [hVX], a
    call BallSpeed
    ldh [hVY], a
    ld a, PADDLE_Y - BALL_SIZE
    ldh [hBallY], a
    ld hl, SfxHit
    jp PlayTone
.bricks:
    ld a, c
    bit 7, b
    jr nz, .probe
    add BALL_SIZE - 1
.probe:
    ld e, a
    ldh a, [hBallX]
    add BALL_SIZE / 2
    ld d, a
    call HitBrick
    jp nz, FlipY
    ld a, c
    ldh [hBallY], a
    ret
.ceiling:
    ld a, FIELD_T
    ldh [hBallY], a
    call FlipY
    ld hl, SfxThud
    jp PlayTone
.lost:
    ld hl, SfxCrash
    call PlayNoise
    ld hl, hLives
    dec [hl]
    jp nz, ToServe

GameOver:
    ld a, STATE_OVER
    ldh [hState], a
    ldh a, [hBestH]
    ld b, a
    ldh a, [hScoreH]
    cp b
    jr c, .show
    jr nz, .best
    ldh a, [hBestL]
    ld b, a
    ldh a, [hScoreL]
    cp b
    jr c, .show
    jr z, .show
.best:
    ldh a, [hScoreL]
    ldh [hBestL], a
    ldh a, [hScoreH]
    ldh [hBestH], a
.show:
    ld hl, $9800 + 32 * 11 + 5
    ld de, GameOverText
    call PrintText

DrawBest:
    ld a, 31
    ldh [hBlink], a
    ld hl, $9800 + 32 * 15 + 5
    ld de, BestText
    call PrintText
    ldh a, [hBestH]
    call PrintBCD
    ldh a, [hBestL]
    jp PrintBCD

HitBrick:
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
    add l
    ld l, a
    ld a, h
    adc high($9800)
    ld h, a
    ld a, [hl]
    sub TILE_BRICK
    cp 6
    jr nc, .none
    bit 0, a
    jr z, .left
    dec hl
.left:
    ld [hl], TILE_SPACE
    inc hl
    ld [hl], TILE_SPACE
    srl a
    add a
    add a
    ld e, a
    ld d, 0
    ld hl, BrickSounds
    add hl, de
    call PlayTone
    ldh a, [hScoreL]
    add 1
    daa
    ldh [hScoreL], a
    jr nc, .counted
    ldh a, [hScoreH]
    add 1
    daa
    ldh [hScoreH], a
.counted:
    ld hl, hBricks
    dec [hl]
    or 1
    ret
.none:
    xor a
    ret

BlinkPrompt:
    ld hl, hBlink
    inc [hl]
    ld a, [hl]
    and 31
    ret nz
    ld a, [hl]
    and 32
    ld hl, MSG_ROW + 4
    ld de, PressText
    jr nz, .show
    ld de, PressBlank
.show:
    jp PrintText

Draw:
    ld hl, $9800 + 7
    ldh a, [hScoreH]
    call PrintBCD
    ldh a, [hScoreL]
    call PrintBCD
    ldh a, [hLevel]
    add '0' - 32
    ld [$9800 + 14], a
    ld hl, $9800 + 16
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

    ld hl, $fe00
    ldh a, [hPadX]
    add 8
    ld c, a
    ld d, TILE_PADDLE
    ld e, 3
.paddle:
    ld a, PADDLE_Y - 1 + 16
    ld [hl+], a
    ld a, c
    ld [hl+], a
    add 8
    ld c, a
    ld a, d
    ld [hl+], a
    inc d
    xor a
    ld [hl+], a
    dec e
    jr nz, .paddle

    ldh a, [hState]
    cp STATE_SERVE
    jr c, .noBall
    cp STATE_OVER
    jr z, .noBall
    ldh a, [hBallY]
    add 16 - 2
    ld [hl+], a
    ldh a, [hBallX]
    add 8 - 2
    ld [hl+], a
    ld a, TILE_BALL
    ld [hl+], a
    xor a
    ld [hl], a
    ret
.noBall:
    xor a
    ld [hl], a
    ret

    include "lib/util.asm"
    include "lib/sound.asm"

Angles:
    db -2, -1, 0, 1, 2

BrickSounds:
    db $80, $c1, low(1890), $80 | high(1890)
    db $80, $c1, low(1850), $80 | high(1850)
    db $80, $c1, low(1810), $80 | high(1810)

ScoreText:
    db "SCORE", 0
LevelText:
    db "LV", 0
TitleText:
    db "B R I C K S", 0
GameOverText:
    db "GAME OVER", 0
BestText:
    db "BEST ", 0
PressText:
    db "PRESS START", 0
PressBlank:
    db "           ", 0
LaunchText:
    db "A: LAUNCH", 0
LaunchBlank:
    db "         ", 0

    include "lib/font.asm"

Tiles:
    dw `32323232
    dw `23232323
    dw `32323232
    dw `23232323
    dw `32323232
    dw `23232323
    dw `32323232
    dw `23232323

    dw `33333333
    dw `32222222
    dw `32222222
    dw `32222222
    dw `32222222
    dw `32222222
    dw `33333333
    dw `00000000

    dw `33333330
    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230
    dw `22222230
    dw `33333330
    dw `00000000

    dw `33333333
    dw `31111111
    dw `31111111
    dw `31111111
    dw `31111111
    dw `31111111
    dw `33333333
    dw `00000000

    dw `33333330
    dw `11111130
    dw `11111130
    dw `11111130
    dw `11111130
    dw `11111130
    dw `33333330
    dw `00000000

    dw `22222222
    dw `21111111
    dw `21000000
    dw `21000000
    dw `21000000
    dw `21000000
    dw `22222222
    dw `00000000

    dw `22222220
    dw `11111120
    dw `00000120
    dw `00000120
    dw `00000120
    dw `00000120
    dw `22222220
    dw `00000000

    dw `00000000
    dw `03333333
    dw `31111111
    dw `31111111
    dw `33333333
    dw `03333333
    dw `00000000
    dw `00000000

    dw `00000000
    dw `33333333
    dw `11111111
    dw `11111111
    dw `33333333
    dw `33333333
    dw `00000000
    dw `00000000

    dw `00000000
    dw `33333330
    dw `11111113
    dw `11111113
    dw `33333333
    dw `33333330
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00033000
    dw `00333300
    dw `00333300
    dw `00033000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00033000
    dw `00333300
    dw `03333330
    dw `03333330
    dw `00333300
    dw `00033000
    dw `00000000
TilesEnd:
