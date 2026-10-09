(module aslHarness/tests/evalTest
  :x [runTests
      testScoutPerfectRecallAndPrecision
      testScoutZeroFindingsZeroRecall
      testScoutExtraneousFindingLowerPrecision
      testScoutWrongFileNoMatch
      testScoutWrongAnchorNoMatch
      testScoutMultipleDefectsPartialRecall
      testScoutMultipleDefectsFullRecall
      testScoutReceiptFailedStatusFails
      testImplementGatePass
      testImplementGateFail
      testImplementGateLastRunGreen
      testImplementGateLastRunRed
      testImplementReceiptFailedStatusFails
      testBipartiteMatchingSingleFindingCannotMatchTwoDefects
      testTimingAndTurnsExtraction
      testLineRegionMatching
      testLineRegionToleranceEdges
      testEvalRunFormFormat
      testSymbolAnchorMatches
      testSymbolWordBoundaryPreventsSubstringMatch
      testOtherSymbolSameFileMisses
      testTruthCarriesSymbol!
      testNestedFindingsSplit
      testFindingsWriteIsDefect
      testDeliverPatchScoresGates
      testTasksPassNoMode!
      testEvalRunCarriesBatching
      testReceiptDeliverPicksScoring
      testEvalRunCarriesPlan
      testInvocationKeepsModelWithoutProfile
      testInvocationOmitsModelWithProfile
      testInvocationPreservesExistingBackend
      testSummarizeEvalRuns
      testSummarizeEvalRunsEmpty]
  :i [(aslHarness/eval :a ev)])

fn scored receipt: String truth: String caseId: String model: String wall: Float64 date: String -> ev/EvalRun
  (mt (ev/scoreCase receipt truth caseId model wall date)
    ((ok run) run)
    ((err e) (do (assert false e) (scored receipt truth caseId model wall "0000-00-00"))))

fn testScoutPerfectRecallAndPrecision -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcpt1 "(:agentReceipt :status :ok :mode :scout :unbacked 0 :turns 1 :findings ((:findings (:claim \"Reports false success\" :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\"))))")
        (res1 (scored rcpt1 truth1 "scout-false-green" "test-model" 1.2 "2026-09-28"))]
    (assert (= res1.recall 1.0) "scout perfect recall")
    (assert (= res1.precision 1.0) "scout perfect precision")
    (assert (= res1.status "ok") "scout perfect status ok")
    true)

fn testScoutZeroFindingsZeroRecall -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcpt2 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ())")
        (res2 (scored rcpt2 truth1 "scout-false-green" "test-model" 1.2 "2026-09-28"))]
    (assert (= res2.recall 0.0) "scout zero findings recall 0.0")
    (assert (= res2.precision 0.0) "scout zero findings precision 0.0")
    (assert (= res2.status "failed") "scout zero findings failed")
    true)

fn testScoutExtraneousFindingLowerPrecision -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcpt3 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Reports false success\" :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\") (:claim \"Harmless comment\" :file \"src/backup.py\" :anchor \"# TODO: clean up\"))))")
        (res3 (scored rcpt3 truth1 "scout-false-green" "test-model" 1.2 "2026-09-28"))]
    (assert (= res3.recall 1.0) "scout extraneous recall 1.0")
    (assert (= res3.precision 0.5) "scout extraneous precision 0.5")
    (assert (= res3.status "ok") "scout extraneous status ok")
    true)

fn testScoutWrongFileNoMatch -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcpt4 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Reports false success\" :file \"src/other.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\"))))")
        (res4 (scored rcpt4 truth1 "scout-false-green" "test-model" 1.2 "2026-09-28"))]
    (assert (= res4.recall 0.0) "scout wrong file recall 0.0")
    (assert (= res4.precision 0.0) "scout wrong file precision 0.0")
    (assert (= res4.status "failed") "scout wrong file failed")
    true)

fn testScoutWrongAnchorNoMatch -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcpt5 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Something else\" :file \"src/backup.py\" :anchor \"def perform_backup():\"))))")
        (res5 (scored rcpt5 truth1 "scout-false-green" "test-model" 1.2 "2026-09-28"))]
    (assert (= res5.recall 0.0) "scout wrong anchor recall 0.0")
    (assert (= res5.precision 0.0) "scout wrong anchor precision 0.0")
    (assert (= res5.status "failed") "scout wrong anchor failed")
    true)

