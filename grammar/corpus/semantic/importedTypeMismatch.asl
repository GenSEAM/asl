"expect-only: type"

"A locally declared Shape where the imported one is required. Identity is"

"nominal and keyed by defining module, so the two must not unify — this is the"

"only fixture covering that direction."

(module text/clash :x [Shape relay] :i [(core/shapes :a s)])

(enum Shape (:c blob [] "The only case of the local union"))

fn relay x: Shape -> Float64
  (s/area x)
