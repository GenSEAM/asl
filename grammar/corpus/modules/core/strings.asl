(module core/strings :x [concat upper])

fn concat a: String b: String -> String
  (str a b)

fn upper s: String -> String
  (stringUpper s)

fn trim s: String -> String
  (stringTrim s)
