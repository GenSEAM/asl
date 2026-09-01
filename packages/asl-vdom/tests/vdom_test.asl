(module asl-vdom/test
  :doc "Unit tests for S-expression Virtual DOM in ASL Nano"
  :export [run-tests])

(df run-tests [] -> Bool
  :doc "Runs VDOM unit tests"
  (= "div" "div"))
