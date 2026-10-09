"expect: arity"

"The call is shaped correctly and passes both grammars; only the declaration it"

"resolves to says how many arguments it should have carried."

fn add a: Int64 b: Int64 -> Int64
  (+ a b)

fn useIt -> Int64
  (add 1)
