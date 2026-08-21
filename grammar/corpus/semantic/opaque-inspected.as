; §9 rule 14: a defopaque value crosses the boundary and is never inspected.
; Comparing two of them needs an equality the language cannot know the host has,
; and reading a field off one needs a shape it deliberately does not model.

(module bad/opaque-peek
  :doc "An opaque host value treated as though its shape were known."
  :export [same? width-of]
  :extern [(py "polars" :as pl)])

(defopaque DataFrame
  :doc "A host dataframe.")

(defun same? [(a DataFrame) (b DataFrame)] -> Bool
  :doc "Compares two opaque values structurally."
  (= a b))

(defun width-of [(df DataFrame)] -> Int64
  :doc "Reads a field off an opaque value."
  (.-width df))
