include "lib/hardware.asm"

TILE_WALL     equ FIRST_TILE
TILE_BEAM     equ FIRST_TILE + 1
TILE_WINDOW   equ FIRST_TILE + 2
TILE_EDGE     equ FIRST_TILE + 3
TILE_FLOOR    equ FIRST_TILE + 4
TILE_BAR      equ FIRST_TILE + 5
TILE_STAR     equ FIRST_TILE + 14
TILE_NOSTAR   equ FIRST_TILE + 15
TILE_LANTERN  equ FIRST_TILE + 16
TILE_CREST    equ FIRST_TILE + 20
TILE_PANEL    equ FIRST_TILE + 24
TILE_MAT      equ FIRST_TILE + 25
TILE_FIGHTER  equ FIRST_TILE + 26
FRAME_TILES   equ 9
TILE_FIREBALL equ TILE_FIGHTER + FRAME_TILES * 10
TILE_SPARK    equ TILE_FIREBALL + 1

F_IDLE    equ 0
F_WALK    equ 1
F_PUNCH   equ 3
F_KICK    equ 4
F_BLOCK   equ 5
F_JUMP    equ 6
F_HIT     equ 7
F_SPECIAL equ 8
F_KO      equ 9

S_IDLE   equ 0
S_WALK   equ 1
S_ATTACK equ 2
S_JUMP   equ 3
S_HIT    equ 4
S_KO     equ 5

A_PUNCH    equ 0
A_KICK     equ 1
A_JUMPKICK equ 2
A_SPECIAL  equ 3
NO_ATTACK  equ $ff

G_TITLE    equ 0
G_INTRO    equ 1
G_FIGHT    equ 2
G_ROUNDEND equ 3
G_MATCHEND equ 4

GROUND     equ 112
MIN_X      equ 4
MAX_X      equ 132
HP_MAX     equ 64
JUMP_V     equ 6
FB_COOL    equ 90
SPECIAL_AT equ 10
SPECIAL_END equ 26
JUMPKICK_DAMAGE equ 7
FIREBALL_DAMAGE equ 9
MSG_ROW    equ $9800 + 32 * 5

P_X     equ 0
P_Y     equ 1
P_VY    equ 2
P_STATE equ 3
P_TIMER equ 4
P_FACE  equ 5
P_HP    equ 6
P_HIT   equ 7
P_ATK   equ 8
P_COOL  equ 9
P_BLOCK equ 10
P_WINS  equ 11
P_FBX   equ 12
P_FBDIR equ 13
P_VX    equ 14
P_FRAME equ 15

hState    equ $ff80
hTimer    equ $ff81
hRound    equ $ff82
hClock    equ $ff83
hClockT   equ $ff84
hTick     equ $ff85
hAiTimer  equ $ff86
hAiBlock  equ $ff87
hIn       equ $ff88
hInP      equ $ff89
hSparkX   equ $ff8a
hSparkY   equ $ff8b
hSparkT   equ $ff8c
hKO       equ $ff8d
hPad2Old  equ $ff8e

P1 equ $ff90
P2 equ $ffa0
ME equ $ffb0
THEM equ $ffc0

mX     equ ME + P_X
mY     equ ME + P_Y
mVY    equ ME + P_VY
mState equ ME + P_STATE
mTimer equ ME + P_TIMER
mFace  equ ME + P_FACE
mHP    equ ME + P_HP
mHit   equ ME + P_HIT
mAtk   equ ME + P_ATK
mCool  equ ME + P_COOL
mBlock equ ME + P_BLOCK
mFbx   equ ME + P_FBX
mFbDir equ ME + P_FBDIR
mVX    equ ME + P_VX
mFrame equ ME + P_FRAME
tX     equ THEM + P_X
tY     equ THEM + P_Y
tVY    equ THEM + P_VY
tState equ THEM + P_STATE
tTimer equ THEM + P_TIMER
tHP    equ THEM + P_HP
tBlock equ THEM + P_BLOCK

    org $40
    reti

    org $100
    nop
    jp Start

    org $134
    db "KNOCKOUT"

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
    ld a, %11011000
    ldh [rOBP1], a
    call SoundOn
    call MusicStop
    call SeedRandom
    call ShowTitle
    ld a, LCDC_ON
    ldh [rLCDC], a
    call EnableVBlank

MainLoop:
    halt
    nop
    call Draw
    call ReadJoypad
    call MusicTick
    ld hl, hTick
    inc [hl]
    ldh a, [hState]
    cp G_FIGHT
    jr z, .fight
    cp G_INTRO
    jr z, .intro
    cp G_ROUNDEND
    jr z, .roundEnd
    cp G_MATCHEND
    jr z, .matchEnd
    call Title
    jr MainLoop
.fight:
    call Fight
    jr MainLoop
.intro:
    call Intro
    jr MainLoop
.roundEnd:
    call RoundEnd
    jr MainLoop
.matchEnd:
    call MatchEnd
    jr MainLoop

DrawStage:
    call ClearScreen
    ld hl, $9800 + 32 * 3
    ld b, 3
.row:
    ld c, 0
.cell:
    ld a, b
    cp 14
    ld a, TILE_EDGE
    jr z, .put
    ld a, b
    cp 14
    ld a, TILE_FLOOR
    jr nc, .put
    ld a, b
    sub 8
    cp 4
    jr nc, .wall
    ld a, c
    cp 6
    jr c, .wall
    cp 14
    jr nc, .wall
    cp 10
    jr z, .wall
    cp 9
    jr z, .wall
    ld a, TILE_WINDOW
    jr .put
.wall:
    ld a, c
    cp 5
    jr z, .beam
    cp 15
    jr z, .beam
    ld a, TILE_WALL
    jr .put
.beam:
    ld a, TILE_BEAM
