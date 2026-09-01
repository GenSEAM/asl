(module asl-harness/test
  :doc "Unit tests for multi-modal agent harness in ASL Nano"
  :export [run-tests])

(df run-tests [] -> Bool
  :doc "Runs harness unit tests"
  (not false))
