; §9 rule 3: the declared return type is a claim about the body, and nothing
; checked it. Both declarations here are well-formed to any grammar.

(module bad/return-type
  :doc "Bodies that do not produce what their signatures promise."
  :export [label branches])

(defun label [(n Int64)] -> String
  :doc "Returns the integer it was given, not a string."
  n)

(defun branches [(b Bool)] -> Int64
  :doc "Two branches of one `if` with different types."
  (if b 1 "two"))
