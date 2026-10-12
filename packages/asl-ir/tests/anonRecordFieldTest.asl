(module asl-ir/tests/anonRecordFieldTest :x [runTests] :i [(tools/nativeTest :a nt) (tools/fleet/run :a fr)])

fn ! nativeEval expr: String -> fr/Done
  (let [(probePath "asl/packages/asl-ir/tests/tmpAnonRecordProbe.asl")
        (src (str "(module anonRecordProbe :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println (str " expr "))\n      (ok 0))\n"))
        (wRes (fileWrite probePath src))]
    (do
      (assert (ok? wRes) "probe source must write")
      (let [(built (nt/prepareRun probePath (nt/fingerprint)))]
        (mt built.binary
          ((none) (do (assert false (str "probe builds natively: " built.reason)) (fr/Done :idx 0 :exit 1 :out "" :ms 0 :verdict "buildFailed")))
          ((some bin) (let [(res (fr/runOne (fr/job (list bin) "." (fr/childEnv (list))))) (_ (pathRemove probePath))] res))))))

fn ! testSimpleFieldGet -> Bool
  (let [(ran (nativeEval "(stringFromInt64 (let [(r {:a 1})] r.a))"))]
    (do
      (assert (= ran.exit 0) (str "a single-field anonymous record builds and runs natively: " ran.out))
      (assert (= ran.out "1\n") (str "{:a 1}.a reads back the field, got " ran.out))
      true))

fn ! testNestedFieldGet -> Bool
  (let [(ran (nativeEval "(stringFromInt64 (let [(r {:a 1 :b {:c 2}})] (+ r.a r.b.c)))"))]
    (do
      (assert (= ran.exit 0) (str "a nested anonymous record builds and runs natively: " ran.out))
      (assert (= ran.out "3\n") (str "{:a 1 :b {:c 2}} reads r.a and r.b.c through the chain, got " ran.out))
      true))

fn ! testMultipleStringFields -> Bool
  (let [(ran (nativeEval "(let [(r {:workerId \"w1\" :tier \"pro\"})] (str r.workerId \"/\" r.tier))"))]
    (do
      (assert (= ran.exit 0) (str "a multi-field string record builds and runs natively: " ran.out))
      (assert (= ran.out "w1/pro\n") (str "{:workerId \"w1\" :tier \"pro\"} reads both fields, got " ran.out))
      true))

fn ! testRecordInListElement -> Bool
  (let [(ran (nativeEval "(stringFromInt64 (let [(xs (list {:n 10} {:n 20}))] (+ (optionOr (listGet xs 0) {:n 0}).n (optionOr (listGet xs 1) {:n 0}).n)))"))]
    (do
      (assert (= ran.exit 0) (str "anonymous records inside a list build and run natively: " ran.out))
      (assert (= ran.out "30\n") (str "fields read off list elements sum correctly, got " ran.out))
      true))

fn ! testNonKeywordBraceStaysMap -> Bool
  (let [(ran (nativeEval "(stringFromInt64 (optionOr (mapGet {\"x\" 9} \"x\") -1))"))]
    (do
      (assert (= ran.exit 0) (str "a non-keyword-keyed brace group still builds as a map: " ran.out))
      (assert (= ran.out "9\n") (str "{\"x\" 9} stays a mapGet-able map, not a record, got " ran.out))
      true))

fn ! runTests -> Bool
  (do
    (assert (testSimpleFieldGet) "a one-field anonymous record literal supports .field natively")
    (assert (testNestedFieldGet) "nested anonymous record literals support chained .field.field natively")
    (assert (testMultipleStringFields) "an anonymous record with several string fields reads each one back")
    (assert (testRecordInListElement) "anonymous records built inside a list literal still support .field")
    (assert (testNonKeywordBraceStaysMap) "a brace group with a non-keyword key still desugars to a dynamic map")
    true)
