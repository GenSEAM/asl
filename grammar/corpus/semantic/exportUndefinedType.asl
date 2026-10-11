(module text/missing :x [Missing shout])

fn shout x: String -> String
  (str (stringUpper x) "!")