fn testScoutMultipleDefectsPartialRecall -> Bool
  (let [(truth6 "(:defects (:defect :file \"src/buffer_pool.py\" :anchor \"self.capacity - 1\" :kind \"off-by-one\") (:defect :file \"src/ring_buffer.py\" :anchor \"tail + 1\" :kind \"off-by-one\"))")
        (rcpt6 "(:agentReceipt :status :ok :mode :scout :turns 2 :findings ((:findings (:claim \"Off by one in buffer pool\" :file \"src/buffer_pool.py\" :anchor \"self.capacity - 1\"))))")
        (res6 (scored rcpt6 truth6 "scout-multiple" "test-model" 1.0 "2026-09-28"))]
    (let [(td (ev/parseTruth truth6))] (assert (= (listLength td.defects) 2) (str "truth6 defect count expected 2 but got " (stringFromInt64 (listLength td.defects)))))
    (assert (= res6.recall 0.5) (str "scout partial recall expected 0.5 but got " (stringFromFloat64 res6.recall) " prec=" (stringFromFloat64 res6.precision) " st=" res6.status " form=" res6.form))
    (assert (= res6.precision 1.0) "scout partial precision 1.0")
    (assert (= res6.status "failed") "scout partial status failed")
    true)

fn testScoutMultipleDefectsFullRecall -> Bool
  (let [(truth6 "(:defects (:defect :file \"src/buffer_pool.py\" :anchor \"self.capacity - 1\" :kind \"off-by-one\") (:defect :file \"src/ring_buffer.py\" :anchor \"tail + 1\" :kind \"off-by-one\"))")
        (rcpt7 "(:agentReceipt :status :ok :mode :scout :turns 3 :findings ((:findings (:claim \"Off by one in buffer pool\" :file \"src/buffer_pool.py\" :anchor \"self.capacity - 1\") (:claim \"Off by one in ring buffer\" :file \"src/ring_buffer.py\" :anchor \"tail + 1\"))))")
        (res7 (scored rcpt7 truth6 "scout-multiple" "test-model" 1.0 "2026-09-28"))]
    (assert (= res7.recall 1.0) "scout full recall 1.0")
    (assert (= res7.precision 1.0) "scout full precision 1.0")
    (assert (= res7.status "ok") "scout full status ok")
    true)

fn testImplementGatePass -> Bool
  (let [(truth8 "(:gate :cmd \"python3 test_tax.py\" :exit 0)")
        (rcpt8 "(:agentReceipt :status :ok :mode :implement :turns 2 :gates ((:cmd \"python3 test_tax.py\" :exit 0)))")
        (res8 (scored rcpt8 truth8 "implement-tax" "test-model" 1.0 "2026-09-28"))]
    (assert (= res8.recall 1.0) "implement pass recall 1.0")
    (assert (= res8.precision 1.0) "implement pass precision 1.0")
    (assert (= res8.status "ok") "implement pass status ok")
    true)

fn testImplementGateFail -> Bool
  (let [(truth9 "(:gate :cmd \"python3 test_tax.py\" :exit 0)")
        (rcpt9 "(:agentReceipt :status :failed :mode :implement :turns 3 :gates ((:cmd \"python3 test_tax.py\" :exit 1)))")
        (res9 (scored rcpt9 truth9 "implement-tax" "test-model" 1.0 "2026-09-28"))]
    (assert (= res9.recall 0.0) "implement fail recall 0.0")
    (assert (= res9.precision 0.0) "implement fail precision 0.0")
    (assert (= res9.status "failed") "implement fail status failed")
    true)

fn testImplementGateLastRunGreen -> Bool
  (let [(truth9 "(:gate :cmd \"python3 test_tax.py\" :exit 0)")
        (rcpt9b "(:agentReceipt :status :ok :mode :implement :turns 9 :gates ((:cmd \"python3 test_tax.py\" :exit 1) (:cmd \"python3 test_tax.py\" :exit 0)))")
        (res9b (scored rcpt9b truth9 "implement-tax" "test-model" 1.0 "2026-09-28"))]
    (assert (= res9b.recall 1.0) "implement last run green recall 1.0")
    (assert (= res9b.status "ok") "implement last run green status ok")
    true)

