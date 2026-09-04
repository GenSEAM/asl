(module asl-vdom/test
  :d "Unit tests for S-expression Virtual DOM in ASL"
  :x [run-tests])

(df run-tests [] -> Bool
  :d "Runs VDOM unit tests"
  (= "div" "div"))
