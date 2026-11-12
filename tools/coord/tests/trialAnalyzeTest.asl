(module asl/tools/coord/tests/trialAnalyzeTest
  :x [runTests]
  :i [(asl-tools/coord/trialAnalyze :a ta) (asl-parser/reader :a rd)])

; (:m :ref TRIAL-ANALYZE :do "fixtures/trialRuns.asn holds one (:fixture :expect C :insert I :record R) per trialStall-v1 class and (:extra ...) rows for H1, unknown shapes, records rebuilt from node2 sessions and real node2 write rows; every record must classify as expected, and swapping two precedence steps that an overlap fixture pins must change at least one class")
fn fixturePath -> String
  "asl/tools/coord/tests/fixtures/trialRuns.asn"

fn ! forms -> (List rd/SExpr)
  (ta/parseForms (resultOr (fileReadString (fixturePath)) ""))

fn plain a: String -> String
  (let [(u (ta/unq a))]
    (if (stringStartsWith? u ":") (optionOr (stringSlice u 1 (stringLength u)) u) u))

fn field f: rd/SExpr key: String -> String
  (match (ta/kvOf f key) ((some v) (plain (ta/atomOf v))) ((none) ""))

fn recordOf f: rd/SExpr -> rd/SExpr
  (optionOr (ta/kvOf f ":record") (rd/makeList (list)))

fn ofKind fs: (List rd/SExpr) head: String -> (List rd/SExpr)
  (filter (fn [(f rd/SExpr)] -> Bool (= (rd/sexprHead f) head)) fs)

fn mismatch rules: (List ta/Rule) f: rd/SExpr -> String
  (let [(v (ta/classifyWith rules (recordOf f)))
        (want (field f ":expect"))
        (ins (field f ":insert"))]
    (if (and (= v.class want) (or (stringEmpty? ins) (= v.insert ins)))
      ""
      (str (field (recordOf f) ":id") (field (recordOf f) ":unit") ": want " want "/" ins " got " v.class "/" v.insert " " v.why)))

fn mismatches rules: (List ta/Rule) fs: (List rd/SExpr) -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map (fn [(f rd/SExpr)] -> String (mismatch rules f)) fs))

fn uniq xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn ! testClasses -> Bool
  (let [(fs (ofKind (forms) ":fixture"))
        (expects (map (fn [(f rd/SExpr)] -> String (field f ":expect")) fs))
        (classes (map (fn [(r ta/Rule)] -> String r.class) (ta/rules)))
        (bad (mismatches (ta/rules) fs))]
    (do (assert (= (listLength classes) 29) (str "taxonomy has 29 classes: " (stringFromInt64 (listLength classes))))
        (assert (= (listLength fs) 29) (str "29 class fixtures: " (stringFromInt64 (listLength fs))))
        (assert (listEmpty? bad) (str "each class fixture maps to its class and insert: " (stringJoin bad "; ")))
        (assert (= (uniq expects) classes) (str "one fixture per class, in precedence order: " (stringJoin expects " ")))
        true))

fn ! testExtras -> Bool
  (let [(fs (ofKind (forms) ":extra"))
        (bad (mismatches (ta/rules) fs))
        (byId (fn [(id String)] -> ta/Verdict
                (ta/classify (recordOf (optionOr (listFind (fn [(f rd/SExpr)] -> Bool (= (field (recordOf f) ":id") id)) fs) (rd/makeList (list)))))))
        (h1 (byId "H1-readonly"))
        (p6 (ta/classify (recordOf (optionOr (listFind (fn [(f rd/SExpr)] -> Bool (= (field (recordOf f) ":unit") "P6")) fs) (rd/makeList (list))))))
        (cut (ta/classify (recordOf (optionOr (listFind (fn [(f rd/SExpr)] -> Bool (= (field (recordOf f) ":unit") "L3-cutAlias")) fs) (rd/makeList (list))))))
        (quoted (byId "M2-quotedexit"))
        (gatesExit (byId "M2-gatesexit"))
        (unknown (byId "X1"))]
    (do (assert (= (listLength fs) 50) (str "50 extra fixtures: " (stringFromInt64 (listLength fs))))
        (assert (listEmpty? bad) (str "each extra maps as expected: " (stringJoin bad "; ")))
        (assert (= h1.class "wReadLoop") (str "H1: 37 read-only turns and no signal is wReadLoop: " h1.class))
        (assert (and (= unknown.class "unclassified") (not (stringEmpty? unknown.why))) (str "an unknown shape is unclassified with a reason: " unknown.class))
        (assert (stringEmpty? unknown.insert) "an unclassified record names no insertion point")
        (assert (and p6.pinUnknown (= p6.model "glmB")) (str "a row served by another alias than :model is flagged pinUnknown: " (ta/classifyText p6)))
        (assert (and (not cut.pinUnknown) (= cut.model "nimA")) (str "a cut servedAlias is unknown, the row keeps its :model: " (ta/classifyText cut)))
        (assert (= quoted.why "malformed :exit in gates") (str "a quoted integer is malformed, not -1: " quoted.why))
        (assert (= gatesExit.why "missing :exit in gates") (str "a missing required key names itself: " gatesExit.why))
        true))

