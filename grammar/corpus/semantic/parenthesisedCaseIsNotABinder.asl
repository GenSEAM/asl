"expect-only: rule-4"

"§5.4 gives `(<case> <p>*)` and `<ident>` different meanings: parenthesised is a"

"case test, bare is a binder that matches anything. Read the other way round —"

"`(notFound)` binding rather than testing — the first arm is a catch-all and"

"this match is exhaustive, so the missing cases are exactly what pins the"

"distinction the backends had to agree on."

fn code e: IoError -> Int64
  (match e ((notFound) 1) ((interrupted) 2))
