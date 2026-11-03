LcdOff:
    ldh a, [rLY]
    cp 144
    jr c, LcdOff
    xor a
    ldh [rLCDC], a
    ret

EnableVBlank:
    ld a, 1
    ldh [rIE], a
    xor a
    ldh [rIF], a
    ei
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

LoadFont:
    ld de, Font
    ld hl, $8000
    ld bc, FontEnd - Font
.byte:
    ld a, [de]
    ld [hl+], a
    ld [hl+], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .byte
    ret

ClearScreen:
    ld hl, $9800
    ld bc, 32 * 32
    ld d, TILE_SPACE
    call MemFill
    ld hl, $fe00
    ld bc, 160
    ld d, 0
    jp MemFill

PrintText:
    ld a, [de]
    and a
    ret z
    sub 32
    ld [hl+], a
    inc de
    jr PrintText

PrintBCD:
    ld b, a
    swap a
    and $0f
    add '0' - 32
    ld [hl+], a
    ld a, b
    and $0f
    add '0' - 32
    ld [hl+], a
    ret

ReadJoypad:
    ld a, $20
    ldh [rJOYP], a
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    cpl
    and $0f
    ld b, a
    ld a, $10
    ldh [rJOYP], a
    ldh a, [rJOYP]
    ldh a, [rJOYP]
    cpl
    and $0f
    swap a
    or b
    ld b, a
    ldh a, [hJoyHeld]
    cpl
    and b
    ldh [hJoyPressed], a
    ld a, b
    ldh [hJoyHeld], a
    ld a, $30
    ldh [rJOYP], a
    ret

SeedRandom:
    ldh a, [rDIV]
    or 1
    ldh [hRand], a
    ret

Random:
    push bc
    ldh a, [hRand]
    add a
    jr nc, .noTap
    xor $1d
.noTap:
    ld b, a
    ldh a, [rDIV]
    xor b
    ldh [hRand], a
    pop bc
    ret
