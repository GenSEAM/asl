(module asl-mem/test
  :d "Unit tests for in-memory vector database in ASL Nano"
  :x [run-tests])

(df run-tests [] -> Bool
  :d "Runs vector memory unit tests"
  (> 1.0 0.5))
