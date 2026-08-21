(module core/numbers
  :doc "Number formatting shared across modules."
  :export [show even? clamped])

(defun show [(n Int64)] -> String
  :doc "Render an integer for display."
  (string-from-int64 n))

(defun even? [(n Int64)] -> Bool
  :doc "True when a number divides by two."
  (= (mod n 2) 0))

(defun clamped [(n Int64) (hi Int64)] -> Int64
  :doc "A number held below a ceiling."
  (min n hi))
