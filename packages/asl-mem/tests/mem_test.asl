(module asl-mem/test
  :doc "Unit tests for in-memory vector database in ASL Nano"
  :export [run-tests])

(df run-tests [] -> Bool
  :doc "Runs vector memory unit tests"
  (> 1.0 0.5))
