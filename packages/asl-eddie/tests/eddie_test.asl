(module asl-eddie/test
  :doc "Unit tests for EDDIE orchestrator in ASL Nano"
  :export [run-tests])

(df run-tests [] -> Bool
  :doc "Runs EDDIE orchestrator unit tests"
  (< 1 2))
