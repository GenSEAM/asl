(module text/partial :x [label] :i [(core/shapes :a s)])

fn label sh: s/Shape -> String
  (match sh ((s/circle r) "circle"))
