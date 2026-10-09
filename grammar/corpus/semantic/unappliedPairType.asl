"expect-only: type-arity"

"The other half of the same rule: a bare Pair has no first component for"

"`.-first` to name, so the accessor's type cannot be read off it."

fn left p: Pair -> Int64
  p.first
