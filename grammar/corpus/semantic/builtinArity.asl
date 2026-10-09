"expect-only: arity"

"`and` is `Bool Bool -> Bool`, not variadic. Builtin arity was excused here"

"because `list` is variadic as a constructor and nullary as a pattern — but a"

"pattern never reaches a call node, so excusing every builtin cost a silent"

"wrong answer: this checked clean and the Python backend emitted `(a and b)`,"

"dropping the third operand with nothing reported."

fn allThree? a: Bool b: Bool c: Bool -> Bool
  (and a b c)
