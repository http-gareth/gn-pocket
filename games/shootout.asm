include "lib/hardware.asm"

TILE_GRASS_A equ FIRST_TILE
TILE_GRASS_B equ FIRST_TILE + 1
TILE_NET     equ FIRST_TILE + 2
TILE_POST    equ FIRST_TILE + 3
TILE_BAR     equ FIRST_TILE + 4
TILE_LINE    equ FIRST_TILE + 5
TILE_BALL    equ FIRST_TILE + 6
TILE_MARK    equ FIRST_TILE + 7
TILE_KEEP    equ FIRST_TILE + 8

PHASE_AIM    equ 0
PHASE_READY  equ 1
PHASE_FLIGHT equ 2
PHASE_RESULT equ 3
PHASE_END    equ 4

RESULT_GOAL  equ 0
RESULT_SAVED equ 1
RESULT_MISS  equ 2

KICKS     equ 10
FLIGHT    equ 32
BALL_X0   equ 76
BALL_Y0   equ 116
BALL_Y1   equ 44
STEP_Y    equ (BALL_Y1 - BALL_Y0) * 256 / FLIGHT
KEEP_Y    equ 40
KEEP_HOME equ 80
KEEP_MIN  equ 44
KEEP_MAX  equ 116
KEEP_REACH equ 11
MARK_MIN  equ 24
MARK_MAX  equ 136
MARK_Y    equ 16
MSG_ROW   equ 10
MSG_ADDR  equ $9800 + 32 * MSG_ROW

hPhase      equ $ff80
hTimer      equ $ff81
hKick       equ $ff82
hYou        equ $ff83
hCpu        equ $ff84
hZone       equ $ff85
hMarkX      equ $ff86
hMarkDir    equ $ff87
hKeepX      equ $ff88
hKeepTarget equ $ff89
hBallXL     equ $ff8a
hBallXH     equ $ff8b
hBallYL     equ $ff8c
hBallYH     equ $ff8d
hStepXL     equ $ff8e
hStepXH     equ $ff8f
hResult     equ $ff90

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "SHOOTOUT"

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
    call NewMatch
    ld a, LCDC_ON
    ldh [rLCDC], a
    call EnableVBlank

MainLoop:
    halt
    nop
    call DrawSprites
    call ReadJoypad
    ldh a, [hPhase]
    cp PHASE_AIM
    jr nz, .notAim
    call Aim
    jr MainLoop
.notAim:
    cp PHASE_READY
    jr nz, .notReady
    call Ready
    jr MainLoop
.notReady:
    cp PHASE_FLIGHT
    jr nz, .notFlight
    call Flight
    jr MainLoop
.notFlight:
    cp PHASE_RESULT
    jr nz, .notResult
    call Result
    jr MainLoop
.notResult:
    call End
    jr MainLoop

NewMatch:
    call ClearScreen
    call DrawPitch
    xor a
    ldh [hKick], a
    ldh [hYou], a
    ldh [hCpu], a
    call DrawScores
    jp StartKick

DrawPitch:
    ld hl, $9800 + 32 * 8
    ld c, 8
.row:
    ld a, c
    srl a
    and 1
    add TILE_GRASS_A
    ld b, 20
.col:
    ld [hl+], a
    dec b
    jr nz, .col
    ld de, 12
    add hl, de
    inc c
    ld a, c
    cp 18
    jr nz, .row

    ld hl, $9800 + 32 * 7
    ld b, 20
    ld a, TILE_LINE
.line:
    ld [hl+], a
    dec b
    jr nz, .line

    ld hl, $9800 + 32 * 3 + 4
    ld b, 12
    ld a, TILE_BAR
.bar:
    ld [hl+], a
    dec b
    jr nz, .bar

    ld hl, $9800 + 32 * 4 + 4
    ld c, 3
.goal:
    ld a, TILE_POST
    ld [hl+], a
    ld b, 10
    ld a, TILE_NET
