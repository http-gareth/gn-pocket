import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fetchRaw, startServer } from './start-server.ts'

const connect = (port: number) => new Promise<{ ws: WebSocket, next: () => Promise<any> }>(resolve => {
  const ws = new WebSocket(`ws://localhost:${port}/link`)
  const inbox: any[] = []
  const waiting: ((value: any) => void)[] = []
  ws.addEventListener('message', e => {
    const message = JSON.parse(String(e.data))
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
  const server = await startServer()
  try {
    const host = await connect(server.port)
    host.ws.send(JSON.stringify({ t: 'host' }))
    const room = await host.next()
    assert.equal(room.t, 'room')
    assert.match(room.code, /^[A-Z]{4}$/)

    const stranger = await connect(server.port)
    stranger.ws.send(JSON.stringify({ t: 'join', code: 'ZZZZ' === room.code ? 'YYYY' : 'ZZZZ' }))
    assert.equal((await stranger.next()).t, 'nope', 'a wrong code is refused')

    const guest = await connect(server.port)
    guest.ws.send(JSON.stringify({ t: 'join', code: room.code.toLowerCase() }))
    assert.deepEqual(await host.next(), { t: 'start', player: 1, delay: 4 })
    assert.deepEqual(await guest.next(), { t: 'start', player: 2, delay: 4 })

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

test('the link cable refuses connections from other websites', async () => {
  const server = await startServer()
  try {
    const handshake = { connection: 'Upgrade', upgrade: 'websocket', 'sec-websocket-version': '13', 'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==' }
    const attempt = await fetchRaw(server.port, '/link', { headers: { ...handshake, origin: 'https://evil.example' } })
    assert.equal(attempt.status, 403)
    const wrongPath = await fetchRaw(server.port, '/other', { headers: handshake })
    assert.equal(wrongPath.status, 400)
  } finally {
    server.stop()
  }
})
