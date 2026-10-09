"expect-only: rule-9"

"`Hidden` is declared by core/private and is absent from its export list. The"

"import is well-formed and the qualified type is well-shaped; only the other"

"module's contract says the type is private."

(module text/peek :x [tag] :i [(core/private :a p)])

fn tag h: p/Hidden -> String
  "hidden"
