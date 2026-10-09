"expect: rule-5"

"try propagates an error out of the enclosing fn, and this one does not"

"return a Result, so there is nothing for it to propagate into."

"Superseded: the host has no try, so it rejects this file with"

"ERR_UNKNOWN_SYMBOL try, not for rule 5."

fn parseIt s: String -> (Result Int64 String)
  (ok 1)

fn useIt -> Int64
  (try (parseIt "1"))
