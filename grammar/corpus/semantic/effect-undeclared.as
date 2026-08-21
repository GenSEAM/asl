; §9 rule 12: a defun that reaches the outside declares :effects [io]. Both
; functions here omit it — one calls a builtin directly, the other only calls
; the first, which is why the rule has to be transitive to mean anything.

(module bad/silent-effects
  :doc "Effectful functions that do not say so."
  :export [read-it wrap-it])

(defun read-it [(path String)] -> (Result String String)
  :doc "Reads a file without declaring the effect."
  (file-read path))

(defun wrap-it [(path String)] -> (Result String String)
  :doc "Calls an effectful function without declaring the effect either."
  (read-it path))
