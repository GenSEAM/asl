"expect: rule-4"

"A match over a closed union that omits a case. Every arm is well-formed, so"

"the omission is only visible against the enum that declares the union."

(enum Shape (:c circle [(radius Float64)] "A circle") (:c square [(side Float64)] "A square"))

fn area s: Shape -> Float64
  (match s ((circle r) (* 3.14159 (* r r))))
