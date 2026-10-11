(module emitRefsSourceEntry
  :x [main]
  :i [(asl-syntax/core/source :a suite)])

fn ! main args: (List String) -> (Result Int64 String)
  (ok (suite/sourceLength (suite/sourceFromString "emitRefs" "a\nb\n")))