.put:
    ld [hl+], a
    inc c
    ld a, c
    cp 20
    jr nz, .cell
    ld de, 12
    add hl, de
    inc b
    ld a, b
    cp 18
    jr nz, .row
    ld hl, $9800 + 32 * 13
    ld bc, 20
    ld d, TILE_PANEL
    call MemFill
    ld hl, $9800 + 32 * 15
    ld bc, 20
    ld d, TILE_MAT
    call MemFill
    ld hl, Decor
.decor:
    ld a, [hl+]
    and a
    jr z, .names
    ld e, a
    ld a, [hl+]
    ld d, a
    ld a, [hl+]
    ld [de], a
    jr .decor
.names:
    ld hl, $9800 + 1
    ld de, P1Name
    call PrintText
    ld hl, $9800 + 16
    ld de, P2Name
    jp PrintText

ResetFighters:
    ld hl, P1
    ld b, 32
    xor a
.clear:
    ld [hl+], a
    dec b
    jr nz, .clear
    ld a, 28
    ldh [P1 + P_X], a
    ld a, 108
    ldh [P2 + P_X], a
    ld a, $20
    ldh [P2 + P_FACE], a
    ld a, GROUND
    ldh [P1 + P_Y], a
    ldh [P2 + P_Y], a
    ld a, HP_MAX
    ldh [P1 + P_HP], a
    ldh [P2 + P_HP], a
    ld a, NO_ATTACK
    ldh [P1 + P_ATK], a
    ldh [P2 + P_ATK], a
    xor a
    ldh [hSparkT], a
    ldh [hAiBlock], a
    ldh [hAiTimer], a
    ld a, $99
    ldh [hClock], a
    ret

ShowTitle:
    call DrawStage
    call ResetFighters
    xor a
    ldh [hState], a
    ld hl, $9800 + 32 * 4 + 2
    ld de, TitleText
    call PrintText
    ld hl, $9800 + 32 * 5 + 3
    ld de, SubtitleText
    jp PrintText

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
    ldh a, [rLINK]
    and a
    jr z, .input
    ld hl, $9800 + 32 * 6 + 3
    ld de, LinkedText
    call PrintText
.input:
    ldh a, [hJoyPressed]
    and PAD_START | PAD_A
    ret z
    ld hl, SfxRise
    call PlaySweep
    call LcdOff
    call DrawStage
    ld a, LCDC_ON
    ldh [rLCDC], a
    xor a
    ldh [P1 + P_WINS], a
    ldh [P2 + P_WINS], a
    ld a, 1
    ldh [hRound], a

StartRound:
    ldh a, [P1 + P_WINS]
    ld b, a
    ldh a, [P2 + P_WINS]
    ld c, a
    push bc
    call ResetFighters
    pop bc
    ld a, b
    ldh [P1 + P_WINS], a
    ld a, c
    ldh [P2 + P_WINS], a
    ld a, $99
    ldh [hClock], a
    ld a, 60
    ldh [hClockT], a
    call ClearMessage
    ld hl, MSG_ROW + 6
    ld de, RoundText
    call PrintText
    ldh a, [hRound]
    add '0' - 32
    ld [hl], a
    ld a, 100
    ldh [hTimer], a
    ld a, G_INTRO
    ldh [hState], a
    ld hl, FightTheme
    jp MusicPlay

ClearMessage:
    ld hl, MSG_ROW
    ld c, 0
.cell:
    ld a, c
    cp 5
    ld a, TILE_BEAM
    jr z, .put
    ld a, c
    cp 15
    ld a, TILE_BEAM
    jr z, .put
    ld a, TILE_WALL
.put:
    ld [hl+], a
    inc c
    ld a, c
    cp 20
    jr nz, .cell
    ret

Intro:
    ld hl, hTimer
    dec [hl]
    ld a, [hl]
    cp 35
    jr nz, .go
    call ClearMessage
    ld hl, MSG_ROW + 7
    ld de, FightText
    call PrintText
    ld hl, SfxRise
    jp PlaySweep
.go:
    and a
    ret nz
    call ClearMessage
    ld a, G_FIGHT
    ldh [hState], a
    ret

Fight:
    ld hl, hClockT
    dec [hl]
    jr nz, .players
    ld [hl], 60
    ldh a, [hClock]
    sub 1
    daa
    ldh [hClock], a
    jp z, TimeUp
.players:
    ldh a, [hJoyHeld]
    ldh [hIn], a
    ldh a, [hJoyPressed]
    ldh [hInP], a
    ld b, low(P1)
    ld c, low(P2)
    call Turn
    call CpuThink
    ld b, low(P2)
    ld c, low(P1)
    call Turn
    ld hl, hSparkT
    ld a, [hl]
    and a
    jr z, .ko
    dec [hl]
.ko:
    ldh a, [P1 + P_STATE]
    cp S_KO
    jr z, .p2Wins
    ldh a, [P2 + P_STATE]
    cp S_KO
    ret nz
    ld hl, P1 + P_WINS
    jr KnockOut
.p2Wins:
    ld hl, P2 + P_WINS

KnockOut:
    inc [hl]
    call MusicStop
    ld hl, SfxCrash
    call PlayNoise
    ld de, KOText
    ld hl, MSG_ROW + 7

EndRound:
    push de
    push hl
    call ClearMessage
    pop hl
    pop de
    call PrintText
    ld a, 150
    ldh [hTimer], a
    ld a, G_ROUNDEND
    ldh [hState], a
    ret

TimeUp:
    call MusicStop
    ldh a, [P2 + P_HP]
    ld b, a
    ldh a, [P1 + P_HP]
    cp b
    jr z, .draw
    ld hl, P1 + P_WINS
    jr nc, .award
    ld hl, P2 + P_WINS
