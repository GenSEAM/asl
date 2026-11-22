(module aslExamples/optionDemo
  :x [firstOr]
  :i [])

fn firstOr xs: (List String) fallback: String -> String
  (match (listHead xs)
    ((some x) x)
    ((none) fallback))
