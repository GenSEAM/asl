(module asl-target-llvm/tests/wasmTailCallTest
  :x [runTests]
  :i [(asl-target-llvm/target :a target)
      (asl-target-llvm/wasmLink :a wl)])

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! findExecutable name: String knownLocations: (List String) -> String
  (let [(known (filter (fn [(c String)] -> Bool (= (sh (str "test -x " (shellQuote c))).exitCode 0)) knownLocations))]
    (mt (listHead known)
      ((some c) c)
      ((none)
        (let [(out (sh (str "command -v " (shellQuote name))))]
          (if (= out.exitCode 0)
            (stringReplace out.stdout "\n" "")
            "")))))

fn ! node -> String
  (findExecutable "node" (list "/opt/homebrew/bin/node" "/usr/local/bin/node" "/usr/bin/node"))

fn ! llc -> String
  (findExecutable "llc" (list "/opt/homebrew/opt/llvm/bin/llc" "/usr/local/opt/llvm/bin/llc" "/usr/lib/llvm-20/bin/llc" "/usr/lib/llvm-19/bin/llc" "/usr/lib/llvm-18/bin/llc"))

fn ! linker -> String
  (findExecutable "wasm-ld" (list "/opt/homebrew/bin/wasm-ld" "/opt/homebrew/opt/lld/bin/wasm-ld" "/usr/local/bin/wasm-ld" "/usr/lib/llvm-20/bin/wasm-ld" "/usr/lib/llvm-19/bin/wasm-ld" "/usr/lib/llvm-18/bin/wasm-ld"))

fn ! source -> (Result String String)
  (fileReadString "asl/packages/asl-target-llvm/tests/fixtures/wasmTail/tail.ll")

fn ! runTests -> Bool
  (let [(srcRes (source))
        (nodeBin (node))
        (llcBin (llc))
        (ldBin (linker))]
    (do
      (assert (ok? srcRes) "tail-call fixture exists and reads without error")
      (assert (fileExists? "tools/wasm/run.mjs") "tools/wasm/run.mjs harness exists")
      (assert (not (stringEmpty? nodeBin)) "node is installed and located dynamically")
      (assert (not (stringEmpty? llcBin)) "llc is installed and located dynamically")
      (assert (not (stringEmpty? ldBin)) "wasm-ld is installed and located dynamically")
      (assert (= (sh (str "test -x " (shellQuote nodeBin))).exitCode 0) "node binary is executable")
      (assert (= (sh (str "test -x " (shellQuote llcBin))).exitCode 0) "llc binary is executable")
      (assert (= (sh (str "test -x " (shellQuote ldBin))).exitCode 0) "wasm-ld binary is executable")
      (let [(src (resultOr srcRes ""))
            (work "/tmp/asl-wasm-tail-call")
            (input (str work "/tail.ll"))
            (wasmLl (str work "/tail-wasm.ll"))
            (nativeBin (str work "/native"))
            (obj (str work "/tail.o"))
            (wasm (str work "/tail.wasm"))
            (facts (target/wasm32TargetFacts))
            (wasmText (target/lowerLlvmText src facts))]
        (do
          (assert (stringContains? src "call i64 @selfLoop") "fixture has a self-tail call")
          (assert (stringContains? src "call i64 @oddLoop") "fixture has a mutual-tail call")
          (assert (= (sh (str "rm -rf " (shellQuote work))).exitCode 0) "clears build directory")
          (assert (ok? (dirCreate work)) "creates build directory")
          (assert (ok? (fileWrite input src)) "writes fixture")
          (assert (ok? (fileWrite wasmLl wasmText)) "lowers fixture for wasm32")
          (let [(nativeLinked (sh (str "/usr/bin/cc -O2 -x ir " (shellQuote input) " -o " (shellQuote nativeBin))))]
            (assert (= nativeLinked.exitCode 0) (str "native fixture compiles: " nativeLinked.stderr)))
          (let [(compiled (sh (str (shellQuote llcBin) " -mtriple=wasm32-unknown-unknown -mattr=+bulk-memory,+tail-call -filetype=obj " (shellQuote wasmLl) " -o " (shellQuote obj))))]
            (assert (= compiled.exitCode 0) (str "llc compiles with wasm tail-call feature: " compiled.stderr)))
          (let [(linked (wl/linkWasm32 ldBin (list obj) (list "main") wasm))]
            (assert (= linked.exitCode 0) (str "wasm link succeeds: " linked.stderr)))
          (let [(native (sh (shellQuote nativeBin)))
                (wasmRun (sh (str (shellQuote nodeBin) " tools/wasm/run.mjs " (shellQuote wasm))))]
            (do
              (assert (= native.exitCode 0) (str "native million-deep self and mutual calls complete: " native.stderr))
              (assert (= wasmRun.exitCode native.exitCode) (str "wasm exit equals native: " wasmRun.exitCode " vs " native.exitCode "; " wasmRun.stderr))
              (assert (= native.stdout "1000000 1000000\n") (str "native produces expected output: " native.stdout))
              (assert (= wasmRun.stdout native.stdout) (str "wasm stdout equals native byte for byte: wasm '" wasmRun.stdout "', native '" native.stdout "'"))
              true))))))
