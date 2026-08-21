; §9 rule 13: :target is mandatory on every defextern. Omitting it leaves the
; declaration naming no ecosystem, which the grammar permits because extern_opt
; is a repetition — making the requirement a count, and counts are not
; context-free.

(module bad/no-target
  :doc "A foreign declaration that names no ecosystem."
  :export [rows]
  :extern [(py "polars" :as pl)])

(defopaque DataFrame
  :doc "A host dataframe.")

(defextern pl/height [(df DataFrame)] -> Int64
  :doc "Row count of a dataframe.")

(defun rows [(df DataFrame)] -> (Result Int64 String)
  :doc "Row count, or the host failure."
  (pl/height df))