.net:
    ld [hl+], a
    dec b
    jr nz, .net
    ld a, TILE_POST
    ld [hl+], a
    ld de, 32 - 12
    add hl, de
    dec c
    jr nz, .goal

    ld hl, $9800 + 1
    ld de, YouText
    call PrintText
    ld hl, $9800 + 14
    ld de, CpuText
    call PrintText
    ld hl, $9800 + 32 + 1
    ld de, Dashes
    call PrintText
    ld hl, $9800 + 32 + 14
    ld de, Dashes
    jp PrintText

DrawScores:
    ldh a, [hYou]
    add '0' - 32
    ld [$9800 + 5], a
    ldh a, [hCpu]
    add '0' - 32
    ld [$9800 + 18], a
    ret

StartKick:
    ld a, BALL_X0
    ldh [hBallXH], a
    ld a, BALL_Y0
    ldh [hBallYH], a
    xor a
    ldh [hBallXL], a
    ldh [hBallYL], a
    ld a, KEEP_HOME
    ldh [hKeepX], a
    ld a, MARK_MIN
    ldh [hMarkX], a
    ldh a, [hKick]
    srl a
    srl a
    add 2
    ldh [hMarkDir], a
    ldh a, [hKick]
    and 1
    jr nz, .cpu
    ld a, PHASE_AIM
    ldh [hPhase], a
    ld de, MsgShoot
    jp ShowMessage
.cpu:
    ld a, 45
    ldh [hTimer], a
    ld a, PHASE_READY
    ldh [hPhase], a
    ld de, MsgSave
    jp ShowMessage

Aim:
    ldh a, [hMarkDir]
    ld b, a
    ldh a, [hMarkX]
    add b
    cp MARK_MIN
    jr nc, .notLow
    ld a, b
    cpl
    inc a
    ldh [hMarkDir], a
    ld a, MARK_MIN
    jr .store
.notLow:
    cp MARK_MAX + 1
    jr c, .store
    ld a, b
    cpl
    inc a
    ldh [hMarkDir], a
    ld a, MARK_MAX
.store:
    ldh [hMarkX], a
    ldh a, [hJoyPressed]
    and PAD_A
    ret z
    ldh a, [hMarkX]
    sub MARK_MIN
    swap a
    and $0f
    cp 7
    jr c, .zone
    ld a, 6
.zone:
    ldh [hZone], a
    call RandomGoalZone
    call ZoneCenter
    ldh [hKeepTarget], a
    jp Launch

Ready:
    ld hl, hTimer
    dec [hl]
    ret nz
    call Random
    and 15
    jr z, .wideLeft
    cp 15
    jr z, .wideRight
    call RandomGoalZone
    jr .chosen
.wideLeft:
    xor a
    jr .chosen
.wideRight:
    ld a, 6
.chosen:
    ldh [hZone], a
    jp Launch

RandomGoalZone:
    call Random
    and 7
    cp 5
    jr nc, RandomGoalZone
    inc a
    ret

ZoneCenter:
    swap a
    add 32
    ret

Launch:
    ldh a, [hZone]
    add a
    ld e, a
    ld d, 0
    ld hl, StepTable
    add hl, de
    ld a, [hl+]
    ldh [hStepXL], a
    ld a, [hl]
    ldh [hStepXH], a
    ld a, FLIGHT
    ldh [hTimer], a
    ld a, PHASE_FLIGHT
    ldh [hPhase], a
    ld hl, SfxKick
    call PlayNoise
    jp HideMessage

Flight:
    ldh a, [hStepXL]
    ld b, a
    ldh a, [hBallXL]
    add b
    ldh [hBallXL], a
    ldh a, [hStepXH]
    ld b, a
    ldh a, [hBallXH]
    adc b
    ldh [hBallXH], a
    ldh a, [hBallYL]
    add low(STEP_Y)
    ldh [hBallYL], a
    ldh a, [hBallYH]
    adc high(STEP_Y)
    ldh [hBallYH], a

    ldh a, [hKick]
    and 1
    jr nz, .playerKeeps
    ldh a, [hKeepTarget]
    ld b, a
    ldh a, [hKeepX]
    cp b
    jr z, .tick
    jr c, .right
    dec a
    jr .move
