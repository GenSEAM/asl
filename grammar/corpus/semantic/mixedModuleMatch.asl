(module text/mixed :x [Shape label] :i [(core/shapes :a s)])

(enum Shape (:c circle [(radius Float64)] "A local circle"))

fn label sh: Shape -> String
  (match sh ((circle r) "local") ((s/rectangle w h) "imported"))
