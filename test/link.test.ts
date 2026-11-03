import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fetchRaw, startServer } from './start-server.ts'

const relay = async () => {
  if (process.env.LINK_URL) return { base: process.env.LINK_URL, port: Number(new URL(process.env.LINK_URL).port), stop: () => {} }
  const server = await startServer()
  return { base: `ws://localhost:${server.port}`, port: server.port, stop: server.stop }
}

const connect = (base: string, role: string, pongAfter = 0) => new Promise<{ ws: WebSocket, next: () => Promise<any> }>(resolve => {
  const ws = new WebSocket(`${base}/link?${role}`)
  const inbox: any[] = []
  const waiting: ((value: any) => void)[] = []
  ws.addEventListener('message', e => {
    const message = JSON.parse(String(e.data))
    if (message.t === 'ping') return void setTimeout(() => ws.send(JSON.stringify({ t: 'pong' })), pongAfter)
    const waiter = waiting.shift()
    if (waiter) waiter(message)
    else inbox.push(message)
  })
  ws.addEventListener('open', () => resolve({
    ws,
    next: () => inbox.length ? Promise.resolve(inbox.shift()) : new Promise(r => waiting.push(r))
  }))
})

test('the link cable pairs two consoles by code and relays only well-formed button presses', async () => {
  const server = await relay()
  try {
    const host = await connect(server.base, 'host')
    const room = await host.next()
    assert.equal(room.t, 'room')
    assert.match(room.code, /^[A-Z]{4}$/)

    const stranger = await connect(server.base, `join=${room.code === 'ZZZZ' ? 'YYYY' : 'ZZZZ'}`)
    assert.equal((await stranger.next()).t, 'nope', 'a wrong code is refused')

    const guest = await connect(server.base, `join=${room.code.toLowerCase()}`)
    const start = await host.next()
    assert.equal(start.player, 1)
    assert.ok(start.delay >= 4, `a nearby link uses the minimum delay or a little more (${start.delay})`)
    assert.deepEqual(await guest.next(), { t: 'start', player: 2, delay: start.delay })

    guest.ws.send('not json')
    guest.ws.send(JSON.stringify({ t: 'in', f: 'x', b: 1 }))
    guest.ws.send(JSON.stringify({ t: 'start', player: 1 }))
    guest.ws.send(JSON.stringify({ t: 'in', f: 4, b: 16, extra: '<script>' }))
    assert.deepEqual(await host.next(), { t: 'in', f: 4, b: 16 }, 'junk is dropped and extra fields are stripped')
    host.ws.send(JSON.stringify({ t: 'in', f: 4, b: 1 }))
    assert.deepEqual(await guest.next(), { t: 'in', f: 4, b: 1 })

    guest.ws.close()
    assert.deepEqual(await host.next(), { t: 'bye' }, 'the host hears the cable come out')
    for (const peer of [host, stranger]) peer.ws.close()
  } finally {
    server.stop()
  }
})

test('the link cable refuses other websites and malformed requests', async () => {
  const server = await relay()
  try {
    const handshake = { connection: 'Upgrade', upgrade: 'websocket', 'sec-websocket-version': '13', 'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==' }
    assert.equal((await fetchRaw(server.port, '/link?host', { headers: { ...handshake, origin: 'https://evil.example' } })).status, 403)
    assert.equal((await fetchRaw(server.port, '/link', { headers: handshake })).status, 400, 'no role')
    assert.equal((await fetchRaw(server.port, '/link?join=AB1', { headers: handshake })).status, 400, 'a malformed code')
  } finally {
    server.stop()
  }
})

test('the relay times each player and gives far-away players a longer link delay', async () => {
  const server = await relay()
  try {
    const host = await connect(server.base, 'host', 200)
    const { code } = await host.next()
    const guest = await connect(server.base, `join=${code}`)
    const start = await host.next()
    assert.equal(start.t, 'start')
    assert.ok(start.delay >= 8, `a 200 ms player gets a longer delay (${start.delay} frames)`)
    assert.deepEqual(await guest.next(), { t: 'start', player: 2, delay: start.delay }, 'both consoles use the same delay')
    for (const peer of [host, guest]) peer.ws.close()
  } finally {
    server.stop()
  }
})
