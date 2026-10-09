(module aslHarness/feedback :x [FeedbackStatus ExecutionReceipt TaskFeedback newTaskFeedback makeExecutionReceipt feedbackWithStatus feedbackAddReceipt feedbackAddCompleted feedbackAddGap formatFeedbackSummary discloseObservedGaps] :i [])

(enum FeedbackStatus (:c verified [] "All requirements and verification gates verified") (:c partiallyVerified [] "Core requirements verified but non-blocking gaps remain") (:c blocked [] "Execution blocked by gate failure or invariant violation"))

(schema ExecutionReceipt (:f command Str) (:f exitCode I64) (:f stdoutTail Str) (:f passed Bool))

fn makeExecutionReceipt command: Str exitCode: I64 stdoutTail: Str -> ExecutionReceipt
  (ExecutionReceipt :command command :exitCode exitCode :stdoutTail stdoutTail :passed (= exitCode 0))

(schema TaskFeedback (:f taskId Str) (:f status FeedbackStatus) (:f receipts (List ExecutionReceipt)) (:f completedWork (List Str)) (:f observedTradeoffs (List Str)) (:f unverifiedGaps (List Str)) (:f userPrompt Str))

fn newTaskFeedback taskId: Str -> TaskFeedback
  (TaskFeedback :taskId taskId :status (verified) :receipts (list) :completedWork (list) :observedTradeoffs (list) :unverifiedGaps (list) :userPrompt "")

fn feedbackWithStatus fb: TaskFeedback status: FeedbackStatus -> TaskFeedback
  (with fb :status status)

fn feedbackAddReceipt fb: TaskFeedback receipt: ExecutionReceipt -> TaskFeedback
  (let [(newStatus (if receipt.passed fb.status (blocked)))] (with fb :status newStatus :receipts (listAppend fb.receipts (list receipt))))

fn feedbackAddCompleted fb: TaskFeedback item: Str -> TaskFeedback
  (with fb :completedWork (listAppend fb.completedWork (list item)))

fn feedbackAddGap fb: TaskFeedback gap: Str -> TaskFeedback
  (with fb :unverifiedGaps (listAppend fb.unverifiedGaps (list gap)))

fn formatFeedbackSummary fb: TaskFeedback -> Str
  (let [(doneCount (listLength fb.completedWork)) (receiptCount (listLength fb.receipts)) (gapCount (listLength fb.unverifiedGaps)) (doneStr (stringJoin fb.completedWork "\n  - ")) (gapStr (if (= gapCount 0) "None (all requirements verified)" (stringJoin fb.unverifiedGaps "\n  - ")))] (str "Task Feedback [" fb.taskId "]:\n" "Receipts (" (stringFromInt64 receiptCount) ")\n" "Completed (" (stringFromInt64 doneCount) "):\n  - " doneStr "\n" "Disclosed Gaps (" (stringFromInt64 gapCount) "):\n  - " gapStr))

fn discloseObservedGaps gaps: (List Str) -> Str
  (if (listEmpty? gaps) "[OK] No unverified gaps or defects observed." (str "[WARN] Transparent Disclosures:\n  - " (stringJoin gaps "\n  - ")))
