import type { IncomingMessage } from 'node:http'
import type { Duplex } from 'node:stream'
import { createHash } from 'node:crypto'
import { MAX_MESSAGE_BYTES, linkRole, newCode, parseClientMessage } from '../src/netplay/protocol.ts'
import type { ServerMessage } from '../src/netplay/protocol.ts'
import { Room, seat, withinRate } from '../src/netplay/room.ts'

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const MAX_PEERS = 200
const JOINS_PER_MINUTE = 10
const IDLE_MS = 10 * 60_000

const rooms = new Map<string, Room>()
const joins = new Map<string, { count: number, since: number }>()
let peers = 0

const frame = (op: number, body: Buffer) => {
  const head = body.length < 126 ? Buffer.from([0x80 | op, body.length]) : Buffer.from([0x80 | op, 126, body.length >> 8, body.length & 255])
  return Buffer.concat([head, body])
}

const mayJoin = (address: string) => {
  const now = Date.now()
  if (joins.size > MAX_PEERS) for (const [key, value] of joins) if (now - value.since > 60_000) joins.delete(key)
  const entry = joins.get(address)
  if (!entry || now - entry.since > 60_000) {
    joins.set(address, { count: 1, since: now })
    return true
  }
  return ++entry.count <= JOINS_PER_MINUTE
}

const sameOrigin = (req: IncomingMessage) => {
  const origin = req.headers.origin
  if (!origin) return true
  try {
    return new URL(origin).host === req.headers.host
  } catch {
    return false
  }
}

const clientAddress = (req: IncomingMessage) => {
  const forwarded = process.env.TRUST_PROXY ? String(req.headers['x-forwarded-for'] ?? '').split(',').at(-1)!.trim() : ''
  return forwarded || req.socket.remoteAddress || ''
}

const refuse = (socket: Duplex, status: string) => {
  socket.end(`HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`)
}

export const upgrade = (req: IncomingMessage, socket: Duplex, head: Buffer) => {
  const key = req.headers['sec-websocket-key']
  const url = new URL(req.url ?? '/', 'http://localhost')
  const role = url.pathname === '/link' ? linkRole(url.search) : null
  if (!role || req.headers.upgrade?.toLowerCase() !== 'websocket' || typeof key !== 'string') return refuse(socket, '400 Bad Request')
  if (!sameOrigin(req)) return refuse(socket, '403 Forbidden')
  if (peers >= MAX_PEERS) return refuse(socket, '503 Service Unavailable')
  const accept = createHash('sha1').update(key + GUID).digest('base64')
  socket.write(['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade', `Sec-WebSocket-Accept: ${accept}`, '', ''].join('\r\n'))
  peers++

  const close = (code: number) => {
    if (!socket.destroyed) socket.end(frame(8, Buffer.from([code >> 8, code & 255])))
  }
  const me = seat((message: ServerMessage) => {
    if (!socket.destroyed) socket.write(frame(1, Buffer.from(JSON.stringify(message))))
  })
  let code = ''
  let room: Room | undefined
  if (role.host) {
    do code = newCode()
    while (rooms.has(code))
    room = new Room(me)
    rooms.set(code, room)
    me.send({ t: 'room', code })
  } else {
    const found = mayJoin(clientAddress(req)) ? rooms.get(role.code) : undefined
    if (found?.open) {
      code = role.code
      room = found
      room.join(me)
    } else {
      me.send({ t: 'nope' })
      close(1000)
    }
  }

  let buffer = Buffer.alloc(0)
  socket.setTimeout(IDLE_MS, () => close(1001))
  const receive = (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk])
    while (buffer.length >= 2) {
      const finished = (buffer[0] & 0x80) !== 0
      const op = buffer[0] & 0x0f
      const masked = (buffer[1] & 0x80) !== 0
      let length = buffer[1] & 0x7f
      let offset = 2
      if (!finished || !masked || op === 0 || op === 2 || length === 127) return close(1002)
      if (length === 126) {
        if (buffer.length < 4) return
        length = buffer.readUInt16BE(2)
        offset = 4
      }
      if (length > MAX_MESSAGE_BYTES) return close(1009)
      const body = offset + 4
      if (buffer.length < body + length) return
      const data = Buffer.from(buffer.subarray(body, body + length))
      for (let i = 0; i < data.length; i++) data[i] ^= buffer[offset + (i & 3)]
      buffer = buffer.subarray(body + length)
      if (!withinRate(me)) return close(1008)
      if (op === 8) return close(1000)
      if (op === 9) socket.write(frame(10, data))
      else if (op === 1) {
        const message = parseClientMessage(data.toString('utf8'))
        if (message && room) room.receive(me, message)
      }
    }
  }
  const safely = (chunk: Buffer) => {
    try {
      receive(chunk)
    } catch {
      socket.destroy()
    }
  }
  socket.on('data', safely)
  socket.on('close', () => {
    peers--
    if (!room) return
    room.leave(me)
    if (rooms.get(code) === room) rooms.delete(code)
  })
  socket.on('error', () => socket.destroy())
  if (head.length) safely(head)
}
