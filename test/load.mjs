// Loads the QML-side JavaScript libraries (.pragma library files) into Node so
// they can be unit tested, exactly as QML sees them under `import "lib/X.js" as X`.
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"
import vm from "node:vm"

const here = dirname(fileURLToPath(import.meta.url))

export function loadLib(name) {
  const file = join(here, "..", "lib", name + ".js")
  const src = readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
  const ctx = vm.createContext({})
  vm.runInContext(src, ctx, { filename: file })
  return ctx
}

export const Gen = loadLib("Gen")
