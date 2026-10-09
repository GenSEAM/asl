(module aslGateway/tests/serverTest :x [testExtractThinkBlocks testDetectEshViolation testInspectCompletionCleanTurn testInspectCompletionEshRejection testInspectCompletionQuarantine runTests] :i [(server :a srv)])

fn testExtractThinkBlocks -> Bool
  (let [(raw "<think>Planning the solution step by step</think>Here is the completed code.") (res (srv/extractThinkBlocks raw)) (thinkPart (pairFirst res)) (uiPart (pairSecond res))] (do (assert (= thinkPart "Planning the solution step by step") "Think content must match") (assert (= uiPart "Here is the completed code.") "UI content must be stripped of think tags") true))

fn testDetectEshViolation -> Bool
  (do (assert (srv/detectEshViolation "I ran the suite and all 5 tests pass cleanly.") "Must detect all 5 tests pass") (assert (srv/detectEshViolation "Done! All tests pass.") "Must detect all tests pass") (assert (srv/detectEshViolation "The gate passes cleanly without issues.") "Must detect gate passes cleanly") (assert (not (srv/detectEshViolation "Here is the diff for reviewing.")) "Normal progress statement must not be flagged") true)

fn testInspectCompletionCleanTurn -> Bool
  (let [(raw "(:call :tool \"bash\" :cmd \"asl test\")") (verdict (srv/inspectCompletionTurn raw true))] (do (assert verdict.allowed "Clean turn must be allowed") (assert (= (listLength verdict.toolCalls) 1) "Tool call must be extracted") (assert (= verdict.quarantinedThink "") "No think block in raw text") true))

fn testInspectCompletionEshRejection -> Bool
  (let [(raw "The refactor is done and all tests pass cleanly.") (verdict (srv/inspectCompletionTurn raw false))] (do (assert (not verdict.allowed) "Turn must be rejected due to ESH violation") (assert (stringContains? verdict.rejectionReason "ESH violation") "Rejection reason must reference ESH") (assert (stringContains? verdict.cleanOutput "Action blocked") "Clean output must be blocked notice") true))

fn testInspectCompletionQuarantine -> Bool
  (let [(raw "<think>Internal scratchpad</think>Final answer.") (verdict (srv/inspectCompletionTurn raw true))] (do (assert verdict.allowed "Turn must be allowed") (assert (= verdict.quarantinedThink "Internal scratchpad") "CoT must be quarantined") (assert (= verdict.cleanOutput "Final answer.") "User output must match") true))

fn runTests -> Bool
  (and (testExtractThinkBlocks) (and (testDetectEshViolation) (and (testInspectCompletionCleanTurn) (and (testInspectCompletionEshRejection) (testInspectCompletionQuarantine)))))
