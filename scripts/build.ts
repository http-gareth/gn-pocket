import { cp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'
import { join } from 'node:path'
import { contentSecurityPolicy } from '../server/files.ts'

const OUT = 'dist'
const CHARSET = '<meta charset="utf-8">'
const POLICY = `<meta http-equiv="Content-Security-Policy" content="${contentSecurityPolicy()}">`

const toJs = (text: string) => text.replace(/(['"])([^'"\s]+)\.ts\1/g, '$1$2.js$1')
const withPolicy = (html: string) => {
  if (!html.includes(CHARSET)) throw new Error('every page needs a charset meta for the policy to follow')
  return html.replace(CHARSET, `${CHARSET}\n  ${POLICY}`)
}

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
    await writeFile(path, withPolicy(toJs(text)))
  }
}
console.log(`Built ${OUT}/`)
