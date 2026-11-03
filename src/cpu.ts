export interface Bus {
  read(addr: number): number
  write(addr: number, value: number): void
}

export const FLAG_Z = 0x80
export const FLAG_N = 0x40
export const FLAG_H = 0x20
export const FLAG_C = 0x10

const IE = 0xffff
const IF = 0xff0f

export class IllegalOpcode extends Error {}

export class CPU {
  a = 0x01
  f = 0xb0
  b = 0x00
  c = 0x13
  d = 0x00
  e = 0xd8
  h = 0x01
  l = 0x4d
  sp = 0xfffe
  pc = 0x0100
  ime = false
  halted = false
  cycles = 0
  #imeDelay = 0
  #haltBug = false
  #bus: Bus

  save() {
    return [this.a, this.f, this.b, this.c, this.d, this.e, this.h, this.l, this.sp, this.pc, +this.ime, +this.halted, this.#imeDelay, +this.#haltBug]
  }

  load(state: number[]) {
    [this.a, this.f, this.b, this.c, this.d, this.e, this.h, this.l, this.sp, this.pc] = state
    this.ime = state[10] === 1
    this.halted = state[11] === 1
    this.#imeDelay = state[12]
    this.#haltBug = state[13] === 1
  }

  constructor(bus: Bus) {
    this.#bus = bus
  }

  get bc() { return (this.b << 8) | this.c }
  set bc(v: number) { this.b = (v >> 8) & 0xff; this.c = v & 0xff }
  get de() { return (this.d << 8) | this.e }
  set de(v: number) { this.d = (v >> 8) & 0xff; this.e = v & 0xff }
  get hl() { return (this.h << 8) | this.l }
  set hl(v: number) { this.h = (v >> 8) & 0xff; this.l = v & 0xff }
  get af() { return (this.a << 8) | this.f }
  set af(v: number) { this.a = (v >> 8) & 0xff; this.f = v & 0xf0 }

  step(): number {
    const start = this.cycles
    const pending = this.#bus.read(IE) & this.#bus.read(IF) & 0x1f
    if (this.halted) {
      if (!pending) {
        this.#idle()
        return this.cycles - start
      }
      this.halted = false
    }
    if (this.ime && pending) {
      const bit = pending & -pending
      this.ime = false
      this.#bus.write(IF, this.#bus.read(IF) & ~bit)
      this.#idle()
      this.#idle()
      this.#push(this.pc)
      this.pc = 0x40 + (31 - Math.clz32(bit)) * 8
      this.#idle()
      return this.cycles - start
    }
    this.#execute(this.#fetch())
    if (this.#imeDelay && --this.#imeDelay === 0) this.ime = true
    return this.cycles - start
  }

  #flag(mask: number) { return (this.f & mask) !== 0 }

  #flags(z: boolean, n: boolean, h: boolean, c: boolean) {
    this.f = (z ? FLAG_Z : 0) | (n ? FLAG_N : 0) | (h ? FLAG_H : 0) | (c ? FLAG_C : 0)
  }

  #read(addr: number) {
    this.cycles += 4
    return this.#bus.read(addr & 0xffff)
  }

