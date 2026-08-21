; A well-formed foreign module that names the systems target. Not semantically
; invalid — it exists so the two refusal reasons can be told apart: a backend
; that does not emit :rs must call this a target mismatch, and the :rs backend
; must call it an unimplemented lowering.

(module data/rsframes
  :doc "A foreign module that names the systems target."
  :export [rows]
  :extern [(rs "polars" :as pl)])

(defopaque DataFrame
  :doc "A host dataframe.")

(defextern pl/height [(df DataFrame)] -> Int64
  :doc "Row count."
  :target :rs)

(defun rows [(df DataFrame)] -> (Result Int64 String)
  :doc "Row count, or the host failure."
  (pl/height df))