fn testImplementGateLastRunRed -> Bool
  (let [(truth9 "(:gate :cmd \"python3 test_tax.py\" :exit 0)")
        (rcpt9c "(:agentReceipt :status :ok :mode :implement :turns 9 :gates ((:cmd \"python3 test_tax.py\" :exit 0) (:cmd \"python3 test_tax.py\" :exit 1)))")
        (res9c (scored rcpt9c truth9 "implement-tax" "test-model" 1.0 "2026-09-28"))]
    (assert (= res9c.recall 0.0) "implement last run red recall 0.0")
    (assert (= res9c.status "failed") "implement last run red status failed")
    true)

fn testTimingAndTurnsExtraction -> Bool
  (let [(truth10 "(:gate :cmd \"python3 test_tax.py\" :exit 0)")
        (rcpt10 "(:agentReceipt :status :ok :mode :implement :turns 4 :queueWaitSec 0.45 :execSec 3.82 :gates ((:cmd \"python3 test_tax.py\" :exit 0)))")
        (res10 (scored rcpt10 truth10 "timing-test" "test-model" 5.12 "2026-09-28"))]
    (assert (= res10.turns 4) "timing turns 4")
    (assert (< (abs (- res10.queueWaitSec 0.45)) 0.0001) "queueWaitSec 0.45")
    (assert (< (abs (- res10.wallSec 5.12)) 0.0001) "wallSec 5.12")
    true)

fn testLineRegionMatching -> Bool
  (let [(truth11 "(:defect :file \"src/ring_buffer.py\" :line 16 :kind \"off-by-one\")")
        (rcpt11 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Defect found at line 16\" :file \"src/ring_buffer.py\"))))")
        (res11 (scored rcpt11 truth11 "line-region-test" "test-model" 1.0 "2026-09-28"))]
    (assert (= res11.recall 1.0) "line region recall 1.0")
    (assert (= res11.status "ok") "line region status ok")
    true)

fn testEvalRunFormFormat -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcpt1 "(:agentReceipt :status :ok :mode :scout :unbacked 0 :turns 1 :findings ((:findings (:claim \"Reports false success\" :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\"))))")
        (res1 (scored rcpt1 truth1 "scout-false-green" "test-model" 1.2 "2026-09-28"))
        (form res1.form)]
    (assert (stringContains? form ":evalRun") "form has :evalRun")
    (assert (stringContains? form ":date") "form has :date")
    (assert (stringContains? form ":model") "form has :model")
    (assert (stringContains? form ":case") "form has :case")
    (assert (stringContains? form ":recall") "form has :recall")
    (assert (stringContains? form ":precision") "form has :precision")
    (assert (stringContains? form ":turns") "form has :turns")
    (assert (stringContains? form ":wallSec") "form has :wallSec")
    (assert (stringContains? form ":queueWaitSec") "form has :queueWaitSec")
    (assert (stringContains? form ":status") "form has :status")
    (assert (= (stringCountChar form "(") (stringCountChar form ")")) "form parens balanced")
    true)

fn testSymbolAnchorMatches -> Bool
  (let [(dSym (ev/Defect :file "src/backup.py" :anchor "return {\"status\": \"success\"" :kind "" :line (none) :symbol "perform_backup" :raw ""))
        (hit (ev/Finding :file "src/backup.py" :anchor "perform_backup" :claim "perform_backup reports success on failure" :line (none) :raw ""))]
    (assert (ev/matchFindingToDefect hit dSym) "symbol anchor matches")
    true)

fn testOtherSymbolSameFileMisses -> Bool
  (let [(dSym (ev/Defect :file "src/backup.py" :anchor "return {\"status\": \"success\"" :kind "" :line (none) :symbol "perform_backup" :raw ""))
        (miss (ev/Finding :file "src/backup.py" :anchor "restore_backup" :claim "restore_backup swallows errors" :line (none) :raw ""))]
    (refute (ev/matchFindingToDefect miss dSym) "other symbol same file misses")
    true)

fn testTruthCarriesSymbol! -> Bool
  (let [(rawTruth (resultOr (fileRead "tests/agentEval/cases/scout-false-green/truth.asn") ""))
        (truth (ev/parseTruth rawTruth))
        (defects truth.defects)
        (d0 (optionOr (listHead defects) (ev/Defect :file "" :anchor "" :kind "" :line (none) :symbol "" :raw "")))]
    (assert (> (listLength defects) 0) "defects parsed from truth.asn")
    (assert (= d0.symbol "perform_backup") "truth carries symbol perform_backup")
    true)

