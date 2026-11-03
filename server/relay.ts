import type { IncomingMessage } from 'node:http'
import type { Duplex } from 'node:stream'
import { createHash, randomInt } from 'node:crypto'
import { CODE_LENGTH, CODE_LETTERS, MAX_MESSAGE_BYTES, parseClientMessage } from '../src/netplay/protocol.ts'
import { delayFor } from '../src/netplay/lockstep.ts'
import type { ServerMessage } from '../src/netplay/protocol.ts'

type Peer = { socket: Duplex, address: string, room?: Room, sent: number, since: number, misses: number, rtt: number | null, pingAt: number }
type Room = { code: string, host: Peer, guest?: Peer, started: boolean }

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
const MAX_PEERS = 200
const MESSAGES_PER_SECOND = 300
const JOINS_PER_MINUTE = 10
const MISSES_PER_CONNECTION = 5
const IDLE_MS = 10 * 60_000
const PING_TIMEOUT_MS = 1500

const rooms = new Map<string, Room>()
const joins = new Map<string, { count: number, since: number }>()
let peers = 0

const frame = (op: number, body: Buffer) => {
  const head = body.length < 126 ? Buffer.from([0x80 | op, body.length]) : Buffer.from([0x80 | op, 126, body.length >> 8, body.length & 255])
  return Buffer.concat([head, body])
}

const send = (peer: Peer | undefined, message: ServerMessage) => {
  if (peer && !peer.socket.destroyed) peer.socket.write(frame(1, Buffer.from(JSON.stringify(message))))
}

const close = (peer: Peer, code: number) => {
  if (!peer.socket.destroyed) peer.socket.end(frame(8, Buffer.from([code >> 8, code & 255])))
}

const partner = (peer: Peer) => peer.room && (peer.room.host === peer ? peer.room.guest : peer.room.host)

const leave = (peer: Peer) => {
  const room = peer.room
  if (!room) return
  const other = partner(peer)
  rooms.delete(room.code)
  peer.room = undefined
  if (other) {
    other.room = undefined
    send(other, { t: 'bye' })
  }
}

const ping = (peer: Peer) => {
  peer.rtt = null
  peer.pingAt = Date.now()
  if (!peer.socket.destroyed) peer.socket.write(frame(9, Buffer.alloc(0)))
}

const startRoom = (room: Room, timedOut: boolean) => {
  const { host, guest } = room
  if (room.started || !guest || rooms.get(room.code) !== room) return
  if (!timedOut && (host.rtt === null || guest.rtt === null)) return
  room.started = true
  const delay = delayFor(((host.rtt ?? PING_TIMEOUT_MS) + (guest.rtt ?? PING_TIMEOUT_MS)) / 2)
  send(host, { t: 'start', player: 1, delay })
  send(guest, { t: 'start', player: 2, delay })
}

const newCode = () => {
  let code = ''
  do code = Array.from({ length: CODE_LENGTH }, () => CODE_LETTERS[randomInt(CODE_LETTERS.length)]).join('')
  while (rooms.has(code))
  return code
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

const withinRate = (peer: Peer) => {
  const now = Date.now()
  if (now - peer.since >= 1000) {
    peer.since = now
    peer.sent = 0
  }
  return ++peer.sent <= MESSAGES_PER_SECOND
}

const handle = (peer: Peer, text: string) => {
  const message = parseClientMessage(text)
  if (!message) return
  if (message.t === 'host') {
    leave(peer)
    peer.room = { code: newCode(), host: peer, started: false }
    rooms.set(peer.room.code, peer.room)
    send(peer, { t: 'room', code: peer.room.code })
  } else if (message.t === 'join') {
    const room = mayJoin(peer.address) ? rooms.get(message.code) : undefined
    if (!room || room.guest || room.host === peer) {
      send(peer, { t: 'nope' })
      if (++peer.misses >= MISSES_PER_CONNECTION) close(peer, 1008)
      return
    }
    leave(peer)
    room.guest = peer
    peer.room = room
    ping(room.host)
    ping(peer)
    setTimeout(() => startRoom(room, true), PING_TIMEOUT_MS)
  } else {
    send(partner(peer), message)
  }
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
  if (req.url !== '/link' || req.headers.upgrade?.toLowerCase() !== 'websocket' || typeof key !== 'string') return refuse(socket, '400 Bad Request')
  if (!sameOrigin(req)) return refuse(socket, '403 Forbidden')
  if (peers >= MAX_PEERS) return refuse(socket, '503 Service Unavailable')
  const accept = createHash('sha1').update(key + GUID).digest('base64')
  socket.write(['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade', `Sec-WebSocket-Accept: ${accept}`, '', ''].join('\r\n'))
  const peer: Peer = { socket, address: clientAddress(req), sent: 0, since: Date.now(), misses: 0, rtt: null, pingAt: 0 }
  peers++
  let buffer = Buffer.alloc(0)
  socket.setTimeout(IDLE_MS, () => close(peer, 1001))
  const receive = (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk])
    while (buffer.length >= 2) {
      const finished = (buffer[0] & 0x80) !== 0
      const op = buffer[0] & 0x0f
      const masked = (buffer[1] & 0x80) !== 0
      let length = buffer[1] & 0x7f
      let offset = 2
      if (!finished || !masked || op === 0 || op === 2 || length === 127) return close(peer, 1002)
      if (length === 126) {
        if (buffer.length < 4) return
        length = buffer.readUInt16BE(2)
        offset = 4
      }
      if (length > MAX_MESSAGE_BYTES) return close(peer, 1009)
      const start = offset + 4
      if (buffer.length < start + length) return
      const data = Buffer.from(buffer.subarray(start, start + length))
      for (let i = 0; i < data.length; i++) data[i] ^= buffer[offset + (i & 3)]
      buffer = buffer.subarray(start + length)
      if (!withinRate(peer)) return close(peer, 1008)
      if (op === 8) return close(peer, 1000)
      if (op === 9) socket.write(frame(10, data))
      else if (op === 10 && peer.pingAt) {
        peer.rtt = Date.now() - peer.pingAt
        peer.pingAt = 0
        if (peer.room) startRoom(peer.room, false)
      } else if (op === 1) handle(peer, data.toString('utf8'))
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
    leave(peer)
  })
  socket.on('error', () => socket.destroy())
  if (head.length) safely(head)
}