fn ! swapRed a: String b: String -> Bool
  (let [(fs (listAppend (ofKind (forms) ":fixture") (ofKind (forms) ":extra")))
        (swapped (ta/swapRules (ta/rules) a b))
        (order (map (fn [(r ta/Rule)] -> String r.class) swapped))]
    (and (!= order (map (fn [(r ta/Rule)] -> String r.class) (ta/rules)))
         (not (listEmpty? (mismatches swapped fs)))))

fn ! testPrecedence -> Bool
  (do (assert (swapRed "wProvider" "wReadLoop") "swapping wProvider and wReadLoop misclassifies a fixture")
      (assert (swapRed "wToolRoot" "wReadLoop") "swapping wToolRoot and wReadLoop misclassifies a fixture")
      (assert (swapRed "wRefused" "wRepeat") "swapping wRefused and wRepeat misclassifies a fixture")
      (assert (swapRed "rFalsePass" "merged") "swapping rFalsePass and merged misclassifies a fixture")
      (assert (swapRed "wPinBroken" "merged") "swapping wPinBroken and merged misclassifies a fixture")
      (assert (swapRed "wStallKill" "wReadLoop") "swapping wStallKill and wReadLoop misclassifies a fixture")
      (assert (swapRed "wRevertGreen" "wVacuous") "swapping wRevertGreen and wVacuous misclassifies a fixture")
      (assert (swapRed "wNeedsReview" "wGateRed") "swapping wNeedsReview and wGateRed misclassifies a fixture")
      (assert (swapRed "wMalformed" "wReadLoop") "swapping wMalformed and wReadLoop misclassifies a fixture")
      (assert (swapRed "wReadLoop" "wRefused") "swapping wReadLoop and wRefused misclassifies a fixture")
      (assert (swapRed "wCompile" "wGateRed") "swapping wCompile and wGateRed misclassifies a fixture")
      (assert (not (swapRed "wProvider" "noSuchClass")) "a swap with an unknown class changes nothing")
      true)

fn ! testReport -> Bool
  (let [(classRecs (map recordOf (ofKind (forms) ":fixture")))
        (allRecs (map recordOf (listAppend (ofKind (forms) ":fixture") (ofKind (forms) ":extra"))))
        (r (ta/reportText classRecs "2026-11-05"))
        (all (ta/reportText allRecs "2026-11-05"))
        (extras (listLength (ofKind (forms) ":extra")))]
    (do (assert (stringStartsWith? r "(:trialReport :taxonomy trialStall-v1 :date \"2026-11-05\" :runs 29 :merged 1 :unclassified 0 :partial 0 :pinBroken 1 ") (str "report head: " r))
        (assert (stringContains? r "(:alias \"hzQwen3827b\" :cells 8 :merged 1 ") (str "Qwen cells: " r))
        (assert (stringContains? r "(:alias \"ifmIfmK2Horizon375bA23b\" :cells 11 :merged 0 ") (str "Ifm cells: " r))
        (assert (stringContains? r "(:alias \"nimNvidiaNemotron35SuperVl120bA12b\" :cells 9 :merged 0 ") (str "Nim cells without the pinBroken one: " r))
        (assert (stringContains? r ":insert ((:hint 5) (:tool 4) (:limit 2) (:harness 12) (:task 3) (:model 2) (:none 1))") (str "insert totals: " r))
        (assert (stringContains? r "(:class wReadLoop :n 1 :insert hint :models (\"nimNvidiaNemotron35SuperVl120bA12b\") :exemplar \"T1-Nim-readloop\")") (str "byClass row: " r))
        (assert (stringContains? r ":unclassifiedWhy ())") (str "no unclassified reasons: " r))
        (assert (stringContains? all (str ":runs " (stringFromInt64 (+ 29 extras)) " :merged 1 :unclassified 15 :partial 29 :pinBroken 2 :pinUnknown 1 ")) (str "full report counts: " all))
        (assert (stringContains? all "(:why \"readStreak without :cause and without op evidence\" :n 2)") (str "reasons grouped: " all))
        true))

fn ! testRecordsOf -> Bool
  (let [(text (str "(:t :unit \"A\" :from writing :to ready :stage write :model \"m\" :verdict \"fail: cut \\\" :ms 1)\n"
                   "(:t :unit \"B\" :from ready :to writing :stage claim :verdict \"admitted\")\n"
                   "(:wip :unit \"A\" :reason \"stalled\")\n"
                   "(:t :unit \"C\" :from writing :to gating :stage write :model \"m\" :verdict \"written\")\n"
                   "(:trialRun :id \"R1\"\n  :stages ((:write :ok true :sig \"written\")))\n"))
        (recs (ta/recordsOf text))
        (ids (map (fn [(x rd/SExpr)] -> String (str (field x ":id") (field x ":unit"))) recs))]
    (do (assert (= (listLength recs) 3) (str "a trialRun and two write rows: " (stringJoin ids " ")))
        (assert (listContains? ids "C") "a row after a cut string is still read")
        (assert (not (listContains? ids "B")) "a claim row is not a write row")
        (assert (listContains? ids "R1") "a trialRun spanning lines is read")
        true))

fn ! runTests -> Bool
  (do (assert (testExtras) "H1, unknown shapes, node2 records and rows map as expected")
      (assert (testClasses) "one fixture per class maps to its class and insert")
      (assert (testPrecedence) "precedence swaps that a fixture pins go red")
      (assert (testReport) "report counts by model, class and insert")
      (assert (testRecordsOf) "file reading: write rows per line, trialRun forms across lines")
      true)
