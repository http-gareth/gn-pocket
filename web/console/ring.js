const SIZE = 32768
const MASK = SIZE - 1

export class Ring {
  constructor(rate) {
    this.data = new Float32Array(SIZE)
    this.read = 0
    this.write = 0
    this.playing = false
    this.start = rate * 0.05
    this.low = rate * 0.03
    this.high = rate * 0.09
    this.max = rate * 0.2
  }

  buffered() {
    return (this.write - this.read) & MASK
  }

  push(samples) {
    for (let i = 0; i < samples.length; i++) {
      this.data[this.write] = samples[i]
      this.write = (this.write + 1) & MASK
    }
    if (this.buffered() > this.max) this.read = (this.write - Math.floor(this.start)) & MASK
  }

  pull(out) {
    const buffered = this.buffered()
    if (!this.playing) this.playing = buffered > this.start
    const drift = buffered > this.high ? 2 : buffered < this.low ? 0 : 1
    for (let i = 0; i < out.length; i++) {
      if (!this.playing || this.read === this.write) {
        this.playing = false
        out[i] = 0
        continue
      }
      out[i] = this.data[this.read]
      this.read = (this.read + ((i & 127) === 127 ? drift : 1)) & MASK
    }
  }
}
