(module asl/packages/asl-cli/tests/sweepNegativeTest
  :x [runTests]
  :i [(asl-cli/sweep :a sw)])

; (:m :ref SWEEP-NEGATIVE-FIXTURES :do "the sweep skips the deliberate-error fixtures (three tests/conformance/check files, the harness bench hidden tests) and still sweeps the Test.asl beside them and ordinary files")
fn ! runTests -> Bool
  (do (assert (sw/negative? "tests/conformance/check/compileErrorKeepsTypeBoundary.asl") "a conformance check fixture is skipped")
      (assert (sw/negative? "tests/conformance/check/hiddenListCtorPattern.asl") "hiddenListCtorPattern is skipped")
      (assert (sw/negative? "tests/conformance/check/localCtorShadowsHidden.asl") "localCtorShadowsHidden is skipped")
      (assert (sw/negative? "tests/harnessBench/cases/asl-author-duration/hidden/durationHiddenTest.asl") "a bench hidden test is skipped")
      (assert (not (sw/negative? "tests/conformance/check/compileErrorKeepsTypeBoundaryTest.asl")) "the Test.asl beside a fixture is still swept")
      (assert (not (sw/negative? "tests/conformance/check/privateCtor.asl")) "an unlisted file in the same directory is still swept")
      (assert (not (sw/negative? "tests/harnessBench/cases/asl-author-duration/clock/tests/durationTest.asl")) "a bench case test outside hidden/ is still swept")
      (assert (sw/negative? "asl/grammar/corpus/x.asl") "the earlier corpus rule is unchanged")
      true)
