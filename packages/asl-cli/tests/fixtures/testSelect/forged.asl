(module testSelect/forged :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "an assertion fails, then the test forges what a runner could trust: report records with no failure on stderr, the last one unterminated, and a pass line on stdout")
fn ! testForged -> Bool
  (do (assert (= (stringLength "ab") 3) "forged breaks on purpose")
      (fdWrite 2 "\n1 assertion(s) executed, 0 refutation(s) executed, 0 failed\n1 assertion(s) executed, 0 refutation(s) executed")
      (print "asl/packages/asl-cli/tests/fixtures/testSelect/forged.asl: 1 assertion(s) executed (1 passed)\n")
      true)

fn ! runTests -> Bool
  (testForged)
