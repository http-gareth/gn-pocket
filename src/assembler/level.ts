export const LEVEL_WIDTH = 128
export const LEVEL_HEIGHT = 17

const ROW = /^[ !#-[\]-~]*$/
const LEVEL_1 = new RegExp(`Level1:\\r?\\n(    db ".*"\\r?\\n){${LEVEL_HEIGHT}}`)

export const parseLevel = (text: string | null): string[] | null => {
  if (!text) return null
  try {
    const rows: unknown = JSON.parse(text)
    const valid = Array.isArray(rows) && rows.length === LEVEL_HEIGHT &&
      rows.every(row => typeof row === 'string' && row.length === LEVEL_WIDTH && ROW.test(row))
    return valid ? rows as string[] : null
  } catch {
    return null
  }
}

export const withLevel = (pipSource: string, rows: string[]) => {
  if (!LEVEL_1.test(pipSource)) throw new Error('Pip Quest has no Level1 block to replace')
  return pipSource.replace(LEVEL_1, () => `Level1:\n${rows.map(row => `    db "${row}"\n`).join('')}`)
}
