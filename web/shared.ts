export const readGame = async (path: string) => {
  const res = await fetch(new URL(`../games/${path}`, import.meta.url), { cache: 'no-store' })
  if (!res.ok) throw new Error(`can't load ${path}`)
  return res.text()
}

export const stored = (key: string) => {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

export const store = (key: string, value: string) => {
  try {
    localStorage.setItem(key, value)
    return true
  } catch {
    return false
  }
}
