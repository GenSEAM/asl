(module asl-forms/tests/healCorpusTest
  :x [runTests corpusCases healFloor]
  :i [(asl-forms/heal :a h)])

; (:m :do "HEAL corpus gate: real LLM generations from the SYN-PROBES wave5 run (free OpenCode models via Leon, 2026-10-15), deduplicated; every passing program comes back byte-identical, every failing one never scores worse, a healed text rechecks clean, and the healed count stays at or above the recorded floor")
; (:m :scope "fixtures/healCorpus/passing.txt: 102 unique programs that checked and passed their test raw; failing.txt: 151 unique non-passing programs (every second unique one, empty generations dropped)")

fn fixtureDir -> String
  "asl/packages/asl-forms/tests/fixtures/healCorpus"

; (:m :do "the recorded floor: 130 of 151 failing cases healed clean on 2026-10-15 (method: this suite over failing.txt; adopted as the ratchet, raise it when rules improve)")
fn healFloor -> Int64
  130

fn caseOf piece: String -> (Pair String String)
  (mt (stringIndexOf piece "\n")
    ((none) (pair piece ""))
    ((some i)
      (let [(body (optionOr (stringSlice piece (+ i 1) (stringLength piece)) ""))
            (n (stringLength body))]
        (pair (optionOr (stringSlice piece 0 i) "") (if (stringEndsWith? body "\n") (optionOr (stringSlice body 0 (- n 1)) body) body)))))

fn ! corpusCases name: String -> (List (Pair String String))
  (mt (fileReadString (str (fixtureDir) "/" name))
    ((err e) (list))
    ((ok text) (map caseOf (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit text ";;; case ")))))

fn ! testPassingUnchanged vocab: (List String) -> Bool
  (let [(cases (corpusCases "passing.txt"))]
    (assert (= (listLength cases) 102) (str "passing.txt holds the 102 recorded programs, found " (stringFromInt64 (listLength cases))))
    (fold (fn [(ok Bool) (c (Pair String String))] -> Bool
            (let [(res (h/healSourceWith (pairSecond c) "cand.asl" (mapEmpty) vocab))]
              (assert (and (= res.text (pairSecond c)) (not res.changed)) (str (pairFirst c) ": a passing program comes back byte-identical, receipt " res.receipt))
              (and ok true)))
          true cases))

fn ! testFailingImproved vocab: (List String) -> Bool
  (let [(cases (corpusCases "failing.txt"))
        (healed (fold (fn [(n Int64) (c (Pair String String))] -> Int64
                        (let [(before (h/healScore (h/healDiags (pairSecond c) (mapEmpty) "cand.asl")))
                              (res (h/healSourceWith (pairSecond c) "cand.asl" (mapEmpty) vocab))
                              (recheck (h/healDiags res.text (mapEmpty) "cand.asl"))
                              (after (h/healScore recheck))]
                          (assert (or (> before 0) (not res.changed)) (str (pairFirst c) ": a failing case that already checks and lowers (it fails its test on logic or naming) is left untouched"))
                          (assert (if res.changed (< after before) (= res.text (pairSecond c))) (str (pairFirst c) ": a change lowers the score (" (stringFromInt64 before) " -> " (stringFromInt64 after) "), no change leaves the text"))
                          (assert (= (listEmpty? recheck) (listEmpty? res.left)) (str (pairFirst c) ": the receipt's :left agrees with an independent recheck"))
                          (if (listEmpty? recheck) (+ n 1) n)))
                      0 cases))]
    (assert (= (listLength cases) 151) (str "failing.txt holds the 151 recorded programs, found " (stringFromInt64 (listLength cases))))
    (assert (>= healed (healFloor)) (str "healed " (stringFromInt64 healed) " of " (stringFromInt64 (listLength cases)) " failing cases, floor " (stringFromInt64 (healFloor))))
    (println (str "(:healCorpus :failing " (stringFromInt64 (listLength cases)) " :healed " (stringFromInt64 healed) " :floor " (stringFromInt64 (healFloor)) ")"))
    true)

fn ! runTests -> Bool
  (let [(vocab (h/preludeVocab! "asl/prelude/prelude.asl"))]
    (assert (listContains? vocab "listSum") "the prelude vocabulary loads")
    (and (testPassingUnchanged vocab) (testFailingImproved vocab)))
