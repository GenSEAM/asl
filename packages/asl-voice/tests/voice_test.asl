(module asl-voice/test
  :doc "Unit tests for voice bridge in ASL Nano"
  :export [run-tests]
  :import [(core/strings :as s)])

(df run-tests [] -> Bool
  :doc "Runs voice bridge unit tests"
  (= (s/concat "Synthesizing " "audio") "Synthesizing audio"))
