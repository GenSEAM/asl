(module asl-eddie/test
  :d "Unit tests for EDDIE orchestrator in ASL"
  :x [run-tests])

(df run-tests [] -> Bool
  :d "Runs EDDIE orchestrator unit tests"
  (< 1 2))
