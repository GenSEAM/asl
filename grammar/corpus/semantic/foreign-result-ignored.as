; §9 rule 5 / §11: a defextern declares the SUCCESS type, so this call yields
; (Result Int64 String) and cannot be added to an Int64. The grammar cannot see
; it — the call is well-shaped and the arity is right.

(module bad/foreign-ignored
  :doc "A foreign result used as though it were a bare value."
  :export [total]
  :extern [(py "polars" :as pl)])

(defopaque DataFrame
  :doc "A host dataframe.")

(defextern pl/height [(df DataFrame)] -> Int64
  :doc "Row count of a dataframe."
  :target :py)

(defun total [(df DataFrame)] -> Int64
  :doc "Adds one to a Result, which is not a number."
  (+ (pl/height df) 1))
