(module aslHarness/modelCalibration :x [CanaryTask CalibrationCandidate CalibrationEvaluationResult CalibrationSweepConfig CtrfSummary ScalarLossMetric makeCanaryTask canonicalCanaryTasks slmCalibrationTasks nanoCalibrationTasks browserCalibrationTasks mediumCalibrationTasks frontierCalibrationTasks superHardCalibrationTasks fullSpectrumCanaryTasks tasksForTier enforceBrowserModelCeiling computeParetoScore computeGradientParetoScore computeLossProgress computeScalarLoss computeCeilingLoss parseCtrfSummary evaluateCtrfTrial evaluateScalarLossTrial evaluateCandidate runCalibrationSweep runCalibrationSweepWithTranslation generateCandidatesWithTranslationLoop makeCalibrationCandidate makeEvaluationResult findOptimalCandidate formatCalibrationResultAsn] :i [(contextAssembler :a ca) (contextBench :a cb) (promptTranslator :a pt)])

(schema CanaryTask (:f taskId Str) (:f name Str) (:f kind Str) (:f totalSteps I64) (:f blocks (List ca/ContextBlock)) (:f requiredFacts (List Str)))

(schema CalibrationCandidate (:f modelName Str) (:f strategy Str) (:f temperature F64) (:f budgetCeiling I64) (:f asnPromptEnabled Bool))

(schema CalibrationEvaluationResult (:f candidate CalibrationCandidate) (:f passRate F64) (:f continuousProgress F64) (:f avgTokens I64) (:f latencyMs I64) (:f amnesiaDetected Bool) (:f paretoScore F64) (:f status Str) (:f asnPromptUsed Bool) (:f asnFallbackTriggered Bool))

(schema CalibrationSweepConfig (:f modelName Str) (:f strategies (List Str)) (:f temperatures (List F64)) (:f budgetCeilings (List I64)) (:f dryRun Bool))

(schema CtrfSummary (:f totalTests I64) (:f passedTests I64) (:f failedTests I64) (:f progressRatio F64))

(schema ScalarLossMetric (:f metricName Str) (:f currentVal F64) (:f targetVal F64) (:f normalizedLoss F64))

fn makeCanaryTask taskId: Str name: Str kind: Str steps: I64 blocks: (List ca/ContextBlock) facts: (List Str) -> CanaryTask
  (CanaryTask :taskId taskId :name name :kind kind :totalSteps steps :blocks blocks :requiredFacts facts)

fn canonicalCanaryTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 50 "You are Implementer")) (bSyn (ca/makeContextBlock "syn" "task-spec" 90 "Refactor syntax AST [fact: lexer-rule-42]")) (t1 (makeCanaryTask "CANARY-SYNTAX-01" "Syntax Refactoring" "syntax" 3 (list bSys bSyn) (list "lexer-rule-42"))) (bFsm (ca/makeContextBlock "fsm" "task-spec" 110 "FSM state step [fact: state-id-beta]")) (t2 (makeCanaryTask "CANARY-STATE-02" "State Machine Step" "state-machine" 4 (list bSys bFsm) (list "state-id-beta"))) (bAmn (ca/makeContextBlock "amn" "task-spec" 100 "Crypto seed probe [fact: seed-salt-888]")) (t3 (makeCanaryTask "CANARY-AMNESIA-03" "Amnesia Retention Probe" "amnesia-probe" 4 (list bSys bAmn) (list "seed-salt-888")))] (list t1 t2 t3))

