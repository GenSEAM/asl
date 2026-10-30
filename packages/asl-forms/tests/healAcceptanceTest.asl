(module asl-forms/tests/healAcceptanceTest
  :x [runTests]
  :i [(asl-forms/heal :a heal) (asl-cli/heal :a healCli)])

; (:m :do "Task54003 acceptance (HEAL 2026-10-15): the self-healing bridge is the one heal pipeline asl-forms/heal behind asl heal; a broken file is repaired on disk in one call with a (:repaired ... :left ...) receipt, a checking file is never written, a second call is a no-op, and the attempt ceiling bounds the rounds")

fn broken -> String
  "(module healProbe :x [f])\n\nfn f n: Int64 -> Int64\n(cond [(> n 0) (+ n 1)] [(else 0)]))\n"

fn healed -> String
  "(module healProbe :x [f])\n\nfn f n: Int64 -> Int64\n  (cond ((> n 0) (+ n 1)) (else 0))\n"

fn ! testHelpAndUsage! -> Bool
  (match (healCli/runHealCommand! (list "--help"))
    ((err _) (assert false "heal --help succeeds"))
    ((ok msg)
      (do (assert (stringContains? msg "Usage: asl heal") "help shows the usage line")
          (assert (stringContains? msg "--max-attempts") "help documents the attempt ceiling")
          (assert (stringContains? msg "bodyIndent") "help lists the named rules")
          (refute (stringContains? msg ":line") "zero-line-number invariant in heal help")
          (refute (stringContains? msg ":col") "zero-col invariant in heal help"))))
  (match (healCli/runHealCommand! (list))
    ((ok _) (assert false "heal without a file fails"))
    ((err msg) (do (assert (stringContains? msg "Usage: asl heal") "a missing file returns the usage")
                   (refute (stringContains? msg ":written") "nothing is reported written"))))
  true

fn ! testHealsFileOnDisk! -> Bool
  (let [(path (str "/tmp/aslTask54003-" (stringFromInt64 (procSelf)) ".asl"))
        (_ (fileWrite path (broken)))
        (first (healCli/runHealCommand! (list path)))
        (afterFirst (resultOr (fileReadString path) ""))
        (second (healCli/runHealCommand! (list path)))
        (afterSecond (resultOr (fileReadString path) ""))
        (_ (pathRemove path))]
    (match first
      ((err e) (assert false (str "a repairable file heals, got " e)))
      ((ok receipt)
        (do (assert (stringContains? receipt ":written true") "the repaired text is written back")
            (assert (stringContains? receipt "delimiterBalance") "the receipt names delimiterBalance")
            (assert (stringContains? receipt "bodyIndent") "the receipt names bodyIndent")
            (assert (stringContains? receipt "condClauses") "the receipt names condClauses")
            (assert (stringContains? receipt ":left ()") "nothing is left")
            (refute (stringContains? receipt ":written false") "the first call is not a no-op"))))
    (assert (= afterFirst (healed)) (str "the file on disk is the healed text, got " afterFirst))
    (refute (= afterFirst (broken)) "the broken text is gone")
    (match second
      ((err e) (assert false (str "a healed file stays clean, got " e)))
      ((ok receipt)
        (do (assert (stringContains? receipt ":written false") "a checking file is not written")
            (assert (stringContains? receipt ":repaired ()") "a checking file has no repairs")
            (refute (stringContains? receipt "bodyIndent") "no rule fires twice"))))
    (assert (= afterSecond afterFirst) "the second call leaves the file byte-identical")
    (refute (fileExists? path) "the probe file is removed")
    true)

fn ! testDryRunAndCeiling! -> Bool
  (let [(path (str "/tmp/aslTask54003-dry-" (stringFromInt64 (procSelf)) ".asl"))
        (_ (fileWrite path (broken)))
        (dry (healCli/runHealCommand! (list "--dry-run" path)))
        (afterDry (resultOr (fileReadString path) ""))
        (capped (healCli/runHealCommand! (list "--dry-run" "--max-attempts=1" path)))
        (_ (pathRemove path))]
    (match dry
      ((err e) (assert false (str "dry run reports the repairs, got " e)))
      ((ok receipt) (do (assert (stringContains? receipt ":written false") "dry run writes nothing")
                        (refute (stringContains? receipt ":repaired ()") "dry run still reports the repairs"))))
    (assert (= afterDry (broken)) "dry run leaves the file untouched")
    (match capped
      ((ok _) (assert false "one attempt cannot heal a three-rule file"))
      ((err receipt) (do (assert (stringContains? receipt ":repaired (delimiterBalance)") "the ceiling stops after the first rule")
                         (refute (stringContains? receipt ":left ()") "the capped run reports what is left"))))
    (refute (fileExists? path) "the dry-run probe file is removed")
    true)

fn testPipelineInvariants -> Bool
  (let [(clean (healed))
        (res (heal/healSource clean "healProbe.asl"))
        (bad (heal/healSource (broken) "healProbe.asl"))]
    (assert (= res.text clean) "a checking text is returned byte-identical")
    (refute res.changed "a checking text is not marked changed")
    (assert (= bad.text clean) "the pure pipeline heals the same text the CLI writes")
    (refute (listEmpty? bad.repaired) "the pure pipeline names its rules")
    (assert (listEmpty? bad.left) "the pure pipeline leaves nothing")
    (refute (= (heal/healScore (heal/healDiags (broken) (mapEmpty) "healProbe.asl")) 0) "the broken text scores above zero before healing")
    true)

fn ! runTests -> Bool
  (and (testHelpAndUsage!) (testHealsFileOnDisk!) (testDryRunAndCeiling!) (testPipelineInvariants))
