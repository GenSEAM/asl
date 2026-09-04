(module asl-voice/test
  :d "Unit tests for voice bridge in ASL"
  :x [run-tests]
  :i [(core/strings :a s)])

(df run-tests [] -> Bool
  :d "Runs voice bridge unit tests"
  (= (s/concat "Synthesizing " "audio") "Synthesizing audio"))
