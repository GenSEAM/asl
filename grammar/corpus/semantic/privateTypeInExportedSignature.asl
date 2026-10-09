"expect-only: rule-13"

"`area` is exported and its parameter type is declared here and not exported,"

"so no importer can write the type of what it receives. This scenario survives"

"a fix that checks only the lexical half untouched."

(module text/leak :x [area])

(enum Shape (:c circle [(radius Float64)] "A circle") (:c rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle"))

fn area sh: Shape -> Float64
  (match sh ((circle r) (* 3.14159 (* r r))) ((rectangle w h) (* w h)))
