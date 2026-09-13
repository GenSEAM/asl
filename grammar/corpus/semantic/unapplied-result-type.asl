"expect-only: type-arity"
"§3 writes Result applied — `(Result T E)`. Bare, it names no type, and the"
"error half the `try` form propagates into does not exist to be read."
(df parseIt [(s String)] -> (Result Int64 String)
  :doc "A fallible helper to try."
  (ok 1))

(df useIt [(s String)] -> Result
  (ok (try (parseIt s))))
