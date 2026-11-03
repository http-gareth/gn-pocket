export class AsmError extends Error {}

const R8: Record<string, number> = { b: 0, c: 1, d: 2, e: 3, h: 4, l: 5, '[hl]': 6, a: 7 }
const RP: Record<string, number> = { bc: 0, de: 1, hl: 2, sp: 3 }
const RP2: Record<string, number> = { bc: 0, de: 1, hl: 2, af: 3 }
const CC: Record<string, number> = { nz: 0, z: 1, nc: 2, c: 3 }
const ALU: Record<string, number> = { add: 0, adc: 1, sub: 2, sbc: 3, and: 4, xor: 5, or: 6, cp: 7 }
const ROT: Record<string, number> = { rlc: 0, rrc: 1, rl: 2, rr: 3, sla: 4, sra: 5, swap: 6, srl: 7 }
const BITOP: Record<string, number> = { bit: 1, res: 2, set: 3 }
const BARE: Record<string, number[]> = {
  nop: [0x00], halt: [0x76], stop: [0x10, 0x00], di: [0xf3], ei: [0xfb], reti: [0xd9],
  rlca: [0x07], rrca: [0x0f], rla: [0x17], rra: [0x1f], daa: [0x27], cpl: [0x2f], scf: [0x37], ccf: [0x3f]
}
const HL_INC = new Set(['[hl+]', '[hli]'])
const HL_DEC = new Set(['[hl-]', '[hld]'])
const FIXED_MEM = new Set(['[bc]', '[de]', '[c]', '[hl]', ...HL_INC, ...HL_DEC])

interface Ctx {
  final: boolean
  pc: number
  value(expr: string): number
}

const fail = (message: string): never => { throw new AsmError(message) }

const inRange = (ctx: Ctx, v: number, lo: number, hi: number, what: string) => {
  if (ctx.final && (v < lo || v > hi)) fail(`${what} ${v} out of range`)
  return v
}

const TOKEN = /\s*(?:(`[0-3]{8})|(\$[0-9a-fA-F]+|0x[0-9a-fA-F]+)|(%[01]+|0b[01]+)|(\d+)|'(.)'|(<<|>>|[-+*/&|^~(),])|([.A-Za-z_][\w.]*))/y

const tokenize = (src: string) => {
  const tokens: string[] = []
  TOKEN.lastIndex = 0
  while (TOKEN.lastIndex < src.length) {
    const start = TOKEN.lastIndex
    const m = TOKEN.exec(src)
    if (!m) {
      if (!src.slice(start).trim()) break
      fail(`can't read "${src.slice(start).trim()}"`)
    }
    const [, tile, hex, bin, dec, chr, op, ident] = m as RegExpExecArray
    if (tile) tokens.push(tile)
    else if (hex) tokens.push(String(parseInt(hex.replace(/^\$|^0x/i, ''), 16)))
    else if (bin) tokens.push(String(parseInt(bin.replace(/^%|^0b/i, ''), 2)))
    else if (dec) tokens.push(dec)
    else if (chr !== undefined) tokens.push(String(chr.charCodeAt(0)))
    else tokens.push(op ?? ident)
  }
  return tokens
}

const tileRow = (pixels: string) => {
  let lo = 0
  let hi = 0
  for (let i = 0; i < 8; i++) {
    const c = Number(pixels[i])
    lo |= (c & 1) << (7 - i)
    hi |= ((c >> 1) & 1) << (7 - i)
  }
  return (hi << 8) | lo
}

