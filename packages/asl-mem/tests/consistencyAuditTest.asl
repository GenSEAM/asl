(module aslMem/tests/consistencyAuditTest :x [runTests testShortcodeBidirectionalMatch testD52CompletenessCheck testRoadmapGateVerification testCleanReportSucceeds testBrokenReportFails] :i [(consistencyAudit :a ca)])

fn testShortcodeBidirectionalMatch -> Bool
  (let [(code1 "D52") (code2 "D0052") (code3 "D999")] (assert (ca/verifyShortcodeBidirectional? code1 code2) "D52 and D0052 must match under normalization") (assert (not (ca/verifyShortcodeBidirectional? code1 code3)) "D52 and D999 must not match") true)

fn testD52CompletenessCheck -> Bool
  (let [(fullFields (list ":motivation" ":purpose" ":context" ":outcomes" ":owns" ":invariants" ":variations" ":failureModes" ":adr" ":decision" ":gate" ":actionDag")) (partialFields (list ":motivation" ":purpose" ":context" ":outcomes"))] (assert (ca/checkD52Completeness? fullFields) "Full fields list must pass D52 check") (assert (not (ca/checkD52Completeness? partialFields)) "Partial fields list must fail D52 check") true)

fn testRoadmapGateVerification -> Bool
  (let [(goodGate "asl test --strict-falsify asl/packages/asl-mem/tests/vfs_test.asl && asl gate") (emptyGate "") (whitespaceGate "   ") (invalidGate "echo ok")] (assert (ca/verifyRoadmapGate? goodGate) "Standard asl gate command must pass validation") (assert (not (ca/verifyRoadmapGate? emptyGate)) "Empty gate string must fail validation") (assert (not (ca/verifyRoadmapGate? whitespaceGate)) "Whitespace-only gate must fail validation") true)

fn testCleanReportSucceeds -> Bool
  (let [(rep (ca/makeCleanReport 55 272 175 58 89 39))] (assert rep.allPassed "Clean report must have all-passed true") (assert (= rep.brokenLinks 0) "Clean report must have zero broken links") (assert (= rep.desyncIntents 0) "Clean report must have zero desync intents") (assert (= rep.contextVoids 0) "Clean report must have zero context voids") (assert (= rep.delimiterErrors 0) "Clean report must have zero delimiter errors") (assert (= rep.emojiViolations 0) "Clean report must have zero emoji violations") true)

fn testBrokenReportFails -> Bool
  (let [(repBroken (ca/auditConsistencyState 55 272 1 0 0 0 0 0)) (repDesync (ca/auditConsistencyState 55 272 0 1 0 0 0 0)) (repVoids (ca/auditConsistencyState 55 272 0 0 1 0 0 0)) (repDelim (ca/auditConsistencyState 55 272 0 0 0 0 1 0)) (repEmoji (ca/auditConsistencyState 55 272 0 0 0 0 0 1))] (assert (not repBroken.allPassed) "Report with broken link must fail") (assert (not repDesync.allPassed) "Report with desync intent must fail") (assert (not repVoids.allPassed) "Report with context void must fail") (assert (not repDelim.allPassed) "Report with delimiter error must fail") (assert (not repEmoji.allPassed) "Report with emoji violation must fail") true)

fn runTests -> Bool
  (do (testShortcodeBidirectionalMatch) (testD52CompletenessCheck) (testRoadmapGateVerification) (testCleanReportSucceeds) (testBrokenReportFails) true)
