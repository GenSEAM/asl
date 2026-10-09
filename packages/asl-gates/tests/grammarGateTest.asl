(module asl-gates/tests/grammarGateTest :x [testMakeEntry testCountKebab testAuditDensity testRegistered testGetSymbol runTests] :i [(grammarGate :a gg)])

fn testMakeEntry -> Bool
  (let [(e (gg/makeSymbolEntry "test-fn" (gg/symFn) 2 true "rationale"))] (do (assert (= e.name "test-fn") "name") (assert (= e.tokens 2) "tokens") (assert e.hasRationale "hasRationale") (assert (= e.rationale "rationale") "rationale") true))

fn testCountKebab -> Bool
  (do (assert (= (gg/countKebabTokens "simple") 1) "simple 1 token") (assert (= (gg/countKebabTokens "two-words") 2) "two-words 2 tokens") (assert (= (gg/countKebabTokens "three-word-name") 3) "three-word-name 3 tokens") (assert (= (gg/countKebabTokens "") 1) "empty string 1 token minimum") true)

fn testAuditDensity -> Bool
  (let [(short (gg/makeSymbolEntry "run" (gg/symFn) 1 false "")) (atBaseline (gg/makeSymbolEntry "make-it" (gg/symFn) 2 false "")) (overWithRationale (gg/makeSymbolEntry "make-circuit-board" (gg/symFn) 3 true "Complex hardware mapping")) (overNoRationale (gg/makeSymbolEntry "make-circuit-board" (gg/symFn) 3 false "")) (overEmptyRationale (gg/makeSymbolEntry "make-circuit-board" (gg/symFn) 3 true ""))] (do (assert (gg/auditSymbolDensity short 1) "short passes") (assert (gg/auditSymbolDensity atBaseline 2) "at baseline passes") (assert (gg/auditSymbolDensity overWithRationale 2) "over with rationale passes") (assert (not (gg/auditSymbolDensity overNoRationale 2)) "over without rationale fails") (assert (not (gg/auditSymbolDensity overEmptyRationale 2)) "over with empty rationale fails") true))

fn testRegistered -> Bool
  (let [(e1 (gg/makeSymbolEntry "foo" (gg/symFn) 1 false "")) (e2 (gg/makeSymbolEntry "bar" (gg/symType) 1 false "")) (reg (list e1 e2))] (do (assert (gg/isRegistered? "foo" reg) "foo registered") (assert (gg/isRegistered? "bar" reg) "bar registered") (assert (not (gg/isRegistered? "baz" reg)) "baz not registered") true))

fn testGetSymbol -> Bool
  (let [(e1 (gg/makeSymbolEntry "foo" (gg/symFn) 1 false "")) (reg (list e1)) (found (gg/getRegisteredSymbol "foo" reg)) (notFound (gg/getRegisteredSymbol "missing" reg))] (do (mt found ((some s) (assert (= s.name "foo") "found name")) ((none) (assert false "foo should be found"))) (mt notFound ((some _) (assert false "missing should not be found")) ((none) true)) true))

fn runTests -> Bool
  (do (assert (testMakeEntry) "testMakeEntry") (assert (testCountKebab) "testCountKebab") (assert (testAuditDensity) "testAuditDensity") (assert (testRegistered) "testRegistered") (assert (testGetSymbol) "testGetSymbol") true)
