(module text/clean :x [clean] :i [(core/strings :a s)])

fn clean x: String -> String
  (s/trim x)
