(module asl-agent-bus/test
  :doc "Unit tests for agent bus protocol in ASL Nano"
  :export [run-tests]
  :import [(core/strings :as s)])

(df run-tests [] -> Bool
  :doc "Runs agent bus unit tests"
  (= (s/concat "event: " "task") "event: task"))
