"expect-only: type-arity"

"§3 writes Result applied — `(Result T E)`. Bare, it names no type, and the"

"error half a match would take apart does not exist to be read."

fn parseIt s: String -> (Result Int64 String)
  (ok 1)

fn useIt s: String -> Result
  (parseIt s)
