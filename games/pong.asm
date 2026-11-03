TILE_PADDLE   equ 1
TILE_BALL     equ 2
TILE_NET      equ 3
TILE_DIGITS   equ 4

FIELD_TOP     equ 16
FIELD_BOTTOM  equ 144
PADDLE_HEIGHT equ 24
PADDLE_MIN    equ FIELD_TOP
PADDLE_MAX    equ FIELD_BOTTOM - PADDLE_HEIGHT
BALL_MAX_Y    equ FIELD_BOTTOM - 8
MAX_SPEED     equ 3

include "lib/hardware.asm"

hBallX   equ $ff80
hBallY   equ $ff81
hBallDX  equ $ff82
hBallDY  equ $ff83
hP1Y     equ $ff84
hP2Y     equ $ff85
hScore1  equ $ff86
hScore2  equ $ff87
hFrame   equ $ff88
hServe   equ $ff89
hJoy     equ $ff8a
hSpeed   equ $ff8b
hHits    equ $ff8c

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "PONG"

    org $150
Start:
    di
    ld sp, STACK_TOP
.waitVBlank:
    ldh a, [rLY]
    cp 144
    jr c, .waitVBlank
    xor a
    ldh [rLCDC], a

    ld de, Tiles
    ld hl, $8000
    ld bc, TilesEnd - Tiles
    call MemCopy

    ld hl, $9800
    ld bc, 32 * 32
    ld d, 0
    call MemFill

    ld hl, $fe00
    ld bc, 160
    ld d, 0
    call MemFill

    ld hl, $9800 + 2 * 32 + 9
    ld b, 16
.net:
    ld a, TILE_NET
    ld [hl], a
    ld de, 32
    add hl, de
    dec b
    jr nz, .net

    xor a
    ldh [hScore1], a
    ldh [hScore2], a
    ldh [hFrame], a
    ld a, 60
    ldh [hP1Y], a
    ldh [hP2Y], a
    call Serve
    call SoundOn

    ld a, %11100100
    ldh [rBGP], a
    ldh [rOBP0], a
    ld a, %10010011
    ldh [rLCDC], a

    ld a, 1
    ldh [rIE], a
    xor a
    ldh [rIF], a
    ei

MainLoop:
    halt
    nop
    call Draw
    call ReadJoy
    call MovePlayer
    call MoveCpu
    call MoveBall
    ld hl, hFrame
    inc [hl]
    jr MainLoop

Draw:
    ld hl, $fe00
    ldh a, [hP1Y]
    add 16
    ld b, a
    ld c, 16
    call DrawPaddle
    ldh a, [hP2Y]
    add 16
    ld b, a
    ld c, 160
    call DrawPaddle
    ldh a, [hBallY]
    add 16
    ld [hl+], a
    ldh a, [hBallX]
    add 8
    ld [hl+], a
    ld a, TILE_BALL
    ld [hl+], a
    xor a
    ld [hl+], a
    ldh a, [hScore1]
    add TILE_DIGITS
    ld [$9800 + 32 + 7], a
    ldh a, [hScore2]
    add TILE_DIGITS
    ld [$9800 + 32 + 12], a
    ret

DrawPaddle:
    ld d, 3
.part:
    ld a, b
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, TILE_PADDLE
    ld [hl+], a
    xor a
    ld [hl+], a
    ld a, b
    add 8
    ld b, a
    dec d
    jr nz, .part
    ret

ReadJoy:
    ld a, $20
    ldh [rJOYP], a
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    cpl
    and $0f
    ldh [hJoy], a
    ld a, $30
    ldh [rJOYP], a
    ret

MovePlayer:
    ldh a, [hJoy]
    bit 2, a
    jr z, .notUp
    ldh a, [hP1Y]
    cp PADDLE_MIN + 2
    jr c, .notUp
    sub 2
    ldh [hP1Y], a
.notUp:
    ldh a, [hJoy]
    bit 3, a
    ret z
    ldh a, [hP1Y]
    cp PADDLE_MAX
    ret nc
    add 2
    ldh [hP1Y], a
    ret

MoveCpu:
    ldh a, [rLINK]
    and a
    jr z, .cpu
    ldh a, [rPAD2]
    bit PADB_UP, a
    jr z, .p2Down
    ldh a, [hP2Y]
    cp PADDLE_MIN + 2
    jr c, .p2Down
    sub 2
    ldh [hP2Y], a
.p2Down:
    ldh a, [rPAD2]
    bit PADB_DOWN, a
    ret z
    ldh a, [hP2Y]
    cp PADDLE_MAX
    ret nc
    add 2
    ldh [hP2Y], a
    ret
.cpu:
    ldh a, [hFrame]
    and 3
    ret z
    ldh a, [hBallY]
    add 4
    ld b, a
    ldh a, [hP2Y]
    add PADDLE_HEIGHT / 2
    cp b
    ret z
    jr c, .down
    ldh a, [hP2Y]
    cp PADDLE_MIN + 1
    ret c
    dec a
    ldh [hP2Y], a
    ret
.down:
    ldh a, [hP2Y]
    cp PADDLE_MAX
    ret nc
    inc a
    ldh [hP2Y], a
    ret

MoveBall:
    ldh a, [hServe]
    and a
    jr z, .moving
    dec a
    ldh [hServe], a
    ret
.moving:
    ldh a, [hBallDX]
    ld b, a
    ldh a, [hBallX]
    add b
    ldh [hBallX], a
    ldh a, [hBallDY]
    ld b, a
    ldh a, [hBallY]
    add b
    ldh [hBallY], a
    cp FIELD_TOP
    jr nc, .notTop
    ld a, FIELD_TOP
    ldh [hBallY], a
    call BounceY
    jr .paddles
