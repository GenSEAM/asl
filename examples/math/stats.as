; Arithmetic and the numeric conversions, in use. The point of the file is the
; boundary: no operation here mixes Int64 with Float64 without saying so.

(module math/stats
  :doc "Summarise a sample of integer measurements without implicit conversion."
  :export [span clamp distance mean-or-zero leftover safe-share widen narrow
           whole-part over-budget? within? differs?])

(defun span [(lo Int64) (hi Int64)] -> Int64
  :doc "Distance between two bounds, whichever way round they came."
  (abs (- hi lo)))

(defun clamp [(x Int64) (lo Int64) (hi Int64)] -> Int64
  :doc "Hold a value inside a closed range."
  (min hi (max lo x)))

(defun distance [(x Int64)] -> Int64
  :doc "How far a value sits from zero, on the negative side of the origin."
  (neg (abs x)))

(defun mean-or-zero [(xs (List Int64))] -> Int64
  :doc "Truncating mean of a sample; an empty sample means zero, not a trap."
  (option-or (checked-div (list-sum xs) (list-length xs)) 0))

(defun leftover [(total Int64) (per-page Int64)] -> Int64
  :doc "Items on the last partial page, or zero when the page size is zero."
  (option-or (checked-mod total per-page) 0))

(defun safe-share [(part Int64) (whole Int64)] -> (Result Float64 String)
  :doc "Part as a fraction of whole, in floating point, or why it could not be."
  (if (= whole 0)
    (err "no whole to divide by")
    (ok (/ (int64-to-float64 part) (int64-to-float64 whole)))))

(defun widen [(small Int32)] -> Int64
  :doc "A narrow integer as a wide one; this direction always succeeds."
  (int32-to-int64 small))

(defun narrow [(wide Int64)] -> (Result Int32 String)
  :doc "A wide integer as a narrow one, or the reason it does not fit."
  (option-to-result (int64-to-int32 wide) "out of Int32 range"))

(defun whole-part [(x Float64)] -> (Result Int64 String)
  :doc "Truncate toward zero, rejecting NaN, infinity and out-of-range values."
  (option-to-result (float64-to-int64 x) "not a finite integer"))

(defun over-budget? [(spent Int64) (budget Int64)] -> Bool
  :doc "True when spending has passed the budget, or exactly met a zero one."
  (or (> spent budget) (and (= budget 0) (>= spent 0))))

(defun within? [(x Int64) (lo Int64) (hi Int64)] -> Bool
  :doc "True when a value sits inside a closed range."
  (and (>= x lo) (<= x hi)))

(defun differs? [(a Int64) (b Int64)] -> Bool
  :doc "True when two measurements are not equal."
  (!= a b))
