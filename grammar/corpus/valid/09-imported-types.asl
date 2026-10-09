"A type crossing a module boundary: named in a signature, matched through its"

"imported cases, and constructed. This is also the fixture that names an"

"imported type and therefore has to import its module (§4.0)."

(module text/labels :x [label unit] :i [(core/shapes :a s)])

fn label sh: s/Shape -> String
  (match sh ((s/circle r) "circle") ((s/rectangle w h) "rectangle"))

fn unit -> s/Shape
  (s/rectangle 1.0 1.0)
