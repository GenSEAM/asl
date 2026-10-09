(module aslHarness/skillsProjectionTest :x [testTeleologyMandateProjections testStepsPipelineProjection testGapAuditContractProjection testAntiHallucinationProjection runProjectionTests runTests] :i [(teleology :a tel) (multiLensPipeline :a pipe) (antiHallucination :a anti) (asl-parser/balance :a bal)])

fn testTeleologyMandateProjections -> Bool
  (let [(scout (tel/makeScoutMandate)) (planner (tel/makePlannerMandate)) (impl (tel/makeImplementerMandate)) (auditor (tel/makeAuditorMandate))] (assert (= scout.archetypeId "scout") "scout archetype id matches") (assert (= planner.archetypeId "planner") "planner archetype id matches") (assert (= impl.archetypeId "implementer") "implementer archetype id matches") (assert (= auditor.archetypeId "auditor") "auditor archetype id matches") (assert (> (listLength scout.values) 0) "scout has declared values") (assert (> (listLength planner.values) 0) "planner has declared values") (assert (> (listLength impl.values) 0) "implementer has declared values") (assert (> (listLength auditor.values) 0) "auditor has declared values") true)

fn testStepsPipelineProjection -> Bool
  (let [(stdPhases (pipe/makeStandardPhases "test-task")) (epiPhases (pipe/makeEpistemic7Phases "test-task"))] (assert (= (listLength stdPhases) 5) "standard pipeline creates exactly 5 phases") (let [(p1 (optionOr (listHead stdPhases) (pipe/StepPhase :id "" :name "" :stage "" :gateCommand "" :status "" :findings (list))))] (assert (= p1.stage "scout") "first standard phase stage is scout")) (assert (= (listLength epiPhases) 7) "epistemic pipeline creates exactly 7 stages") (let [(e1 (optionOr (listHead epiPhases) (pipe/StepPhase :id "" :name "" :stage "" :gateCommand "" :status "" :findings (list))))] (assert (= e1.stage "s1-ingest") "first epistemic stage is s1-ingest")) true)

fn testGapAuditContractProjection -> Bool
  (let [(res (pipe/GapAuditResult :verdict "approve" :omissions (list) :bloatWarnings (list) :invariantsPreserved true :recommendations (list "keep minimal")))] (assert res.invariantsPreserved "gap audit preserves invariants") (assert (= res.verdict "approve") "gap audit reports approve verdict") true)

fn testAntiHallucinationProjection -> Bool
  (let [(unbalanced "(:batch (:out \"test.asl\"") (balanced (bal/balanceDelimiters unbalanced))] (assert (stringEndsWith? balanced "))") "anti-hallucination auto-balances S-expressions") (assert (not (stringEndsWith? balanced "test.asl\"")) "delimiters are not unclosed") true)

fn runProjectionTests -> Bool
  (do (testTeleologyMandateProjections) (testStepsPipelineProjection) (testGapAuditContractProjection) (testAntiHallucinationProjection) true)

fn runTests -> Bool
  (runProjectionTests)
