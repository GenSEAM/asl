(module core/shapes :x [Shape area])

"Search-path companion: the module whose type the importing fixtures name."

"Its export list carries a type beside a function, which is what the whole"

"boundary rests on."

(enum Shape (:c circle [(radius Float64)] "A circle") (:c rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle"))

fn area sh: Shape -> Float64
  (match sh ((circle r) (* 3.14159 (* r r))) ((rectangle w h) (* w h)))
