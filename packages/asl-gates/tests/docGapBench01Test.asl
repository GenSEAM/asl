(module asl-gates/tests/docGapBench01Test
  :x [runTests]
  :i [])

fn docPath -> String
  "asl/doc/bench.asn"

fn baselinePath -> String
  "asl/packages/asl-gates/tests/docCoverageBaseline.asn"

fn linesOf path: String -> (List String)
  (stringLines (resultOr (fileReadString path) ""))

fn names -> (List String)
  (list "TrialResult" "PolicyEvaluation" "makeTrialResult" "makePolicyEvaluation" "evaluateTrialConsistency")

fn docRow? lines: (List String) name: String -> Bool
  (listAny? (fn [(l String)] -> Bool (stringContains? l (str "(:doc :symbol \"asl/bench/attentionProsthesis.asl#" name "\" :text "))) lines)

fn gapLine? lines: (List String) name: String -> Bool
  (listAny? (fn [(l String)] -> Bool (stringContains? l (str "(:gap \"asl/bench/attentionProsthesis.asl#" name "\")"))) lines)

fn missingDocs lines: (List String) -> (List String)
  (filter (fn [(n String)] -> Bool (not (docRow? lines n))) (names))

fn remainingGaps lines: (List String) -> (List String)
  (filter (fn [(n String)] -> Bool (gapLine? lines n)) (names))

fn ! runTests -> Bool
  (let [(docs (linesOf (docPath)))
        (base (linesOf (baselinePath)))
        (missing (missingDocs docs))
        (gaps (remainingGaps base))]
    (do
      (assert (> (listLength docs) 0) (str "asl/doc/bench.asn loads from " (docPath)))
      (assert (> (listLength base) 0) (str "the coverage baseline loads from " (baselinePath)))
      (assert (listEmpty? missing) (str "every named export has a (:doc) row in asl/doc/bench.asn; missing: " (stringJoin missing " ")))
      (assert (listEmpty? gaps) (str "every named export's (:gap) row left docCoverageBaseline.asn; still present: " (stringJoin gaps " ")))
      true))
