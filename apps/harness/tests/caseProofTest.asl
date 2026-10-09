(module aslHarness/tests/caseProofTest
  :x [runTests]
  :i [(caseProofKit :a kit)])

fn ! runTests -> Bool
  (let [(caseDir "tests/agentEval/cases/implement-two-behaviours-large-file")
        (stepperLines (- (listLength (stringSplit (resultOr (fileReadString (str caseDir "/src/stepper.py")) "") "\n")) 1))
        (laid (kit/layCase! caseDir "TwoBehaviours"))
        (repo (mt laid ((ok l) l.repo) ((err e) (str "/nonexistent/" e))))
        (ran (kit/runIn! (list "python3" "test_behaviours.py") repo (list)))
        (lines (kit/outputLines (pairSecond ran)))
        (out (pairSecond ran))]
    (do
      (mt laid ((ok l) (kit/removeLaid! l)) ((err e) (do (println (str "layCase: " e)) false)))
      (assert (> stepperLines 2000) "srcOver2000Lines")
      (assert (!= (pairFirst ran) 0) "checkExitsNonZero")
      (assert (listAny? (fn [(l String)] -> Bool (kit/gateLine? "twoBehaviours" l)) lines) "checkRanToGateLine")
      (assert (not (listAny? (fn [(w String)] -> Bool (stringContains? out w)) (list "Traceback" "SyntaxError" "ImportError" "ModuleNotFoundError"))) "noCrash")
      (assert (>= (kit/countPrefixed lines "FAIL owns") 1) "ownsBehaviourFails")
      (assert (>= (kit/countPrefixed lines "FAIL evidence") 1) "evidenceBehaviourFails")
      (assert (kit/scoresImplement? (resultOr (fileReadString (str caseDir "/truth.asn")) "") "python3 test_behaviours.py") "truthScoresImplement")
      true))