fn slmCalibrationTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 40 "Affirmative ASL agent")) (bDelim (ca/makeContextBlock "delim" "syntax-spec" 60 "Balance delimiter [fact: token-parens-ok]")) (t1 (makeCanaryTask "SLM-DELIM-01" "Delimiter Balance" "syntax" 2 (list bSys bDelim) (list "token-parens-ok"))) (bTool (ca/makeContextBlock "tool" "tool-spec" 50 "Invoke AST symbol [fact: sym-resolve-42]")) (t2 (makeCanaryTask "SLM-TOOL-02" "Affirmative Tool Call" "tool-schema" 2 (list bSys bTool) (list "sym-resolve-42"))) (bSlice (ca/makeContextBlock "slice" "slice-spec" 55 "Targeted slice read [fact: line-slice-range]")) (t3 (makeCanaryTask "SLM-SLICE-03" "Narrow Slice Read" "context-slice" 3 (list bSys bSlice) (list "line-slice-range"))) (bFact (ca/makeContextBlock "fact" "retention-spec" 45 "Retain state key [fact: salt-micro-777]")) (t4 (makeCanaryTask "SLM-FACT-04" "Short Horizon Fact Retention" "amnesia-probe" 3 (list bSys bFact) (list "salt-micro-777"))) (bExit (ca/makeContextBlock "exit" "recovery-spec" 50 "Catch error code [fact: exit-halt-0]")) (t5 (makeCanaryTask "SLM-EXIT-05" "Error Circuit Break" "error-recovery" 2 (list bSys bExit) (list "exit-halt-0")))] (list t1 t2 t3 t4 t5))

fn frontierCalibrationTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 80 "Autonomous Systems Architect & Sovereign Implementer")) (bHeap (ca/makeContextBlock "heap" "crash-spec" 180 "Diagnose heap corruption in custom-memory-heap-crash [fact: alloc-header-guard]")) (t1 (makeCanaryTask "FRONT-HEAP-01" "Custom Memory Heap Crash" "memory-safety" 5 (list bSys bHeap) (list "alloc-header-guard"))) (bBlast (ca/makeContextBlock "blast" "refactor-spec" 160 "Execute blast-radius refactor across 4 callers [fact: caller-graph-acyclic]")) (t2 (makeCanaryTask "FRONT-BLAST-02" "Multi-Module Blast Radius" "ast-refactor" 5 (list bSys bBlast) (list "caller-graph-acyclic"))) (bAir (ca/makeContextBlock "air" "airgap-spec" 150 "Hermetic cross-compilation sysroot resolution [fact: target-triple-sysroot]")) (t3 (makeCanaryTask "FRONT-AIRGAP-03" "Hermetic Sysroot Resolution" "cross-compile" 4 (list bSys bAir) (list "target-triple-sysroot"))) (bEsh (ca/makeContextBlock "esh" "gate-spec" 140 "Reject unexecuted verbal assertion claims [fact: ctrf-physical-receipt]")) (t4 (makeCanaryTask "FRONT-ESH-04" "Verbal ESH Interception" "gate-audit" 4 (list bSys bEsh) (list "ctrf-physical-receipt"))) (bWork (ca/makeContextBlock "work" "worktree-spec" 170 "Multi-branch isolated git worktree lifecycle [fact: worktree-ref-head]")) (t5 (makeCanaryTask "FRONT-WORKTREE-05" "Worktree Scoping Invariant" "worktree" 5 (list bSys bWork) (list "worktree-ref-head")))] (list t1 t2 t3 t4 t5))

fn mediumCalibrationTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 60 "Specialized Coding Subagent")) (bPatch (ca/makeContextBlock "patch" "multi-patch-spec" 120 "Perform atomic multi-hunk patch across two modules [fact: patch-atomic-hunk]")) (t1 (makeCanaryTask "MED-PARSE-01" "Concurrent Multi-Hunk Form Patch" "ast-patch" 3 (list bSys bPatch) (list "patch-atomic-hunk"))) (bRoll (ca/makeContextBlock "roll" "rollback-spec" 110 "Roll back dirty buffer on compiler failure [fact: buffer-rollback-ok]")) (t2 (makeCanaryTask "MED-COMPILER-ROLLBACK-02" "In-Memory Error Rollback" "compiler-feedback" 3 (list bSys bRoll) (list "buffer-rollback-ok"))) (bSpool (ca/makeContextBlock "spool" "search-spec" 130 "Find deadlock line in 1000-line spool [fact: thread-deadlock-line]")) (t3 (makeCanaryTask "MED-LOG-BM25-SEARCH-03" "Okapi BM25 Spool Log Search" "spool-search" 4 (list bSys bSpool) (list "thread-deadlock-line"))) (bConv (ca/makeContextBlock "conv" "codec-spec" 115 "Transpile JSON payload into ASN typed record [fact: codec-roundtrip-bitexact]")) (t4 (makeCanaryTask "MED-REPRESENTATION-CONVERT-04" "JSON to ASN Codec Transpilation" "asl-codec" 3 (list bSys bConv) (list "codec-roundtrip-bitexact"))) (bWatch (ca/makeContextBlock "watch" "deadline-spec" 125 "Recover from 10-second subprocess deadline timeout [fact: deadline-sigint-recover]")) (t5 (makeCanaryTask "MED-TIMEOUT-DEADLINE-05" "Supervised Deadline Recovery" "deadline" 3 (list bSys bWatch) (list "deadline-sigint-recover")))] (list t1 t2 t3 t4 t5))

