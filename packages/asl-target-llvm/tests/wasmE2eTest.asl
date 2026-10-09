(module asl-target-llvm/tests/wasmE2eTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/wasmLink :a wl)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! toolPath name: String -> String
  (stringReplace (sh (str "command -v " name " 2>/dev/null")).stdout "\n" "")

fn ! node -> String
  (toolPath "node")

fn ! llc -> String
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " (quote c))).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/llc" "/usr/local/opt/llvm/bin/llc" "/usr/lib/llvm-23/bin/llc" "/usr/lib/llvm-22/bin/llc" "/usr/lib/llvm-21/bin/llc" "/usr/lib/llvm-20/bin/llc" "/usr/lib/llvm-19/bin/llc" "/usr/lib/llvm-18/bin/llc")))]
    (mt (listHead known) ((some c) c) ((none) (toolPath "llc"))))

fn ! linker -> String
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " (quote c))).exitCode 0))
                        (list "/opt/homebrew/bin/wasm-ld" "/opt/homebrew/opt/lld/bin/wasm-ld" "/usr/local/bin/wasm-ld" "/usr/local/opt/lld/bin/wasm-ld" "/usr/bin/wasm-ld" "/usr/lib/llvm-23/bin/wasm-ld" "/usr/lib/llvm-22/bin/wasm-ld" "/usr/lib/llvm-21/bin/wasm-ld" "/usr/lib/llvm-20/bin/wasm-ld" "/usr/lib/llvm-19/bin/wasm-ld" "/usr/lib/llvm-18/bin/wasm-ld")))]
    (mt (listHead known) ((some c) c) ((none) (toolPath "wasm-ld"))))

fn quote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! emitLinked facts: libc/TripleFacts tf: target/TargetFacts source: String -> (Result String (List irTy/IrDiag))
  (mt (lk/lowerSourceLinked! source)
    ((err ds) (err ds))
    ((ok m) (llvm/emitLlvmProgramForTarget facts tf m "main")))

fn text r: (Result String (List irTy/IrDiag)) -> String
  (mt r ((ok s) s) ((err ds) (str "LOWERING ERROR: " (diag ds))))

fn diag ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) ds) "; ")

fn ! compile name: String part: String body: String work: String -> Bool
  (let [(ll (str work "/" part ".ll")) (obj (str work "/" part ".o"))]
    (do
      (assert (ok? (fileWrite ll body)) (str name " writes " part " IR"))
      (let [(out (sh (str (quote (llc)) " -mtriple=wasm32-unknown-unknown -mattr=+bulk-memory -filetype=obj " (quote ll) " -o " (quote obj))))]
        (assert (= out.exitCode 0) (str name " compiles " part ": " out.stderr)))
      true))

fn ! nativeRun name: String source: String work: String -> ProcessOutput
  (let [(un (sh "uname -s -m"))
        (triple (gr/hostTriple un.stdout))
        (facts (optionOr (libc/libcFacts triple) (libc/emptyTripleFacts)))
        (nativeText (emitLinked facts (target/nativeTargetFacts triple) source))
        (ll (str work "/" name ".native.ll"))
        (bin (str work "/" name ".native"))]
    (do
      (assert (some? (libc/libcFacts triple)) (str name " has native facts for " triple))
      (assert (ok? nativeText) (str name " native lowering: " (mt nativeText ((ok _) "ok") ((err ds) (diag ds)))))
      (assert (ok? (fileWrite ll (text nativeText))) (str name " writes native IR"))
      (let [(linked (sh (str "/usr/bin/cc -Wno-override-module -x ir " (quote ll) " -x none asl/host/out/libaslrt.a -lm -o " (quote bin))))]
        (assert (= linked.exitCode 0) (str name " native link: " linked.stderr))
        (sh (quote bin)))))

