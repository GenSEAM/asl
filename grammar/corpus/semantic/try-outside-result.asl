"expect: rule-5"
"try propagates an error out of the enclosing defun, and this one does not"
"return a Result, so there is nothing for it to propagate into."
(df parseIt [(s String)] -> (Result Int64 String)
  :doc "A fallible helper to try."
  (ok 1))

(df useIt [] -> Int64
  (try (parseIt "1")))