fn superHardCalibrationTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 100 "Principal Distributed Systems & Formal Verification Architect")) (bPaxos (ca/makeContextBlock "paxos" "consensus-spec" 240 "Synthesize split-brain recovery under asymmetric network partitions and monotonic clock drift [fact: byzantine-paxos-quorum]")) (t1 (makeCanaryTask "IMPOSSIBLE-DISTRIB-CONSENSUS-01" "Distributed Byzantine Paxos Under Dynamic Partitions" "formal-consensus" 6 (list bSys bPaxos) (list "byzantine-paxos-quorum"))) (bArena (ca/makeContextBlock "arena" "allocator-spec" 250 "Zero-allocation generational compacting arena in 64KB Wasm Linear Memory with cyclic pointer relocation [fact: bitexact-arena-reloc]")) (t2 (makeCanaryTask "IMPOSSIBLE-ZERO-ALLOC-GC-02" "Wasm MicroVM Zero-Allocation Arena Compactor" "linear-memory-gc" 6 (list bSys bArena) (list "bitexact-arena-reloc")))] (list t1 t2))

fn fullSpectrumCanaryTasks -> (List CanaryTask)
  (listAppend (slmCalibrationTasks) (listAppend (mediumCalibrationTasks) (listAppend (frontierCalibrationTasks) (superHardCalibrationTasks))))

fn nanoCalibrationTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 25 "Nano Classifier")) (bTag (ca/makeContextBlock "tag" "tag-spec" 30 "Classify token [fact: tag-intent-read]")) (t1 (makeCanaryTask "NANO-TAG-01" "Single Token Classify" "classification" 2 (list bSys bTag) (list "tag-intent-read"))) (bMat (ca/makeContextBlock "mat" "match-spec" 35 "Match regex token [fact: match-sym-ident]")) (t2 (makeCanaryTask "NANO-MATCH-02" "Regex Token Match" "pattern-match" 2 (list bSys bMat) (list "match-sym-ident"))) (bCnt (ca/makeContextBlock "cnt" "count-spec" 30 "Count parens balance [fact: count-parens-1]")) (t3 (makeCanaryTask "NANO-COUNT-03" "Paren Delimiter Count" "delimiter" 2 (list bSys bCnt) (list "count-parens-1")))] (list t1 t2 t3))

fn browserCalibrationTasks -> (List CanaryTask)
  (let [(bSys (ca/makeContextBlock "sys" "sys-mandate" 40 "Browser SLM Agent")) (bDom (ca/makeContextBlock "dom" "dom-spec" 65 "Resolve DOM selector [fact: dom-selector-query]")) (t1 (makeCanaryTask "BROWSER-DOM-01" "DOM Selector Resolution" "dom-query" 2 (list bSys bDom) (list "dom-selector-query"))) (bAct (ca/makeContextBlock "act" "act-spec" 55 "Affirmative 4-tool action dispatch [fact: affirm-action-valid]")) (t2 (makeCanaryTask "BROWSER-ACT-02" "Affirmative Action Dispatch" "affirmative-tool" 2 (list bSys bAct) (list "affirm-action-valid"))) (bToy (ca/makeContextBlock "toy" "toy-spec" 70 "Simulate cellular automata grid step [fact: toy-life-step-ok]")) (t3 (makeCanaryTask "BROWSER-TOY-03" "Interactive Toy Simulation Step" "toy-sim" 3 (list bSys bToy) (list "toy-life-step-ok"))) (bVdom (ca/makeContextBlock "vdom" "vdom-spec" 75 "Emit reactive VDOM element form [fact: vdom-render-pure]")) (t4 (makeCanaryTask "BROWSER-VDOM-04" "Reactive VDOM Form Generation" "vdom-render" 3 (list bSys bVdom) (list "vdom-render-pure")))] (list t1 t2 t3 t4))

