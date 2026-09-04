(module asl-gates/test
  :d "Unit tests for pure AgentScript verification gate runners."
  :x [test-syntax-valid test-syntax-invalid run-tests]
  :i [(gates :a g)])

(df test-syntax-valid [] -> Bool
  :d "Verifies clean syntax passes gate parser check."
  (g/verify-source-syntax "(module test/m :doc \"d\" :export [f]) (defun f [(x Int64)] -> Int64 :doc \"f\" (+ x 1))"))

(df test-syntax-invalid [] -> Bool
  :d "Verifies invalid syntax is rejected by gate parser."
  (not (g/verify-source-syntax "(module broken (:export unclosed")))

(df run-tests [] -> Bool
  :d "Runs all pure ASL gate tests."
  (fold (fn [(acc Bool) (p Bool)] -> Bool (and acc p))
        true
        (list (test-syntax-valid)
              (test-syntax-invalid))))
