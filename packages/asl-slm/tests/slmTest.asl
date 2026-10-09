(module asl-slm/tests/slmTest
  :x [testGrammarCompilation testMaskerStateTransitions testTerminalAllowance testTokenMaskBitset testDualPolarityRefutations runTests RunTests]
  :i [(asl-slm :a slm)])

fn testGrammarCompilation -> Bool
  (let [(validGrammar "root ::= '(' symbol number ')' ;")
        (pda (slm/compileGrammarToDfa validGrammar))
        (emptyPda (slm/compileGrammarToDfa ""))]
    (do
      (assert (= pda.status "ok") "valid grammar compiles with status ok")
      (refute (!= pda.status "ok") "valid grammar refutes non-ok")
      (assert (> pda.stateCount 0) "valid grammar state count > 0")
      (assert pda.rootRequiresDelimiter "root rule requires delimiter")
      (refute (not pda.rootRequiresDelimiter) "rootRequiresDelimiter refutes false")
      (assert (= emptyPda.status "error") "empty grammar returns error")
      (refute (= emptyPda.status "ok") "empty grammar refutes ok")
      (assert (= emptyPda.diagnosticCode "ERR_GRAMMAR_EMPTY") "diagnostic code is ERR_GRAMMAR_EMPTY")
      true))

fn testMaskerStateTransitions -> Bool
  (let [(grammar "root ::= '(' symbol number ')' ;")
        (pda (slm/compileGrammarToDfa grammar))
        (st0 (slm/maskerInit pda 99))
        (st1 (slm/advanceMaskerState pda st0 "("))
        (st2 (slm/advanceMaskerState pda st1 "foo"))
        (st3 (slm/advanceMaskerState pda st2 ")"))]
    (do
      (assert (= st0.stackDepth 0) "initial stack depth is 0")
      (assert (not st0.isEosAllowed) "EOS not allowed at state 0")
      (refute st0.isEosAllowed "state 0 refutes EOS")
      (assert (= st1.stackDepth 1) "open paren increases stack depth to 1")
      (refute (!= st1.stackDepth 1) "open paren refutes non-1 depth")
      (assert (= st2.stackDepth 1) "terminal maintains stack depth 1")
      (assert (= st3.stackDepth 0) "closing paren decreases stack depth to 0")
      (assert st3.isEosAllowed "EOS allowed after balanced closing paren")
      (refute (not st3.isEosAllowed) "state 3 refutes EOS disallowance")
      true))

fn testTerminalAllowance -> Bool
  (let [(grammar "root ::= '(' symbol number string ')' ;")
        (pda (slm/compileGrammarToDfa grammar))]
    (do
      (assert (slm/isGrammarTerminalAllowed pda "42") "number terminal 42 is allowed")
      (refute (not (slm/isGrammarTerminalAllowed pda "42")) "number 42 refutes false")
      (assert (slm/isGrammarTerminalAllowed pda "myIdentifier") "symbol terminal is allowed")
      (assert (slm/isGrammarTerminalAllowed pda "\"hello\"") "string literal is allowed")
      (assert (not (slm/isGrammarTerminalAllowed pda "^^invalid^^")) "malformed token is disallowed")
      (refute (slm/isGrammarTerminalAllowed pda "^^invalid^^") "malformed token refutes true")
      true))

fn testTokenMaskBitset -> Bool
  (let [(grammar "root ::= '(' symbol ')' ;")
        (pda (slm/compileGrammarToDfa grammar))
        (st0 (slm/maskerInit pda 99))
        (vocab (list (pair 1 "(") (pair 2 ")") (pair 3 "ident")))
        (mask0 (slm/computeTokenMaskBitset pda st0 vocab))]
    (do
      (assert (slm/isTokenAllowed mask0 1) "open paren token 1 is allowed at start")
      (refute (not (slm/isTokenAllowed mask0 1)) "token 1 refutes disallowed")
      (assert (not (slm/isTokenAllowed mask0 2)) "close paren token 2 is disallowed at start")
      (refute (slm/isTokenAllowed mask0 2) "token 2 refutes allowed")
      (assert (= mask0.totalVocabSize 3) "total vocab size is 3")
      true))

fn testDualPolarityRefutations -> Bool
  (let [(grammar "root ::= number ;")
        (pda (slm/compileGrammarToDfa grammar))]
    (do
      (assert (not pda.rootRequiresDelimiter) "grammar without parens has rootRequiresDelimiter false")
      (refute pda.rootRequiresDelimiter "non-delim grammar refutes rootRequiresDelimiter")
      true))

fn runTests -> Bool
  (do
    (assert (testGrammarCompilation) "testGrammarCompilation")
    (assert (testMaskerStateTransitions) "testMaskerStateTransitions")
    (assert (testTerminalAllowance) "testTerminalAllowance")
    (assert (testTokenMaskBitset) "testTokenMaskBitset")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations")
    true)

fn RunTests -> Bool
  (runTests)
