"expect-only: rule-9"

"`secret` is a case of core/private's Hidden, which is not exported. A case is"

"public exactly when its type is, so reaching one of an unexported union is the"

"same violation as naming the union."

(module text/pry :x [make] :i [(core/private :a p)])

fn make -> String
  (p/secret "x")