fn enforceBrowserModelCeiling modelName: Str -> Bool
  (if (or (stringContains? modelName "7B") (or (stringContains? modelName "7b") (or (stringContains? modelName "8B") (or (stringContains? modelName "8b") (or (stringContains? modelName "9B") (or (stringContains? modelName "9b") (or (stringContains? modelName "14B") (or (stringContains? modelName "14b") (or (stringContains? modelName "31B") (or (stringContains? modelName "31b") (or (stringContains? modelName "70B") (stringContains? modelName "70b")))))))))))) false true)

fn tasksForTier tier: Str -> (List CanaryTask)
  (cond ((= tier "nano") (nanoCalibrationTasks)) ((= tier "browser") (browserCalibrationTasks)) ((= tier "slm") (slmCalibrationTasks)) ((= tier "medium") (mediumCalibrationTasks)) ((= tier "frontier") (frontierCalibrationTasks)) ((= tier "impossible") (superHardCalibrationTasks)) ((= tier "super-hard") (superHardCalibrationTasks)) ((= tier "all") (fullSpectrumCanaryTasks)) (else (canonicalCanaryTasks)))

fn extractFirstDigits chars: (List Str) acc: Str -> Str
  (if (listEmpty? chars) acc (let [(c (optionOr (listHead chars) "")) (rst (optionOr (listTail chars) (list)))] (if (stringContains? "0123456789" c) (extractFirstDigits rst (str acc c)) (if (stringEmpty? acc) (if (or (= c " ") (or (= c ":") (or (= c "\t") (= c "\n")))) (extractFirstDigits rst "") acc) acc))))

fn extractIntKw raw: Str kw: Str -> I64
  (let [(idxOpt (stringIndexOf raw kw))] (mt idxOpt ((some idx) (let [(tailOpt (stringSlice raw (+ idx (stringLength kw)) (stringLength raw))) (tail (optionOr tailOpt "")) (digits (extractFirstDigits (stringChars tail) ""))] (optionOr (stringToInt64 digits) 0))) ((none) 0)))

fn parseCtrfSummary ctrfContent: Str -> CtrfSummary
  (let [(tests (let [(t (extractIntKw ctrfContent ":tests"))] (if (> t 0) t (extractIntKw ctrfContent "\"tests\":")))) (passed (let [(p (extractIntKw ctrfContent ":passed"))] (if (> p 0) p (extractIntKw ctrfContent "\"passed\":")))) (failed (let [(f (extractIntKw ctrfContent ":failed"))] (if (> f 0) f (extractIntKw ctrfContent "\"failed\":")))) (effTotal (if (> tests 0) tests (+ passed failed))) (fPass (int64ToFloat64 passed)) (fTotal (int64ToFloat64 (max 1 effTotal))) (ratio (if (> effTotal 0) (/ fPass fTotal) 0.0))] (CtrfSummary :totalTests effTotal :passedTests passed :failedTests failed :progressRatio ratio))

fn computeLossProgress loss: F64 -> F64
  (if (<= loss 0.0) 1.0 (/ 1.0 (+ 1.0 loss)))

fn computeScalarLoss name: Str curr: F64 target: F64 -> ScalarLossMetric
  (let [(delta (- curr target)) (absDelta (if (< delta 0.0) (- 0.0 delta) delta)) (denom (if (= target 0.0) 1.0 (if (< target 0.0) (- 0.0 target) target))) (normLoss (/ absDelta denom))] (ScalarLossMetric :metricName name :currentVal curr :targetVal target :normalizedLoss normLoss))

fn computeCeilingLoss name: Str curr: F64 ceiling: F64 -> ScalarLossMetric
  (let [(excess (- curr ceiling)) (normLoss (if (<= excess 0.0) 0.0 (/ excess (max 1.0 ceiling))))] (ScalarLossMetric :metricName name :currentVal curr :targetVal ceiling :normalizedLoss normLoss))