.notTop:
    cp BALL_MAX_Y + 1
    jr c, .paddles
    ld a, BALL_MAX_Y
    ldh [hBallY], a
    call BounceY
.paddles:
    ldh a, [hBallDX]
    bit 7, a
    jr z, .right
    ldh a, [hBallX]
    cp 4
    jr c, .cpuScores
    cp 14
    ret nc
    cp 8
    ret c
    ldh a, [hP1Y]
    ld c, a
    call HitTest
    ret nc
    call SpeedUp
    ldh a, [hSpeed]
    ldh [hBallDX], a
    ld hl, SfxHit
    jp PlayTone
.right:
    ldh a, [hBallX]
    cp 156
    jr nc, .playerScores
    cp 147
    ret c
    cp 153
    ret nc
    ldh a, [hP2Y]
    ld c, a
    call HitTest
    ret nc
    call SpeedUp
    ldh a, [hSpeed]
    cpl
    inc a
    ldh [hBallDX], a
    ld hl, SfxHit
    jp PlayTone
.cpuScores:
    ld hl, hScore2
    jr .point
.playerScores:
    ld hl, hScore1
.point:
    inc [hl]
    push hl
    ld hl, SfxFall
    call PlaySweep
    pop hl
    ld a, [hl]
    cp 10
    jr c, Serve
    xor a
    ldh [hScore1], a
    ldh [hScore2], a
    jr Serve

BounceY:
    ldh a, [hBallDY]
    cpl
    inc a
    ldh [hBallDY], a
    ld hl, SfxThud
    jp PlayTone

SpeedUp:
    ld hl, hHits
    inc [hl]
    ld a, [hl]
    and 3
    ret nz
    ldh a, [hSpeed]
    cp MAX_SPEED
    ret nc
    inc a
    ldh [hSpeed], a
    ret

HitTest:
    ldh a, [hBallY]
    add 8
    cp c
    jr c, .miss
    jr z, .miss
    ld a, c
    add PADDLE_HEIGHT
    ld b, a
    ldh a, [hBallY]
    cp b
    jr nc, .miss
    add 4
    sub c
    jr c, .top
    cp 6
    jr c, .top
    cp 12
    jr c, .upper
    cp 18
    jr c, .lower
    ld a, 2
    jr .set
.top:
    ld a, -2
    jr .set
.upper:
    ld a, -1
    jr .set
.lower:
    ld a, 1
.set:
    ld b, a
    ldh a, [rDIV]
    and 3
    jr nz, .keep
    ldh a, [rDIV]
    rrca
    rrca
    and 3
    ld e, a
    ld d, 0
    ld hl, Angles
    add hl, de
    ld b, [hl]
.keep:
    ld a, b
    ldh [hBallDY], a
    scf
    ret
.miss:
    and a
    ret

Serve:
    ld a, 76
    ldh [hBallX], a
    ldh [hBallY], a
    ld a, 60
    ldh [hServe], a
    ld a, 1
    ldh [hSpeed], a
    xor a
    ldh [hHits], a
    ldh a, [hScore1]
    ld b, a
    ldh a, [hScore2]
    add b
    and 1
    jr z, .left
    ld a, 1
    jr .aim
.left:
    ld a, -1
.aim:
    ldh [hBallDX], a
    ld a, 1
    ldh [hBallDY], a
    ret

MemCopy:
    ld a, [de]
    ld [hl+], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, MemCopy
    ret

MemFill:
    ld a, d
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, MemFill
    ret

    include "lib/sound.asm"

Angles:
    db -2, -1, 1, 2

Tiles:
    ds 16, 0

    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300

    dw `00333300
    dw `03333330
    dw `33333333
    dw `33333333
    dw `33333333
    dw `33333333
    dw `03333330
    dw `00333300

    dw `00011000
    dw `00011000
    dw `00011000
    dw `00011000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00333000
    dw `03000300
    dw `03003300
    dw `03030300
    dw `03300300
    dw `03000300
    dw `00333000
    dw `00000000

    dw `00030000
    dw `00330000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `00030000
    dw `00333000
    dw `00000000

    dw `00333000
    dw `03000300
    dw `00000300
    dw `00003000
    dw `00030000
    dw `00300000
    dw `03333300
    dw `00000000

    dw `03333300
    dw `00003000
    dw `00030000
    dw `00003000
    dw `00000300
    dw `03000300
    dw `00333000
    dw `00000000

    dw `00003000
    dw `00033000
    dw `00303000
    dw `03003000
    dw `03333300
    dw `00003000
    dw `00003000
    dw `00000000

    dw `03333300
    dw `03000000
    dw `03333000
    dw `00000300
    dw `00000300
    dw `03000300
    dw `00333000
    dw `00000000

    dw `00033000
    dw `00300000
    dw `03000000
    dw `03333000
    dw `03000300
    dw `03000300
    dw `00333000
    dw `00000000

    dw `03333300
    dw `00000300
    dw `00003000
    dw `00030000
    dw `00300000
    dw `00300000
    dw `00300000
    dw `00000000

    dw `00333000
    dw `03000300
    dw `03000300
    dw `00333000
    dw `03000300
    dw `03000300
    dw `00333000
    dw `00000000

    dw `00333000
    dw `03000300
    dw `03000300
    dw `00333300
    dw `00000300
    dw `00003000
    dw `00330000
    dw `00000000
TilesEnd:
