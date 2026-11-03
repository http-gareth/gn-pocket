rJOYP   equ $ff00
rDIV    equ $ff04
rIF     equ $ff0f
rLCDC   equ $ff40
rSTAT   equ $ff41
rSCY    equ $ff42
rSCX    equ $ff43
rLY     equ $ff44
rLYC    equ $ff45
rBGP    equ $ff47
rOBP0   equ $ff48
rOBP1   equ $ff49
rWY     equ $ff4a
rWX     equ $ff4b
rRUMBLE equ $ff7c
rLINK   equ $ff7d
rPAD2   equ $ff7e
rLAUNCH equ $ff7f
rNR10   equ $ff10
rNR21   equ $ff16
rNR30   equ $ff1a
rNR32   equ $ff1c
rNR33   equ $ff1d
rNR34   equ $ff1e
rNR41   equ $ff20
rNR50   equ $ff24
rNR51   equ $ff25
rNR52   equ $ff26
rWAVE   equ $ff30
rIE     equ $ffff

PADB_RIGHT  equ 0
PADB_LEFT   equ 1
PADB_UP     equ 2
PADB_DOWN   equ 3
PADB_A      equ 4
PADB_B      equ 5
PADB_SELECT equ 6
PADB_START  equ 7

PAD_RIGHT  equ 1 << PADB_RIGHT
PAD_LEFT   equ 1 << PADB_LEFT
PAD_UP     equ 1 << PADB_UP
PAD_DOWN   equ 1 << PADB_DOWN
PAD_A      equ 1 << PADB_A
PAD_B      equ 1 << PADB_B
PAD_SELECT equ 1 << PADB_SELECT
PAD_START  equ 1 << PADB_START

LCDC_ON     equ %10010011
PALETTE     equ %11100100
TILE_SPACE  equ 0
FIRST_TILE  equ 64

STACK_TOP   equ $e000

hJoyHeld    equ $fff0
hJoyPressed equ $fff1
hRand       equ $fff2
hSongLo     equ $ffe0
hSongHi     equ $ffe1
hMusicLo    equ $ffe2
hMusicHi    equ $ffe3
hMusicTime  equ $ffe4
