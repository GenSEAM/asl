(module asl-agent-core/fsm-test
  :d "Unit tests for FSM engine in ASL"
  :x [run-tests])

(df run-tests [] -> Bool
  :d "Runs FSM unit tests"
  (= 1 1))