fn computeGradientParetoScore passRate: F64 continuousProgress: F64 tokens: I64 amnesia: Bool latMs: I64 -> F64
  (let [(fTok (int64ToFloat64 tokens)) (fLat (int64ToFloat64 latMs)) (effectiveRate (max passRate (* continuousProgress 100.0))) (baseEff (/ (* effectiveRate 1000.0) (+ fTok 10.0))) (amnesiaPen (if amnesia 500.0 0.0)) (latPen (/ fLat 2000.0))] (- (- baseEff amnesiaPen) latPen))

fn computeParetoScore passRate: F64 tokens: I64 amnesia: Bool latMs: I64 -> F64
  (computeGradientParetoScore passRate (if (> passRate 0.0) (/ passRate 100.0) 0.0) tokens amnesia latMs)

fn simulateCanaryStep cTask: CanaryTask strat: Str ceiling: I64 -> cb/StrategyRunMetrics
  (let [(benchTask (cb/makeBenchTask cTask.taskId cTask.name cTask.totalSteps cTask.blocks cTask.requiredFacts false))] (cb/simulateTaskUnderStrategy benchTask strat ceiling))

(schema CanaryEvalAcc (:f passedCount I64) (:f tokenSum I64) (:f amnesiaCount I64) (:f latencySum I64))

fn makeCalibrationCandidate model: Str strat: Str temp: F64 budget: I64 asnEnabled: Bool -> CalibrationCandidate
  (CalibrationCandidate :modelName model :strategy strat :temperature temp :budgetCeiling budget :asnPromptEnabled asnEnabled)

fn makeEvaluationResult cand: CalibrationCandidate pass: F64 prog: F64 tok: I64 lat: I64 amn: Bool pareto: F64 status: Str asnUsed: Bool fallback: Bool -> CalibrationEvaluationResult
  (CalibrationEvaluationResult :candidate cand :passRate pass :continuousProgress prog :avgTokens tok :latencyMs lat :amnesiaDetected amn :paretoScore pareto :status status :asnPromptUsed asnUsed :asnFallbackTriggered fallback)

fn evaluateCandidate cand: CalibrationCandidate tasks: (List CanaryTask) dryRun: Bool -> CalibrationEvaluationResult
  (let [(strat cand.strategy) (ceiling cand.budgetCeiling) (model cand.modelName) (asnEnabled cand.asnPromptEnabled) (transCfg (pt/makeTranslationConfig asnEnabled true true model)) (transRes (pt/translatePrompt "Canary evaluation run" transCfg)) (asnUsed transRes.translated) (fallbackTriggered transRes.fallbackUsed) (initAcc (CanaryEvalAcc :passedCount 0 :tokenSum 0 :amnesiaCount 0 :latencySum 0)) (finalAcc (fold (fn [(acc CanaryEvalAcc) (t CanaryTask)] -> CanaryEvalAcc (let [(res (simulateCanaryStep t strat ceiling)) (isPass res.passed) (baseTok res.promptTokens) (tok (if asnUsed (/ (* baseTok 70) 100) baseTok)) (isAmn res.amnesiaDetected) (lat res.durationMs)] (CanaryEvalAcc :passedCount (if isPass (+ acc.passedCount 1) acc.passedCount) :tokenSum (+ acc.tokenSum tok) :amnesiaCount (if isAmn (+ acc.amnesiaCount 1) acc.amnesiaCount) :latencySum (+ acc.latencySum lat)))) initAcc tasks)) (totalTasks (listLength tasks)) (fTotal (int64ToFloat64 (max 1 totalTasks))) (fPassed (int64ToFloat64 finalAcc.passedCount)) (passRate (* (/ fPassed fTotal) 100.0)) (continuousProgress (/ fPassed fTotal)) (avgTok (/ finalAcc.tokenSum (max 1 totalTasks))) (avgLat (/ finalAcc.latencySum (max 1 totalTasks))) (amnesiaDetected (> finalAcc.amnesiaCount 0)) (pareto (computeGradientParetoScore passRate continuousProgress avgTok amnesiaDetected avgLat)) (status (if (and (>= passRate 90.0) (not amnesiaDetected)) ":passed" ":rejected"))] (CalibrationEvaluationResult :candidate cand :passRate passRate :continuousProgress continuousProgress :avgTokens avgTok :latencyMs avgLat :amnesiaDetected amnesiaDetected :paretoScore pareto :status status :asnPromptUsed asnUsed :asnFallbackTriggered fallbackTriggered))