.award:
    inc [hl]
.draw:
    ld de, TimeText
    ld hl, MSG_ROW + 7
    jr EndRound

RoundEnd:
    ld hl, hTimer
    dec [hl]
    ret nz
    ldh a, [P1 + P_WINS]
    cp 2
    jr nc, .match
    ldh a, [P2 + P_WINS]
    cp 2
    jr nc, .match
    ld hl, hRound
    inc [hl]
    jp StartRound
.match:
    call ClearMessage
    ldh a, [rLINK]
    and a
    ld de, WinText
    ld bc, LoseText
    jr z, .names
    ld de, KaiWinsText
    ld bc, ZedWinsText
.names:
    ld hl, MSG_ROW + 5
    ldh a, [P1 + P_WINS]
    cp 2
    jr nc, .show
    ld d, b
    ld e, c
.show:
    call PrintText
    ldh a, [P1 + P_WINS]
    cp 2
    ld hl, SfxCrowd
    call nc, PlayNoise
    ld hl, SfxFall
    ldh a, [P1 + P_WINS]
    cp 2
    call c, PlaySweep
    ld a, 240
    ldh [hTimer], a
    ld a, G_MATCHEND
    ldh [hState], a
    ret

MatchEnd:
    ld hl, hTimer
    dec [hl]
    ret nz
    call LcdOff
    call ShowTitle
    ld a, LCDC_ON
    ldh [rLCDC], a
    ret

Turn:
    push bc
    ld h, $ff
    ld l, b
    ld de, ME
    call Copy16
    pop bc
    push bc
    ld h, $ff
    ld l, c
    ld de, THEM
    call Copy16
    call FighterUpdate
    pop bc
    push bc
    ld hl, ME
    ld d, $ff
    ld e, b
    call Copy16
    pop bc
    ld hl, THEM
    ld d, $ff
    ld e, c

Copy16:
    ld b, 16
.copy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .copy
    ret

FighterUpdate:
    ld hl, mCool
    ld a, [hl]
    and a
    jr z, .state
    dec [hl]
.state:
    call MoveFireball
    ldh a, [mState]
    cp S_KO
    jp z, Fallen
    cp S_HIT
    jp z, Stunned
    cp S_ATTACK
    jp z, Attacking
    cp S_JUMP
    jp z, Jumping
    call FaceThem
    xor a
    ldh [mBlock], a
    ldh a, [hInP]
    bit PADB_A, a
    jr z, .notA
    ldh a, [hIn]
    bit PADB_DOWN, a
    jr z, .punch
    ldh a, [mCool]
    and a
    jr nz, .punch
    ldh a, [mFbx]
    and a
    jr nz, .punch
    ld a, A_SPECIAL
    jp StartAttack
.punch:
    ld a, A_PUNCH
    jp StartAttack
.notA:
    ldh a, [hInP]
    bit PADB_B, a
    jr z, .notB
    ld a, A_KICK
    jp StartAttack
.notB:
    ldh a, [hIn]
    bit PADB_UP, a
    jr z, .walk
    ld c, 0
    bit PADB_RIGHT, a
    jr z, .driftLeft
    inc c
.driftLeft:
    bit PADB_LEFT, a
    jr z, .drift
    dec c
.drift:
    ld a, c
    ldh [mVX], a
    ld a, 256 - JUMP_V
    ldh [mVY], a
    ld a, NO_ATTACK
    ldh [mAtk], a
    ld a, S_JUMP
    ldh [mState], a
    ld a, F_JUMP
    ldh [mFrame], a
    ld hl, SfxFlap
    jp PlaySweep
.walk:
    ldh a, [hIn]
    and PAD_LEFT | PAD_RIGHT
    jr z, .idle
    ld b, a
    ldh a, [mFace]
    and a
    jr nz, .faceLeft
    bit PADB_LEFT, b
    jr nz, .back
    ld a, 1
    jr .forward
.faceLeft:
    bit PADB_RIGHT, b
    jr nz, .back
    ld a, -1
.forward:
    call MoveBy
    ld a, S_WALK
    ldh [mState], a
    ldh a, [hTick]
    and 8
    ld a, F_WALK
    jr z, .walkFrame
    inc a
.walkFrame:
    ldh [mFrame], a
    ret
.back:
    ld a, 1
    ldh [mBlock], a
    ld a, F_BLOCK
    ldh [mFrame], a
    ld a, S_WALK
    ldh [mState], a
    ldh a, [hTick]
    and 1
    ret nz
    ldh a, [mFace]
    and a
    ld a, -1
    jr z, .retreat
    ld a, 1
.retreat:
    jp MoveBy
.idle:
    xor a
    ldh [mState], a
    ld a, F_IDLE
    ldh [mFrame], a
    ret

FaceThem:
    ldh a, [tX]
    ld b, a
    ldh a, [mX]
    cp b
    ld a, 0
    jr c, .face
    ld a, $20
.face:
    ldh [mFace], a
    ret

MoveBy:
    ld b, a
    ldh a, [mX]
    ld c, a
    add b
    cp MIN_X
    jr nc, .low
    ld a, MIN_X
.low:
    cp 200
    jr c, .high
    ld a, MIN_X
.high:
    cp MAX_X + 1
    jr c, .set
    ld a, MAX_X
.set:
    ld b, a
    ldh [mX], a
    ldh a, [mY]
    cp GROUND
    ret c
    ldh a, [tY]
    cp GROUND
    ret c
    call Gap
    cp 16
    ret nc
    ld d, a
    ld a, c
    ldh [mX], a
    call Gap
    cp d
    ret nc
    ld a, b
    ldh [mX], a
    ret

Gap:
    ldh a, [tX]
    ld e, a
    ldh a, [mX]
    sub e
    ret nc
    cpl
    inc a
    ret

