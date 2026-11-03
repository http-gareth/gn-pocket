import { createServer } from 'node:http'
import { networkInterfaces } from 'node:os'
import { serveFile } from './files.ts'
import { upgrade } from './relay.ts'

const port = Number(process.env.PORT ?? 5190)

const server = createServer((req, res) => {
  serveFile(req, res).catch(() => {
    if (!res.headersSent) res.writeHead(500)
    res.end()
  })
})
server.on('upgrade', upgrade)
server.on('clientError', (_, socket) => socket.destroy())

server.listen(port, () => {
  console.log(`Game Boy running at http://localhost:${port}`)
  const lan = Object.values(networkInterfaces()).flat().filter(net => net?.family === 'IPv4' && !net.internal)
  for (const net of lan) console.log(`On your phone (same Wi-Fi): http://${net!.address}:${port}`)
})
