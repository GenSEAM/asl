"expect-only: literal-range"

"The same rule at the narrow width, where the literal is in range for Int64 and"

"so only the context decides: `n` fixes the operand type at Int32, and the"

"literal has to fit that, not the width it would take on its own."

fn bump n: Int32 -> Int32
  (+ n 2147483648)
