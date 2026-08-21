(module bench/arith
  :doc "Numeric edge cases the backends have historically disagreed on."
  :export [probe])

(defun probe [(text String)] -> String
  :doc "Render division, truncation and rounding for a parsed pair of numbers.

  Every value here is one the backends can differ on: integer division rounds
  toward zero rather than toward negative infinity, float division must not
  become an IEEE infinity when the divisor is zero, and float-to-int truncation
  must reject a non-finite value instead of wrapping."
  (let [(parts (string-split text " "))
        (a (option-or (string-to-int64 (option-or (list-get parts 0) "0")) 0))
        (b (option-or (string-to-int64 (option-or (list-get parts 1) "1")) 1))
        (fa (int64-to-float64 a))
        (fb (int64-to-float64 b))]
    (str (string-from-int64 (option-or (checked-div a b) 0))
         "|"
         (string-from-int64 (option-or (checked-mod a b) 0))
         "|"
         (string-from-float64 (option-or (checked-div fa fb) 0.0))
         "|"
         (string-from-int64 (option-or (float64-to-int64 (/ fa 4.0)) 0)))))
