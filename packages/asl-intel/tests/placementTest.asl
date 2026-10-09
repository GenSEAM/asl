(module aslIntel/tests/placementTest :x [runTests] :i [(placement :a p)])

fn runTests -> Bool
  (let [(repRec (p/auditFilePlacement "schema.asl" ":record Point (:f x I64) (:f y I64)"))
        (repPlain (p/auditFilePlacement "math.asl" "fn add a: I64 b: I64 -> I64\n  (+ a b)"))]
    (assert (stringContains? repRec "recommended-layout \"columnar\"") "Record file must recommend columnar")
    (assert (stringContains? repPlain "recommended-layout \"aos\"") "Plain file must recommend aos")
    (assert (stringContains? repPlain "estimated-savings \"0.0%\"") "Plain file must have 0% savings")
    (assert (stringContains? repRec ":status \"analyzed\"") "Report must carry analyzed status")
    true)
