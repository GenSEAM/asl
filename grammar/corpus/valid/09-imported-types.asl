(module text/labels :x [label unit] :i [(core/shapes :a s)])

fn label sh: s/Shape -> String
  (match sh ((s/circle r) "circle") ((s/rectangle w h) "rectangle"))

fn unit -> s/Shape
  (s/rectangle 1.0 1.0)
