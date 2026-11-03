import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fetchRaw, startServer } from './start-server.ts'

test('the dev server only serves the game, sends security headers and survives bad requests', async () => {
  const server = await startServer()
  try {
    const home = await fetchRaw(server.port, '/')
    assert.equal(home.status, 200)
    const policy = String(home.headers['content-security-policy'])
    assert.match(policy, /script-src 'self'/)
    assert.match(policy, /object-src 'none'/)
    assert.match(policy, /frame-ancestors 'none'/)
    assert.equal(home.headers['x-content-type-options'], 'nosniff')
    assert.equal(home.headers['referrer-policy'], 'no-referrer')

    for (const path of [
      '/package.json', '/server/index.ts', '/.git/config', '/web/..%2f..%2fpackage.json',
      '/web/%2e%2e/server/relay.ts', '/games/..%5c..%5cpackage.json', '/web/index.html%00', '/web/'
    ]) {
      assert.equal((await fetchRaw(server.port, path)).status, 404, path)
    }
    assert.equal((await fetchRaw(server.port, '/%')).status, 400, 'a broken escape is a bad request, not a crash')
    assert.equal((await fetchRaw(server.port, '/', { method: 'POST' })).status, 405)
    assert.equal((await fetchRaw(server.port, '/web/index.html')).status, 200, 'still running afterwards')
  } finally {
    server.stop()
  }
})
