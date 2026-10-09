"A whole program across a module boundary: an imported union matched, an"

"imported function called, and one module reached through two aliases. The two"

"former backend targets represented that union completely differently — a"

"tagged tuple on one, a namespaced variant on the other — and each derived its"

"representation independently, so only running both proved they agreed."

(module text/show :x [describe main] :i [(core/shapes :a s) (core/shapes :a g)])

fn describe sh: s/Shape -> String
  (match sh ((g/circle r) "circle") ((g/rectangle w h) "rectangle"))

fn ! main args: (List String) -> (Result Unit IoError)
  (let [(sh (g/rectangle 2.0 3.0))] (println (describe sh)) (println (stringFromFloat64 (s/area sh))) (ok ()))
