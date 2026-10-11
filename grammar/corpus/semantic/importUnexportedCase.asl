(module text/pry :x [make] :i [(core/private :a p)])

fn make -> String
  (p/secret "x")