fn testNestedFindingsSplit -> Bool
  (let [(nested "(:agentReceipt :status :ok :turns 3 :findings ((:findings (:claim \"a\" :file \"src/backup.py\" :anchor \"if x:\") (:claim \"b\" :file \"src/backup.py\" :anchor \"except E:\"))))")
        (rcpt (ev/parseReceipt nested))
        (fList rcpt.findings)
        (f0 (optionOr (listHead fList) (ev/Finding :file "" :anchor "" :claim "" :line (none) :raw "")))
        (f1 (optionOr (listHead (optionOr (listTail fList) (list))) (ev/Finding :file "" :anchor "" :claim "" :line (none) :raw "")))]
    (assert (= (listLength fList) 2) "nested findings split count 2")
    (assert (= f0.anchor "if x:") "first anchor if x:")
    (assert (= f1.anchor "except E:") "second anchor except E:")
    true)

fn testFindingsWriteIsDefect -> Bool
  (let [(truth11 "(:defect :file \"src/ring_buffer.py\" :line 16 :kind \"off-by-one\")")
        (cleanRcpt "(:agentReceipt :status :ok :deliver :findings :turns 2 :findings ((:findings (:claim \"Defect found at line 16\" :file \"src/ring_buffer.py\"))))")
        (wroteRcpt "(:agentReceipt :status :ok :deliver :findings :turns 2 :written (\"src/ring_buffer.py\") :findings ((:findings (:claim \"Defect found at line 16\" :file \"src/ring_buffer.py\"))))")
        (okRes (scored cleanRcpt truth11 "clean" "test-model" 1.0 "2026-09-28"))
        (badRes (scored wroteRcpt truth11 "wrote" "test-model" 1.0 "2026-09-28"))]
    (assert (= okRes.status "ok") "clean findings status ok")
    (assert (stringEmpty? okRes.defect) "clean findings defect empty")
    (assert (= badRes.status "failed") "wrote findings status failed")
    (assert (= badRes.defect "wrote 1 files on a findings deliverable") "wrote findings defect message")
    (assert (stringContains? badRes.form ":defect \"wrote 1 files on a findings deliverable\"") "form carries defect")
    true)

fn testDeliverPatchScoresGates -> Bool
  (let [(rcpt "(:agentReceipt :status :ok :deliver :patch :turns 2 :written (\"src/tax.py\") :gates ((:cmd \"python3 test_tax.py\" :exit 0)))")
        (truth "(:truth (:expectedGate :cmd \"python3 test_tax.py\" :exit 0))")
        (res (scored rcpt truth "patch" "test-model" 1.0 "2026-09-28"))]
    (assert (= res.status "ok") "deliver patch scores gates ok")
    (assert (stringEmpty? res.defect) "deliver patch no defect")
    true)

fn testTasksPassNoMode! -> Bool
  (let [(scoutTask1 (resultOr (fileRead "tests/agentEval/cases/scout-false-green/task.asn") ""))
        (scoutTask2 (resultOr (fileRead "tests/agentEval/cases/scout-hardcoded-token/task.asn") ""))
        (scoutTask3 (resultOr (fileRead "tests/agentEval/cases/scout-off-by-one/task.asn") ""))
        (implTask1 (resultOr (fileRead "tests/agentEval/cases/implement-one-line-fix/task.asn") ""))]
    (refute (stringContains? scoutTask1 ":mode") "scout1 has no :mode")
    (refute (stringContains? scoutTask2 ":mode") "scout2 has no :mode")
    (refute (stringContains? scoutTask3 ":mode") "scout3 has no :mode")
    (refute (stringContains? implTask1 ":mode") "impl1 has no :mode")
    (assert (stringContains? scoutTask1 ":owns ()") "scout1 has :owns ()")
    (assert (stringContains? scoutTask2 ":owns ()") "scout2 has :owns ()")
    (assert (stringContains? scoutTask3 ":owns ()") "scout3 has :owns ()")
    true)

