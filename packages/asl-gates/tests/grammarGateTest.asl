(module asl-gates/tests/grammarGateTest
  :d "Comprehensive unit tests for grammar_gate functionality."
  :x [testMakeEntry testCountKebab testAuditDensity testRegistered testGetSymbol runTests]
  :i [(grammarGate :a gg)])

(df testMakeEntry [] -> Bool
  :d "Verifies makeSymbolEntry construction"
  (let [(e (gg/makeSymbolEntry "test-fn" (gg/symFn) 2 true "rationale"))]
    (do
      (assert (= (.-name e) "test-fn") "name")
      (assert (= (.-tokens e) 2) "tokens")
      (assert (.-hasRationale e) "hasRationale")
      (assert (= (.-rationale e) "rationale") "rationale")
      true)))

(df testCountKebab [] -> Bool
  :d "Verifies countKebabTokens for various identifiers"
  (do
    (assert (= (gg/countKebabTokens "simple") 1) "simple 1 token")
    (assert (= (gg/countKebabTokens "two-words") 2) "two-words 2 tokens")
    (assert (= (gg/countKebabTokens "three-word-name") 3) "three-word-name 3 tokens")
    (assert (= (gg/countKebabTokens "") 1) "empty string 1 token minimum")
    true))

(df testAuditDensity [] -> Bool
  :d "Verifies auditSymbolDensity policy for various token counts"
  (let [(short (gg/makeSymbolEntry "run" (gg/symFn) 1 false ""))
        (atBaseline (gg/makeSymbolEntry "make-it" (gg/symFn) 2 false ""))
        (overWithRationale (gg/makeSymbolEntry "make-circuit-board" (gg/symFn) 3 true "Complex hardware mapping"))
        (overNoRationale (gg/makeSymbolEntry "make-circuit-board" (gg/symFn) 3 false ""))
        (overEmptyRationale (gg/makeSymbolEntry "make-circuit-board" (gg/symFn) 3 true ""))]
    (do
      (assert (gg/auditSymbolDensity short 1) "short passes")
      (assert (gg/auditSymbolDensity atBaseline 2) "at baseline passes")
      (assert (gg/auditSymbolDensity overWithRationale 2) "over with rationale passes")
      (assert (not (gg/auditSymbolDensity overNoRationale 2)) "over without rationale fails")
      (assert (not (gg/auditSymbolDensity overEmptyRationale 2)) "over with empty rationale fails")
      true)))

(df testRegistered [] -> Bool
  :d "Verifies isRegistered? lookup"
  (let [(e1 (gg/makeSymbolEntry "foo" (gg/symFn) 1 false ""))
        (e2 (gg/makeSymbolEntry "bar" (gg/symType) 1 false ""))
        (reg (list e1 e2))]
    (do
      (assert (gg/isRegistered? "foo" reg) "foo registered")
      (assert (gg/isRegistered? "bar" reg) "bar registered")
      (assert (not (gg/isRegistered? "baz" reg)) "baz not registered")
      true)))

(df testGetSymbol [] -> Bool
  :d "Verifies getRegisteredSymbol retrieval"
  (let [(e1 (gg/makeSymbolEntry "foo" (gg/symFn) 1 false ""))
        (reg (list e1))
        (found (gg/getRegisteredSymbol "foo" reg))
        (notFound (gg/getRegisteredSymbol "missing" reg))]
    (do
      (mt found
        ((some s) (assert (= (.-name s) "foo") "found name"))
        ((none) (assert false "foo should be found")))
      (mt notFound
        ((some _) (assert false "missing should not be found"))
        ((none) true))
      true)))

(df runTests [] -> Bool
  :d "Master test runner for grammar gate."
  (do
    (assert (testMakeEntry) "testMakeEntry")
    (assert (testCountKebab) "testCountKebab")
    (assert (testAuditDensity) "testAuditDensity")
    (assert (testRegistered) "testRegistered")
    (assert (testGetSymbol) "testGetSymbol")
    true))
