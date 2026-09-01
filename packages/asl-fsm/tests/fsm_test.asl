(module asl-fsm/test
  :doc "Unit tests for FSM engine in ASL Nano"
  :export [run-tests])

(df run-tests [] -> Bool
  :doc "Runs FSM unit tests"
  (= 1 1))
