(enum Shape (:c circle [(radius Float64)] "A circle") (:c square [(side Float64)] "A square"))

fn area s: Shape -> Float64
  (match s ((circle r) (* 3.14159 (* r r))))
