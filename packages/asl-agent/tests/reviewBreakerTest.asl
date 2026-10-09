(module aslAgentTests/reviewBreakerTest :x [testReviewApproval testReviewRejectionUnderCeiling testReviewTrippedOnSecondRejection testEscalationReportFormatting runTests] :i [(aslAgent/reviewBreaker :a rev)])

fn testReviewApproval -> Bool
  (let [(initEx (rev/makeReviewExchange "Draft feature" 2)) (approvedEx (rev/recordReviewApproval initEx))] (assert (rev/isReviewPassed? approvedEx) "c-rev-pos-001: review approved") (assert (not (rev/isReviewTripped? approvedEx)) "c-rev-pos-001: approved not tripped") true)

fn testReviewRejectionUnderCeiling -> Bool
  (let [(initEx (rev/makeReviewExchange "Draft feature" 2)) (r1 (rev/recordReviewCritique initEx "Fix off-by-one error"))] (assert (not (rev/isReviewTripped? r1)) "single rejection not tripped") (assert (not (rev/isReviewPassed? r1)) "single rejection not passed") true)

fn testReviewTrippedOnSecondRejection -> Bool
  (let [(initEx (rev/makeReviewExchange "Draft feature" 2)) (r1 (rev/recordReviewCritique initEx "First critique")) (r2 (rev/recordReviewCritique r1 "Second critique"))] (assert (rev/isReviewTripped? r2) "c-rev-neg-001: review tripped on second rejection") (assert (not (rev/isReviewPassed? r2)) "c-rev-neg-001: tripped is not passed") true)

fn testEscalationReportFormatting -> Bool
  (let [(initEx (rev/makeReviewExchange "Draft feature" 2)) (r1 (rev/recordReviewCritique initEx "Fix edge case")) (r2 (rev/recordReviewCritique r1 "Still broken")) (rep (rev/formatEscalationReport r2))] (assert (stringContains? rep "REVIEW ESCALATION") "report contains header") (assert (not (= rep "")) "report not empty") true)

fn runTests -> Bool
  (and (testReviewApproval) (and (testReviewRejectionUnderCeiling) (and (testReviewTrippedOnSecondRejection) (testEscalationReportFormatting))))
