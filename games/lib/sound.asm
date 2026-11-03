SoundOn:
    ld a, $80
    ldh [rNR52], a
    ld a, $77
    ldh [rNR50], a
    ld a, $ff
    ldh [rNR51], a
    ret

PlaySweep:
    ld c, low(rNR10)
    ld b, 5
    jr PlayRegs

PlayTone:
    ld c, low(rNR21)
    ld b, 4
    jr PlayRegs

PlayNoise:
    ld c, low(rNR41)
    ld b, 4

PlayRegs:
    ld a, [hl+]
    ldh [c], a
    inc c
    dec b
    jr nz, PlayRegs
    ret

SfxBlip:
    db $80, $a1, low(1900), $80 | high(1900)
SfxHit:
    db $80, $f1, low(1810), $80 | high(1810)
SfxThud:
    db $40, $b1, low(1600), $80 | high(1600)
SfxDing:
    db $80, $f2, low(1955), $80 | high(1955)
SfxRise:
    db $16, $80, $f3, low(1650), $80 | high(1650)
SfxFall:
    db $1e, $80, $f4, low(1960), $80 | high(1960)
SfxFlap:
    db $15, $80, $82, low(1500), $80 | high(1500)
SfxCrash:
    db $00, $f3, $55, $80
SfxKick:
    db $00, $b1, $31, $80
SfxCrowd:
    db $00, $c6, $46, $80
