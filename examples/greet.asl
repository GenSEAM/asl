(module asl/examples/greet
  :x [greet]
  :i [])

fn greet name: String -> String
  (str "hello, " name)
