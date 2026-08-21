; §9 rule 5: try is legal only inside a defun returning a compatible Result.
; This one returns Int64, so there is nowhere for the err to go. The grammar
; accepts it because try_form is an ordinary expression.

(module bad/stray-try
  :doc "try in a function that cannot propagate a failure."
  :export [length-of])

(defun length-of [(path String)] -> Int64
  :doc "Returns a plain integer, so the try has no Result to return into."
  :effects [fs]
  (string-length (try (file-read path))))
