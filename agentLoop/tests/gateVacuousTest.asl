(module asl/agentLoop/tests/gateVacuousTest
  :x [runTests]
  :i [(asl/agentLoop/gateIntegrity :a gi) (asl/agentLoop/agentConfig :a ac)])

; (:m :ref WRITER-GATE-VACUOUS :do "journal 983e37bce8bba22c line 61 (LL-SIZED-RT, node2 2026-10-31): the revert check of a finished turn whose gate stayed green with sizedRt.asl reverted; the run ended failed and the writer never saw it")
fn journalMessage -> String
  "no gate reports a failed assertion with asl/packages/asl-target-llvm/src/sizedRt.asl reverted to HEAD: ./bin/asl test asl/packages/asl-target-llvm/tests/sizedRtTest.asl :passesOnRevert :exit 0"

fn askText -> String
  ":passesOnRevert true :do \"each gate stays green with the files reverted to HEAD, so it does not test the change; change the test so it fails with them reverted, run it, then finish\")"

fn journalForm -> String
  (str "(:gateVacuous :gates (\"./bin/asl test asl/packages/asl-target-llvm/tests/sizedRtTest.asl\") :files (\"asl/packages/asl-target-llvm/src/sizedRt.asl\") " (askText))

fn mixedMessage -> String
  "no gate reports a failed assertion with src/a.asl, src/b.asl reverted to HEAD: sh one.sh :passesOnRevert :exit 0; sh two.sh :missingOnRevert :exit 127"

fn shown v: (Option String) -> String
  (optionOr v "none")

fn ! runTests -> Bool
  (let [(cfg (ac/configText! "."))
        (real (gi/gateVacuousRounds cfg))
        (journal (shown (gi/vacuousForm (pair false (journalMessage)))))
        (mixed (shown (gi/vacuousForm (pair false (mixedMessage)))))]
    (do
      (assert (= journal (journalForm)) (str "the journal's revert failure becomes one form naming the gate and the reverted file: " journal))
      (assert (= mixed (str "(:gateVacuous :gates (\"sh one.sh\") :files (\"src/a.asl\" \"src/b.asl\") " (askText))) (str "only the gates that passed on revert are named, every reverted file is: " mixed))
      (assert (= (shown (gi/vacuousForm (pair true "revertCheck: sh t.sh :failsOnRevert :exit 1"))) "none") "a passing revert check sends nothing")
      (assert (= (shown (gi/vacuousForm (pair false "gate \"sh t.sh\" is :vacuous: it reports no (:gate ... :asserts n :failed 0) with n > 0"))) "none") "a gate with no asserts is another cause")
      (assert (= (shown (gi/vacuousForm (pair false "restore failed"))) "none") "a failed restore is another cause")
      (assert (= (shown (gi/vacuousForm (pair false "spec check: sh t.sh reverted to HEAD: sh t.sh :passesOnRevert :exit 0"))) "none") "a message that is not the revert check is another cause even when it names a gate green on revert")
      (assert (= (shown (gi/vacuousRetry (pair false (journalMessage)) 1 2)) (journalForm)) "under the cap the writer gets the form")
      (assert (= (shown (gi/vacuousRetry (pair false (journalMessage)) 2 2)) "none") "at the cap the run ends as before")
      (assert (= (gi/gateVacuousRounds "") 2) "no config: default 2")
      (assert (= (gi/gateVacuousRounds "(:x :agentLoop (:gateVacuousRounds 5))") 5) "the :agentLoop row sets the cap")
      (assert (= (gi/gateVacuousRounds "(:x :agentLoop (:gateVacuousRounds 0))") 2) "an invalid row keeps the default")
      (assert (listContains? (ac/configProblems "(:x :agentLoop (:gateVacuousRounds 0))") ":agentLoop :gateVacuousRounds must be a positive integer, got \"0\"") "configProblems rejects an invalid :gateVacuousRounds")
      (assert (= (ac/agentLoopValue cfg ":gateVacuousRounds") (some "2")) "the workspace .asl.config.asn carries the :gateVacuousRounds row")
      (assert (= real 2) (str "the workspace row sets the cap to 2: " (stringFromInt64 real)))
      true))
