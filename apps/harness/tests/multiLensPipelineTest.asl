(module aslHarness/multiLensPipelineTest :x [testCreatePipeline testGapAuditClean testGapAuditOmission testGapAuditBloat testImplAuditClean testImplAuditFailed testAdvanceStage testEntropyClassification testPipelineModes testAddieConfig runStepsPipelineTests runTests] :i [(multiLensPipeline :a sp)])

fn testCreatePipeline -> Bool
  (let [(p (sp/createStepsPipeline "task-x" "Build an HTML sanitizer in /app/filter.py"))] (do (assert (= p.taskId "task-x")) (assert (= p.activeStage "scout")) (assert (= (listLength p.phases) 5)) (assert (not p.isCompleted)) true))

fn testGapAuditClean -> Bool
  (let [(inst "Write a script taking argv[1] and exit 1 on error") (steps ["1. Check argv[1] input" "2. Parse payload" "3. If error exit 1" "4. Test runner"]) (audit (sp/auditPlanGaps inst steps))] (do (assert (= audit.verdict "approve")) (assert audit.invariantsPreserved) (assert (not (= audit.verdict "reject"))) true))

fn testGapAuditOmission -> Bool
  (let [(inst "Write a script taking argv[1] and modifying in-place") (steps ["1. Just process hardcoded file" "2. Done"]) (audit (sp/auditPlanGaps inst steps))] (do (assert (= audit.verdict "approve-with-amendments")) (assert (not audit.invariantsPreserved)) (assert (> (listLength audit.omissions) 0)) true))

fn testGapAuditBloat -> Bool
  (let [(inst "Simple string replace") (steps ["1. A" "2. B" "3. C" "4. D" "5. E" "6. F" "7. G" "8. H" "9. I" "10. J"]) (audit (sp/auditPlanGaps inst steps))] (do (assert (= audit.verdict "approve-with-amendments")) (assert (> (listLength audit.bloatWarnings) 0)) (assert (not (= (listLength audit.bloatWarnings) 0))) true))

fn testImplAuditClean -> Bool
  (let [(inst "Modify in-place") (diff "+ with open(p, 'w') as f: f.write(res)") (audit (sp/auditImplGaps inst diff true))] (do (assert (= audit.verdict "approve")) (assert audit.invariantsPreserved) (assert (not (= audit.verdict "reject"))) true))

fn testImplAuditFailed -> Bool
  (let [(inst "Modify in-place") (diff "+ bad code") (audit (sp/auditImplGaps inst diff false))] (do (assert (= audit.verdict "reject")) (assert (not (= audit.verdict "approve"))) true))

fn testAdvanceStage -> Bool
  (let [(p (sp/createStepsPipeline "task-1" "Simple task")) (p1 (sp/advancePipelineStage p true "ls ok"))] (do (assert (= p1.currentPhaseIdx 1)) (assert (= p1.activeStage "plan")) (assert (not (= p1.currentPhaseIdx 0))) true))

fn testEntropyClassification -> Bool
  (do (assert (= (sp/classifyTaskEntropy "terminal-bench/html-js-filter: prevent xss attacks") "full")) (assert (= (sp/classifyTaskEntropy "TB-042: solve interleaved vigenere cipher") "full")) (assert (= (sp/classifyTaskEntropy "Fix small typo in comment") "fast")) (assert (= (sp/classifyTaskEntropy "Add REST endpoint for user profiles") "standard")) (assert (not (= (sp/classifyTaskEntropy "Fix small typo in comment") "full"))) true)

fn testPipelineModes -> Bool
  (let [(pFast (sp/makePipelineByMode "t-fast" "fix typo" "fast")) (pStd (sp/makePipelineByMode "t-std" "add endpoint" "standard")) (pFull (sp/makePipelineByMode "t-full" "xss security filter" "full")) (pAdapt (sp/makePipelineByMode "t-adapt" "crypto vigenere solver" "adaptive"))] (do (assert (= (listLength pFast.phases) 2)) (assert (= pFast.activeStage "impl")) (assert (= (listLength pStd.phases) 3)) (assert (= pStd.activeStage "plan")) (assert (= (listLength pFull.phases) 5)) (assert (= pFull.activeStage "scout")) (assert (= (listLength pAdapt.phases) 5)) (assert (not (= (listLength pFast.phases) 5))) true))

fn testAddieConfig -> Bool
  (let [(cfg (sp/defaultAddieConfig))] (do (assert (= cfg.pipeline "full")) (assert cfg.aslFirst) (assert cfg.scoutPolyglot) (assert (not (= cfg.pipeline "fast"))) true))

fn runStepsPipelineTests -> Bool
  (do (assert (testCreatePipeline)) (assert (testGapAuditClean)) (assert (testGapAuditOmission)) (assert (testGapAuditBloat)) (assert (testImplAuditClean)) (assert (testImplAuditFailed)) (assert (testAdvanceStage)) (assert (testEntropyClassification)) (assert (testPipelineModes)) (assert (testAddieConfig)) true)

fn runTests -> Bool
  (runStepsPipelineTests)