fn evaluateCtrfTrial cand: CalibrationCandidate ctrfText: Str tokens: I64 latMs: I64 -> CalibrationEvaluationResult
  (let [(ctrf (parseCtrfSummary ctrfText)) (contProg ctrf.progressRatio) (passRate (if (= ctrf.totalTests 0) 0.0 (if (= ctrf.failedTests 0) 100.0 0.0))) (pareto (computeGradientParetoScore passRate contProg tokens false latMs)) (status (if (= passRate 100.0) ":passed" ":rejected"))] (CalibrationEvaluationResult :candidate cand :passRate passRate :continuousProgress contProg :avgTokens tokens :latencyMs latMs :amnesiaDetected false :paretoScore pareto :status status :asnPromptUsed cand.asnPromptEnabled :asnFallbackTriggered false))

fn evaluateScalarLossTrial cand: CalibrationCandidate metric: ScalarLossMetric tokens: I64 latMs: I64 -> CalibrationEvaluationResult
  (let [(contProg (computeLossProgress metric.normalizedLoss)) (passRate (if (<= metric.normalizedLoss 0.0) 100.0 0.0)) (pareto (computeGradientParetoScore passRate contProg tokens false latMs)) (status (if (= passRate 100.0) ":passed" ":rejected"))] (CalibrationEvaluationResult :candidate cand :passRate passRate :continuousProgress contProg :avgTokens tokens :latencyMs latMs :amnesiaDetected false :paretoScore pareto :status status :asnPromptUsed cand.asnPromptEnabled :asnFallbackTriggered false))

(schema SweepCandidateList (:f candidates (List CalibrationCandidate)))

fn generateCandidatesLoop model: Str strats: (List Str) temps: (List F64) budgets: (List I64) -> (List CalibrationCandidate)
  (fold (fn [(acc (List CalibrationCandidate)) (strat Str)] -> (List CalibrationCandidate) (let [(tempCand (fold (fn [(acc2 (List CalibrationCandidate)) (temp F64)] -> (List CalibrationCandidate) (let [(bCand (map (fn [(b I64)] -> CalibrationCandidate (CalibrationCandidate :modelName model :strategy strat :temperature temp :budgetCeiling b :asnPromptEnabled false)) budgets))] (listAppend acc2 bCand))) (list) temps))] (listAppend acc tempCand))) (list) strats)

fn generateCandidatesWithTranslationLoop model: Str strats: (List Str) temps: (List F64) budgets: (List I64) asnFlags: (List Bool) -> (List CalibrationCandidate)
  (fold (fn [(acc (List CalibrationCandidate)) (asnFlag Bool)] -> (List CalibrationCandidate) (let [(cands (fold (fn [(acc2 (List CalibrationCandidate)) (strat Str)] -> (List CalibrationCandidate) (let [(tempCand (fold (fn [(acc3 (List CalibrationCandidate)) (temp F64)] -> (List CalibrationCandidate) (let [(bCand (map (fn [(b I64)] -> CalibrationCandidate (CalibrationCandidate :modelName model :strategy strat :temperature temp :budgetCeiling b :asnPromptEnabled asnFlag)) budgets))] (listAppend acc3 bCand))) (list) temps))] (listAppend acc2 tempCand))) (list) strats))] (listAppend acc cands))) (list) asnFlags)

fn insertResult item: CalibrationEvaluationResult sorted: (List CalibrationEvaluationResult) -> (List CalibrationEvaluationResult)
  (if (listEmpty? sorted) (list item) (let [(defaultR (CalibrationEvaluationResult :candidate (CalibrationCandidate :modelName "" :strategy "" :temperature 0.0 :budgetCeiling 0 :asnPromptEnabled false) :passRate 0.0 :continuousProgress 0.0 :avgTokens 0 :latencyMs 0 :amnesiaDetected false :paretoScore 0.0 :status "" :asnPromptUsed false :asnFallbackTriggered false)) (headR (optionOr (listHead sorted) defaultR)) (tailR (optionOr (listTail sorted) (list)))] (if (> item.paretoScore headR.paretoScore) (cons item sorted) (cons headR (insertResult item tailR)))))

