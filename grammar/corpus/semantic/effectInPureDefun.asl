"expect: rule-12"

"The call is well-typed and well-scoped; only the missing marker makes it an"

"error. Nothing context-free can see that `fileRead` touches the world."

fn readConfig path: String -> (Result String IoError)
  (fileRead path)