StartAttack:
    ldh [mAtk], a
    ld a, S_ATTACK
    ldh [mState], a
    xor a
    ldh [mTimer], a
    ldh [mHit], a
    ld a, F_IDLE
    ldh [mFrame], a
    ld hl, SfxBlip
    jp PlayTone

Attacking:
    ld hl, mTimer
    inc [hl]
    ld b, [hl]
    ldh a, [mAtk]
    cp A_SPECIAL
    jr z, .special
    add a
    add a
    add a
    add low(AttackData)
    ld l, a
    ld a, high(AttackData)
    adc 0
    ld h, a
    ld a, b
    cp [hl]
    jr c, .windup
    inc hl
    ldh a, [mAtk]
    and a
    ld a, F_PUNCH
    jr z, .pose
    ld a, F_KICK
.pose:
    ldh [mFrame], a
    ld a, b
    cp [hl]
    inc hl
    jr nc, .recover
    ldh a, [mHit]
    and a
    jr nz, .recover
    push hl
    inc hl
    ld d, [hl]
    inc hl
    ld e, [hl]
    push bc
    call TryHit
    pop bc
    pop hl
.recover:
    ld a, b
    cp [hl]
    ret c
    xor a
    ldh [mState], a
    ret
.windup:
    ret
.special:
    ld a, F_SPECIAL
    ldh [mFrame], a
    ld a, b
    cp SPECIAL_AT
    jr nz, .done
    ldh a, [mFace]
    ldh [mFbDir], a
    and a
    ldh a, [mX]
    jr nz, .throwLeft
    add 20
    jr .throw
.throwLeft:
    sub 4
.throw:
    ldh [mFbx], a
    ld a, FB_COOL
    ldh [mCool], a
    ld hl, SfxFall
    call PlaySweep
.done:
    ld a, b
    cp SPECIAL_END
    ret c
    xor a
    ldh [mState], a
    ret

TryHit:
    ldh a, [tX]
    ld b, a
    ldh a, [mX]
    ld c, a
    ldh a, [mFace]
    and a
    jr nz, .left
    ld a, b
    sub c
    jr .reach
.left:
    ld a, c
    sub b
.reach:
    add 2
    ld b, a
    ld a, e
    add 3
    ld c, a
    ld a, b
    cp c
    ret nc
    ldh a, [mState]
    cp S_JUMP
    jr z, .air
    ldh a, [mY]
    sub 14
    ld b, a
    ldh a, [tY]
    cp b
    ret c
    jr .connect
.air:
    ldh a, [tY]
    sub 20
    ld b, a
    ldh a, [mY]
    cp b
    ret c
.connect:
    ld a, 1
    ldh [mHit], a

ApplyHit:
    ldh a, [tState]
    cp S_KO
    ret z
    ld b, a
    ldh a, [tBlock]
    and a
    jr z, .hurt
    ld a, b
    cp S_ATTACK
    jr nc, .hurt
    ld d, 1
    call Damage
    ld a, 3
    call Knock
    call Spark
    ld hl, SfxThud
    jp PlayTone
.hurt:
    call Damage
    call Spark
    ld a, 6
    ldh [rRUMBLE], a
    ldh a, [tHP]
    and a
    jr z, .ko
    ld a, S_HIT
    ldh [tState], a
    ld a, 16
    ldh [tTimer], a
    xor a
    ldh [tBlock], a
    ld a, F_HIT
    ldh [THEM + P_FRAME], a
    ld hl, SfxKick
    jp PlayNoise
.ko:
    ld a, 30
    ldh [rRUMBLE], a
    ld a, S_KO
    ldh [tState], a
    ld a, F_KO
    ldh [THEM + P_FRAME], a
    ret

Damage:
    ldh a, [tHP]
    sub d
    jr nc, .set
    xor a
.set:
    ldh [tHP], a
    ret

Knock:
    ld d, a
    ldh a, [mX]
    ld b, a
    ldh a, [tX]
    cp b
    jr c, .left
    add d
    cp MAX_X + 1
    jr c, .set
    ld a, MAX_X
    jr .set
.left:
    sub d
    jr c, .wall
    cp MIN_X
    jr nc, .set
.wall:
    ld a, MIN_X
.set:
    ldh [tX], a
    ret

Spark:
    ldh a, [mX]
    ld b, a
    ldh a, [tX]
    add b
    rra
    add 16
    ldh [hSparkX], a
    ldh a, [tY]
    sub 2
    ldh [hSparkY], a
    ld a, 8
    ldh [hSparkT], a
    ret

Stunned:
    ld hl, mTimer
    dec [hl]
    ld a, [hl]
    push af
    cp 8
    jr c, .fall
    ldh a, [tX]
    ld b, a
    ldh a, [mX]
    cp b
    ld a, -1
    jr c, .push
    ld a, 1
.push:
    call MoveBy
.fall:
    call Settle
    pop af
    and a
    ret nz
    xor a
    ldh [mState], a
    ret

Fallen:
    ld a, F_KO
    ldh [mFrame], a

Settle:
    ldh a, [mY]
    cp GROUND
    ret nc
    add 3
    cp GROUND
    jr c, .set
    ld a, GROUND
.set:
    ldh [mY], a
    ret

Jumping:
    ldh a, [hInP]
    and PAD_A | PAD_B
    jr z, .physics
    ldh a, [mAtk]
    cp NO_ATTACK
    jr nz, .physics
    ld a, A_JUMPKICK
    ldh [mAtk], a
    xor a
    ldh [mHit], a
    ld a, F_KICK
    ldh [mFrame], a
    ld hl, SfxBlip
    call PlayTone