fn testEvalRunCarriesBatching -> Bool
  (let [(truth11 "(:defect :file \"src/ring_buffer.py\" :line 16 :kind \"off-by-one\")")
        (batchedRcpt "(:agentReceipt :status :ok :turns 5 :usage (:input 900 :cached 400 :output 100) :batching (:opsPerTurn 2.5 :singleOpShare 0.25 :opTurns 4))")
        (batched (scored batchedRcpt truth11 "batched" "test-model" 1.0 "2026-09-28"))
        (form batched.form)]
    (assert (= batched.tokens 1000) "tokens sum input+output = 1000")
    (assert (stringContains? form ":turns 5 :opsPerTurn 2.5 :singleOpShare 0.25 :tokens 1000 ") "form carries batching and tokens")
    true)

fn testReceiptDeliverPicksScoring -> Bool
  (let [(rPatch (ev/parseReceipt "(:agentReceipt :status :ok :deliver :patch :turns 1)"))
        (rFind (ev/parseReceipt "(:agentReceipt :status :ok :deliver :findings :turns 1)"))
        (rImpl (ev/parseReceipt "(:agentReceipt :status :ok :mode :implement :turns 1)"))]
    (assert (= rPatch.mode "implement") "deliver patch mode implement")
    (assert (= rFind.mode "scout") "deliver findings mode scout")
    (assert (= rImpl.mode "implement") "mode implement preserved")
    true)

fn testEvalRunCarriesPlan -> Bool
  (let [(truth11 "(:defect :file \"src/ring_buffer.py\" :line 16 :kind \"off-by-one\")")
        (plannedRcpt "(:agentReceipt :status :ok :turns 5 :findings ((:findings (:claim \"x\" :file \"a.py\"))) :batching (:opsPerTurn 2.5 :singleOpShare 0.25 :opTurns 4) :plan (:steps 3 :done 2 :dropped 1 :revisions 1))")
        (batchedRcpt "(:agentReceipt :status :ok :turns 5 :usage (:input 900 :cached 400 :output 100) :batching (:opsPerTurn 2.5 :singleOpShare 0.25 :opTurns 4))")
        (planned (scored plannedRcpt truth11 "planned" "test-model" 1.0 "2026-09-28"))
        (batched (scored batchedRcpt truth11 "batched" "test-model" 1.0 "2026-09-28"))]
    (assert (stringEndsWith? planned.form " :plan (:steps 3 :done 2 :dropped 1 :revisions 1))") "form ends with plan")
    (mt planned.plan
      ((some pl) (do (assert (= pl.steps 3) "plan steps 3") (assert (= pl.done 2) "plan done 2") (assert (= pl.dropped 1) "plan dropped 1") (assert (= pl.revisions 1) "plan revisions 1")))
      ((none) (assert false "plan expected")))
    (refute (stringContains? batched.form ":plan ") "batched has no :plan in form")
    (mt batched.plan
      ((some _) (assert false "batched plan must be none"))
      ((none) true))
    true)

fn testInvocationKeepsModelWithoutProfile -> Bool
  (let [(task "(:agent :task \"fix it\" :owns (\"a.py\"))")
        (inv (ev/buildInvocation task "gemini-3.8-flash" ""))]
    (assert (stringContains? inv ":model \"gemini-3.8-flash\"") "invocation keeps model")
    (assert (stringContains? inv ":backend \"agy\"") "invocation adds backend agy")
    true)

fn testInvocationOmitsModelWithProfile -> Bool
  (let [(task "(:agent :task \"fix it\" :owns (\"a.py\"))")
        (inv1 (ev/buildInvocation task "profile-agy" "agy"))
        (inv2 (ev/buildInvocation task "none" ""))]
    (refute (stringContains? inv1 ":model") "invocation omits model when profile set")
    (refute (stringContains? inv2 ":model") "invocation omits model when none")
    (assert (stringContains? inv1 ":backend \"agy\"") "inv1 has backend agy")
    (assert (stringContains? inv2 ":backend \"agy\"") "inv2 has backend agy")
    true)

