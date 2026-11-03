import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'

const port = 5300 + Math.floor(Math.random() * 500)

const startServer = () => new Promise<ReturnType<typeof spawn>>((resolve, reject) => {
  const child = spawn(process.execPath, ['--experimental-strip-types', '--disable-warning=ExperimentalWarning', 'server.ts'], {
    cwd: new URL('..', import.meta.url), env: { ...process.env, PORT: String(port) }
  })
  child.stdout.on('data', chunk => { if (String(chunk).includes('running')) resolve(child) })
  child.on('error', reject)
})

const connect = () => new Promise<{ ws: WebSocket, next: () => Promise<any> }>(resolve => {
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

test('the link cable pairs two consoles by code and relays their buttons', async () => {
  const server = await startServer()
  try {
    const host = await connect()
    host.ws.send(JSON.stringify({ t: 'host' }))
    const room = await host.next()
    assert.equal(room.t, 'room')
    assert.match(room.code, /^[A-Z]{4}$/)

    const stranger = await connect()
    stranger.ws.send(JSON.stringify({ t: 'join', code: 'ZZZZ' === room.code ? 'YYYY' : 'ZZZZ' }))
    assert.equal((await stranger.next()).t, 'nope', 'a wrong code is refused')

    const guest = await connect()
    guest.ws.send(JSON.stringify({ t: 'join', code: room.code.toLowerCase() }))
    assert.deepEqual(await host.next(), { t: 'start', player: 1 })
    assert.deepEqual(await guest.next(), { t: 'start', player: 2 })

    guest.ws.send(JSON.stringify({ t: 'in', f: 4, b: 16 }))
    assert.deepEqual(await host.next(), { t: 'in', f: 4, b: 16 })
    host.ws.send(JSON.stringify({ t: 'in', f: 4, b: 1 }))
    assert.deepEqual(await guest.next(), { t: 'in', f: 4, b: 1 })

    guest.ws.close()
    assert.deepEqual(await host.next(), { t: 'bye' }, 'the host hears the cable come out')
    for (const peer of [host, stranger]) peer.ws.close()
  } finally {
    server.kill()
  }
})