.right:
    inc a
.move:
    ldh [hKeepX], a
    jr .tick
.playerKeeps:
    ldh a, [hJoyHeld]
    ld b, a
    ldh a, [hKeepX]
    bit PADB_LEFT, b
    jr z, .noLeft
    cp KEEP_MIN + 1
    jr c, .noLeft
    dec a
.noLeft:
    bit PADB_RIGHT, b
    jr z, .noRight
    cp KEEP_MAX
    jr nc, .noRight
    inc a
.noRight:
    ldh [hKeepX], a
.tick:
    ld hl, hTimer
    dec [hl]
    ret nz

Judge:
    ldh a, [hZone]
    and a
    jr z, .miss
    cp 6
    jr z, .miss
    ldh a, [hBallXH]
    add 4
    ld b, a
    ldh a, [hKeepX]
    sub b
    jr nc, .distance
    cpl
    inc a
.distance:
    cp KEEP_REACH
    jr c, .saved
    ld c, RESULT_GOAL
    jr .record
.saved:
    ld c, RESULT_SAVED
    jr .record
.miss:
    ld c, RESULT_MISS
.record:
    ld a, c
    ldh [hResult], a
    ldh a, [hKick]
    srl a
    ld b, a
    ldh a, [hKick]
    and 1
    ld a, b
    jr nz, .cpuSlot
    add 1
    jr .slot
.cpuSlot:
    add 14
.slot:
    add $20
    ld l, a
    ld h, $98
    ld a, c
    and a
    ld a, 'O' - 32
    jr z, .mark
    ld a, 'X' - 32
.mark:
    ld [hl], a

    ld a, c
    and a
    jr nz, .say
    ldh a, [hKick]
    and 1
    ld hl, hYou
    jr z, .point
    ld hl, hCpu
.point:
    inc [hl]
    call DrawScores
.say:
    ld a, c
    ld de, MsgGoal
    and a
    jr z, .show
    ld de, MsgSaved
    dec a
    jr z, .show
    ld de, MsgMiss
.show:
    call ShowMessage
    call ResultSound
    ld a, 70
    ldh [hTimer], a
    ld a, PHASE_RESULT
    ldh [hPhase], a
    ret

Result:
    ld hl, hTimer
    dec [hl]
    ret nz
    ld hl, hKick
    inc [hl]
    ld a, [hl]
    cp KICKS
    jp c, StartKick
    ld a, PHASE_END
    ldh [hPhase], a
    ldh a, [hCpu]
    ld b, a
    ldh a, [hYou]
    cp b
    ld de, MsgDraw
    jr z, .final
    ld de, MsgWin
    jr nc, .final
    ld de, MsgLose
.final:
    call ShowMessage
    ld hl, MSG_ADDR + 64
    ld de, MsgAgain
    jp PrintText

ResultSound:
    ldh a, [hResult]
    and a
    jr nz, .notGoal
    ld hl, SfxCrowd
    call PlayNoise
    ld hl, SfxRise
    jp PlaySweep
.notGoal:
    dec a
    ld hl, SfxThud
    jp z, PlayTone
    ld hl, SfxFall
    jp PlaySweep

End:
    ldh a, [hJoyPressed]
    and PAD_A | PAD_START
    ret z
    call LcdOff
    call NewMatch
    ld a, LCDC_ON
    ldh [rLCDC], a
    ret

ShowMessage:
    ld hl, MSG_ADDR
    jp PrintText

HideMessage:
    ld hl, MSG_ADDR
    ld b, 20
    ld a, TILE_GRASS_A + ((MSG_ROW >> 1) & 1)
