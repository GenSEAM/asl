"expect: rule-5"

"The enclosing fn does return a Result, but try sits inside a lambda, where"

"the specification does not say what it returns from."

"Superseded: the host has no try, so it rejects this file with"

"ERR_UNKNOWN_SYMBOL try, not for rule 5."

fn parseIt s: String -> (Result Int64 String)
  (ok 1)

fn sumAll xs: (List String) -> (Result (List Int64) String)
  (ok (map (fn [(x String)] -> Int64 (try (parseIt x))) xs))