.physics:
    ldh a, [mVX]
    and a
    call nz, MoveBy
    ldh a, [mVY]
    ld b, a
    ldh a, [mY]
    add b
    ldh [mY], a
    ldh a, [hTick]
    and 1
    jr nz, .landing
    ld hl, mVY
    inc [hl]
.landing:
    ldh a, [mVY]
    bit 7, a
    jr nz, .attack
    ldh a, [mY]
    cp GROUND
    jr c, .attack
    ld a, GROUND
    ldh [mY], a
    xor a
    ldh [mState], a
    ld a, NO_ATTACK
    ldh [mAtk], a
    ld a, F_IDLE
    ldh [mFrame], a
    ret
.attack:
    ldh a, [mAtk]
    cp A_JUMPKICK
    ret nz
    ldh a, [mHit]
    and a
    ret nz
    ld d, JUMPKICK_DAMAGE
    ld e, 20
    jp TryHit

MoveFireball:
    ldh a, [mFbx]
    and a
    ret z
    ld b, a
    ldh a, [mFbDir]
    and a
    ld a, b
    jr nz, .left
    add 2
    jr .moved
.left:
    sub 2
.moved:
    cp 156
    jr nc, .gone
    cp 4
    jr c, .gone
    ldh [mFbx], a
    ldh a, [tX]
    add 8
    ld b, a
    ldh a, [mFbx]
    sub b
    add 8
    cp 16
    ret nc
    ldh a, [tY]
    cp GROUND - 10
    ret c
    xor a
    ldh [mFbx], a
    ld d, FIREBALL_DAMAGE
    jp ApplyHit
.gone:
    xor a
    ldh [mFbx], a
    ret

CpuThink:
    ldh a, [rLINK]
    and a
    jr z, .cpu
    ldh a, [hPad2Old]
    cpl
    ld b, a
    ldh a, [rPAD2]
    ldh [hIn], a
    ldh [hPad2Old], a
    and b
    ldh [hInP], a
    ret
.cpu:
    xor a
    ldh [hIn], a
    ldh [hInP], a
    ldh a, [P1 + P_X]
    ld b, a
    ldh a, [P2 + P_X]
    sub b
    ld d, PAD_LEFT
    ld e, PAD_RIGHT
    jr nc, .gap
    cpl
    inc a
    ld d, PAD_RIGHT
    ld e, PAD_LEFT
.gap:
    ld c, a
    ldh a, [P2 + P_STATE]
    cp S_JUMP
    jr nz, .grounded
    ld a, c
    cp 26
    ret nc
    ld a, PAD_B
    ldh [hInP], a
    ret
.grounded:
    cp S_ATTACK
    ret nc
    ld hl, hAiBlock
    ld a, [hl]
    and a
    jr z, .watch
    dec [hl]
    ld a, e
    ldh [hIn], a
    ret
.watch:
    ldh a, [P1 + P_STATE]
    cp S_ATTACK
    jr nz, .fireball
    ldh a, [P1 + P_TIMER]
    cp 1
    jr nz, .fireball
    ld a, c
    cp 40
    jr nc, .fireball
    call Random
    cp 140
    jr nc, .fireball
    ld [hl], 18
    ld a, e
    ldh [hIn], a
    ret
.fireball:
    ldh a, [P1 + P_FBX]
    and a
    jr z, .think
    ld b, a
    ldh a, [P2 + P_X]
    add 8
    sub b
    jr nc, .near
    cpl
    inc a
.near:
    cp 40
    jr nc, .think
    call Random
    and 1
    ld a, PAD_UP
    jr z, .dodge
    ld a, e
.dodge:
    ldh [hIn], a
    ret
.think:
    ld hl, hAiTimer
    ld a, [hl]
    and a
    jr z, .decide
    dec [hl]
    ld a, c
    cp 24
    ret c
    ld a, d
    ldh [hIn], a
    ret
.decide:
    call Random
    and 15
    add 14
    ld [hl], a
    ld a, c
    cp 24
    jr c, .close
    cp 56
    jr c, .approach
    call Random
    and 3
    jr nz, .approach
    ldh a, [P2 + P_COOL]
    and a
    jr nz, .approach
    ld a, PAD_DOWN
    ldh [hIn], a
    ld a, PAD_A
    ldh [hInP], a
    ret
.approach:
    ld a, d
    ldh [hIn], a
    ret
.close:
    call Random
    and 7
    cp 3
    jr c, .punch
    cp 5
    jr c, .kick
    cp 6
    jr c, .jump
    ld a, e
    ldh [hIn], a
    ret
.punch:
    ld a, PAD_A
    ldh [hInP], a
    ret
.kick:
    ld a, PAD_B
    ldh [hInP], a
    ret
.jump:
    ld a, PAD_UP
    or d
    ldh [hIn], a
    ret

Draw:
    ld hl, $9800 + 9
    ldh a, [hClock]
    call PrintBCD
    ld hl, $9800 + 32 + 1
    ldh a, [P1 + P_HP]
    call DrawBar
    ld hl, $9800 + 32 + 11
    ldh a, [P2 + P_HP]
    call DrawBar
    ld hl, $9800 + 32 * 2 + 1
    ldh a, [P1 + P_WINS]
    call DrawWins
    ld hl, $9800 + 32 * 2 + 17
    ldh a, [P2 + P_WINS]
    call DrawWins

    ld hl, $fe00
    ld c, low(P1)
    ld e, 0
    call DrawFighter
    ld c, low(P2)
    ld e, $10
    call DrawFighter
    ld c, low(P1)
    ld e, 0
    call DrawFireball
    ld c, low(P2)
    ld e, $10
    call DrawFireball
    ldh a, [hSparkT]
    and a
    jr z, .noSpark
    ldh a, [hSparkY]
    add 16 - 20