.fill:
    ld [hl+], a
    dec b
    jr nz, .fill
    ret

DrawSprites:
    ld hl, $fe00
    ldh a, [hBallYH]
    add 16
    ld [hl+], a
    ldh a, [hBallXH]
    add 8
    ld [hl+], a
    ld a, TILE_BALL
    ld [hl+], a
    xor a
    ld [hl+], a

    ldh a, [hPhase]
    and a
    ld a, 0
    jr nz, .markY
    ld a, MARK_Y + 16
.markY:
    ld [hl+], a
    ldh a, [hMarkX]
    add 8 - 4
    ld [hl+], a
    ld a, TILE_MARK
    ld [hl+], a
    xor a
    ld [hl+], a

    ldh a, [hKeepX]
    ld c, a
    ld b, KEEP_Y + 16
    ld d, TILE_KEEP
    call KeeperRow
    ld b, KEEP_Y + 16 + 8

KeeperRow:
    ld a, b
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, d
    ld [hl+], a
    xor a
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld a, c
    add 8
    ld [hl+], a
    ld a, d
    inc a
    ld [hl+], a
    xor a
    ld [hl+], a
    inc d
    inc d
    ret

    include "lib/util.asm"
    include "lib/sound.asm"

StepTable:
    dw (0 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT
    dw (1 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT
    dw (2 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT
    dw (3 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT
    dw (4 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT
    dw (5 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT
    dw (6 * 16 + 32 - 4 - BALL_X0) * 256 / FLIGHT

YouText:
    db "YOU", 0
CpuText:
    db "CPU", 0
Dashes:
    db "-----", 0
MsgShoot:
    db "  PRESS A TO SHOOT  ", 0
MsgSave:
    db "  SAVE IT: USE < >  ", 0
MsgGoal:
    db "        GOAL!       ", 0
MsgSaved:
    db "       SAVED!       ", 0
MsgMiss:
    db "        MISS!       ", 0
MsgWin:
    db "      YOU WIN!      ", 0
MsgLose:
    db "     CPU WINS!      ", 0
MsgDraw:
    db "       DRAW!        ", 0
MsgAgain:
    db "   A: PLAY AGAIN    ", 0

    include "lib/font.asm"

Tiles:
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111
    dw `11111111

    dw `11111111
    dw `11121111
    dw `11111111
    dw `11111121
    dw `11111111
    dw `12111111
    dw `11111111
    dw `11111211

    dw `20000020
    dw `02000200
    dw `00202000
    dw `00020000
    dw `00202000
    dw `02000200
    dw `20000020
    dw `00000000

    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300
    dw `00333300

    dw `33333333
    dw `33333333
    dw `33333333
    dw `00000000
    dw `00202000
    dw `00020000
    dw `00202000
    dw `02000200

    dw `11111111
    dw `11111111
    dw `11111111
    dw `00000000
    dw `00000000
    dw `11111111
    dw `11111111
    dw `11111111

    dw `00333300
    dw `03111130
    dw `31133113
    dw `31333313
    dw `31333313
    dw `31133113
    dw `03111130
    dw `00333300

    dw `00033000
    dw `00033000
    dw `00033000
    dw `00033000
    dw `03333330
    dw `00333300
    dw `00033000
    dw `00000000

    dw `00000033
    dw `00000333
    dw `00000333
    dw `00000033
    dw `33002222
    dw `03302222
    dw `00332222
    dw `00002222

    dw `33000000
    dw `33300000
    dw `33300000
    dw `33000000
    dw `22220033
    dw `22220330
    dw `22223300
    dw `22220000

    dw `00002222
    dw `00002222
    dw `00001111
    dw `00001100
    dw `00001100
    dw `00001100
    dw `00033300
    dw `00033300

    dw `22220000
    dw `22220000
    dw `11110000
    dw `00110000
    dw `00110000
    dw `00110000
    dw `00333000
    dw `00333000
TilesEnd:
