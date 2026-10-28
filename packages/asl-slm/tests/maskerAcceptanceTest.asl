(module asl-slm/tests/maskerAcceptanceTest
  :x [runTests RunTests testSlmAcceptancePipeline testSlmAcceptanceRefutations]
  :i [(asl-slm :a slm)])

fn testSlmAcceptancePipeline -> Bool
  (let [(grammar "root ::= '(' symbol number ')' ;")
        (pda (slm/compileGrammarToDfa grammar))
        (st0 (slm/maskerInit pda 10))
        (st1 (slm/advanceMaskerState pda st0 "("))
        (vocab (list (pair 1 "(") (pair 2 ")") (pair 3 "symbolName")))
        (mask0 (slm/computeTokenMaskBitset pda st0 vocab))
        (mask1 (slm/computeTokenMaskBitset pda st1 vocab))]
    (do
      (assert (= pda.status "ok") "compiled grammar PDA status is ok")
      (refute (!= pda.status "ok") "compiled grammar PDA refutes non-ok")
      (assert pda.rootRequiresDelimiter "grammar requires delimiter")
      (assert (slm/isTokenAllowed mask0 1) "open paren is allowed initially")
      (refute (slm/isTokenAllowed mask0 2) "close paren is disallowed initially")
      (assert (slm/isTokenAllowed mask1 3) "symbol token is allowed inside open paren")
      true))

fn testSlmAcceptanceRefutations -> Bool
  (let [(pdaBad (slm/compileGrammarToDfa "invalid-no-arrow"))]
    (do
      (assert (= pdaBad.status "error") "malformed grammar produces error status")
      (refute (= pdaBad.status "ok") "malformed grammar refutes ok status")
      (assert (= pdaBad.diagnosticCode "ERR_GRAMMAR_MALFORMED_RULE") "diagnostic code is ERR_GRAMMAR_MALFORMED_RULE")
      (refute (!= pdaBad.diagnosticCode "ERR_GRAMMAR_MALFORMED_RULE") "diagnostic code refutes divergence")
      true))

fn runTests -> Bool
  (do
    (assert (testSlmAcceptancePipeline) "testSlmAcceptancePipeline passed")
    (assert (testSlmAcceptanceRefutations) "testSlmAcceptanceRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
