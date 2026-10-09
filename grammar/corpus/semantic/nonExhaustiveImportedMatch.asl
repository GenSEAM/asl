"expect-only: rule-4"

"The match omits `rectangle`. Exhaustiveness left keyed on the local case table"

"reports \"s/circle is not a case of any union\" beside rule-4, and a gate that"

"asserts `want in codes` accepts that — which is why this fixture is expect-only."

(module text/partial :x [label] :i [(core/shapes :a s)])

fn label sh: s/Shape -> String
  (match sh ((s/circle r) "circle"))
