"expect-only: rule-4"

"The arms mix a local case and an imported one. Keyed on the bare enum name the"

"two collapse to \"Shape\", the arms-mix test cannot fire, and the file checks"

"clean while matching one union's value against another's constructor."

(module text/mixed :x [Shape label] :i [(core/shapes :a s)])

(enum Shape (:c circle [(radius Float64)] "A local circle"))

fn label sh: Shape -> String
  (match sh ((circle r) "local") ((s/rectangle w h) "imported"))