.noSpark:
    ld [hl+], a
    ldh a, [hSparkX]
    ld [hl+], a
    ld a, TILE_SPARK
    ld [hl+], a
    xor a
    ld [hl], a
    ret

DrawBar:
    ld b, a
    ld c, 8
.cell:
    ld a, b
    cp 8
    jr c, .part
    ld a, 8
.part:
    add TILE_BAR
    ld [hl+], a
    ld a, b
    sub 8
    jr nc, .next
    xor a
.next:
    ld b, a
    dec c
    jr nz, .cell
    ret

DrawWins:
    ld b, a
    ld c, 2
.star:
    ld a, b
    and a
    ld a, TILE_NOSTAR
    jr z, .put
    dec b
    ld a, TILE_STAR
.put:
    ld [hl+], a
    dec c
    jr nz, .star
    ret

DrawFighter:
    ld a, c
    add P_FRAME
    ld c, a
    ldh a, [c]
    ld b, a
    add a
    add a
    add a
    add b
    add TILE_FIGHTER
    ld d, a
    ld a, c
    sub P_FRAME - P_FACE
    ld c, a
    ldh a, [c]
    or e
    ld e, a
    ld a, c
    sub P_FACE - P_Y
    ld c, a
    ldh a, [c]
    sub 24 - 16
    ld b, a
    dec c
    ldh a, [c]
    add 8
    ld c, a
    ld a, 3
.row:
    push af
    push bc
    push de
    bit 5, e
    jr z, .cols
    ld a, c
    add 16
    ld c, a
.cols:
    ld a, 3
.col:
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
    ld a, c
    bit 5, e
    jr z, .right
    sub 16
.right:
    add 8
    ld c, a
    pop af
    dec a
    jr nz, .col
    pop de
    pop bc
    ld a, b
    add 8
    ld b, a
    ld a, d
    add 3
    ld d, a
    pop af
    dec a
    jr nz, .row
    ret

DrawFireball:
    ld a, c
    add P_FBX
    ld c, a
    ldh a, [c]
    and a
    jr z, .hide
    add 8
    ld c, a
    ld a, GROUND - 18 + 16
    ld [hl+], a
    ld a, c
    ld [hl+], a
    ld a, TILE_FIREBALL
    ld [hl+], a
    ldh a, [hTick]
    and 4
    swap a
    or e
    ld [hl+], a
    ret
.hide:
    xor a
    ld [hl+], a
    inc l
    inc l
    inc l
    ret

    include "lib/util.asm"
    include "lib/sound.asm"
    include "lib/music.asm"

Decor:
    db low($9800 + 32 * 3), high($9800 + 32 * 3), TILE_LANTERN
    db low($9800 + 32 * 3 + 1), high($9800 + 32 * 3 + 1), TILE_LANTERN + 1
    db low($9800 + 32 * 4), high($9800 + 32 * 4), TILE_LANTERN + 2
    db low($9800 + 32 * 4 + 1), high($9800 + 32 * 4 + 1), TILE_LANTERN + 3
    db low($9800 + 32 * 3 + 18), high($9800 + 32 * 3 + 18), TILE_LANTERN
    db low($9800 + 32 * 3 + 19), high($9800 + 32 * 3 + 19), TILE_LANTERN + 1
    db low($9800 + 32 * 4 + 18), high($9800 + 32 * 4 + 18), TILE_LANTERN + 2
    db low($9800 + 32 * 4 + 19), high($9800 + 32 * 4 + 19), TILE_LANTERN + 3
    db low($9800 + 32 * 9 + 9), high($9800 + 32 * 9 + 9), TILE_CREST
    db low($9800 + 32 * 9 + 10), high($9800 + 32 * 9 + 10), TILE_CREST + 1
    db low($9800 + 32 * 10 + 9), high($9800 + 32 * 10 + 9), TILE_CREST + 2
    db low($9800 + 32 * 10 + 10), high($9800 + 32 * 10 + 10), TILE_CREST + 3
    db 0

AttackData:
    db 3, 7, 14, 5, 18, 0, 0, 0
    db 5, 10, 20, 8, 22, 0, 0, 0

TitleText:
    db "K N O C K O U T", 0
SubtitleText:
    db "BEST OF THREE", 0
PressText:
    db "PRESS START", 0
PressBlank:
    db "           ", 0
P1Name:
    db "KAI", 0
P2Name:
    db "ZED", 0
RoundText:
    db "ROUND ", 0
FightText:
    db "FIGHT!", 0
KOText:
    db "K.O.!", 0
TimeText:
    db "TIME!", 0
WinText:
    db "YOU WIN!", 0
LoseText:
    db "YOU LOSE", 0
KaiWinsText:
    db "KAI WINS!", 0
ZedWinsText:
    db "ZED WINS!", 0
LinkedText:
    db "2 PLAYERS LINKED", 0

FightTheme:
    db N_A2, 7, N_A3, 7, N_A2, 7, N_G3, 7, N_A2, 7, N_E3, 7, N_G2, 7, N_A2, 7
    db N_F2, 7, N_F3, 7, N_F2, 7, N_E3, 7, N_F2, 7, N_C3, 7, N_E2, 7, N_F2, 7
    db N_D2, 7, N_D3, 7, N_D2, 7, N_C3, 7, N_D2, 7, N_A2, 7, N_C2, 7, N_D2, 7
    db N_E2, 7, N_E3, 7, N_E2, 7, N_D3, 7, N_E2, 7, N_B2, 7, N_GS2, 7, N_B2, 7
    db $ff

    include "lib/font.asm"

