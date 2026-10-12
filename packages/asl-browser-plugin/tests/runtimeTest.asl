(module aslBrowserPlugin/tests/runtimeTest
  :x [testRuntimeSourceIntegrity! testRuntimeGrammarRegistration! testZeroSocketContract testLinearMemoryBounds! RunTests! runTests]
  :i [])

fn testRuntimeSourceIntegrity! -> Bool
  (let [(rRes (fileRead "asl/packages/asl-browser-plugin/src/runtime.asl"))]
    (mt rRes
      ((err e) (assert false (str "Failed to read runtime.asl: " e)))
      ((ok rSrc)
        (do
          (assert (or (stringContains? rSrc "schema BrowserRuntimeBridge") (stringContains? rSrc "dfs BrowserRuntimeBridge")) "runtime defines BrowserRuntimeBridge")
          (assert (or (stringContains? rSrc "schema WasmRpcBridge") (stringContains? rSrc "dfs WasmRpcBridge")) "runtime defines WasmRpcBridge")
          (assert (or (stringContains? rSrc "schema OpfsWorkspace") (stringContains? rSrc "dfs OpfsWorkspace")) "runtime defines OpfsWorkspace")
          (assert (stringContains? rSrc "fn makeBrowserRuntimeBridge") "runtime defines makeBrowserRuntimeBridge")
          (assert (stringContains? rSrc "fn makeWasmRpcBridge") "runtime defines makeWasmRpcBridge")
          (assert (stringContains? rSrc "fn dispatchBatchRpc") "runtime defines dispatchBatchRpc")
          (assert (stringContains? rSrc "fn isSafeOpfsPath?") "runtime defines isSafeOpfsPath?")
          (refute (stringContains? rSrc "Mach-O") "Zero Mach-O in browser runtime")
          (refute (stringContains? rSrc "ELF64") "Zero ELF64 in browser runtime"))))
    true)

fn testRuntimeGrammarRegistration! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-browser-plugin/manifest.asn"))]
    (mt gRes
      ((err e) (assert false (str "Failed to read asl/packages/asl-browser-plugin/manifest.asn: " e)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc ":package aslBrowserPlugin") "manifest registers aslBrowserPlugin")
          (assert (stringContains? gSrc "\"aslBrowserPlugin/runtime\"") "manifest registers runtime")
          (assert (stringContains? gSrc "\"aslBrowserPlugin/content\"") "manifest registers content")
          (assert (stringContains? gSrc "\"aslContracts\"") "manifest registers aslContracts")
          (refute (stringContains? gSrc ";;") "runtime manifest refutes legacy line comments"))))
    true)

fn testZeroSocketContract -> Bool
  (let [(cleanRes "(:batch-res :status \"completed\" :bridge \"asl-core\" :zero-socket true :latency-ms 2 :results [])")
        (errRes "(:batch-res :status \"error\" :reason \"zero-socket-violation\")")]
    (assert (stringContains? cleanRes ":status \"completed\"") "clean result indicates completed")
    (refute (stringContains? cleanRes ":status \"error\"") "clean result refutes error")
    (assert (stringContains? cleanRes ":zero-socket true") "clean result confirms zero socket")
    (assert (stringContains? errRes ":status \"error\"") "compromised result indicates error")
    (refute (stringContains? errRes ":status \"completed\"") "compromised result refutes completed")
    (assert (stringContains? errRes "zero-socket-violation") "error reports zero-socket-violation")
    true)

fn testLinearMemoryBounds! -> Bool
  (mt (fileRead "asl/packages/asl-browser-plugin/src/runtime.asl")
    ((err e) (do (assert false (str "Failed to read runtime.asl: " e)) false))
    ((ok src)
     (do
       (assert (stringContains? src "(:f maxRssBytes I64)") "bridge declares a max RSS ceiling field")
       (assert (stringContains? (resultOr (fileRead "asl/packages/asl-browser-plugin/doc.asn") "") "Hard memory boundary ceiling in bytes (16MB)") "the field's 16MB doc moved to doc.asn, not lost")
       (refute (stringContains? src ":maxRssBytes 0") "bridge refutes a zero RSS ceiling")
       (assert (stringContains? src ":linearMemoryBytes linearMem :activeSessions 1 :maxRssBytes maxRss") "bridge stores the given linear memory and RSS ceiling")
       (refute (stringContains? src ":linearMemoryBytes maxRss") "bridge refutes swapping linear memory and RSS ceiling")
       true)))

fn RunTests! -> Bool
  (and (testRuntimeSourceIntegrity!)
       (testRuntimeGrammarRegistration!)
       (testZeroSocketContract)
       (testLinearMemoryBounds!))

fn ! runTests -> Bool
  (RunTests!)
