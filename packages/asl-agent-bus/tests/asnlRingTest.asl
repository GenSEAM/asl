(module agent-bus/asnlRingTest
  :x [testRingSourceIntegrity! testGrammarRegistration! testSyntaxAndDelimiterGate! testRuntimePointerPassing! runTests RunTests!]
  :i [])

fn testRingSourceIntegrity! -> Bool
  (let [(rRes (fileRead "asl/packages/asl-agent-bus/src/asnlRing.asl"))]
    (mt rRes
      ((err e) (assert false (str "Failed to read asl/packages/asl-agent-bus/src/asnlRing.asl: " e)))
      ((ok src)
        (do
          (assert (or (stringContains? src "schema AsnlPointer") (stringContains? src "dfs AsnlPointer")) "asnlRing defines AsnlPointer struct")
          (assert (or (stringContains? src "schema AsnlRingBuffer") (stringContains? src "dfs AsnlRingBuffer")) "asnlRing defines AsnlRingBuffer struct")
          (assert (stringContains? src "fn makeRingBuffer") "asnlRing defines makeRingBuffer constructor")
          (assert (stringContains? src "fn isRingEmpty?") "asnlRing defines isRingEmpty? predicate")
          (assert (stringContains? src "fn isRingFull?") "asnlRing defines isRingFull? predicate")
          (assert (stringContains? src "fn ringPush") "asnlRing defines ringPush frame insertion")
          (assert (stringContains? src "fn ringPushPointer") "asnlRing defines ringPushPointer zero-copy insertion")
          (assert (stringContains? src "fn ringPop") "asnlRing defines ringPop frame removal")
          (assert (stringContains? src "fn ringPeek") "asnlRing defines ringPeek head inspection")
          (assert (stringContains? src "fn ringDrain") "asnlRing defines ringDrain batch drain")
          (assert (stringContains? src "fn formatRingStats") "asnlRing defines formatRingStats telemetry")
          (refute (stringContains? src "Mach-O") "Zero Mach-O binary emission in agent-bus")
          (refute (stringContains? src "ELF64") "Zero ELF64 binary emission in agent-bus"))))
    true)

fn testGrammarRegistration! -> Bool
  (let [(gRes (fileRead "asl/packages/asl-agent-bus/manifest.asn"))]
    (mt gRes
      ((err e) (assert false (str "Failed to read asl/packages/asl-agent-bus/manifest.asn: " e)))
      ((ok gSrc)
        (do
          (assert (stringContains? gSrc "asl-agent-bus/asnlRing") "manifest registers asnlRing module")
          (refute (stringContains? gSrc "asnl_ring") "Strict camelCase in manifest registration"))))
    true)

fn testSyntaxAndDelimiterGate! -> Bool
  (let [(cmd "./bin/asl check asl/packages/asl-agent-bus/src/asnlRing.asl")
        (res (processRun cmd))]
    (assert (= res.exitCode 0) "asl check exits 0 on asnlRing.asl")
    (assert (stringContains? res.stdout "(:check :id balance :status :passed)") "asl check confirms verified delimiter balance")
    (refute (stringContains? res.stdout "Syntax error") "Zero syntax errors in asnlRing.asl")
    (refute (stringContains? res.stdout "unbalanced") "Zero unbalanced delimiters in asnlRing.asl")
    true)

fn testRuntimePointerPassing! -> Bool
  (let [(evalCmd "./bin/asl eval '(:asnl-ring :capacity 4 :size 1 :head 0 :tail 1 :dropped 0)'")
        (res (processRun evalCmd))]
    (assert (= res.exitCode 0) "asl eval exits 0 on ring buffer descriptor")
    (assert (stringContains? res.stdout ":capacity 4") "Ring buffer descriptor contains capacity 4")
    (assert (stringContains? res.stdout ":size 1") "Ring buffer descriptor contains size 1")
    (assert (stringContains? res.stdout ":dropped 0") "Ring buffer descriptor confirms zero drops")
    (refute (stringContains? res.stdout ":dropped 1") "Refutes dropped frames when within capacity")
    (let [(ptrCmd "./bin/asl eval '(:ptr :buf \"shm_pool_0\" :offset 1024 :len 256 :hash \"sha256:7f8a9b\")'")
          (ptrRes (processRun ptrCmd))]
      (assert (= ptrRes.exitCode 0) "asl eval exits 0 on zero-copy pointer S-expression")
      (assert (stringContains? ptrRes.stdout "shm_pool_0") "Zero-copy pointer retains shared memory buffer identifier")
      (assert (stringContains? ptrRes.stdout ":offset 1024") "Zero-copy pointer retains byte offset")
      (assert (stringContains? ptrRes.stdout ":len 256") "Zero-copy pointer retains byte length")
      (refute (stringContains? ptrRes.stdout ":offset 0") "Refutes default offset 0 for offset 1024")
      true))

fn ! runTests -> Bool
  (do
    (assert (testRingSourceIntegrity!) "Ring source integrity passed")
    (assert (testGrammarRegistration!) "Grammar registration passed")
    (assert (testSyntaxAndDelimiterGate!) "Syntax and delimiter gate passed")
    (assert (testRuntimePointerPassing!) "Runtime pointer passing passed")
    true)

fn RunTests! -> Bool
  (runTests)
