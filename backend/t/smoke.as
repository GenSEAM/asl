(module smoke
  :doc "End-to-end check of the Python backend."
  :export [area classify sum-list safe-div parse-double describe])

(defenum Shape
  (:case circle    [(radius Float64)]                 "A circle")
  (:case rectangle [(width Float64) (height Float64)] "A rectangle")
  (:case point     []                                 "A degenerate shape"))

(defun area [(sh Shape)] -> Float64
  :doc "Area of a shape."
  (match sh
    ((circle r)      (* 3.0 (* r r)))
    ((rectangle w h) (* w h))
    ((point)         0.0)))

(defun classify [(n Int64)] -> String
  :doc "Sign of an integer."
  (cond
    ((< n 0) "negative")
    ((= n 0) "zero")
    (:else   "positive")))

(defun sum-list [(xs (List Int64))] -> Int64
  :doc "Sum by structural recursion."
  (match xs
    ((list)     0)
    ((cons h t) (+ h (sum-list t)))))

(defun safe-div [(a Int64) (b Int64)] -> (Result Int64 String)
  :doc "Division that reports a zero divisor as a value."
  (if (= b 0)
    (err "division by zero")
    (ok (/ a b))))

(defun parse-double [(s String)] -> (Result Int64 String)
  :doc "Parse then double, propagating failure with try."
  (let [(n (try (option-to-result (string-to-int64 s) "not a number")))]
    (ok (* n 2))))

(defun describe [(r (Result Int64 String))] -> String
  :doc "Render a result."
  (match r
    ((ok n)    (string-from-int64 n))
    ((err msg) msg)))
