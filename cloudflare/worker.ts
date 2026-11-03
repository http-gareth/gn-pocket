import { DurableObject } from 'cloudflare:workers'
import { MAX_MESSAGE_BYTES, linkRole, newCode, parseClientMessage } from '../src/netplay/protocol.ts'
import type { ServerMessage } from '../src/netplay/protocol.ts'
import { Room, seat, withinRate } from '../src/netplay/room.ts'

type Stub = { fetch: (request: Request) => Promise<Response> }
type Env = {
  ASSETS: { fetch: (request: Request) => Promise<Response> }
  ROOMS: { idFromName: (name: string) => unknown, get: (id: unknown) => Stub }
}

const WAIT_MS = 10 * 60_000
const LINK_MS = 60 * 60_000
const HOST_ATTEMPTS = 5

const sameOrigin = (request: Request, url: URL) => {
  const origin = request.headers.get('origin')
  if (!origin) return true
  try {
    return new URL(origin).host === url.host
  } catch {
    return false
  }
}

export class LinkRoom extends DurableObject {
  #room: Room | null = null

  async fetch(request: Request) {
    const url = new URL(request.url)
    const hosting = url.searchParams.has('host')
    if (hosting && this.#room) return new Response(null, { status: 409 })
    const [client, socket] = Object.values(new WebSocketPair())
    socket.accept()
    const end = (code: number, reason: string) => {
      try {
        socket.close(code, reason)
      } catch {}
    }
    const me = seat((message: ServerMessage) => socket.send(JSON.stringify(message)))
    const room = hosting ? new Room(me) : this.#room?.open ? this.#room : null
    if (!room) {
      me.send({ t: 'nope' })
      end(1000, 'no game with that code')
      return new Response(null, { status: 101, webSocket: client })
    }
    if (hosting) {
      this.#room = room
      me.send({ t: 'room', code: url.searchParams.get('code') ?? '' })
      setTimeout(() => { if (room.open) end(1001, 'nobody joined') }, WAIT_MS)
    } else {
      room.join(me)
    }
    setTimeout(() => end(1001, 'time up'), LINK_MS)
    socket.addEventListener('message', (event: MessageEvent) => {
      if (typeof event.data !== 'string' || event.data.length > MAX_MESSAGE_BYTES) return end(1009, 'too big')
      if (!withinRate(me)) return end(1008, 'too fast')
      const message = parseClientMessage(event.data)
      if (message) room.receive(me, message)
    })
    const leave = () => {
      room.leave(me)
      if (this.#room === room) this.#room = null
      end(1000, 'bye')
    }
    socket.addEventListener('close', leave)
    socket.addEventListener('error', leave)
    return new Response(null, { status: 101, webSocket: client })
  }
}

export default {
  async fetch(request: Request, env: Env) {
    const url = new URL(request.url)
    if (url.pathname !== '/link') return env.ASSETS.fetch(request)
    const role = linkRole(url.search)
    if (!role) return new Response('bad link request', { status: 400 })
    if (!sameOrigin(request, url)) return new Response('forbidden', { status: 403 })
    if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') return new Response('expected a websocket', { status: 426 })
    const room = (code: string) => env.ROOMS.get(env.ROOMS.idFromName(code))
    if (!role.host) return room(role.code).fetch(request)
    for (let attempt = 0; attempt < HOST_ATTEMPTS; attempt++) {
      const code = newCode()
      const response = await room(code).fetch(new Request(`https://room/link?host&code=${code}`, request))
      if (response.status !== 409) return response
    }
    return new Response('busy, try again', { status: 503 })
  }
}
