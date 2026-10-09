(module aslHarness/feedbackTest :x [testFeedbackInit testFeedbackAddCompleted testFeedbackAddGap testFeedbackFormatting testFeedbackStatusAndReceipts runTests] :i [(feedback :a fb)])

fn testFeedbackInit -> Bool
  (let [(f (fb/newTaskFeedback "TASK-200"))] (do (assert (= f.taskId "TASK-200")) (assert (= (listLength f.completedWork) 0)) (assert (= (listLength f.unverifiedGaps) 0)) (assert (not (stringEmpty? f.taskId))) true))

fn testFeedbackAddCompleted -> Bool
  (let [(f0 (fb/newTaskFeedback "TASK-201")) (f1 (fb/feedbackAddCompleted f0 "Fixed off-by-one error in parser")) (f2 (fb/feedbackAddCompleted f1 "Added unit test coverage"))] (do (assert (= (listLength f2.completedWork) 2)) (assert (stringContains? (fb/formatFeedbackSummary f2) "Fixed off-by-one")) (assert (not (= (listLength f2.completedWork) 0))) true))

fn testFeedbackAddGap -> Bool
  (let [(f0 (fb/newTaskFeedback "TASK-202")) (f1 (fb/feedbackAddGap f0 "Optional IPv6 support omitted per YAGNI")) (summary (fb/formatFeedbackSummary f1)) (disc (fb/discloseObservedGaps f1.unverifiedGaps))] (do (assert (= (listLength f1.unverifiedGaps) 1)) (assert (stringContains? summary "Optional IPv6 support")) (assert (stringContains? disc "Transparent Disclosures")) (assert (not (= (listLength f1.unverifiedGaps) 0))) true))

fn testFeedbackFormatting -> Bool
  (let [(disc (fb/discloseObservedGaps (list)))] (do (assert (stringContains? disc "No unverified gaps")) (assert (not (stringContains? disc "Transparent Disclosures:"))) true))

fn testFeedbackStatusAndReceipts -> Bool
  (let [(f0 (fb/newTaskFeedback "TASK-203")) (r1 (fb/makeExecutionReceipt "asl test harness/tests/feedback-test.asl" 0 "PASS")) (f1 (fb/feedbackAddReceipt f0 r1)) (r2 (fb/makeExecutionReceipt "asl gate" 1 "FAIL: invariant violation")) (f2 (fb/feedbackAddReceipt f1 r2)) (f3 (fb/feedbackWithStatus f0 (fb/partiallyVerified)))] (do (assert (= (listLength f2.receipts) 2)) (assert r1.passed) (assert (not r2.passed)) (assert (= f2.status (fb/blocked))) (assert (= f3.status (fb/partiallyVerified))) true))

fn runTests -> Bool
  (do (assert (testFeedbackInit)) (assert (testFeedbackAddCompleted)) (assert (testFeedbackAddGap)) (assert (testFeedbackFormatting)) (assert (testFeedbackStatusAndReceipts)) true)
