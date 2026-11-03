N_C2 equ 1
N_CS2 equ 2
N_D2 equ 3
N_DS2 equ 4
N_E2 equ 5
N_F2 equ 6
N_FS2 equ 7
N_G2 equ 8
N_GS2 equ 9
N_A2 equ 10
N_AS2 equ 11
N_B2 equ 12
N_C3 equ 13
N_CS3 equ 14
N_D3 equ 15
N_DS3 equ 16
N_E3 equ 17
N_F3 equ 18
N_FS3 equ 19
N_G3 equ 20
N_GS3 equ 21
N_A3 equ 22
N_AS3 equ 23
N_B3 equ 24
N_C4 equ 25
N_CS4 equ 26
N_D4 equ 27
N_DS4 equ 28
N_E4 equ 29
N_F4 equ 30
N_FS4 equ 31
N_G4 equ 32
N_GS4 equ 33
N_A4 equ 34
N_AS4 equ 35
N_B4 equ 36
N_C5 equ 37
N_CS5 equ 38
N_D5 equ 39
N_DS5 equ 40
N_E5 equ 41
N_F5 equ 42
N_FS5 equ 43
N_G5 equ 44
N_GS5 equ 45
N_A5 equ 46
N_AS5 equ 47
N_B5 equ 48
N_C6 equ 49

MUSIC_VOLUME equ $40

MusicPlay:
    ld a, l
    ldh [hSongLo], a
    ldh [hMusicLo], a
    ld a, h
    ldh [hSongHi], a
    ldh [hMusicHi], a
    ld a, 1
    ldh [hMusicTime], a

LoadWave:
    xor a
    ldh [rNR30], a
    ld hl, WaveShape
    ld c, low(rWAVE)
.load:
    ld a, [hl+]
    ldh [c], a
    inc c
    ld a, c
    cp low(rWAVE) + 16
    jr nz, .load
    ld a, $80
    ldh [rNR30], a
    ret

MusicStop:
    xor a
    ldh [hMusicHi], a
    ldh [rNR30], a
    ret

MusicTick:
    ldh a, [hMusicHi]
    and a
    ret z
    ld hl, hMusicTime
    dec [hl]
    jr z, .next
    ld a, [hl]
    cp 1
    ret nz
    xor a
    ldh [rNR32], a
    ret
.next:
    ldh a, [hMusicLo]
    ld l, a
    ldh a, [hMusicHi]
    ld h, a
    ld a, [hl]
    cp $ff
    jr nz, .note
    ldh a, [hSongLo]
    ld l, a
    ldh a, [hSongHi]
    ld h, a
    ld a, [hl]
.note:
    inc hl
    ld b, [hl]
    inc hl
    ld c, a
    ld a, l
    ldh [hMusicLo], a
    ld a, h
    ldh [hMusicHi], a
    ld a, b
    ldh [hMusicTime], a
    ld a, c
    and a
    jr nz, PlayNote
    ldh [rNR32], a
    ret

PlayNote:
    add a
    add low(NotePeriods - 2)
    ld l, a
    ld a, high(NotePeriods - 2)
    adc 0
    ld h, a
    ld a, MUSIC_VOLUME
    ldh [rNR32], a
    ld a, [hl+]
    ldh [rNR33], a
    ld a, [hl]
    or $80
    ldh [rNR34], a
    ret

WaveShape:
    db $9b, $cd, $ee, $ff, $ff, $ee, $dc, $b9
    db $64, $32, $11, $00, $00, $11, $23, $46

NotePeriods:
    dw 1046, 1102, 1155, 1205, 1253, 1297, 1339, 1379
    dw 1417, 1452, 1486, 1517, 1547, 1575, 1602, 1627
    dw 1650, 1673, 1694, 1714, 1732, 1750, 1767, 1783
    dw 1798, 1812, 1825, 1837, 1849, 1860, 1871, 1881
    dw 1890, 1899, 1907, 1915, 1923, 1930, 1936, 1943
    dw 1949, 1954, 1959, 1964, 1969, 1974, 1978, 1982
    dw 1985
