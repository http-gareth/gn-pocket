const CPU_HZ = 4194304
const SEQUENCER_PERIOD = 8192
const BATCH_CYCLES = 64
const DUTY = [0b00000001, 0b10000001, 0b10000111, 0b01111110]
const NOISE_DIVISORS = [8, 16, 32, 48, 64, 80, 96, 112]
const WAVE_SHIFT = [4, 0, 1, 2]
const READ_MASK = [
  0x80, 0x3f, 0x00, 0xff, 0xbf,
  0xff, 0x3f, 0x00, 0xff, 0xbf,
  0x7f, 0xff, 0x9f, 0xff, 0xbf,
  0xff, 0xff, 0x00, 0x00, 0xbf,
  0x00, 0x00
]

class Channel {
  on = false
  dac = false
  length = 0
  lengthEnabled = false

  clockLength() {
    if (this.lengthEnabled && this.length > 0 && --this.length === 0) this.on = false
  }
}

class Enveloped extends Channel {
  volume = 0
  #initial = 0
  #increase = false
  #period = 0
  #timer = 0

  setEnvelope(v: number) {
    this.#initial = v >> 4
    this.#increase = (v & 0x08) !== 0
    this.#period = v & 0x07
    this.dac = (v & 0xf8) !== 0
    if (!this.dac) this.on = false
  }

  restartEnvelope() {
    this.volume = this.#initial
    this.#timer = this.#period
  }

