(module asl-tools/fleet/tests/executedOfTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "the executed-assert count of a shell gate counts only in the declared form ./bin/asl test FILE... and only from the verdict lines the host prints last, one per declared file: an echoed count, a count printed by the suite and a verdict count that does not match the declared files are no count")
fn ! gate cmd: String -> fr/Done
  (fr/runShell! cmd (resultOr (realPath ".") ".") (fr/childEnv (list)) (fr/limits 300 100))

fn count d: fr/Done -> Int64
  (optionOr (fr/executedOf d.out) 0)

fn ! runTests -> Bool
  (let [(three "asl/tools/fleet/tests/fixtures/threeAssertsSuite.asl")
        (noisy "asl/tools/fleet/tests/fixtures/noisySuite.asl")
        (echoed (gate "echo '5 assertion(s) executed (5 passed)'"))
        (echoedForm (gate "echo ./bin/asl test x.asl; echo 'x.asl: 5 assertion(s) executed (5 passed)'"))
        (failEcho (gate "echo 'FAIL x.asl: ERR_ASSERT: boom (after 7 asserts)'"))
        (real (gate (str "./bin/asl test " three)))
        (realEcho (gate (str "./bin/asl test " three "; echo '50 assertion(s) executed (50 passed)'")))
        (realNoisy (gate (str "./bin/asl test " noisy)))
        (chained (gate (str "./bin/asl test " three " && echo '" three ": 50 assertion(s) executed (50 passed)'")))
        (pureTwoOne (fr/gateOut (str "./bin/asl test " three " " noisy) (str three ": 3 assertion(s) executed (3 passed)\n")))
        (pureTwoTwo (fr/gateOut (str "./bin/asl test " three " " noisy) (str three ": 3 assertion(s) executed (3 passed)\n" noisy ": 3 assertion(s) executed (3 passed)\n")))
        (pureOtherPath (fr/gateOut (str "./bin/asl test " three) "other.asl: 3 assertion(s) executed (3 passed)\n"))
        (pureNotLast (fr/gateOut (str "./bin/asl test " three) (str three ": 3 assertion(s) executed (3 passed)\ntrailing noise\n")))
        (pureRed (fr/gateOut (str "./bin/asl test " three) (str "t.asl:5:9: ERR_ASSERT: assertion failed: x\nFAIL " three ": ERR_ASSERT: assertion failed: x (after 2 asserts)\n")))]
    (do (assert (and (= echoed.exit 0) (= (count echoed) 0) (stringContains? echoed.out "gateFormUndeclared")) (str "an echoed count line is no count: " (stringFromInt64 (count echoed)) " in " echoed.out))
        (assert (= (count echoedForm) 0) (str "an echo that spells the declared form is no count: " (stringFromInt64 (count echoedForm))))
        (assert (= (count failEcho) 0) (str "an echoed FAIL line is no count: " (stringFromInt64 (count failEcho))))
        (assert (and (= real.exit 0) (= (count real) 3)) (str "a real suite of three assertions reads 3: " (stringFromInt64 (count real)) " exit " (stringFromInt64 real.exit) " " real.out))
        (assert (= (count realEcho) 0) (str "a line echoed after a real suite breaks the form: " (stringFromInt64 (count realEcho))))
        (assert (= (count chained) 0) (str "a path-prefixed count echoed after a real suite is a duplicate verdict: " (stringFromInt64 (count chained))))
        (assert (and (= realNoisy.exit 0) (= (count realNoisy) 0) (stringContains? realNoisy.out "gateVerdictInvalid")) (str "a suite that prints its own path-prefixed count is a duplicate verdict: " (stringFromInt64 (count realNoisy)) " in " realNoisy.out))
        (assert (and (none? (fr/executedOf pureTwoOne)) (stringContains? pureTwoOne "gateVerdictInvalid")) "two files declared and one verdict is no count")
        (assert (= (fr/executedOf pureTwoTwo) (some 3)) (str "two files and two verdicts read the last verdict: " pureTwoTwo))
        (assert (none? (fr/executedOf pureOtherPath)) "a verdict of an undeclared path is no count")
        (assert (none? (fr/executedOf pureNotLast)) "a verdict that is not the last line is no count")
        (assert (and (= (fr/executedOf pureRed) (some 2)) (stringContains? pureRed (str "FAIL " three ": ERR_ASSERT"))) (str "a declared FAIL verdict keeps its cause and count: " pureRed))
        true))
