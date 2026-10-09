(module asl-lint/tests/anchorGuardTest :x [testAnchorCompliantReceipt testLineNumberViolation testContentAnchorOnly testEmptyReceipt testAuditPair testAuditWithDiagnostics runTests] :i [(asl-lint/anchorGuard :a ag)])

fn testAnchorCompliantReceipt -> Bool
  (let [(r "(:receipt :file \"asl/packages/asl-cli/src/batch.asl\" :symbol \"evalBatch\" :status :ok)")
        (hasForb (or (stringContains? r ":line ") (or (stringContains? r "line:") (or (stringContains? r "line_number") (or (stringContains? r ":lineNumber") (or (stringContains? r "StartLine") (stringContains? r "EndLine")))))))
        (hasSym (or (stringContains? r ":symbol") (or (stringContains? r ":sym") (or (stringContains? r ":name") (stringContains? r ":fn")))))
        (hasAnch (or (stringContains? r ":anchor") (or (stringContains? r ":hash") (or (stringContains? r ":cas") (or (stringContains? r ":old") (stringContains? r ":baseHash"))))))
        (isCompliant (and (or hasSym hasAnch) (not hasForb)))]
    (assert isCompliant "symbol anchor must be compliant")
    (assert hasSym "symbol flag must be true")
    (refute hasForb "no forbidden line flag")
    true)

fn testLineNumberViolation -> Bool
  (let [(r "(:receipt :file \"foo.asl\" :line 42 :status :ok)")
        (hasForb (or (stringContains? r ":line ") (or (stringContains? r "line:") (or (stringContains? r "line_number") (or (stringContains? r ":lineNumber") (or (stringContains? r "StartLine") (stringContains? r "EndLine")))))))
        (hasSym (or (stringContains? r ":symbol") (or (stringContains? r ":sym") (or (stringContains? r ":name") (stringContains? r ":fn")))))
        (hasAnch (or (stringContains? r ":anchor") (or (stringContains? r ":hash") (or (stringContains? r ":cas") (or (stringContains? r ":old") (stringContains? r ":baseHash"))))))
        (isCompliant (and (or hasSym hasAnch) (not hasForb)))]
    (refute isCompliant "raw integer line number must violate invariant")
    (assert hasForb "forbidden line flag must be true")
    true)

fn testContentAnchorOnly -> Bool
  (let [(r "(:patch :file \"bar.asl\" :old \"oldText\" :new \"newText\" :anchor \"cas123\")")
        (hasForb (or (stringContains? r ":line ") (or (stringContains? r "line:") (or (stringContains? r "line_number") (or (stringContains? r ":lineNumber") (or (stringContains? r "StartLine") (stringContains? r "EndLine")))))))
        (hasSym (or (stringContains? r ":symbol") (or (stringContains? r ":sym") (or (stringContains? r ":name") (stringContains? r ":fn")))))
        (hasAnch (or (stringContains? r ":anchor") (or (stringContains? r ":hash") (or (stringContains? r ":cas") (or (stringContains? r ":old") (stringContains? r ":baseHash"))))))
        (isCompliant (and (or hasSym hasAnch) (not hasForb)))]
    (assert isCompliant "content anchor must be compliant")
    (assert hasAnch "anchor flag must be true")
    (refute hasForb "no forbidden line")
    true)

fn testEmptyReceipt -> Bool
  (let [(r "(:receipt :status :ok)")
        (hasForb (or (stringContains? r ":line ") (or (stringContains? r "line:") (or (stringContains? r "line_number") (or (stringContains? r ":lineNumber") (or (stringContains? r "StartLine") (stringContains? r "EndLine")))))))
        (hasSym (or (stringContains? r ":symbol") (or (stringContains? r ":sym") (or (stringContains? r ":name") (stringContains? r ":fn")))))
        (hasAnch (or (stringContains? r ":anchor") (or (stringContains? r ":hash") (or (stringContains? r ":cas") (or (stringContains? r ":old") (stringContains? r ":baseHash"))))))
        (isCompliant (and (or hasSym hasAnch) (not hasForb)))]
    (refute isCompliant "unanchored receipt must not be compliant")
    true)

fn testAuditPair -> Bool
  (let [(rValid1 "(:receipt :file \"a.asl\" :symbol \"fn1\")")
        (rValid2 "(:receipt :file \"b.asl\" :anchor \"hash99\")")
        (rInvalid "(:receipt :file \"b.asl\" :line 10)")
        (v1Compliant (and (or (stringContains? rValid1 ":symbol") (stringContains? rValid1 ":anchor")) (not (stringContains? rValid1 ":line "))))
        (v2Compliant (and (or (stringContains? rValid2 ":symbol") (stringContains? rValid2 ":anchor")) (not (stringContains? rValid2 ":line "))))
        (invCompliant (and (or (stringContains? rInvalid ":symbol") (stringContains? rInvalid ":anchor")) (not (stringContains? rInvalid ":line "))))]
    (assert (and v1Compliant v2Compliant) "all valid receipts must pass audit")
    (refute (and v1Compliant invCompliant) "receipt with line number must fail audit")
    true)

fn testAuditWithDiagnostics -> Bool
  (let [(rValid "(:receipt :file \"a.asl\" :symbol \"fn1\")")
        (rLine "(:receipt :file \"a.asl\" :line 10)")
        (rEmpty "(:receipt :status :ok)")
        (cValid (ag/isReceiptCompliant? rValid))]
    (do
      (assert cValid "isReceiptCompliant must return true for rValid")
      (let [(resValid (ag/auditAnchorReceiptWithDiagnostics rValid))
            (resLine (ag/auditAnchorReceiptWithDiagnostics rLine))
            (resEmpty (ag/auditAnchorReceiptWithDiagnostics rEmpty))]
        (do
          (assert (pairFirst resValid) "Valid receipt must pass diagnostics check")
          (assert (= (listLength (pairSecond resValid)) 0) "Valid receipt must have 0 diagnostics")
          (refute (pairFirst resLine) "Line receipt must fail diagnostics check")
          (assert (> (listLength (pairSecond resLine)) 0) "Line receipt must report diagnostic error")
          (refute (pairFirst resEmpty) "Empty unanchored receipt must fail diagnostics check")
          (assert (> (listLength (pairSecond resEmpty)) 0) "Empty receipt must report diagnostic error")
          true))))

fn runTests -> Bool
  (do (assert (testAnchorCompliantReceipt) "testAnchorCompliantReceipt")
      (assert (testLineNumberViolation) "testLineNumberViolation")
      (assert (testContentAnchorOnly) "testContentAnchorOnly")
      (assert (testEmptyReceipt) "testEmptyReceipt")
      (assert (testAuditPair) "testAuditPair")
      (assert (testAuditWithDiagnostics) "testAuditWithDiagnostics")
      true)

fn RunTests -> Bool
  (runTests)
