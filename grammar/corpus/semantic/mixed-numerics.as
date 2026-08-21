; §9 rule 6: no numeric operation mixes types. `+` is `N N -> N` — one numeric
; type across both operands — and §6.4 has the explicit conversions. The grammar
; cannot see it: the form is well-shaped and the arity is right.

(module bad/mixed-numerics
  :doc "Arithmetic across two numeric types."
  :export [total])

(defun total [(count Int64) (rate Float64)] -> Float64
  :doc "Adds an integer to a float without converting either."
  (+ count rate))