  #write(addr: number, value: number) {
    this.cycles += 4
    this.#bus.write(addr & 0xffff, value & 0xff)
  }

  #idle() { this.cycles += 4 }

  #fetch() {
    const value = this.#read(this.pc)
    if (this.#haltBug) this.#haltBug = false
    else this.pc = (this.pc + 1) & 0xffff
    return value
  }

  #fetch16() {
    const lo = this.#fetch()
    return lo | (this.#fetch() << 8)
  }

  #push(value: number) {
    this.sp = (this.sp - 1) & 0xffff
    this.#write(this.sp, value >> 8)
    this.sp = (this.sp - 1) & 0xffff
    this.#write(this.sp, value)
  }

  #pop() {
    const lo = this.#read(this.sp)
    this.sp = (this.sp + 1) & 0xffff
    const hi = this.#read(this.sp)
    this.sp = (this.sp + 1) & 0xffff
    return (hi << 8) | lo
  }

  #getR(i: number): number {
    switch (i) {
      case 0: return this.b
      case 1: return this.c
      case 2: return this.d
      case 3: return this.e
      case 4: return this.h
      case 5: return this.l
      case 6: return this.#read(this.hl)
      default: return this.a
    }
  }

  #setR(i: number, v: number) {
    switch (i) {
      case 0: this.b = v; break
      case 1: this.c = v; break
      case 2: this.d = v; break
      case 3: this.e = v; break
      case 4: this.h = v; break
      case 5: this.l = v; break
      case 6: this.#write(this.hl, v); break
      default: this.a = v
    }
  }

  #getRP(p: number) {
    return p === 0 ? this.bc : p === 1 ? this.de : p === 2 ? this.hl : this.sp
  }

  #setRP(p: number, v: number) {
    v &= 0xffff
    if (p === 0) this.bc = v
    else if (p === 1) this.de = v
    else if (p === 2) this.hl = v
    else this.sp = v
  }

  #cond(i: number) {
    switch (i) {
      case 0: return !this.#flag(FLAG_Z)
      case 1: return this.#flag(FLAG_Z)
      case 2: return !this.#flag(FLAG_C)
      default: return this.#flag(FLAG_C)
    }
  }

  #alu(op: number, v: number) {
    const a = this.a
    const carry = this.#flag(FLAG_C) ? 1 : 0
    switch (op) {
      case 0: {
        const r = a + v
        this.#flags((r & 0xff) === 0, false, (a & 0xf) + (v & 0xf) > 0xf, r > 0xff)
        this.a = r & 0xff
        return
      }
      case 1: {
        const r = a + v + carry
        this.#flags((r & 0xff) === 0, false, (a & 0xf) + (v & 0xf) + carry > 0xf, r > 0xff)
        this.a = r & 0xff
        return
      }
      case 2: {
        const r = a - v
        this.#flags((r & 0xff) === 0, true, (a & 0xf) < (v & 0xf), r < 0)
        this.a = r & 0xff
        return
      }
      case 3: {
        const r = a - v - carry
        this.#flags((r & 0xff) === 0, true, (a & 0xf) < (v & 0xf) + carry, r < 0)
        this.a = r & 0xff
        return
      }
      case 4: this.a = a & v; this.#flags(this.a === 0, false, true, false); return
      case 5: this.a = a ^ v; this.#flags(this.a === 0, false, false, false); return
      case 6: this.a = a | v; this.#flags(this.a === 0, false, false, false); return
      default: {
        const r = a - v
        this.#flags((r & 0xff) === 0, true, (a & 0xf) < (v & 0xf), r < 0)
      }
    }
  }

  #inc(v: number) {
    const r = (v + 1) & 0xff
    this.f = (this.f & FLAG_C) | (r === 0 ? FLAG_Z : 0) | ((v & 0xf) === 0xf ? FLAG_H : 0)
    return r
  }

  #dec(v: number) {
    const r = (v - 1) & 0xff
    this.f = (this.f & FLAG_C) | (r === 0 ? FLAG_Z : 0) | FLAG_N | ((v & 0xf) === 0 ? FLAG_H : 0)
    return r
  }

  #addHL(v: number) {
    const hl = this.hl
    const r = hl + v
    this.f = (this.f & FLAG_Z) | ((hl & 0xfff) + (v & 0xfff) > 0xfff ? FLAG_H : 0) | (r > 0xffff ? FLAG_C : 0)
    this.hl = r & 0xffff
    this.#idle()
  }

  #spOffset() {
    const u = this.#fetch()
    this.f = ((this.sp & 0xf) + (u & 0xf) > 0xf ? FLAG_H : 0) | ((this.sp & 0xff) + u > 0xff ? FLAG_C : 0)
    return (this.sp + ((u ^ 0x80) - 0x80)) & 0xffff
  }

  #daa() {
    let adjust = 0
    let carry = this.#flag(FLAG_C)
    const sub = this.#flag(FLAG_N)
    if (this.#flag(FLAG_H) || (!sub && (this.a & 0xf) > 9)) adjust |= 0x06
    if (carry || (!sub && this.a > 0x99)) { adjust |= 0x60; carry = true }
    this.a = (sub ? this.a - adjust : this.a + adjust) & 0xff
    this.f = (this.a === 0 ? FLAG_Z : 0) | (sub ? FLAG_N : 0) | (carry ? FLAG_C : 0)
  }

  #jr(take: boolean) {
    const offset = (this.#fetch() ^ 0x80) - 0x80
    if (take) {
      this.pc = (this.pc + offset) & 0xffff
      this.#idle()
    }
  }

  #halt() {
    const pending = this.#bus.read(IE) & this.#bus.read(IF) & 0x1f
    if (!this.ime && pending) this.#haltBug = true
    else this.halted = true
  }

  #cb() {
    const op = this.#fetch()
    const r = op & 7
    const y = (op >> 3) & 7
    const x = op >> 6
    const v = this.#getR(r)
    if (x === 1) {
      this.f = (this.f & FLAG_C) | (v & (1 << y) ? 0 : FLAG_Z) | FLAG_H
      return
    }
    if (x === 2) return this.#setR(r, v & ~(1 << y))
    if (x === 3) return this.#setR(r, v | (1 << y))
    let out: number
    let carry: number
    switch (y) {
      case 0: carry = v >> 7; out = ((v << 1) | carry) & 0xff; break
      case 1: carry = v & 1; out = (v >> 1) | (carry << 7); break
      case 2: carry = v >> 7; out = ((v << 1) | (this.#flag(FLAG_C) ? 1 : 0)) & 0xff; break
      case 3: carry = v & 1; out = (v >> 1) | (this.#flag(FLAG_C) ? 0x80 : 0); break
      case 4: carry = v >> 7; out = (v << 1) & 0xff; break
      case 5: carry = v & 1; out = (v >> 1) | (v & 0x80); break
      case 6: carry = 0; out = ((v & 0xf) << 4) | (v >> 4); break
      default: carry = v & 1; out = v >> 1
    }
    this.f = (out === 0 ? FLAG_Z : 0) | (carry ? FLAG_C : 0)
    this.#setR(r, out)
  }

  #execute(op: number) {
    if (op >= 0x40 && op < 0x80) {
      if (op === 0x76) return this.#halt()
      return this.#setR((op >> 3) & 7, this.#getR(op & 7))
    }
    if (op >= 0x80 && op < 0xc0) return this.#alu((op >> 3) & 7, this.#getR(op & 7))

    switch (op) {
      case 0x00: return
      case 0x01: case 0x11: case 0x21: case 0x31: return this.#setRP(op >> 4, this.#fetch16())
      case 0x02: return this.#write(this.bc, this.a)
      case 0x12: return this.#write(this.de, this.a)
      case 0x22: this.#write(this.hl, this.a); this.hl = (this.hl + 1) & 0xffff; return
      case 0x32: this.#write(this.hl, this.a); this.hl = (this.hl - 1) & 0xffff; return
      case 0x0a: this.a = this.#read(this.bc); return
      case 0x1a: this.a = this.#read(this.de); return
      case 0x2a: this.a = this.#read(this.hl); this.hl = (this.hl + 1) & 0xffff; return
      case 0x3a: this.a = this.#read(this.hl); this.hl = (this.hl - 1) & 0xffff; return
      case 0x03: case 0x13: case 0x23: case 0x33: this.#setRP(op >> 4, this.#getRP(op >> 4) + 1); return this.#idle()
      case 0x0b: case 0x1b: case 0x2b: case 0x3b: this.#setRP(op >> 4, this.#getRP(op >> 4) - 1); return this.#idle()
      case 0x09: case 0x19: case 0x29: case 0x39: return this.#addHL(this.#getRP(op >> 4))
      case 0x04: case 0x0c: case 0x14: case 0x1c: case 0x24: case 0x2c: case 0x34: case 0x3c: {
        const r = (op >> 3) & 7
        return this.#setR(r, this.#inc(this.#getR(r)))
      }
      case 0x05: case 0x0d: case 0x15: case 0x1d: case 0x25: case 0x2d: case 0x35: case 0x3d: {
        const r = (op >> 3) & 7
        return this.#setR(r, this.#dec(this.#getR(r)))
      }
      case 0x06: case 0x0e: case 0x16: case 0x1e: case 0x26: case 0x2e: case 0x36: case 0x3e:
        return this.#setR((op >> 3) & 7, this.#fetch())
      case 0x07: {
        const carry = this.a >> 7
        this.a = ((this.a << 1) | carry) & 0xff
        this.f = carry ? FLAG_C : 0
        return
      }
      case 0x0f: {
        const carry = this.a & 1
        this.a = (this.a >> 1) | (carry << 7)
        this.f = carry ? FLAG_C : 0
        return
      }
      case 0x17: {
        const carry = this.a >> 7
        this.a = ((this.a << 1) | (this.#flag(FLAG_C) ? 1 : 0)) & 0xff
        this.f = carry ? FLAG_C : 0
        return
      }
      case 0x1f: {
        const carry = this.a & 1
        this.a = (this.a >> 1) | (this.#flag(FLAG_C) ? 0x80 : 0)
        this.f = carry ? FLAG_C : 0
        return
      }
      case 0x27: return this.#daa()
      case 0x2f: this.a ^= 0xff; this.f |= FLAG_N | FLAG_H; return
      case 0x37: this.f = (this.f & FLAG_Z) | FLAG_C; return
      case 0x3f: this.f = (this.f & FLAG_Z) | (this.#flag(FLAG_C) ? 0 : FLAG_C); return
      case 0x08: {
        const addr = this.#fetch16()
        this.#write(addr, this.sp & 0xff)
        this.#write(addr + 1, this.sp >> 8)
        return
      }
      case 0x10: this.#fetch(); return
      case 0x18: return this.#jr(true)
      case 0x20: case 0x28: case 0x30: case 0x38: return this.#jr(this.#cond((op >> 3) & 3))
      case 0xc0: case 0xc8: case 0xd0: case 0xd8:
        this.#idle()
        if (this.#cond((op >> 3) & 3)) { this.pc = this.#pop(); this.#idle() }
        return
      case 0xc9: this.pc = this.#pop(); return this.#idle()
      case 0xd9: this.pc = this.#pop(); this.#idle(); this.ime = true; return
      case 0xc1: this.bc = this.#pop(); return
      case 0xd1: this.de = this.#pop(); return
      case 0xe1: this.hl = this.#pop(); return
      case 0xf1: this.af = this.#pop(); return
      case 0xc5: this.#idle(); return this.#push(this.bc)
      case 0xd5: this.#idle(); return this.#push(this.de)
      case 0xe5: this.#idle(); return this.#push(this.hl)
      case 0xf5: this.#idle(); return this.#push(this.af)
      case 0xc2: case 0xca: case 0xd2: case 0xda: {
        const addr = this.#fetch16()
        if (this.#cond((op >> 3) & 3)) { this.pc = addr; this.#idle() }
        return
      }
      case 0xc3: this.pc = this.#fetch16(); return this.#idle()
      case 0xe9: this.pc = this.hl; return
      case 0xc4: case 0xcc: case 0xd4: case 0xdc: {
        const addr = this.#fetch16()
        if (this.#cond((op >> 3) & 3)) { this.#idle(); this.#push(this.pc); this.pc = addr }
        return
      }
      case 0xcd: {
        const addr = this.#fetch16()
        this.#idle()
        this.#push(this.pc)
        this.pc = addr
        return
      }
      case 0xc6: case 0xce: case 0xd6: case 0xde: case 0xe6: case 0xee: case 0xf6: case 0xfe:
        return this.#alu((op >> 3) & 7, this.#fetch())
      case 0xc7: case 0xcf: case 0xd7: case 0xdf: case 0xe7: case 0xef: case 0xf7: case 0xff:
        this.#idle()
        this.#push(this.pc)
        this.pc = op & 0x38
        return
      case 0xcb: return this.#cb()
      case 0xe0: return this.#write(0xff00 + this.#fetch(), this.a)
      case 0xf0: this.a = this.#read(0xff00 + this.#fetch()); return
      case 0xe2: return this.#write(0xff00 + this.c, this.a)
      case 0xf2: this.a = this.#read(0xff00 + this.c); return
      case 0xea: return this.#write(this.#fetch16(), this.a)
      case 0xfa: this.a = this.#read(this.#fetch16()); return
      case 0xe8: this.sp = this.#spOffset(); this.#idle(); this.#idle(); return
      case 0xf8: this.hl = this.#spOffset(); return this.#idle()
      case 0xf9: this.sp = this.hl; return this.#idle()
      case 0xf3: this.ime = false; this.#imeDelay = 0; return
      case 0xfb: this.#imeDelay = 2; return
      default:
        throw new IllegalOpcode(`illegal opcode $${op.toString(16).padStart(2, '0')} at $${((this.pc - 1) & 0xffff).toString(16).padStart(4, '0')}`)
    }
  }
}
