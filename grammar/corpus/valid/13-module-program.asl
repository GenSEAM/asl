(module text/show :x [describe main] :i [(core/shapes :a s) (core/shapes :a g)])

fn describe sh: s/Shape -> String
  (match sh ((g/circle r) "circle") ((g/rectangle w h) "rectangle"))

fn ! main args: (List String) -> (Result Unit IoError)
  (let [(sh (g/rectangle 2.0 3.0))] (println (describe sh)) (println (stringFromFloat64 (s/area sh))) (ok ()))
