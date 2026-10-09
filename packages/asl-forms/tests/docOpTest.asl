(module asl-forms/tests/docOpTest
  :x [runTests]
  :i [(asl-forms/kernel :a k) (asl-forms/ops :a ops) (asl-forms/docOp :a doc) (asl-forms/gate :a g)])

fn ! sandboxDir! -> String
  (stringTrim (processRun "mktemp -d").stdout)

fn ! buildSandbox! -> String
  (let [(dir (sandboxDir!))
        (made1 (processRun (str "mkdir -p '" dir "/asl/packages/fxpkg/src'")))
        (made2 (ok? (fileWrite (str dir "/asl/packages/fxpkg/src/thing.asl") "(module asl-replay/fx/thing :x [addOne] :i [])\n\nfn addOne a: Int64 -> Int64\n  (+ a 1)\n")))
        (made3 (ok? (fileWrite (str dir "/asl/packages/fxpkg/doc.asn") "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#addOne\" :text \"Adds one to a\")\n")))]
    (do (assert (= made1.exitCode 0) "sandbox src dir made") (assert made2 "sandbox source written") (assert made3 "sandbox ledger written") dir))

fn ! cleanup! dir: String -> Bool
  (do (assert (= (processRun (str "rm -rf '" dir "'")).exitCode 0) "sandbox removed") true)

fn testDocStepSymbolHit! -> Bool
  (let [(dir (buildSandbox!))
        (out (doc/docStep! dir 1 (mapSet (mapSet (mapEmpty) "symbol" "asl/packages/fxpkg/src/thing.asl#addOne") "op" "doc")))]
    (do
      (assert (= out.errCount 0) "symbol hit does not error")
      (assert (stringContains? (stringJoin out.lines " ") "Adds one to a") "docStep! recovers the ledgered text for a hit")
      (cleanup! dir)))

fn testDocStepSymbolMiss! -> Bool
  (let [(dir (buildSandbox!))
        (out (doc/docStep! dir 1 (mapSet (mapEmpty) "symbol" "asl/packages/fxpkg/src/thing.asl#noSuchFn")))]
    (do
      (assert (= out.errCount 0) "symbol miss does not error")
      (assert (stringContains? (stringJoin out.lines " ") ":found false") "docStep! reports a clean miss")
      (cleanup! dir)))

fn testDocStepFile! -> Bool
  (let [(dir (buildSandbox!))
        (out (doc/docStep! dir 1 (mapSet (mapEmpty) "file" "asl/packages/fxpkg/src/thing.asl")))]
    (do
      (assert (= out.errCount 0) "file listing does not error")
      (assert (stringContains? (stringJoin out.lines " ") "addOne") "docStep! lists the file's rows")
      (cleanup! dir)))

fn testDocStepMissingArg! -> Bool
  (let [(out (doc/docStep! "." 1 (mapEmpty)))]
    (do
      (assert (= out.errCount 1) "doc with neither :symbol nor :file is rejected")
      (assert (stringContains? (stringJoin out.lines " ") "ERR_MISSING_ARG") "the rejection names the missing argument")
      true))

fn testRunStepDispatchesDoc! -> Bool
  (let [(dir (buildSandbox!))
        (form (str "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#addOne\")"))
        (out (ops/runStep! dir 1 form))]
    (do
      (assert (= out.errCount 0) "ops/runStep! routes the doc op without error")
      (assert (stringContains? (stringJoin out.lines " ") "Adds one to a") "the step line carries the recovered text, proving ops.asl's doc branch is wired")
      (cleanup! dir)))

fn ! externalDocRun! root: String form: String -> g/RunOut
  (let [(repo (resultOr (realPath ".") ""))
        (host (k/joinPath repo "asl/host/out/asl-host"))
        (mainPath (k/joinPath repo "asl/packages/asl-forms/src/main.asl"))]
    (g/runArgv! (list host "run" mainPath "--root" root form) (some repo) (none) 10000 0))

fn testCliRoundTrip! -> Bool
  (let [(dir (buildSandbox!))
        (out (externalDocRun! dir "(:doc :symbol \"asl/packages/fxpkg/src/thing.asl#addOne\")"))]
    (do
      (assert (= out.code 0) "the real asl-host CLI dispatch for (:doc) exits zero")
      (assert (stringContains? out.out "Adds one to a") "the CLI round trip through main.asl and tools.asn recovers the ledgered text")
      (cleanup! dir)))

fn ! runTests -> Bool
  (do
    (assert (testDocStepSymbolHit!) "testDocStepSymbolHit!")
    (assert (testDocStepSymbolMiss!) "testDocStepSymbolMiss!")
    (assert (testDocStepFile!) "testDocStepFile!")
    (assert (testDocStepMissingArg!) "testDocStepMissingArg!")
    (assert (testRunStepDispatchesDoc!) "testRunStepDispatchesDoc!")
    (assert (testCliRoundTrip!) "testCliRoundTrip!")
    true)
