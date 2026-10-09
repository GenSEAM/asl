(module asl-gates/tests/lexiconGateTest :x [testMakeTerm testIsSpoken testAuditLexicon testCheckLocalAlias testVerifyReferents runTests] :i [(lexiconGate :a lg)])

fn testMakeTerm -> Bool
  (let [(t (lg/makeLexiconTerm "canon" (list "spok") "scope" "why"))] (do (assert (= t.canonical "canon") "canon") (assert (= (listLength t.spoken) 1) "spoken length") (assert (= t.scope "scope") "scope") (assert (= t.why "why") "why") true))

fn testIsSpoken -> Bool
  (let [(sp (list "bad" "worse"))] (do (assert (lg/isSpokenMishearing? "bad" sp) "bad in list") (assert (not (lg/isSpokenMishearing? "good" sp)) "good not in list") true))

fn testAuditLexicon -> Bool
  (let [(validTerm (lg/makeLexiconTerm "c" (list "s") "sc" "w")) (invalidTerm1 (lg/makeLexiconTerm "" (list "s") "sc" "w")) (invalidTerm2 (lg/makeLexiconTerm "c" (list) "sc" "w")) (emptyReg (lg/LexiconRegistry :version "1" :terms (list))) (validReg (lg/LexiconRegistry :version "1" :terms (list validTerm))) (invalidReg1 (lg/LexiconRegistry :version "1" :terms (list validTerm invalidTerm1))) (invalidReg2 (lg/LexiconRegistry :version "1" :terms (list validTerm invalidTerm2)))] (do (assert (not (lg/auditLexiconTerms emptyReg)) "empty") (assert (lg/auditLexiconTerms validReg) "valid") (assert (not (lg/auditLexiconTerms invalidReg1)) "invalid 1") (assert (not (lg/auditLexiconTerms invalidReg2)) "invalid 2") true))

fn testCheckLocalAlias -> Bool
  (let [(valid (list "main.asl" "lexicon.asn" "some_alias_table_lexicon.asn")) (invalid (list "main.asl" "alias_table.txt"))] (do (assert (lg/checkLocalAliasTables valid) "valid") (assert (not (lg/checkLocalAliasTables invalid)) "invalid") true))

fn testVerifyReferents -> Bool
  (let [(t1 (lg/makeLexiconTerm "foo" (list) "sc" "w")) (t2 (lg/makeLexiconTerm "bar" (list) "sc" "w")) (terms (list t1 t2)) (corpusValid "here is foo and bar") (corpusInvalid "here is foo only")] (do (assert (lg/verifyCanonicalReferents terms corpusValid) "valid") (assert (not (lg/verifyCanonicalReferents terms corpusInvalid)) "invalid") true))

fn runTests -> Bool
  (do (assert (testMakeTerm) "testMakeTerm") (assert (testIsSpoken) "testIsSpoken") (assert (testAuditLexicon) "testAuditLexicon") (assert (testCheckLocalAlias) "testCheckLocalAlias") (assert (testVerifyReferents) "testVerifyReferents") true)
