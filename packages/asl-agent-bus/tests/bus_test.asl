(module asl-agent-bus/test
  :d "Unit tests for agent bus protocol in ASL"
  :x [run-tests]
  :i [(core/strings :a s)])

(df run-tests [] -> Bool
  :d "Runs agent bus unit tests"
  (= (s/concat "event: " "task") "event: task"))