  clockEnvelope() {
    if (!this.#period || --this.#timer > 0) return
    this.#timer = this.#period
    if (this.#increase && this.volume < 15) this.volume++
    else if (!this.#increase && this.volume > 0) this.volume--
  }
}

class Pulse extends Enveloped {
  duty = 2
  freq = 0
  #step = 0
  #timer = 0

  tick(cycles: number) {
    if (!this.on) return
    this.#timer -= cycles
    while (this.#timer <= 0) {
      this.#timer += (2048 - this.freq) * 4
      this.#step = (this.#step + 1) & 7
    }
  }

  output() {
    return this.on && (DUTY[this.duty] >> (7 - this.#step)) & 1 ? this.volume : 0
  }

  trigger() {
    this.on = this.dac
    if (!this.length) this.length = 64
    this.#timer = (2048 - this.freq) * 4
    this.restartEnvelope()
  }
}

class SweepPulse extends Pulse {
  #period = 0
  #negate = false
  #shift = 0
  #shadow = 0
  #timer = 0
  #enabled = false

  setSweep(v: number) {
    this.#period = (v >> 4) & 7
    this.#negate = (v & 0x08) !== 0
    this.#shift = v & 7
  }

  trigger() {
    super.trigger()
    this.#shadow = this.freq
    this.#timer = this.#period || 8
    this.#enabled = this.#period > 0 || this.#shift > 0
    if (this.#shift) this.#next()
  }

  clockSweep() {
    if (--this.#timer > 0) return
    this.#timer = this.#period || 8
    if (!this.#enabled || !this.#period) return
    const freq = this.#next()
    if (freq <= 2047 && this.#shift) {
      this.freq = this.#shadow = freq
      this.#next()
    }
  }

  #next() {
    const delta = this.#shadow >> this.#shift
    const freq = this.#negate ? this.#shadow - delta : this.#shadow + delta
    if (freq > 2047) this.on = false
    return freq
  }
}

class Wave extends Channel {
  readonly ram = new Uint8Array(16)
  freq = 0
  shift = 4
  #position = 0
  #timer = 0

  tick(cycles: number) {
    if (!this.on) return
    this.#timer -= cycles
    while (this.#timer <= 0) {
      this.#timer += (2048 - this.freq) * 2
      this.#position = (this.#position + 1) & 31
    }
  }

  output() {
    if (!this.on) return 0
    const byte = this.ram[this.#position >> 1]
    return (this.#position & 1 ? byte & 0x0f : byte >> 4) >> this.shift
  }

  trigger() {
    this.on = this.dac
    if (!this.length) this.length = 256
    this.#timer = (2048 - this.freq) * 2
    this.#position = 0
  }
}

class Noise extends Enveloped {
  #lfsr = 0x7fff
  #period = 8
  #narrow = false
  #timer = 0

  setPolynomial(v: number) {
    this.#period = NOISE_DIVISORS[v & 7] << (v >> 4)
    this.#narrow = (v & 0x08) !== 0
  }

  tick(cycles: number) {
    if (!this.on) return
    this.#timer -= cycles
    while (this.#timer <= 0) {
      this.#timer += this.#period
      const bit = (this.#lfsr ^ (this.#lfsr >> 1)) & 1
      this.#lfsr = (this.#lfsr >> 1) | (bit << 14)
      if (this.#narrow) this.#lfsr = (this.#lfsr & ~0x40) | (bit << 6)
    }
  }

  output() {
    return this.on && !(this.#lfsr & 1) ? this.volume : 0
  }

  trigger() {
    this.on = this.dac
    if (!this.length) this.length = 64
    this.#lfsr = 0x7fff
    this.#timer = this.#period
    this.restartEnvelope()
  }
}

export class APU {
  sampleRate = 48000
  capture = false
  readonly pulse1 = new SweepPulse()
  readonly pulse2 = new Pulse()
  readonly wave = new Wave()
  readonly noise = new Noise()
  #regs = new Uint8Array(0x17)
  #power = false
  #sequencer = SEQUENCER_PERIOD
  #step = 0
  #clock = 0
  #dc = 0
  #pending = 0
  #samples = new Float32Array(4096)
  #count = 0

  read(reg: number) {
    this.#catchUp()
    if (reg >= 0x30) return this.wave.ram[reg - 0x30]
    if (reg === 0x26) {
      return (this.#power ? 0x80 : 0) | 0x70 |
        (this.pulse1.on ? 1 : 0) | (this.pulse2.on ? 2 : 0) | (this.wave.on ? 4 : 0) | (this.noise.on ? 8 : 0)
    }
    if (reg > 0x26 || reg === 0x15 || reg === 0x1f) return 0xff
    return this.#regs[reg - 0x10] | READ_MASK[reg - 0x10]
  }

  write(reg: number, v: number) {
    this.#catchUp()
    if (reg >= 0x30) { this.wave.ram[reg - 0x30] = v; return }
    if (reg === 0x26) {
      this.#power = (v & 0x80) !== 0
      if (!this.#power) {
        this.#regs.fill(0)
        for (const ch of [this.pulse1, this.pulse2, this.wave, this.noise]) ch.on = false
      }
      return
    }
    if (!this.#power || reg > 0x26) return
    this.#regs[reg - 0x10] = v
    switch (reg) {
      case 0x10: this.pulse1.setSweep(v); break
      case 0x11: this.pulse1.duty = v >> 6; this.pulse1.length = 64 - (v & 0x3f); break
      case 0x12: this.pulse1.setEnvelope(v); break
      case 0x13: this.pulse1.freq = (this.pulse1.freq & 0x700) | v; break
      case 0x14:
        this.pulse1.freq = (this.pulse1.freq & 0xff) | ((v & 7) << 8)
        this.pulse1.lengthEnabled = (v & 0x40) !== 0
        if (v & 0x80) this.pulse1.trigger()
        break
      case 0x16: this.pulse2.duty = v >> 6; this.pulse2.length = 64 - (v & 0x3f); break
      case 0x17: this.pulse2.setEnvelope(v); break
      case 0x18: this.pulse2.freq = (this.pulse2.freq & 0x700) | v; break
      case 0x19:
        this.pulse2.freq = (this.pulse2.freq & 0xff) | ((v & 7) << 8)
        this.pulse2.lengthEnabled = (v & 0x40) !== 0
        if (v & 0x80) this.pulse2.trigger()
        break
      case 0x1a: this.wave.dac = (v & 0x80) !== 0; if (!this.wave.dac) this.wave.on = false; break
      case 0x1b: this.wave.length = 256 - v; break
      case 0x1c: this.wave.shift = WAVE_SHIFT[(v >> 5) & 3]; break
      case 0x1d: this.wave.freq = (this.wave.freq & 0x700) | v; break
      case 0x1e:
        this.wave.freq = (this.wave.freq & 0xff) | ((v & 7) << 8)
        this.wave.lengthEnabled = (v & 0x40) !== 0
        if (v & 0x80) this.wave.trigger()
        break
      case 0x20: this.noise.length = 64 - (v & 0x3f); break
      case 0x21: this.noise.setEnvelope(v); break
      case 0x22: this.noise.setPolynomial(v); break
      case 0x23:
        this.noise.lengthEnabled = (v & 0x40) !== 0
        if (v & 0x80) this.noise.trigger()
        break
    }
  }

  tick(cycles: number) {
    this.#pending += cycles
    if (this.#pending >= BATCH_CYCLES) this.#catchUp()
  }

  #catchUp() {
    const cycles = this.#pending
    this.#pending = 0
    if (this.#power) {
      this.pulse1.tick(cycles)
      this.pulse2.tick(cycles)
      this.wave.tick(cycles)
      this.noise.tick(cycles)
      this.#sequencer -= cycles
      while (this.#sequencer <= 0) {
        this.#sequencer += SEQUENCER_PERIOD
        this.#sequence()
      }
    }
    if (!this.capture) return
    this.#clock += cycles * this.sampleRate
    while (this.#clock >= CPU_HZ) {
      this.#clock -= CPU_HZ
      if (this.#count === this.#samples.length) {
        const grown = new Float32Array(this.#count * 2)
        grown.set(this.#samples)
        this.#samples = grown
      }
      this.#samples[this.#count++] = this.#mix()
    }
  }

  takeSamples() {
    const out = this.#samples.slice(0, this.#count)
    this.#count = 0
    return out
  }

  #sequence() {
    const step = this.#step
    if (!(step & 1)) {
      this.pulse1.clockLength()
      this.pulse2.clockLength()
      this.wave.clockLength()
      this.noise.clockLength()
    }
    if (step === 2 || step === 6) this.pulse1.clockSweep()
    if (step === 7) {
      this.pulse1.clockEnvelope()
      this.pulse2.clockEnvelope()
      this.noise.clockEnvelope()
    }
    this.#step = (step + 1) & 7
  }

  #mix() {
    if (!this.#power) return this.#highPass(0)
    const nr50 = this.#regs[0x14]
    const nr51 = this.#regs[0x15]
    const p1 = this.pulse1.output()
    const p2 = this.pulse2.output()
    const wave = this.wave.output()
    const noise = this.noise.output()
    const left = (nr51 & 0x10 ? p1 : 0) + (nr51 & 0x20 ? p2 : 0) + (nr51 & 0x40 ? wave : 0) + (nr51 & 0x80 ? noise : 0)
    const right = (nr51 & 0x01 ? p1 : 0) + (nr51 & 0x02 ? p2 : 0) + (nr51 & 0x04 ? wave : 0) + (nr51 & 0x08 ? noise : 0)
    const level = (left * (((nr50 >> 4) & 7) + 1) + right * ((nr50 & 7) + 1)) / (2 * 4 * 15 * 8)
    return this.#highPass(level)
  }

  #highPass(level: number) {
    this.#dc += (level - this.#dc) * 0.002
    return (level - this.#dc) * 0.9
  }
}