fn testSummarizeEvalRuns -> Bool
  (let [(run1 (ev/EvalRun :date "2026-09-28" :model "test" :caseId "c1" :recall 1.0 :precision 1.0 :turns 2 :opsPerTurn 1.0 :singleOpShare 0.0 :tokens 100 :wallSec 2.0 :queueWaitSec 0.1 :status "ok" :defect "" :plan (none) :form ""))
        (run2 (ev/EvalRun :date "2026-09-28" :model "test" :caseId "c2" :recall 0.0 :precision 0.0 :turns 3 :opsPerTurn 1.0 :singleOpShare 0.0 :tokens 100 :wallSec 4.0 :queueWaitSec 0.1 :status "failed" :defect "" :plan (none) :form ""))
        (summary (ev/summarizeEvalRuns (list run1 run2)))]
    (assert (= summary.totalCases 2) "summary total cases 2")
    (assert (= summary.passedCases 1) "summary passed cases 1")
    (assert (= summary.failedCases 1) "summary failed cases 1")
    (assert (= summary.avgRecall 0.5) "summary avg recall 0.5")
    (assert (= summary.avgPrecision 0.5) "summary avg precision 0.5")
    (assert (= summary.avgWallSec 3.0) "summary avg wall 3.0")
    (refute (ev/evalSummaryPassed? summary (list run1 run2)) "summary failed when 1 failed")
    (assert (stringContains? summary.form ":cases 2 :passed 1 :failed 1") "summary form")
    true)


fn testScoutReceiptFailedStatusFails -> Bool
  (let [(truth1 "(:defect :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\" :kind \"false-green\")")
        (rcptFailed "(:agentReceipt :status :failed :mode :scout :turns 1 :findings ((:findings (:claim \"Reports false success\" :file \"src/backup.py\" :anchor \"return {\\\"status\\\": \\\"success\\\"\"))))")
        (res (scored rcptFailed truth1 "scout-false-green" "test-model" 1.0 "2026-09-28"))]
    (assert (= res.recall 1.0) "scout fail status recall 1.0")
    (assert (= res.status "failed") "scout fail status status failed")
    true)

fn testImplementReceiptFailedStatusFails -> Bool
  (let [(truth8 "(:gate :cmd \"python3 test_tax.py\" :exit 0)")
        (rcptFailed "(:agentReceipt :status :failed :mode :implement :turns 2 :gates ((:cmd \"python3 test_tax.py\" :exit 0)))")
        (res (scored rcptFailed truth8 "implement-tax" "test-model" 1.0 "2026-09-28"))]
    (assert (= res.status "failed") "implement pass gates but receipt failed status is failed")
    true)

fn testBipartiteMatchingSingleFindingCannotMatchTwoDefects -> Bool
  (let [(truthDual "(:defects (:defect :file \"src/backup.py\" :symbol \"perform_backup\" :anchor \"if not os.path.exists\" :kind \"false-green\") (:defect :file \"src/backup.py\" :symbol \"perform_backup\" :anchor \"except Exception\" :kind \"false-green\"))")
        (rcptSingle "(:agentReceipt :status :ok :mode :scout :turns 2 :findings ((:findings (:claim \"Backup error\" :file \"src/backup.py\" :anchor \"perform_backup\"))))")
        (res (scored rcptSingle truthDual "scout-dual" "test-model" 1.0 "2026-09-28"))]
    (assert (= res.recall 0.5) "single finding matches only one of two defects recall 0.5")
    (assert (= res.precision 1.0) "single finding precision 1.0")
    (assert (= res.status "failed") "single finding partial match status failed")
    true)

fn testLineRegionToleranceEdges -> Bool
  (let [(truthL16 "(:defect :file \"src/ring_buffer.py\" :line 16 :kind \"off-by-one\")")
        (rcptP2 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Defect at line 18\" :file \"src/ring_buffer.py\"))))")
        (rcptM2 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Defect at line 14\" :file \"src/ring_buffer.py\"))))")
        (rcptP3 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Defect at line 19\" :file \"src/ring_buffer.py\"))))")
        (rcptM3 "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Defect at line 13\" :file \"src/ring_buffer.py\"))))")
        (rcptPipe "(:agentReceipt :status :ok :mode :scout :turns 1 :findings ((:findings (:claim \"Broken pipeline 16 is fixed\" :file \"src/ring_buffer.py\"))))")
        (resP2 (scored rcptP2 truthL16 "line-test" "test-model" 1.0 "2026-09-28"))
        (resM2 (scored rcptM2 truthL16 "line-test" "test-model" 1.0 "2026-09-28"))
        (resP3 (scored rcptP3 truthL16 "line-test" "test-model" 1.0 "2026-09-28"))
        (resM3 (scored rcptM3 truthL16 "line-test" "test-model" 1.0 "2026-09-28"))
        (resPipe (scored rcptPipe truthL16 "line-test" "test-model" 1.0 "2026-09-28"))]
    (assert (= resP2.recall 1.0) "line 18 matches line 16 (+2)")
    (assert (= resM2.recall 1.0) "line 14 matches line 16 (-2)")
    (assert (= resP3.recall 0.0) "line 19 misses line 16 (+3)")
    (assert (= resM3.recall 0.0) "line 13 misses line 16 (-3)")
    (assert (= resPipe.recall 0.0) "pipeline 16 does not match as line 16")
    true)

