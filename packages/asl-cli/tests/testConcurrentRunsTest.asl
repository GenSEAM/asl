(module asl-cli/tests/testConcurrentRunsTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref TEST-RUNNER-SELECT :do "two asl test runs in one checkout at once both give their own correct verdict: two selections of one file (each builds from its own pid-named copy and slot), two different files, and one file twice; no selection copy is left behind. Two runs at a time, as the resource rule allows")
fn dir -> String
  "asl/packages/asl-cli/tests/fixtures/testSelect/"

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! aslTestJob! args: (List String) -> fr/Job
  (fr/job (listAppend (list (str (repoRoot!) "/bin/asl") "test") args) (repoRoot!) (fr/childEnv (list)))

fn ! together! a: (List String) b: (List String) -> (Pair fr/Done fr/Done)
  (let [(both (fr/runPoolLimited (list (aslTestJob! a) (aslTestJob! b)) 2 (fr/limits 900 64)))
        (missing (fr/Done :idx 0 :exit 127 :out "no result" :ms 0 :verdict "spawnFailed"))]
    (pair (optionOr (listGet both 0) missing) (optionOr (listGet both 1) missing)))

fn ! testTwoSelectionsOfOneFile! -> Bool
  (let [(runs (together! (list (str (dir) "threeFns.asl") "--only" "testFirst") (list (str (dir) "threeFns.asl") "--only" "testThird")))
        (a (pairFirst runs))
        (b (pairSecond runs))]
    (do (assert (and (= a.exit 0) (stringContains? a.out "threeFns.asl --only testFirst: 1 assertion(s) ran in testFirst")) (str "the testFirst selection run alongside another one passes with its own count: " a.out))
        (assert (and (= b.exit 0) (stringContains? b.out "threeFns.asl --only testThird: 2 assertion(s) ran in testThird")) (str "the testThird selection run alongside passes with its own count: " b.out))
        true))

fn ! testTwoFiles! -> Bool
  (let [(runs (together! (list "asl/packages/asl-cli/tests/fixtures/testOk.asl") (list (str (dir) "twoFails.asl"))))
        (ok1 (pairFirst runs))
        (bad (pairSecond runs))]
    (do (assert (and (= ok1.exit 0) (stringContains? ok1.out "asl/packages/asl-cli/tests/fixtures/testOk.asl: 1 assertion(s) executed (1 passed)")) (str "the passing file passes while another runs: " ok1.out))
        (assert (and (= bad.exit 1) (stringContains? bad.out (str "FAIL " (dir) "twoFails.asl: ERR_ASSERT: assertion failed: early breaks on purpose (after 1 asserts)"))) (str "the failing file fails with its own verdict while another runs: " bad.out))
        true))

fn ! testOneFileTwice! -> Bool
  (let [(runs (together! (list "asl/packages/asl-cli/tests/fixtures/testOk.asl") (list "asl/packages/asl-cli/tests/fixtures/testOk.asl")))]
    (do (assert (and (= (pairFirst runs).exit 0) (= (pairSecond runs).exit 0)) (str "one file run twice at once passes twice: " (pairFirst runs).out " | " (pairSecond runs).out))
        true))

fn ! testNoCopyLeft! -> Bool
  (let [(names (resultOr (dirList (dir)) (list)))]
    (do (assert (not (listEmpty? names)) "the fixture directory lists")
        (refute (listAny? (fn [(n String)] -> Bool (stringContains? n ".only.")) names) (str "no selection copy is left beside the file: " (stringJoin names " ")))
        true))

fn ! runTests -> Bool
  (and (testTwoSelectionsOfOneFile!) (and (testTwoFiles!) (and (testOneFileTwice!) (testNoCopyLeft!))))
