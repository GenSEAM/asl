(module asl-utils/tests/exitOfStatusCoverTest
  :x [runTests]
  :i [(asl-utils/timeout :a t)])

fn testSignalled -> Bool
  (do (assert (= (t/exitOfStatus -9) 137) (str "a signalled status -9 maps to 128+9: " (t/exitOfStatus -9)))
      true)

fn testPlain -> Bool
  (do (assert (= (t/exitOfStatus 3) 3) (str "a plain exit status passes through: " (t/exitOfStatus 3)))
      (assert (= (t/exitOfStatus 0) 0) (str "a zero status stays zero: " (t/exitOfStatus 0)))
      true)

fn runTests -> Bool
  (do (assert (testSignalled) "a signalled wait status maps to 128+signal")
      (assert (testPlain) "a plain wait status is the child's exit code")
      true)
