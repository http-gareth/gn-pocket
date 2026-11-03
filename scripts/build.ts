import { cp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import { join } from 'node:path'
import { securityHeaders } from '../server/files.ts'

const OUT = 'dist'

const toJs = (text: string) => text.replace(/(['"])([^'"\s]+)\.ts\1/g, '$1$2.js$1')

await rm(OUT, { recursive: true, force: true })
for (const dir of ['web', 'src', 'games']) await cp(dir, join(OUT, dir), { recursive: true })
await cp('web/index.html', join(OUT, 'index.html'))

for (const file of await readdir(OUT, { recursive: true })) {
  if (!/\.(ts|html)$/.test(file)) continue
  const path = join(OUT, file)
  const text = await readFile(path, 'utf8')
  if (file.endsWith('.ts')) {
    await writeFile(path.replace(/\.ts$/, '.js'), toJs(stripTypeScriptTypes(text)))
    await rm(path)
  } else {
    await writeFile(path, toJs(text))
  }
}

const headers = Object.entries(securityHeaders('', true)).map(([name, value]) => `  ${name}: ${value}`)
await writeFile(join(OUT, '_headers'), ['/*', ...headers, ''].join('\n'))
console.log(`Built ${OUT}/`)