fn testSymbolWordBoundaryPreventsSubstringMatch -> Bool
  (let [(dSym (ev/Defect :file "src/backup.py" :anchor "return {\"status\": \"success\"" :kind "" :line (none) :symbol "backup" :raw ""))
        (missSub (ev/Finding :file "src/backup.py" :anchor "" :claim "restore_backup swallows errors" :line (none) :raw ""))
        (hitExact (ev/Finding :file "src/backup.py" :anchor "" :claim "error in backup function" :line (none) :raw ""))]
    (refute (ev/matchFindingToDefect missSub dSym) "substring restore_backup does not match symbol backup")
    (assert (ev/matchFindingToDefect hitExact dSym) "word backup matches symbol backup")
    true)

fn testInvocationPreservesExistingBackend -> Bool
  (let [(task "(:agent :task \"fix it\" :backend \"custom\" :owns (\"a.py\"))")
        (inv (ev/buildInvocation task "gemini-3.8-flash" ""))]
    (assert (stringContains? inv ":backend \"custom\"") "invocation preserves custom backend")
    (refute (stringContains? inv ":backend \"agy\"") "invocation does not add duplicate agy backend")
    true)

fn testSummarizeEvalRunsEmpty -> Bool
  (let [(summary (ev/summarizeEvalRuns (list)))]
    (assert (= summary.totalCases 0) "empty summary total cases 0")
    (assert (= summary.passedCases 0) "empty summary passed cases 0")
    (assert (= summary.failedCases 0) "empty summary failed cases 0")
    (assert (stringEmpty? summary.date) "empty summary date empty")
    (assert (stringEmpty? summary.model) "empty summary model empty")
    (assert (= summary.form "(:evalSummary :date \"\" :model \"\" :cases 0 :passed 0 :failed 0 :avgRecall 0.0 :avgPrecision 0.0 :avgWallSec 0.0)") "empty summary form")
    true)

fn ! runTests -> Bool
  (and (testScoutPerfectRecallAndPrecision)
  (and (testScoutZeroFindingsZeroRecall)
  (and (testScoutExtraneousFindingLowerPrecision)
  (and (testScoutWrongFileNoMatch)
  (and (testScoutWrongAnchorNoMatch)
  (and (testScoutMultipleDefectsPartialRecall)
  (and (testScoutMultipleDefectsFullRecall)
  (and (testScoutReceiptFailedStatusFails)
  (and (testImplementGatePass)
  (and (testImplementGateFail)
  (and (testImplementGateLastRunGreen)
  (and (testImplementGateLastRunRed)
  (and (testImplementReceiptFailedStatusFails)
  (and (testBipartiteMatchingSingleFindingCannotMatchTwoDefects)
  (and (testTimingAndTurnsExtraction)
  (and (testLineRegionMatching)
  (and (testLineRegionToleranceEdges)
  (and (testEvalRunFormFormat)
  (and (testSymbolAnchorMatches)
  (and (testSymbolWordBoundaryPreventsSubstringMatch)
  (and (testOtherSymbolSameFileMisses)
  (and (testTruthCarriesSymbol!)
  (and (testNestedFindingsSplit)
  (and (testFindingsWriteIsDefect)
  (and (testDeliverPatchScoresGates)
  (and (testTasksPassNoMode!)
  (and (testEvalRunCarriesBatching)
  (and (testReceiptDeliverPicksScoring)
  (and (testEvalRunCarriesPlan)
  (and (testInvocationKeepsModelWithoutProfile)
  (and (testInvocationOmitsModelWithProfile)
  (and (testInvocationPreservesExistingBackend)
  (and (testSummarizeEvalRuns)
       (testSummarizeEvalRunsEmpty))))))))))))))))))))))))))))))))))
