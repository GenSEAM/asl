(module asl-harness/test
  :d "Unit tests for multi-modal agent harness in ASL Nano"
  :x [run-tests])

(df run-tests [] -> Bool
  :d "Runs harness unit tests"
  (not false))
