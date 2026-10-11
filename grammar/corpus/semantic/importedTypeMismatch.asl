(module text/clash :x [Shape relay] :i [(core/shapes :a s)])

(enum Shape (:c blob [] "The only case of the local union"))

fn relay x: Shape -> Float64
  (s/area x)