Tiles:
    dw `00000000
    dw `00000000
    dw `00010000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000001
    dw `00000000

    dw `00122100
    dw `00122100
    dw `00122100
    dw `00122100
    dw `00122100
    dw `00122100
    dw `00122100
    dw `00122100

    dw `22222222
    dw `21112112
    dw `21112112
    dw `21112112
    dw `22222222
    dw `21112112
    dw `21112112
    dw `22222222

    dw `33333333
    dw `22222222
    dw `21112111
    dw `21112111
    dw `22222222
    dw `11211121
    dw `11211121
    dw `22222222

    dw `11211121
    dw `11211121
    dw `22222222
    dw `21112111
    dw `21112111
    dw `22222222
    dw `11121112
    dw `11121112

    dw `33333333
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `33333333
    dw `00000000

    dw `33333333
    dw `20000000
    dw `20000000
    dw `20000000
    dw `20000000
    dw `20000000
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22000000
    dw `22000000
    dw `22000000
    dw `22000000
    dw `22000000
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22200000
    dw `22200000
    dw `22200000
    dw `22200000
    dw `22200000
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22220000
    dw `22220000
    dw `22220000
    dw `22220000
    dw `22220000
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22222000
    dw `22222000
    dw `22222000
    dw `22222000
    dw `22222000
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22222200
    dw `22222200
    dw `22222200
    dw `22222200
    dw `22222200
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22222220
    dw `22222220
    dw `22222220
    dw `22222220
    dw `22222220
    dw `33333333
    dw `00000000

    dw `33333333
    dw `22222222
    dw `22222222
    dw `22222222
    dw `22222222
    dw `22222222
    dw `33333333
    dw `00000000

    dw `00030000
    dw `00333000
    dw `33333330
    dw `03333300
    dw `00333000
    dw `03303300
    dw `33000330
    dw `00000000

    dw `00333000
    dw `03000300
    dw `30000030
    dw `30000030
    dw `30000030
    dw `03000300
    dw `00333000
    dw `00000000

    dw `00000003
    dw `00000003
    dw `00000333
    dw `00033222
    dw `00321111
    dw `03211111
    dw `32222222
    dw `32111111

    dw `30000000
    dw `30000000
    dw `33300000
    dw `22233000
    dw `11112300
    dw `11111230
    dw `22222223
    dw `11111123

    dw `32111111
    dw `32222222
    dw `03211111
    dw `00321111
    dw `00033222
    dw `00000333
    dw `00000003
    dw `00000033

    dw `11111123
    dw `22222223
    dw `11111230
    dw `11112300
    dw `22233000
    dw `33300000
    dw `30000000
    dw `33000000

    dw `00000033
    dw `00003322
    dw `00332223
    dw `00322333
    dw `03223111
    dw `03231111
    dw `32231133
    dw `32331133

    dw `33000000
    dw `22330000
    dw `32223300
    dw `33322300
    dw `11132230
    dw `11113230
    dw `33113223
    dw `33113323

    dw `32331133
    dw `32231133
    dw `03231111
    dw `03223111
    dw `00322333
    dw `00332223
    dw `00003322
    dw `00000033

    dw `33113323
    dw `33113223
    dw `11113230
    dw `11132230
    dw `33322300
    dw `32223300
    dw `22330000
    dw `33000000

    dw `22222222
    dw `21111111
    dw `21111111
    dw `21111111
    dw `22222222
    dw `11112111
    dw `11112111
    dw `33333333

    dw `33333333
    dw `21111112
    dw `21111112
    dw `21111112
    dw `21111112
    dw `21111112
    dw `21111112
    dw `22222222

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00030000
    dw `03323300
    dw `32222230
    dw `32222230
    dw `22113113
    dw `32111130
    dw `32111130
    dw `03111303

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `23000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `31111132
    dw `31111131
    dw `31121111
    dw `31112111
    dw `11111113
    dw `31222230
    dw `32222230
    dw `32111230

    dw `22300000
    dw `23000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000003
    dw `00000003
    dw `00000032
    dw `00000032
    dw `00000322
    dw `00000322
    dw `00003222
    dw `00000323

    dw `22212223
    dw `22232223
    dw `22303222
    dw `23000322
    dw `23000322
    dw `30000032
    dw `30000032
    dw `00000003

    dw `00000000
    dw `00000000
    dw `30000000
    dw `30000000
    dw `23000000
    dw `23000000
    dw `22300000
    dw `23000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00030000
    dw `03323300
    dw `32222230
    dw `32222230
    dw `22113113
    dw `32111130
    dw `32111133

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `23000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `03111332
    dw `31111131
    dw `31111111
    dw `31112111
    dw `11111113
    dw `31222230
    dw `32222230
    dw `03111300

    dw `22300000
    dw `23000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000003
    dw `00000003
    dw `00000003
    dw `00000032
    dw `00000003

    dw `32212230
    dw `32232230
    dw `22232223
    dw `22303223
    dw `22303223
    dw `22303223
    dw `22303222
    dw `23000323

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00030000
    dw `03323300
    dw `32222230
    dw `32222230
    dw `22113113
    dw `32111130
    dw `32111130
    dw `03111303

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `23000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `31111132
    dw `31111131
    dw `31121111
    dw `31112111
    dw `11111113
    dw `31222230
    dw `32222230
    dw `03111230

    dw `22300000
    dw `23000000
    dw `30000000
    dw `30000000
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
    dw `00000000
    dw `00000000

    dw `03212223
    dw `32223222
    dw `32223322
    dw `03223032
    dw `03223032
    dw `03223003
    dw `03222300
    dw `00323000

    dw `00000000
    dw `30000000
    dw `23000000
    dw `23000000
    dw `22300000
    dw `22230000
    dw `32300000
    dw `03000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00003000
    dw `00332330
    dw `03222223
    dw `03222223
    dw `32211311
    dw `03211113
    dw `03211113
    dw `00311133

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `30000300

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `03111111
    dw `03111111
    dw `03122213
    dw `03112113
    dw `31111113
    dw `03122223
    dw `03222223
    dw `03211130

    dw `13333230
    dw `11112223
    dw `13333230
    dw `30000300
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000003
    dw `00000032
    dw `00000032
    dw `00000322
    dw `00000322
    dw `00003222
    dw `00000323

    dw `32221223
    dw `22233223
    dw `22303222
    dw `23000322
    dw `23000322
    dw `30000032
    dw `30000032
    dw `00000003

    dw `00000000
    dw `00000000
    dw `30000000
    dw `30000000
    dw `23000000
    dw `23000000
    dw `22300000
    dw `23000000

    dw `00000000
    dw `00000000
    dw `00000033
    dw `00000322
    dw `00000322
    dw `00003221
    dw `00000321
    dw `00000321

    dw `00000000
    dw `30000000
    dw `23300000
    dw `22230000
    dw `22230000
    dw `13113000
    dw `11130000
    dw `11130300

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00003233
    dw `00032221
    dw `00003211
    dw `00000311
    dw `00000031
    dw `00000003
    dw `00000000
    dw `00000000

    dw `11133230
    dw `11112223
    dw `11111230
    dw `11111303
    dw `11111332
    dw `32222222
    dw `32222222
    dw `03111333

    dw `00000000
    dw `00000000
    dw `00003300
    dw `33332230
    dw `22222223
    dw `22222230
    dw `22333300
    dw `33000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000

    dw `03213000
    dw `32223000
    dw `32223000
    dw `32230000
    dw `32230000
    dw `32230000
    dw `22230000
    dw `32300000

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
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00030000
    dw `03323300
    dw `32222230
    dw `32222230
    dw `22113113
    dw `32111123
    dw `32111112

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000003

    dw `03111113
    dw `31111113
    dw `31111113
    dw `31111111
    dw `31111113
    dw `31111113
    dw `22222130
    dw `22222300

    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000003
    dw `00000003
    dw `00000032
    dw `00000322
    dw `00000322
    dw `00003222
    dw `00000323

    dw `31112300
    dw `22122230
    dw `22332223
    dw `22303223
    dw `23003222
    dw `23000322
    dw `30000322
    dw `00000032

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `30000000
    dw `23000000
    dw `30000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00030000
    dw `03323300
    dw `32222230
    dw `32222230
    dw `22113113
    dw `32111130
    dw `32111133
    dw `03111332

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `23000000
    dw `22300000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `31111131
    dw `31111111
    dw `31112111
    dw `11111113
    dw `31222230
    dw `32222233
    dw `32111222
    dw `32213222

    dw `23000000
    dw `30000000
    dw `30000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `23000000

    dw `00000003
    dw `00000003
    dw `00000003
    dw `00000032
    dw `00000003
    dw `00000000
    dw `00000000
    dw `00000000

    dw `22233222
    dw `22332223
    dw `22322230
    dw `22332300
    dw `23003000
    dw `30000000
    dw `00000000
    dw `00000000

    dw `30000000
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
    dw `00000033
    dw `00000322
    dw `00000322
    dw `00003221
    dw `00032321

    dw `00000000
    dw `00000000
    dw `30000000
    dw `23300000
    dw `22230000
    dw `22230000
    dw `13113000
    dw `11130000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00322221
    dw `00032111
    dw `00003311
    dw `00000031
    dw `00000003
    dw `00000003
    dw `00000000
    dw `00000000

    dw `11133000
    dw `11131300
    dw `11111130
    dw `11111130
    dw `11111123
    dw `11111222
    dw `32222223
    dw `32222230

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000003
    dw `00000032
    dw `00000032
    dw `00000322
    dw `00000032

    dw `03111230
    dw `32212223
    dw `32233222
    dw `22230322
    dw `22300322
    dw `22300322
    dw `23000322
    dw `30000032

    dw `00000000
    dw `00000000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `30000000
    dw `23000000
    dw `30000000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00000000
    dw `00003000
    dw `00332330
    dw `03222223
    dw `03222223
    dw `32211311
    dw `03211113
    dw `03211113

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `30000000
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

    dw `00311133
    dw `03111111
    dw `03111111
    dw `03111111
    dw `03111111
    dw `03111131
    dw `32222233
    dw `32222230

    dw `30003000
    dw `13332300
    dw `11122230
    dw `13322300
    dw `11222300
    dw `33323000
    dw `00030000
    dw `00000000

    dw `00000000
    dw `00000003
    dw `00000003
    dw `00000032
    dw `00000322
    dw `00003222
    dw `00032223
    dw `00003230

    dw `32111223
    dw `22212222
    dw `22233222
    dw `22300332
    dw `23000032
    dw `30000003
    dw `00000003
    dw `00000000

    dw `00000000
    dw `30000000
    dw `23000000
    dw `23000000
    dw `22300000
    dw `22300000
    dw `22230000
    dw `32300000

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
    dw `00000000
    dw `00003000

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00030000
    dw `00323000
    dw `03222300

    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000

    dw `00332333
    dw `03222221
    dw `03222221
    dw `32211311
    dw `03211111
    dw `03211111
    dw `00331331
    dw `00003003

    dw `31123000
    dw `11133330
    dw `11111113
    dw `11112222
    dw `11112222
    dw `11121111
    dw `11222113
    dw `13323330

    dw `00000030
    dw `03333323
    dw `32222222
    dw `22222223
    dw `22222223
    dw `22222222
    dw `32222223
    dw `03333330

    dw `00033000
    dw `00322300
    dw `03211230
    dw `32111123
    dw `32111123
    dw `03211230
    dw `00322300
    dw `00033000

    dw `30000003
    dw `03030030
    dw `00300300
    dw `33033033
    dw `00300300
    dw `03003030
    dw `30000003
    dw `00000000
TilesEnd:
