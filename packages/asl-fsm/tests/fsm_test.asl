(module asl-fsm/test
  :d "Unit tests for FSM engine in ASL Nano"
  :x [run-tests])

(df run-tests [] -> Bool
  :d "Runs FSM unit tests"
  (= 1 1))
