(module asl/packages/asl-compiler/tests/wasmLoweringTest :x [testCodegenDynamicExecution! testLoweringInvariants runTests] :i [(asl-parser/ast :a a) (asl-compiler/wasm :a w) (tools/nativeTest :a nt)])

fn ! testCodegenDynamicExecution! -> Bool
  (let [(path "asl/packages/asl-compiler/tests/wasmCodegenTest.asl") (built (nt/prepare path (nt/fingerprint)))]
    (mt built.binary
      ((none) (do (assert false (str "wasmCodegenTest.asl builds natively: " built.reason)) false))
      ((some bin)
        (let [(run (nt/runProc (list bin) (some (nt/withEnvOverrides! (list "ASL_ASSERT_REPORT=1" "ASL_PRELUDE=asl/host/out/prelude.asl")))))
              (v (nt/verdictOf path run.exitCode run.stderr))]
          (do
            (assert (= v.exit 0) (str "wasmCodegenTest must exit 0: " v.line))
            (refute (!= v.exit 0) "wasmCodegenTest must not fail")
            (assert (stringContains? v.line "assertion(s) executed") "wasmCodegenTest must report executed assertions")
            (assert (stringContains? v.line "refutation(s) executed") "wasmCodegenTest must report executed refutations")
            (refute (stringContains? v.line "ASL_ASSERTION_FAILURE") "wasmCodegenTest must not fail assertions")
            true)))))

fn testLoweringInvariants -> Bool
  (let [(src "(df sub [(x I64) (y I64)] -> I64 (- x y))") (parsed (a/parse src))] (mt parsed ((ok forms) (let [(idxMap (w/buildFunctionTypeIndex forms)) (fnNode (optionOr (listHead (fold (fn [(acc (List a/DefunNode)) (f a/TopForm)] (mt f ((topDefun d) (listAppend acc (list d))) (else acc))) (list) forms)) (a/DefunNode :name "" :typeVars (list) :isExported false :effect false :params (list) :retType "I64" :docstring "" :body (list)))) (fnBody (w/lowerAstFunction fnNode idxMap)) (modBytes (w/lowerAstTopForms forms)) (hdr (w/wasmMagicHeader))] (assert (= (optionOr (mapGet idxMap "sub") -1) 0) "sub function index must be 0") (refute (= (optionOr (mapGet idxMap "sub") -1) -1) "sub function index must be present in map") (assert (> (listLength fnBody) 5) "lowerAstFunction must emit non-empty body") (assert (= (optionOr (listSlice modBytes 0 8) (list)) hdr) "Module must start with Wasm magic header") (refute (listEmpty? modBytes) "Module bytecode must not be empty") (assert (> (listLength modBytes) 25) "Module bytecode length must exceed header + section overhead") true)) ((err _) false)))

fn wasmTopExprProbeSource -> Str
  "(module wasmTopExprProbe :x [main] :i [(asl-parser/ast :a a) (asl-compiler/wasm :a w)])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (mt (a/parse \"(df f [] -> I64 1) (f)\")\n    ((ok forms) (let [(bytes (w/lowerAstTopForms forms))] (do (println (str (listLength bytes))) (ok 0))))\n    ((err _) (ok 1)))\n"

fn ! testTopExprNotSilentlyDropped! -> Bool
  (let [(probePath "asl/packages/asl-compiler/tests/tmpWasmTopExprProbe.asl")
        (wRes (fileWrite probePath (wasmTopExprProbeSource)))
        (built (nt/prepareRun probePath (nt/fingerprint)))]
    (do (assert (ok? wRes) "probe source must write")
        (mt built.binary
          ((none) (do (assert false (str "probe builds natively: " built.reason)) (let [(_ (pathRemove probePath))] false)))
          ((some bin)
            (let [(res (processRun bin))
                  (rmRes (pathRemove probePath))]
              (do (assert (!= res.exitCode 0) (str "lowerAstTopForms on a bare top-level expression must fail, not silently drop it; got exit " (stringFromInt64 res.exitCode)))
                  (refute (= res.exitCode 0) "must not exit 0 when a top-level expression is present")
                  (assert (stringContains? res.stderr "ERR_WASM_TOPLEVEL_EXPR") (str "failure must name the error, got stderr: " res.stderr))
                  (assert (ok? rmRes) "probe source must be removed")
                  true))))))

fn ! runTests -> Bool
  (do (assert (testCodegenDynamicExecution!) "testCodegenDynamicExecution must pass") (assert (testLoweringInvariants) "testLoweringInvariants must pass") (assert (testTopExprNotSilentlyDropped!) "testTopExprNotSilentlyDropped must pass") true)