fn sortResultsLoop unsorted: (List CalibrationEvaluationResult) sorted: (List CalibrationEvaluationResult) -> (List CalibrationEvaluationResult)
  (if (listEmpty? unsorted) sorted (let [(defaultR (CalibrationEvaluationResult :candidate (CalibrationCandidate :modelName "" :strategy "" :temperature 0.0 :budgetCeiling 0 :asnPromptEnabled false) :passRate 0.0 :continuousProgress 0.0 :avgTokens 0 :latencyMs 0 :amnesiaDetected false :paretoScore 0.0 :status "" :asnPromptUsed false :asnFallbackTriggered false)) (headR (optionOr (listHead unsorted) defaultR)) (tailR (optionOr (listTail unsorted) (list)))] (sortResultsLoop tailR (insertResult headR sorted))))

fn sortResultsByScore unsorted: (List CalibrationEvaluationResult) -> (List CalibrationEvaluationResult)
  (sortResultsLoop unsorted (list))

fn runCalibrationSweep cfg: CalibrationSweepConfig -> (List CalibrationEvaluationResult)
  (let [(model cfg.modelName) (strats cfg.strategies) (temps cfg.temperatures) (budgets cfg.budgetCeilings) (dryRun cfg.dryRun) (candidates (generateCandidatesLoop model strats temps budgets)) (tasks (canonicalCanaryTasks)) (evalResults (map (fn [(cand CalibrationCandidate)] -> CalibrationEvaluationResult (evaluateCandidate cand tasks dryRun)) candidates))] (sortResultsByScore evalResults))

fn runCalibrationSweepWithTranslation cfg: CalibrationSweepConfig asnFlags: (List Bool) -> (List CalibrationEvaluationResult)
  (let [(model cfg.modelName) (strats cfg.strategies) (temps cfg.temperatures) (budgets cfg.budgetCeilings) (dryRun cfg.dryRun) (candidates (generateCandidatesWithTranslationLoop model strats temps budgets asnFlags)) (tasks (canonicalCanaryTasks)) (evalResults (map (fn [(cand CalibrationCandidate)] -> CalibrationEvaluationResult (evaluateCandidate cand tasks dryRun)) candidates))] (sortResultsByScore evalResults))

fn findOptimalCandidate results: (List CalibrationEvaluationResult) -> (Option CalibrationCandidate)
  (if (listEmpty? results) (none) (let [(best (optionOr (listHead results) (CalibrationEvaluationResult :candidate (CalibrationCandidate :modelName "" :strategy "" :temperature 0.0 :budgetCeiling 0 :asnPromptEnabled false) :passRate 0.0 :continuousProgress 0.0 :avgTokens 0 :latencyMs 0 :amnesiaDetected false :paretoScore 0.0 :status "" :asnPromptUsed false :asnFallbackTriggered false)))] (some best.candidate)))

fn formatCalibrationResultAsn res: CalibrationEvaluationResult -> Str
  (let [(cand res.candidate)] (str "(:calibration-result\n" "  :model \"" cand.modelName "\"\n" "  :strategy \"" cand.strategy "\"\n" "  :temperature " (stringFromFloat64 cand.temperature) "\n" "  :budget-ceiling " (stringFromInt64 cand.budgetCeiling) "\n" "  :asn-prompt-enabled " (if cand.asnPromptEnabled "true" "false") "\n" "  :asn-prompt-used " (if res.asnPromptUsed "true" "false") "\n" "  :asn-fallback-triggered " (if res.asnFallbackTriggered "true" "false") "\n" "  :pass-rate " (stringFromFloat64 res.passRate) "\n" "  :continuous-progress " (stringFromFloat64 res.continuousProgress) "\n" "  :avg-tokens " (stringFromInt64 res.avgTokens) "\n" "  :latency-ms " (stringFromInt64 res.latencyMs) "\n" "  :amnesia-detected " (if res.amnesiaDetected "true" "false") "\n" "  :pareto-score " (stringFromFloat64 res.paretoScore) "\n" "  :status " res.status "\n" ")"))
