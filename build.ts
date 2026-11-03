import { cp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import { join } from 'node:path'

const out = 'dist'
const toJs = (text: string) => text.replace(/(['"])([^'"\s]+)\.ts\1/g, '$1$2.js$1')

await rm(out, { recursive: true, force: true })
for (const dir of ['web', 'src', 'games']) await cp(dir, join(out, dir), { recursive: true })
await cp('web/index.html', join(out, 'index.html'))

for (const file of await readdir(out, { recursive: true })) {
  if (!/\.(ts|html)$/.test(file)) continue
  const path = join(out, file)
  const text = await readFile(path, 'utf8')
  if (file.endsWith('.ts')) {
    await writeFile(path.replace(/\.ts$/, '.js'), toJs(stripTypeScriptTypes(text)))
    await rm(path)
  } else {
    await writeFile(path, toJs(text))
  }
}
console.log(`Built ${out}/`)
