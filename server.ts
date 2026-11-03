import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import { extname, join, normalize, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { networkInterfaces } from 'node:os'
import { createHash, randomInt } from 'node:crypto'
import type { Duplex } from 'node:stream'

const root = fileURLToPath(new URL('.', import.meta.url))
const port = Number(process.env.PORT ?? 5190)
const served = new Set(['web', 'src', 'games'])
const types: Record<string, string> = {
  '.html': 'text/html', '.css': 'text/css', '.ts': 'text/javascript', '.js': 'text/javascript',
  '.asm': 'text/plain', '.json': 'application/json', '.svg': 'image/svg+xml'
}

type Peer = { socket: Duplex, room?: Room }
type Room = { code: string, host: Peer, guest?: Peer }

const rooms = new Map<string, Room>()
const LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
const MAX_MESSAGE = 1024

const wsFrame = (op: number, body: Buffer) => {
  const head = body.length < 126 ? Buffer.from([0x80 | op, body.length]) : Buffer.from([0x80 | op, 126, body.length >> 8, body.length & 255])
  return Buffer.concat([head, body])
}
const send = (peer: Peer | undefined, message: object | string) => {
  if (peer && !peer.socket.destroyed) peer.socket.write(wsFrame(1, Buffer.from(typeof message === 'string' ? message : JSON.stringify(message))))
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

const handle = (peer: Peer, text: string) => {
  let message: { t?: string, code?: string }
  try { message = JSON.parse(text) } catch { return }
  if (message.t === 'host') {
    leave(peer)
    let code = ''
    do code = Array.from({ length: 4 }, () => LETTERS[randomInt(LETTERS.length)]).join('')
    while (rooms.has(code))
    peer.room = { code, host: peer }
    rooms.set(code, peer.room)
    send(peer, { t: 'room', code })
  } else if (message.t === 'join') {
    const room = rooms.get(String(message.code ?? '').toUpperCase())
    if (!room || room.guest || room.host === peer) return send(peer, { t: 'nope' })
    leave(peer)
    room.guest = peer
    peer.room = room
    send(room.host, { t: 'start', player: 1 })
    send(peer, { t: 'start', player: 2 })
  } else if (message.t === 'in' || message.t === 'sum') {
    send(partner(peer), text)
  }
}

const server = createServer(async (req, res) => {
  const path = decodeURIComponent(new URL(req.url ?? '/', 'http://localhost').pathname)
  const relative = path === '/' ? 'web/index.html' : path.slice(1)
  const top = relative.split('/')[0]
  const base = join(root, top)
  const file = normalize(join(root, relative))
  if (!served.has(top) || !file.startsWith(base + sep)) {
    res.writeHead(404).end('not found')
    return
  }
  try {
    const raw = await readFile(file)
    const ext = extname(file)
    const body = ext === '.ts' ? stripTypeScriptTypes(raw.toString('utf8')) : raw
    res.writeHead(200, { 'content-type': `${types[ext] ?? 'application/octet-stream'}; charset=utf-8`, 'cache-control': 'no-store' })
    res.end(body)
  } catch {
    res.writeHead(404).end('not found')
  }
})

server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key']
  if (req.url !== '/link' || req.headers.upgrade?.toLowerCase() !== 'websocket' || !key) return socket.destroy()
  const accept = createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')
  socket.write(['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade', `Sec-WebSocket-Accept: ${accept}`, '', ''].join('\r\n'))
  const peer: Peer = { socket }
  let buffer = Buffer.alloc(0)
  socket.on('data', (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk])
    while (buffer.length >= 2) {
      const op = buffer[0] & 0x0f
      const masked = (buffer[1] & 0x80) !== 0
      let length = buffer[1] & 0x7f
      let offset = 2
      if (length === 126) {
        if (buffer.length < 4) return
        length = buffer.readUInt16BE(2)
        offset = 4
      } else if (length === 127) {
        return socket.destroy()
      }
      if (length > MAX_MESSAGE) return socket.destroy()
      const start = offset + (masked ? 4 : 0)
      if (buffer.length < start + length) return
      const data = Buffer.from(buffer.subarray(start, start + length))
      if (masked) for (let i = 0; i < data.length; i++) data[i] ^= buffer[offset + (i & 3)]
      buffer = buffer.subarray(start + length)
      if (op === 8) return socket.end()
      if (op === 9) socket.write(wsFrame(10, data))
      else if (op === 1) handle(peer, data.toString('utf8'))
    }
  })
  socket.on('close', () => leave(peer))
  socket.on('error', () => leave(peer))
})

server.listen(port, () => {
  console.log(`Game Boy running at http://localhost:${port}`)
  const lan = Object.values(networkInterfaces()).flat().filter(net => net?.family === 'IPv4' && !net.internal)
  for (const net of lan) console.log(`On your phone (same Wi-Fi): http://${net!.address}:${port}`)
})
