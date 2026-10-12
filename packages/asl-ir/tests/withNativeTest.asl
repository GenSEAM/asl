(module asl-ir/tests/withNativeTest :x [runTests] :i [(tools/nativeTest :a nt) (tools/fleet/run :a fr)])

fn ! nativeEval expr: String decls: (List String) -> fr/Done
  (let [(probePath "asl/packages/asl-ir/tests/tmpWithNativeProbe.asl")
        (header (stringJoin (listAppend (list "(module withNativeProbe :x [main] :i [])") decls) "\n"))
        (src (str header "\n\nfn ! main -> (Result Int64 String)\n  (do (println " expr ")\n      (ok 0))\n"))
        (wRes (fileWrite probePath src))]
    (do
      (assert (ok? wRes) "probe source must write")
      (let [(built (nt/prepareRun probePath (nt/fingerprint)))]
        (mt built.binary
          ((none) (do (assert false (str "probe builds natively: " built.reason)) (fr/Done :idx 0 :exit 1 :out "" :ms 0 :verdict "buildFailed")))
          ((some bin) (let [(res (fr/runOne (fr/job (list bin) "." (fr/childEnv (list))))) (_ (pathRemove probePath))] res))))))

fn ! testNamedWith -> Bool
  (let [(ran (nativeEval
               "(let [(p (Point :x 1 :y 2)) (q (with p :x 9))] (list q.x q.y p.x))"
               (list "(schema Point (:f x Int64) (:f y Int64))")))]
    (do
      (assert (= ran.exit 0) (str "a with on a named schema record builds and runs natively: " ran.out))
      (assert (= ran.out "(9 2 1)\n") (str "with replaces the named field and leaves the rest and the original record alone, got " ran.out))
      true))

fn ! testAnonWith -> Bool
  (let [(ran (nativeEval "(let [(r {:k 1 :v 2}) (s (with r :v 3))] (list s.v s.k r.v))" (list)))]
    (do
      (assert (= ran.exit 0) (str "a with on an anonymous record builds and runs natively: " ran.out))
      (assert (= ran.out "(3 1 2)\n") (str "with replaces the anonymous field and leaves the rest and the original record alone, got " ran.out))
      true))

fn ! testNestedWith -> Bool
  (let [(ran (nativeEval "(let [(r {:a 1 :b 2}) (q (with (with r :a 1) :b 2))] (list q.a q.b))" (list)))]
    (do
      (assert (= ran.exit 0) (str "a with nested inside another with builds and runs natively: " ran.out))
      (assert (= ran.out "(1 2)\n") (str "the outer with sees the inner with's schema and both replacements land, got " ran.out))
      true))

fn ! testFieldReadAfterWith -> Bool
  (let [(ran (nativeEval "(stringFromInt64 (with (Point :x 1 :y 2) :x 9).x)" (list "(schema Point (:f x Int64) (:f y Int64))")))]
    (do
      (assert (= ran.exit 0) (str "a field read directly off a with result builds and runs natively: " ran.out))
      (assert (= ran.out "9\n") (str "(with p :x 9).x reads back the replaced field, got " ran.out))
      true))

fn ! testUnknownFieldIsLowerError -> Bool
  (let [(built (nt/prepareRun (let [(path "asl/packages/asl-ir/tests/tmpWithUnknownFieldProbe.asl")
                                     (_ (fileWrite path "(module withUnknownFieldProbe :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println (let [(r {:a 1})] (with r :z 2)))\n      (ok 0))\n"))]
                                 path)
                               (nt/fingerprint)))
        (bin (optionOr built.binary ""))
        (_ (pathRemove "asl/packages/asl-ir/tests/tmpWithUnknownFieldProbe.asl"))]
    (do
      (assert (stringEmpty? bin) (str "with on an unknown field is a lower-time error, not a native build: " built.reason))
      (assert (stringContains? built.reason "UNKNOWN_FIELD") (str "the diagnostic names the unknown field, got " built.reason))
      true))

fn ! runTests -> Bool
  (do
    (assert (testNamedWith) "with on a named schema record replaces a field natively")
    (assert (testAnonWith) "with on an anonymous record replaces a field natively")
    (assert (testNestedWith) "with nested inside another with resolves the inner with's schema")
    (assert (testFieldReadAfterWith) "a field read chained directly off a with result reads the replacement")
    (assert (testUnknownFieldIsLowerError) "with on a field the schema does not have fails to lower, matching host behavior")
    true)