fn ! runCase name: String -> Bool
  (let [(path (str "asl/packages/asl-target-llvm/tests/fixtures/wasmE2e/" name ".asl"))
        (read (fileRead path))
        (source (mt read ((ok s) s) ((err e) (str "FIXTURE READ ERROR: " e))))
        (work (str "/tmp/asl-wasm-e2e/" name))
        (mainText (emitLinked (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)) (target/wasm32TargetFacts) source))
        (runtime (llvm/emitLlvmRuntimeForTarget (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)) (target/wasm32TargetFacts)))
        (support (llvm/emitLlvmSupportForTarget (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)) (target/wasm32TargetFacts)))
        (wasm (str work "/main.wasm"))]
    (do
      (assert (ok? read) (str name " reads fixture"))
      (assert (= (sh (str "mkdir -p " (quote work))).exitCode 0) (str name " creates work directory"))
      (assert (ok? mainText) (str name " wasm lowering: " (mt mainText ((ok _) "ok") ((err ds) (diag ds)))))
      (assert (ok? runtime) (str name " emits wasm runtime: " (mt runtime ((ok _) "ok") ((err ds) (diag ds)))))
      (assert (ok? support) (str name " emits wasm support: " (mt support ((ok _) "ok") ((err ds) (diag ds)))))
      (assert (compile name "main" (text mainText) work) (str name " main object"))
      (assert (compile name "runtime" (text runtime) work) (str name " runtime object"))
      (assert (compile name "support" (text support) work) (str name " support object"))
      (let [(exports (if (= name "gcLoop") (list "gcAslState") (list)))
            (linked (wl/linkWasm32 (linker) (list (str work "/main.o") (str work "/runtime.o") (str work "/support.o")) exports wasm))]
        (assert (= linked.exitCode 0) (str name " links without undefined imports: " linked.stderr)))
      (let [(imports (wl/wasmImports (node) wasm))]
        (assert (ok? imports) (str name " import section reads: " (mt imports ((ok _) "ok") ((err e) e)))))
      (let [(native (nativeRun name source work))
            (gcCheck (if (= name "gcLoop") " --assert-gc" ""))
            (wasmRun (sh (str (quote (node)) " tools/wasm/run.mjs " (quote wasm) gcCheck)))]
        (do
          (assert (= wasmRun.stderr native.stderr) (str name " stderr bytes equal native; wasm=" wasmRun.stderr " native=" native.stderr))
          (assert (= wasmRun.stdout native.stdout) (str name " stdout bytes equal native; wasm=" wasmRun.stdout " native=" native.stdout))
          (assert (= wasmRun.exitCode native.exitCode) (str name " exit matches native; wasm=" wasmRun.exitCode " native=" native.exitCode))
          (if (= name "list")
            (do
              (assert (= native.stdout "54") "list fixture prints its computed lookup/length result")
              (assert (= native.exitCode 4) "list fixture native exit is 4")
              true)
            (if (= name "gcLoop")
              (do
                (assert (= native.stdout "3088890") "gcLoop executes 200000 unique allocations")
                true)
              (if (= name "map")
              (do
                (assert (= native.stdout "15") "map fixture prints its computed update/missing-key result")
                (assert (= native.exitCode 15) "map fixture native exit is 15")
                true)
              true)))))))

fn ! missingCollectorRejected work: String -> Bool
  (let [(programLl (str work "/missing-collector.ll"))
        (programObj (str work "/missing-collector.o"))
        (output (str work "/missing-collector.wasm"))
        (programText "declare ptr @asl_alloc(i32, i64)\ndefine void @_start() {\n  %p = call ptr @asl_alloc(i32 0, i64 8)\n  ret void\n}\n")]
    (do
      (assert (ok? (fileWrite programLl programText)) "writes a program requiring the collector ABI")
      (let [(compiled (sh (str (quote (llc)) " -mtriple=wasm32-unknown-unknown -filetype=obj " (quote programLl) " -o " (quote programObj))))]
        (do
          (assert (= compiled.exitCode 0) (str "compiles missing-collector probe: " compiled.stderr))
          (let [(linked (wl/linkWasm32 (linker) (list programObj) (list) output))]
            (do
              (assert (not (= linked.exitCode 0)) "wasm link rejects a missing collector entry")
              (assert (stringContains? (str linked.stderr linked.stdout) "asl_alloc") (str "link failure identifies the missing collector entry: " linked.stderr linked.stdout))
              true))))))

fn ! absentCapabilityRejected -> Bool
  (let [(path "asl/packages/asl-target-llvm/tests/fixtures/wasmE2e/tcpListen.asl")
        (read (fileRead path))]
    (do
      (assert (ok? read) "reads tcpListen absent-capability fixture")
      (mt (emitLinked (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts)) (target/wasm32TargetFacts) (mt read ((ok s) s) ((err e) (str "FIXTURE READ ERROR: " e))))
        ((ok _) false)
        ((err ds) (listAny? (fn [(d irTy/IrDiag)] -> Bool (and (= d.code "ERR_CAPABILITY_ABSENT") (stringContains? d.message "tcpListen"))) ds)))))

fn ! runTests -> Bool
  (let [(runtimeTest (sh (str (quote (node)) " tools/wasm/run.mjs --self-test")))
        (work "/tmp/asl-wasm-e2e")]
    (do
      (assert (= runtimeTest.exitCode 0) (str "runtime self-test: " runtimeTest.stderr))
      (assert (= (sh (str "mkdir -p " (quote work))).exitCode 0) "creates wasm acceptance work directory")
      (assert (missingCollectorRejected work) "wasm link rejects missing collector symbols")
      (assert (absentCapabilityRejected) "tcpListen reports ERR_CAPABILITY_ABSENT during wasm target lowering")
      (assert (runCase "hello") "hello compares wasm to native")
      (assert (runCase "arithmetic") "arithmetic compares wasm to native, including status 42")
      (assert (runCase "string") "string compares wasm to native")
      (assert (runCase "list") "list compares wasm to native, including status 4")
      (assert (runCase "map") "map compares wasm to native, including status 15")
      (assert (runCase "gcLoop") "GC-heavy loop compares wasm to native")
      (assert (runCase "trap") "trap compares wasm to native nonzero status")
      true))
