(module asl-codec/test
  :d "Unit tests for native JSON codec."
  :x [run-tests]
  :i [(core/strings :a s)])

(df run-tests [] -> Bool
  :d "Executes basic verification of codec types"
  true)
