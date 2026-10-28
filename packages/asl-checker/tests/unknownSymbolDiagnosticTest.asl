(module asl-checker/tests/unknownSymbolDiagnosticTest :x [testUnknownSymbolDiagnostic testUnknownMatchConstructorDiagnostic testQuoteEvaluationNoUnboundErrors testDualPolarityRefutations runTests] :i [(asl-checker/check :a chk) (asl-checker/types :a ty)])

fn testUnknownSymbolDiagnostic -> Bool
  (let [(src "(module test/unknown :x [runTests]) (df runTests [] -> Bool (do (nonExistentSymbolTarget) true))") (diags (chk/checkSource src (mapEmpty) "tests/fixtures/unknownSymbol.asl")) (rule1Diags (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-1")) diags))] (assert (not (listEmpty? diags)) "Unknown symbol must produce at least one diagnostic") (assert (not (listEmpty? rule1Diags)) "Unknown symbol must produce rule-1 diagnostic") (let [(d1 (optionOr (listHead rule1Diags) (ty/Diagnostic :code "" :message "" :msg "" :path "" :line 0 :col 0)))] (assert (stringContains? d1.msg "unbound symbol: nonExistentSymbolTarget") "Diagnostic message must cite unbound symbol")) true)

fn testUnknownMatchConstructorDiagnostic -> Bool
  (let [(src "(module test/match :x [runTests]) (df runTests [(x Any)] -> Bool (match x ((unknownConstructor a) true) (_ false)))") (diags (chk/checkSource src (mapEmpty) "matchTest.asl")) (ctorDiags (filter (fn [(d ty/Diagnostic)] -> Bool (stringContains? d.msg "unknown constructor in match pattern")) diags))] (assert (not (listEmpty? diags)) "Unknown constructor in match must produce diagnostic") (assert (not (listEmpty? ctorDiags)) "Diagnostic message must cite unknown constructor") true)

fn testQuoteEvaluationNoUnboundErrors -> Bool
  (let [(src "(module test/quote :x [runTests]) (df runTests [] -> SExpr (quote (a b c)))") (diags (chk/checkSource src (mapEmpty) "quoteTest.asl")) (unboundDiags (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-1")) diags))] (assert (listEmpty? unboundDiags) "Quoted data must not trigger unbound symbol diagnostics on symbols inside quote") true)

fn testDualPolarityRefutations -> Bool
  (let [(srcUnknown "(module m :x [f]) (df f [] -> Bool (nonExistentTarget))") (diagsUnknown (chk/checkSource srcUnknown (mapEmpty) "test.asl")) (srcQuote "(module m :x [f]) (df f [] -> SExpr (quote (foo bar baz)))") (diagsQuote (chk/checkSource srcQuote (mapEmpty) "quote.asl")) (unboundQuote (filter (fn [(d ty/Diagnostic)] -> Bool (= d.code "rule-1")) diagsQuote))] (refute (listEmpty? diagsUnknown) "Refute that unknown symbol produces zero diagnostics") (refute (not (listEmpty? unboundQuote)) "Refute that quoted symbols produce unbound errors") true)

fn runTests -> Bool
  (do (assert (testUnknownSymbolDiagnostic) "testUnknownSymbolDiagnostic must pass") (assert (testUnknownMatchConstructorDiagnostic) "testUnknownMatchConstructorDiagnostic must pass") (assert (testQuoteEvaluationNoUnboundErrors) "testQuoteEvaluationNoUnboundErrors must pass") (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass") true)
