import type { IncomingMessage, OutgoingHttpHeaders, ServerResponse } from 'node:http'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import { extname, join, normalize, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const SERVED = new Set(['web', 'src', 'games'])
const TYPES: Record<string, string> = {
  '.html': 'text/html', '.css': 'text/css', '.ts': 'text/javascript', '.js': 'text/javascript',
  '.asm': 'text/plain', '.json': 'application/json', '.svg': 'image/svg+xml'
}
const HOST = /^[a-z0-9.-]+(:\d{1,5})?$/i

const POLICY: Record<string, string> = {
  'default-src': "'self'",
  'script-src': "'self'",
  'style-src': "'self' https://fonts.googleapis.com",
  'font-src': 'https://fonts.gstatic.com',
  'img-src': "'self'",
  'connect-src': "'self'",
  'object-src': "'none'",
  'base-uri': "'none'",
  'form-action': "'none'"
}

const policy = (host: string) => Object.entries({
  ...POLICY,
  'connect-src': HOST.test(host) ? `'self' ws://${host} wss://${host}` : "'self'",
  'frame-ancestors': "'none'"
}).map(([name, value]) => `${name} ${value}`).join('; ')

const securityHeaders = (req: IncomingMessage): OutgoingHttpHeaders => ({
  'content-security-policy': policy(req.headers.host ?? ''),
  ...(process.env.TRUST_PROXY && req.headers['x-forwarded-proto'] === 'https' && { 'strict-transport-security': 'max-age=31536000' }),
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
  'cross-origin-opener-policy': 'same-origin',
  'cross-origin-resource-policy': 'same-origin',
  'permissions-policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  'cache-control': 'no-store'
})

const fail = (res: ServerResponse, headers: OutgoingHttpHeaders, status: number, text: string) => {
  res.writeHead(status, { ...headers, 'content-type': 'text/plain; charset=utf-8' }).end(text)
}

const resolve = (url = '/') => {
  const path = decodeURIComponent(new URL(url, 'http://localhost').pathname)
  if (path.includes('\0')) return null
  const relative = path === '/' ? 'web/index.html' : path.slice(1)
  const top = relative.split(/[\\/]/)[0]
  const file = normalize(join(ROOT, relative))
  return SERVED.has(top) && file.startsWith(join(ROOT, top) + sep) ? file : null
}

export const serveFile = async (req: IncomingMessage, res: ServerResponse) => {
  const headers = securityHeaders(req)
  if (req.method !== 'GET' && req.method !== 'HEAD') return fail(res, { ...headers, allow: 'GET, HEAD' }, 405, 'method not allowed')
  let file: string | null
  try {
    file = resolve(req.url)
  } catch {
    return fail(res, headers, 400, 'bad request')
  }
  if (!file) return fail(res, headers, 404, 'not found')
  let raw: Buffer
  try {
    raw = await readFile(file)
  } catch {
    return fail(res, headers, 404, 'not found')
  }
  const ext = extname(file)
  const body = ext === '.ts' ? stripTypeScriptTypes(raw.toString('utf8')) : raw
  res.writeHead(200, { ...headers, 'content-type': `${TYPES[ext] ?? 'application/octet-stream'}; charset=utf-8` })
  res.end(req.method === 'HEAD' ? undefined : body)
}
