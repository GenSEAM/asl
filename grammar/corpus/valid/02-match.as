; Pattern matching over List, Option and Result.

(defun sum-list [(xs (List Int64))] -> Int64
  (match xs
    ((list)     0)
    ((cons h t) (+ h (sum-list t)))))

(defun first-or [(xs (List Int64)) (fallback Int64)] -> Int64
  (match (list-head xs)
    ((some v) v)
    ((none)   fallback)))

(defun safe-div [(a Int64) (b Int64)] -> (Result Int64 String)
  (if (= b 0)
    (err "division by zero")
    (ok (/ a b))))

(defun describe [(r (Result Int64 String))] -> String
  (match r
    ((ok n)    (string-from-int64 n))
    ((err msg) msg)))

(defun classify [(n Int64)] -> String
  (cond
    ((< n 0) "negative")
    ((= n 0) "zero")
    (:else   "positive")))
