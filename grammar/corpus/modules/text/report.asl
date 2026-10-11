(module text/report :x [describe unitSquare] :i [(core/shapes :a s)])

fn describe sh: s/Shape -> String
  (match sh ((s/circle r) (str "circle " (stringFromFloat64 r))) ((s/rectangle w h) (str "rectangle " (stringFromFloat64 (* w h)))))

fn unitSquare -> s/Shape
  (s/rectangle 1.0 1.0)
