(module asl-forms/tests/healCorpusTest
  :x [runTests corpusCases healFloor cleanSourceDirs]
  :i [(asl-forms/heal :a h) (asl-checker/types :a ty) (asl-checker/resolve :a r) (asl-parser/ast :a a)])

; (:m :do "HEAL corpus gate: real LLM generations from the SYN-PROBES wave5 run (free OpenCode models via Leon, 2026-10-15), deduplicated; every passing program comes back byte-identical, every failing one never scores worse, a healed text rechecks clean, and the healed count stays at or above the recorded floor")
; (:m :scope "fixtures/healCorpus/passing.txt: 102 unique programs that checked and passed their test raw; failing.txt: 151 unique non-passing programs (every second unique one, empty generations dropped)")

fn fixtureDir -> String
  "asl/packages/asl-forms/tests/fixtures/healCorpus"

; (:m :do "the recorded floor: 130 of 151 failing cases healed clean on 2026-10-15 (method: this suite over failing.txt; adopted as the ratchet, raise it when rules improve)")
fn healFloor -> Int64
  130

fn caseOf piece: String -> (Pair String String)
  (match (stringIndexOf piece "\n")
    ((none) (pair piece ""))
    ((some i)
      (let [(body (optionOr (stringSlice piece (+ i 1) (stringLength piece)) ""))
            (n (stringLength body))]
        (pair (optionOr (stringSlice piece 0 i) "") (if (stringEndsWith? body "\n") (optionOr (stringSlice body 0 (- n 1)) body) body)))))

fn ! corpusCases name: String -> (List (Pair String String))
  (match (fileReadString (str (fixtureDir) "/" name))
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

; (:m :ref HEAL-CONDCLAUSES-CLEAN :do "the tracked sources heal is the identity on: every .asl under these directories that passes asl check (it parses, its imports load from the check roots, and the only diagnostics left are the rule-13 lint asl check does not report) goes through heal! the way asl heal runs it and must come back byte-identical; measured 2026-11-14 with this case: asl-agent/src 47 clean sources, 4 changed by condClauses before the fix (core, main, poolServe, runOps), 0 after")
fn cleanSourceDirs -> (List String)
  (list "asl/packages/asl-agent/src")

fn checkRoots -> (List String)
  (list "." "asl/packages" "asl")

fn ! aslFilesUnder dir: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (fold (fn [(acc (List String)) (n String)] -> (List String)
              (if (stringEndsWith? n ".asl") (listAppend acc (list (str dir "/" n))) (listAppend acc (aslFilesUnder (str dir "/" n)))))
            (list) (listSort names))))

fn ! passesCheck? path: String text: String -> Bool
  (match (a/parseForTypeCheck text)
    ((err _) false)
    ((ok forms)
      (let [(summary (r/collectSummary forms path))
            (cl (r/loadModuleDepsFrom! (cons (r/parentDirOf path) (checkRoots)) (r/mapValuesList summary.imports) (mapEmpty) (r/emptyModIndex)))]
        (and (listEmpty? cl.unresolved)
             (and (listEmpty? cl.errors)
                  (listAll? (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-13")) (h/healDiags text cl.deps path)))))))

; (:m :do "one source: (clean changed) grows by the path when it passes check, and by the path and the rules heal named when heal! returns another text")
fn ! cleanStep acc: (Pair (List String) (List String)) path: String -> (Pair (List String) (List String))
  (match (fileReadString path)
    ((err _) acc)
    ((ok text)
      (if (passesCheck? path text)
        (match (h/heal! path text (checkRoots) "asl/prelude/prelude.asl" 24)
          ((err e) (pair (cons path (pairFirst acc)) (cons (str path " (heal! failed: " e ")") (pairSecond acc))))
          ((ok res) (pair (cons path (pairFirst acc))
                          (if (and (= res.text text) (not res.changed)) (pairSecond acc) (cons (str path " (" (stringJoin res.repaired " ") ")") (pairSecond acc))))))
        acc)))

fn ! testCleanSourcesUnchanged -> Bool
  (let [(files (fold (fn [(acc (List String)) (d String)] -> (List String) (listAppend acc (aslFilesUnder d))) (list) (cleanSourceDirs)))
        (res (fold cleanStep (pair (list) (list)) files))
        (clean (listLength (pairFirst res)))
        (changed (listReverse (pairSecond res)))]
    (assert (listContains? (pairFirst res) "asl/packages/asl-agent/src/core.asl") (str "asl-agent/src/core.asl, a source with the rule-13 lint and a two-item cond clause, is among the " (stringFromInt64 clean) " of " (stringFromInt64 (listLength files)) " sources that pass check"))
    (assert (listEmpty? changed) (str "heal changes " (stringFromInt64 (listLength changed)) " of " (stringFromInt64 clean) " sources that pass asl check: " (stringJoin changed ", ")))
    (println (str "(:healCorpus :cleanSources " (stringFromInt64 clean) " :changed " (stringFromInt64 (listLength changed)) ")"))
    true)

fn ! runTests -> Bool
  (let [(vocab (h/preludeVocab! "asl/prelude/prelude.asl"))]
    (assert (listContains? vocab "listSum") "the prelude vocabulary loads")
    (and (testPassingUnchanged vocab) (testFailingImproved vocab) (testCleanSourcesUnchanged)))
