# GN Pocket

A Game Boy, built from scratch — the console *and* its games.

**[Play it in your browser →](https://http-gareth.github.io/gn-pocket/)** Works on a phone too: add it to your home screen and it runs full screen.

- **Emulator** (`src/`) — the Sharp SM83 CPU (every instruction, cycle-accurate per memory access), memory map, timer, interrupts, joypad and the picture processor (background, window, 10 sprites per line with correct priority).
- **Assembler** (`src/assembler.ts`) — turns Game Boy assembly into a cartridge: labels, local labels, constants, expressions, strings and pixel-art rows (`` dw `00333300 ``). It runs in the browser, so every cartridge is assembled live when you insert it.
- **Games** (`games/`) — only games written for this console. No commercial ROMs. A menu cartridge (`menu.asm`) runs on the console itself, scrolls five titles at a time, and hands over to the chosen game through the GN Pocket launcher port (`$FF7F`), like a flash cart. Start + Select returns to the menu.
- **Sound chip** (`src/apu.ts`) — both pulse channels (one with frequency sweep), the wave channel and the noise channel, with length counters, volume envelopes and the 512 Hz frame sequencer, mixed out through Web Audio. Any key or tap turns it on; M mutes.
- **Shared library** (`games/lib/`) — hardware names, a 64-glyph font, joypad, random numbers, screen helpers, sound effects and a music player on the wave channel (so tunes never fight the sound effects), pulled in with `include`.

| Game | How to play |
|---|---|
| Pong | Up / Down. The rally speeds up and angles vary, so nobody can park in a corner forever. |
| Snake | D-pad to steer. Eat, grow, speed up. A to restart. |
| Shootout | Five penalties each: A to shoot, then Left / Right to save. |
| Bricks | Left / Right to move, A to launch. Where the ball hits the paddle sets its angle. Clear the wall for the next level, which is faster. |
| Flap | A to flap through an endless, randomly built pipe course. Score and best on a HUD drawn in the window layer. |
| Blocks | The falling-blocks puzzle. Left / Right to move (hold to slide), A / B to turn with wall kicks, Down to drop faster, Up to slam. Rows flash before they clear; the speed rises every 10 lines. |
| Racer | Top-down highway. Left / Right to steer, Up or A for gas, Down or B to brake. Faster scores more, and the traffic gets thicker. |
| Invasion | Left / Right to move, A to fire. The formation glides and speeds up as it thins; a mystery ship crosses for bonus points. Every third wave is a mothership boss with a health bar. |
| Pip Quest | A side-scrolling platformer with an original hero. Run with B, jump with A (hold for higher). Stomp grubs, bump ? blocks for coins, break bricks, reach the flag. Two overworld courses, then Krag's castle: lava pits and a boss you stomp three times. Five lives and a checkpoint halfway through each course. |
| Knockout | A one-on-one fighter, best of three against the CPU. A punch, B kick, Down + A fireball, Up to jump (A or B in the air for a jump kick), hold away to block. |

**Colour:** the three dots beside the logo (or C) cycle palettes. Like a Game Boy Color running an original Game Boy game, backgrounds and each sprite palette get their own colours, so the PPU tags every pixel with the layer it came from.

**Phone:** on a small screen the console fills the display edge to edge, and it can be added to the home screen as a full-screen app. The server prints the Wi-Fi address to open on a phone. Tap the speaker (or M) for sound on/off.

Scoring HUDs sit in the window layer. Where sprites could cross them, a scanline interrupt at the window's top line switches sprites off for the rest of the frame — the classic raster trick.

Zero dependencies: Node's standard library strips the TypeScript and serves it straight to the browser.

## Run

```bash
npm start       # http://localhost:5190, plus the link-cable server for two players
npm test
npm run build   # static copy in dist/, deployed to GitHub Pages on every push
```

Node 22.13+. The hosted copy plays every game; two-player link play needs `npm start` on a PC, with both phones on its Wi-Fi.

## Controls

| | Keyboard | Touch |
|---|---|---|
| Move | Arrow keys | D-pad |
| A / B | Z / X | A / B |
| Start / Select | Enter / Shift | Start / Select |
| Menu | Start + Select | Start + Select |
| Sound on / off | M | Speaker grille |
| Rewind | Hold R | Hold ◀◀ |
| Colours | C | The three dots |
| Save / Load | S / L | MENU |
| Nerd mode | N | MENU |

## Milestones

- [x] **1. Console core** — CPU, memory, timer, interrupts, joypad, PPU
- [x] **2. Assembler** — every instruction, labels, expressions, pixel art
- [x] **3. First game: Pong** — you vs the CPU, paddle-angle returns, score
- [x] **4. On-console menu + Snake + Shootout** — launcher port, shared library, `include`
- [x] **5. Sound** — the four audio channels, effects in every game, music
- [x] **6. More games** — Bricks, Flap, Blocks, Racer, Invasion (with a boss), Pip Quest (platformer with a boss castle), and a scrolling menu
- [x] **7. Save anywhere + rewind** — whole-machine snapshots; hold ◀◀ (or R) to rewind the last 20 seconds, S / L to save and load
- [x] **8. Two players over the network** — lockstep netplay: both consoles run the same game and swap button presses each frame, with a 4-frame input delay and periodic checksums to catch any desync. Pong and Knockout read player 2 from a second controller port (`$FF7E`). Same Wi-Fi today; deploy the server to play across the internet.
- [x] **9. Nerd mode** — live CPU registers and the routine being run (from the assembler's labels), game variables changing in memory, and all 256 tiles in video memory
- [x] **10. Phone rumble** — games write to a rumble port (`$FF7C`) on hits, crashes and deaths
- [x] **11. Make your own** — a Game Studio page (write assembly, press RUN, play it instantly, errors point at the line) and a Pip Quest level editor that paints with the cartridge's real tiles