const evaluate = (src: string, lookup: (name: string) => number | undefined, final: boolean): number => {
  const tokens = tokenize(src)
  let i = 0
  const peek = () => tokens[i]
  const next = () => tokens[i++]
  const expect = (t: string) => { if (next() !== t) fail(`expected "${t}" in "${src}"`) }

  const binary = (ops: string[], sub: () => number, apply: (op: string, a: number, b: number) => number) => () => {
    let v = sub()
    while (ops.includes(peek())) {
      const op = next()
      v = apply(op, v, sub())
    }
    return v
  }

  const primary = (): number => {
    const t = next()
    if (t === undefined) return fail(`incomplete expression "${src}"`)
    if (t === '(') { const v = expr(); expect(')'); return v }
    if (t === '-') return -primary()
    if (t === '+') return primary()
    if (t === '~') return ~primary()
    if (t.startsWith('`')) return tileRow(t.slice(1))
    if (/^\d+$/.test(t)) return Number(t)
    if (/^[.A-Za-z_]/.test(t)) {
      const fn = t.toLowerCase()
      if ((fn === 'high' || fn === 'low') && peek() === '(') {
        next()
        const v = expr()
        expect(')')
        return fn === 'high' ? (v >> 8) & 0xff : v & 0xff
      }
      const v = lookup(t)
      if (v === undefined) return final ? fail(`unknown symbol "${t}"`) : 0
      return v
    }
    return fail(`unexpected "${t}" in "${src}"`)
  }

  const mul = binary(['*', '/'], primary, (op, a, b) => op === '*' ? a * b : Math.trunc(a / (b || fail('division by zero'))))
  const add = binary(['+', '-'], mul, (op, a, b) => op === '+' ? a + b : a - b)
  const shift = binary(['<<', '>>'], add, (op, a, b) => op === '<<' ? a << b : a >> b)
  const and = binary(['&'], shift, (_, a, b) => a & b)
  const xor = binary(['^'], and, (_, a, b) => a ^ b)
  const expr = binary(['|'], xor, (_, a, b) => a | b)

  const v = expr()
  if (i < tokens.length) fail(`unexpected "${tokens[i]}" in "${src}"`)
  return v
}

const splitArgs = (text: string) => {
  const args: string[] = []
  let depth = 0
  let quote = ''
  let current = ''
  for (const ch of text) {
    if (quote) { current += ch; if (ch === quote) quote = ''; continue }
    if (ch === '"') { quote = ch; current += ch; continue }
    if (ch === '(' || ch === '[') depth++
    if (ch === ')' || ch === ']') depth--
    if (ch === ',' && depth === 0) { args.push(current.trim()); current = ''; continue }
    current += ch
  }
  if (current.trim()) args.push(current.trim())
  return args
}

const stripComment = (line: string) => {
  let quote = ''
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (quote) { if (ch === quote) quote = ''; continue }
    if (ch === '"' || ch === "'") quote = ch
    else if (ch === ';') return line.slice(0, i)
  }
  return line
}

const unbracket = (s: string) => s.trim().replace(/^\[(.*)\]$/s, '$1')

