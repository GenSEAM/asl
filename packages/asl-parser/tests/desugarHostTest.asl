(module asl-parser/desugarHostTest :x [runTests] :i [(indentParser :a ip) (reader :a rd) (tools/nativeTest :a nt) (tools/fleet/run :a fr)])

fn ! nativeEval expr: String -> fr/Done
  (let [(probePath "asl/packages/asl-parser/tests/tmpDesugarProbe.asl")
        (src (str "(module desugarProbe :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println (str " expr "))\n      (ok 0))\n"))
        (wRes (fileWrite probePath src))]
    (do
      (assert (ok? wRes) "probe source must write")
      (let [(built (nt/prepareRun probePath (nt/fingerprint)))]
        (mt built.binary
          ((none) (do (assert false (str "probe builds natively: " built.reason)) (fr/Done :idx 0 :exit 1 :out "" :ms 0 :verdict "buildFailed")))
          ((some bin) (let [(res (fr/runOne (fr/job (list bin) "." (fr/childEnv (list))))) (_ (pathRemove probePath))] res))))))

fn lowered src: String -> String
  (mt (ip/parseIndented src) ((ok s) (rd/renderSexpr s)) ((err e) (str "parse error: " e)))

fn ! testListDestructuringRuns -> Bool
  (let [(form (lowered "let [a b] = pair\n  (+ a b)\n")) (ran (nativeEval (str "(let [(pair (list 1 2))] " form ")")))] (do (assert (= ran.exit 0) (str "the lowering runs natively " form ": " ran.out)) (assert (= ran.out "3\n") (str "let [a b] = (list 1 2) binds the elements, got " ran.out)) true))

fn ! testThreeElementDestructuringRuns -> Bool
  (let [(form (lowered "let [x y z] = coords\n  (- (* x y) z)\n")) (ran (nativeEval (str "(let [(coords (list 3 4 5))] " form ")")))] (do (assert (= ran.out "7\n") (str "let [x y z] = (list 3 4 5) binds each index in order, got " ran.out " from " form)) true))

; (:m :ref STD-IDIOMS-20261018 :do "desugarTry's raw expansion (mt EXPR ((ok __v) __v) ((err __e) (err __e))) only type-checks today when the scrutinee is a literal (err ...): __v then binds a still-unconstrained success type, which unifies loosely against the sibling err-arm's Result type (testTryErrRuns below, unchanged, stays a runs test). A literal (ok ...) scrutinee fixes __v's type concretely (e.g. Int64), which then genuinely disagrees with the err-arm's Result type under plain match-arm unification; typing this properly needs the enclosing function's own return type threaded in as an early-return exemption, exactly what the already-declared but never-constructed fTryInner/fmTryStep frame (asl-checker/src/check.asl) is for. Parked at STD-IDIOMS-20261018, not this unit (team-lead keeps x? as the stdlib's Result-propagation form); until then this case is a rejection probe, not a runs test")
fn ! testTryOkRejectedToday -> Bool
  (let [(form (rd/renderSexpr (ip/desugarTry (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "42"))))))
        (probePath "asl/packages/asl-parser/tests/tmpDesugarProbe.asl")
        (src (str "(module desugarProbe :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println (str " form "))\n      (ok 0))\n"))
        (wRes (fileWrite probePath src))
        (built (nt/prepareRun probePath (nt/fingerprint)))
        (_ (pathRemove probePath))]
    (do
      (assert (ok? wRes) "probe source must write")
      (mt built.binary
        ((some _) (assert false (str "the raw try-ok lowering " form " must still be rejected (fTryInner is unwired): it built successfully instead")))
        ((none) (do
                  (assert (stringContains? built.reason "ERR_TYPE_MISMATCH match arm, branches disagree") (str "expected a match-arm-disagree rejection, got " built.reason))
                  (assert (stringContains? built.reason "expected an integer, found (Result _ _)") (str "expected the specific ok-vs-err arm mismatch text, got " built.reason)))))
      true))

fn ! testTryErrRuns -> Bool
  (let [(form (rd/renderSexpr (ip/desugarTry (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "\"fail\"")))))) (ran (nativeEval form))] (do (assert (= ran.exit 0) (str "the try lowering runs natively " form ": " ran.out)) (assert (= ran.out "(err \"fail\")\n") (str "try of (err \"fail\") yields the error, got " ran.out)) true))

fn ! runTests -> Bool
  (do (assert (testListDestructuringRuns) "list destructuring runs natively")
      (assert (testThreeElementDestructuringRuns) "three-element destructuring runs natively")
      (assert (testTryOkRejectedToday) "try ok's raw lowering is rejected today (STD-IDIOMS-20261018)")
      (assert (testTryErrRuns) "try err runs natively")
      true)
