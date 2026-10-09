"expect-only: not-callable"

"`(-1 2)` is a call whose callee is the number -1, because a sign binds to the"

"digits after it. Written with a space, `(- 1 2)` is subtraction; written"

"without, it is this. Both former backends only discovered it at compile time —"

"a TypeError from Python, E0618 from rustc — so the checker is to name it instead."

fn difference -> Int64
  (-1 2)