const encode = (mn: string, raw: string[], ctx: Ctx): number[] => {
  const ops = raw.map(s => s.trim())
  const n = ops.map(s => s.toLowerCase().replace(/\s+/g, ''))
  const count = ops.length
  const val = (i: number) => ctx.value(unbracket(ops[i]))
  const u8 = (i: number) => inRange(ctx, val(i), -128, 255, 'byte') & 0xff
  const s8 = (v: number) => inRange(ctx, v, -128, 127, 'signed byte') & 0xff
  const u16 = (i: number) => { const v = inRange(ctx, val(i), -32768, 0xffff, 'word') & 0xffff; return [v & 0xff, v >> 8] }
  const high = (i: number) => {
    const v = val(i)
    if (ctx.final && !((v >= 0 && v <= 0xff) || (v >= 0xff00 && v <= 0xffff))) fail(`ldh address ${v} must be $ff00-$ffff`)
    return v & 0xff
  }
  const isMem = (i: number) => n[i].startsWith('[') && !FIXED_MEM.has(n[i])
  const isImm = (i: number) => !(n[i] in R8) && !(n[i] in RP) && n[i] !== 'af' && !n[i].startsWith('[') && !/^sp[+-]/.test(n[i])
  const spOffset = (i: number) => {
    const m = /^sp\s*([+-])\s*(.+)$/i.exec(ops[i]) ?? fail(`bad sp offset "${ops[i]}"`)
    return s8(ctx.value(m[2]) * (m[1] === '-' ? -1 : 1))
  }

  if (mn in BARE) {
    if (count) fail(`${mn} takes no operands`)
    return BARE[mn]
  }

  if (mn === 'ld' && count === 2) {
    const [d, s] = n
    if (d in R8 && s in R8) return d === '[hl]' && s === '[hl]' ? fail('ld [hl], [hl] is not an instruction') : [0x40 | (R8[d] << 3) | R8[s]]
    if (d === 'a') {
      if (s === '[bc]') return [0x0a]
      if (s === '[de]') return [0x1a]
      if (HL_INC.has(s)) return [0x2a]
      if (HL_DEC.has(s)) return [0x3a]
      if (s === '[c]') return [0xf2]
      if (isMem(1)) return [0xfa, ...u16(1)]
    }
    if (s === 'a') {
      if (d === '[bc]') return [0x02]
      if (d === '[de]') return [0x12]
      if (HL_INC.has(d)) return [0x22]
      if (HL_DEC.has(d)) return [0x32]
      if (d === '[c]') return [0xe2]
      if (isMem(0)) return [0xea, ...u16(0)]
    }
    if (d in R8 && isImm(1)) return [0x06 | (R8[d] << 3), u8(1)]
    if (d in RP && isImm(1)) return [0x01 | (RP[d] << 4), ...u16(1)]
    if (isMem(0) && s === 'sp') return [0x08, ...u16(0)]
    if (d === 'sp' && s === 'hl') return [0xf9]
    if (d === 'hl' && /^sp[+-]/.test(s)) return [0xf8, spOffset(1)]
  }

  if (mn === 'ldh' && count === 2) {
    if (n[0] === '[c]' && n[1] === 'a') return [0xe2]
    if (n[0] === 'a' && n[1] === '[c]') return [0xf2]
    if (isMem(0) && n[1] === 'a') return [0xe0, high(0)]
    if (n[0] === 'a' && isMem(1)) return [0xf0, high(1)]
  }

  if ((mn === 'inc' || mn === 'dec') && count === 1) {
    const up = mn === 'inc'
    if (n[0] in R8) return [(up ? 0x04 : 0x05) | (R8[n[0]] << 3)]
    if (n[0] in RP) return [(up ? 0x03 : 0x0b) | (RP[n[0]] << 4)]
  }

  if (mn in ALU) {
    if (mn === 'add' && count === 2 && n[0] === 'hl' && n[1] in RP) return [0x09 | (RP[n[1]] << 4)]
    if (mn === 'add' && count === 2 && n[0] === 'sp') return [0xe8, s8(val(1))]
    const i = count === 2 && n[0] === 'a' ? 1 : count === 1 ? 0 : -1
    if (i >= 0 && n[i] in R8) return [0x80 | (ALU[mn] << 3) | R8[n[i]]]
    if (i >= 0 && isImm(i)) return [0xc6 | (ALU[mn] << 3), u8(i)]
  }

  if (mn === 'jp') {
    if (count === 1 && (n[0] === 'hl' || n[0] === '[hl]')) return [0xe9]
    if (count === 1) return [0xc3, ...u16(0)]
    if (count === 2 && n[0] in CC) return [0xc2 | (CC[n[0]] << 3), ...u16(1)]
  }

  if (mn === 'jr' && (count === 1 || (count === 2 && n[0] in CC))) {
    const offset = inRange(ctx, val(count - 1) - (ctx.pc + 2), -128, 127, 'jr distance') & 0xff
    return count === 1 ? [0x18, offset] : [0x20 | (CC[n[0]] << 3), offset]
  }

  if (mn === 'call') {
    if (count === 1) return [0xcd, ...u16(0)]
    if (count === 2 && n[0] in CC) return [0xc4 | (CC[n[0]] << 3), ...u16(1)]
  }

  if (mn === 'ret') {
    if (count === 0) return [0xc9]
    if (count === 1 && n[0] in CC) return [0xc0 | (CC[n[0]] << 3)]
  }

  if (mn === 'rst' && count === 1) {
    const t = val(0)
    if (ctx.final && (t & ~0x38)) fail(`rst target must be $00, $08 ... $38`)
    return [0xc7 | (t & 0x38)]
  }

  if ((mn === 'push' || mn === 'pop') && count === 1 && n[0] in RP2) return [(mn === 'push' ? 0xc5 : 0xc1) | (RP2[n[0]] << 4)]

  if (mn in ROT && count === 1 && n[0] in R8) return [0xcb, (ROT[mn] << 3) | R8[n[0]]]

  if (mn in BITOP && count === 2 && n[1] in R8) {
    const bit = inRange(ctx, val(0), 0, 7, 'bit')
    return [0xcb, (BITOP[mn] << 6) | ((bit & 7) << 3) | R8[n[1]]]
  }

  return fail(`can't encode "${mn}${count ? ' ' + raw.join(', ') : ''}"`)
}

export interface Assembled {
  rom: Uint8Array
  symbols: Map<string, number>
}

export interface AssembleOptions {
  files?: Record<string, string>
  name?: string
  size?: number
}

interface SourceLine {
  text: string
  file: string
  line: number
}

const INCLUDE = /^\s*include\s+"([^"]+)"\s*$/i

