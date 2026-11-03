import { spawn } from 'node:child_process'
import { request } from 'node:http'
import type { IncomingHttpHeaders } from 'node:http'

export const startServer = (env: Record<string, string> = {}) => new Promise<{ port: number, stop: () => void }>((resolve, reject) => {
  const port = 5300 + Math.floor(Math.random() * 2000)
  const child = spawn(process.execPath, ['--experimental-strip-types', '--disable-warning=ExperimentalWarning', 'server/index.ts'], {
    cwd: new URL('..', import.meta.url), env: { ...process.env, ...env, PORT: String(port) }
  })
  child.stdout.on('data', chunk => { if (String(chunk).includes('running')) resolve({ port, stop: () => child.kill() }) })
  child.on('error', reject)
})

export const fetchRaw = (port: number, path: string, options: { method?: string, headers?: Record<string, string> } = {}) =>
  new Promise<{ status: number, headers: IncomingHttpHeaders }>((resolve, reject) => {
    const req = request({ host: '127.0.0.1', port, path, ...options }, res => {
      res.resume()
      res.on('end', () => resolve({ status: res.statusCode ?? 0, headers: res.headers }))
    })
    req.on('error', reject)
    req.end()
  })
