(module asl/agentLoop/tests/gateVacuousTest
  :x [runTests]
  :i [(asl/agentLoop/gateIntegrity :a gi) (asl/agentLoop/gates :a g) (asl/agentLoop/agentConfig :a ac) (asl/agentLoop/core :a c)])

; (:m :ref WRITER-GATE-VACUOUS :do "journal 983e37bce8bba22c line 61 (LL-SIZED-RT, node2 2026-10-31): the revert check of a finished turn whose gate stayed green with sizedRt.asl reverted; the run ended failed and the writer never saw it")
fn journalMessage -> String
  "no gate reports a failed assertion with asl/packages/asl-target-llvm/src/sizedRt.asl reverted to HEAD: ./bin/asl test asl/packages/asl-target-llvm/tests/sizedRtTest.asl :passesOnRevert :exit 0"

fn askText -> String
  ":passesOnRevert true :do \"each gate stays green with the files reverted to HEAD, so it does not test the change; change the test so it fails with them reverted, run it, then finish\")"

fn journalForm -> String
  (str "(:gateVacuous :gates (\"./bin/asl test asl/packages/asl-target-llvm/tests/sizedRtTest.asl\") :files (\"asl/packages/asl-target-llvm/src/sizedRt.asl\") " (askText))

fn green cmd: String -> g/GateResult
  (g/makeGateResult cmd 0 "" "" false 1)

fn missing cmd: String -> g/GateResult
  (g/makeGateResult cmd 127 "" "sh: not found" false 0)

fn failing cmd: String -> g/GateResult
  (g/makeGateResult cmd 1 "(:gate :asserts 2 :failed 1)" "" false 1)

; (:m :ref WRITER-GATE-VACUOUS :do "the integrity pair the revert check returns for reverted results, through the producer itself")
fn verdictOf results: (List g/GateResult) impl: (List String) -> (Pair Bool String)
  (gi/revertVerdict results (g/gateVerdicts results true) impl (list))

fn trickyCmd -> String
  "sh -c 'a; b' \"q\\x\"; echo"

fn shown v: (Option String) -> String
  (optionOr v "none")

fn ! runTests -> Bool
  (let [(cfg (ac/configText! "."))
        (real (gi/gateVacuousRounds cfg))
        (jr (list (green "./bin/asl test asl/packages/asl-target-llvm/tests/sizedRtTest.asl")))
        (ji (list "asl/packages/asl-target-llvm/src/sizedRt.asl"))
        (journal (verdictOf jr ji))
        (plain (g/gateRevertVerdict jr (g/gateVerdicts jr true) ji (list)))
        (tr (list (green (trickyCmd)) (missing "sh absent.sh")))
        (ti (list "src/a, b.asl" "src/c.asl"))
        (tricky (shown (gi/vacuousForm (verdictOf tr ti))))
        (failed (verdictOf (list (green "sh one.sh") (failing "sh two.sh")) (list "src/a.asl")))]
    (do
      (assert (= (pairSecond plain) (journalMessage)) (str "gateRevertVerdict still prints the journal's line: " (pairSecond plain)))
      (assert (= (pairSecond journal) (str (journalMessage) "\n" (journalForm))) (str "revertVerdict keeps that line and adds the form: " (pairSecond journal)))
      (assert (= (shown (gi/vacuousForm journal)) (journalForm)) "the journal's revert failure becomes one form naming the gate and the reverted file")
      (assert (= tricky (str "(:gateVacuous :gates (\"" (c/escapeAsn (trickyCmd)) "\") :files (\"src/a, b.asl\" \"src/c.asl\") " (askText))) (str "a command with '; ', a quote and a backslash and a path with ', ' arrive whole, and only the gate green on revert is named: " tricky))
      (assert (stringContains? tricky "\\\"q\\\\x\\\"") (str "the quote and backslash are escaped in the form: " tricky))
      (assert (pairFirst failed) "a gate that fails on revert passes the check")
      (assert (= (shown (gi/vacuousForm failed)) "none") "a passing revert check sends nothing")
      (assert (= (shown (gi/vacuousForm (pair true (pairSecond journal)))) "none") "an ok pair sends nothing even when its text holds the form")
      (assert (= (shown (gi/vacuousForm (pair false (journalMessage)))) "none") "a message with no form line is another cause")
      (assert (= (shown (gi/vacuousForm (pair false "restore failed"))) "none") "a failed restore is another cause")
      (assert (= (shown (gi/vacuousRetry journal 1 2)) (journalForm)) "under the cap the writer gets the form")
      (assert (= (shown (gi/vacuousRetry journal 2 2)) "none") "at the cap the run ends as before")
      (assert (= (gi/gateVacuousRounds "") 2) "no config: default 2")
      (assert (= (gi/gateVacuousRounds "(:x :agentLoop (:gateVacuousRounds 5))") 5) "the :agentLoop row sets the cap")
      (assert (= (shown (gi/vacuousRetry journal 4 (gi/gateVacuousRounds "(:x :agentLoop (:gateVacuousRounds 5))"))) (journalForm)) "a configured cap of 5 still retries at round 4")
      (assert (= (gi/gateVacuousRounds "(:x :agentLoop (:gateVacuousRounds 0))") 2) "an invalid row keeps the default")
      (assert (listContains? (ac/configProblems "(:x :agentLoop (:gateVacuousRounds 0))") ":agentLoop :gateVacuousRounds must be a positive integer, got \"0\"") "configProblems rejects an invalid :gateVacuousRounds")
      (assert (= (ac/agentLoopValue cfg ":gateVacuousRounds") (some "2")) "the workspace .asl.config.asn carries the :gateVacuousRounds row")
      (assert (= real 2) (str "the workspace row sets the cap to 2: " (stringFromInt64 real)))
      true))