const includesOf = (source: string) =>
  source.split(/\r?\n/).map(line => INCLUDE.exec(stripComment(line))?.[1]).filter((path): path is string => !!path)

export const resolveFiles = async (entry: string, read: (path: string) => string | Promise<string>, known: Record<string, string> = {}) => {
  const files: Record<string, string> = { ...known }
  const seen = new Set<string>()
  const queue = [entry]
  while (queue.length) {
    const path = queue.pop() as string
    if (seen.has(path)) continue
    seen.add(path)
    files[path] ??= await read(path)
    queue.push(...includesOf(files[path]))
  }
  return files
}

const expand = (source: string, file: string, files: Record<string, string>, stack: string[]): SourceLine[] =>
  source.split(/\r?\n/).flatMap((text, i) => {
    const include = INCLUDE.exec(stripComment(text))
    if (!include) return [{ text, file, line: i + 1 }]
    const path = include[1]
    if (stack.includes(path)) return fail(`${file} line ${i + 1}: include loop through "${path}"`)
    const body = files[path]
    if (body === undefined) return fail(`${file} line ${i + 1}: can't find "${path}"`)
    return expand(body, path, files, [...stack, path])
  })

export const assemble = (source: string, { files = {}, name = 'main', size = 0x8000 }: AssembleOptions = {}): Assembled => {
  const lines = expand(source, name, files, [name])
  const symbols = new Map<string, number>()
  const rom = new Uint8Array(size)

  for (const final of [false, true]) {
    let pc = 0
    let scope = ''
    const qualify = (name: string) => name.startsWith('.') ? scope + name : name
    const ctx: Ctx = {
      final,
      pc: 0,
      value: expr => evaluate(expr, name => symbols.get(qualify(name)), final)
    }
    const emit = (bytes: number[]) => {
      if (pc + bytes.length > size) fail(`code runs past the end of the ROM at $${pc.toString(16)}`)
      if (final) rom.set(bytes, pc)
      pc += bytes.length
    }

    lines.forEach(({ text, file, line: number }) => {
      try {
        let line = stripComment(text)
        const label = /^\s*([.A-Za-z_][\w.]*)::?/.exec(line)
        if (label) {
          if (!label[1].startsWith('.')) scope = label[1]
          const name = qualify(label[1])
          if (!final && symbols.has(name)) fail(`"${name}" is defined twice`)
          symbols.set(name, pc)
          line = line.slice(label[0].length)
        }
        line = line.trim()
        if (!line) return

        const equ = /^([A-Za-z_]\w*)\s+equ\s+(.+)$/i.exec(line)
        if (equ) {
          if (!final && symbols.has(equ[1])) fail(`"${equ[1]}" is defined twice`)
          symbols.set(equ[1], ctx.value(equ[2]))
          return
        }

        const space = line.search(/\s/)
        const mn = (space < 0 ? line : line.slice(0, space)).toLowerCase()
        const args = space < 0 ? [] : splitArgs(line.slice(space + 1))
        ctx.pc = pc

        if (mn === 'org') {
          pc = evaluate(args[0] ?? fail('org needs an address'), name => symbols.get(qualify(name)), true)
          return
        }
        if (mn === 'db') {
          for (const arg of args) {
            if (/^".*"$/s.test(arg)) emit([...arg.slice(1, -1)].map(ch => ch.charCodeAt(0) & 0xff))
            else emit([inRange(ctx, ctx.value(arg), -128, 255, 'byte') & 0xff])
          }
          return
        }
        if (mn === 'dw') {
          for (const arg of args) {
            const v = inRange(ctx, ctx.value(arg), -32768, 0xffff, 'word') & 0xffff
            emit([v & 0xff, v >> 8])
          }
          return
        }
        if (mn === 'ds') {
          const length = evaluate(args[0] ?? fail('ds needs a length'), name => symbols.get(qualify(name)), true)
          const fill = args[1] ? ctx.value(args[1]) & 0xff : 0
          emit(new Array(length).fill(fill))
          return
        }
        emit(encode(mn, args, ctx))
      } catch (error) {
        if (error instanceof AsmError && !/ line \d+: /.test(` ${error.message}`)) throw new AsmError(`${file} line ${number}: ${error.message}`)
        throw error
      }
    })
  }

  let checksum = 0
  for (let i = 0x134; i <= 0x14c; i++) checksum = (checksum - rom[i] - 1) & 0xff
  rom[0x14d] = checksum
  return { rom, symbols }
}
