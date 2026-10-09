(module text/report :x [describe unitSquare] :i [(core/shapes :a s)])

"Search-path companion: it speaks in another module's type, so rule 13 has to"

"be checked against the module that DEFINES a type, not the one naming it."

fn describe sh: s/Shape -> String
  (match sh ((s/circle r) (str "circle " (stringFromFloat64 r))) ((s/rectangle w h) (str "rectangle " (stringFromFloat64 (* w h)))))

fn unitSquare -> s/Shape
  (s/rectangle 1.0 1.0)
