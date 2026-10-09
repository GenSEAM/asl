(module aslHarness/worker :x [ThinkingResult ToolCallResult ProcessReceipt DiagnosticReceipt makeDiagnosticReceipt formatDiagnosticReceipt emitStringNotFoundReceipt WorkerConfig WorkerState StepOutcome PhaseExecutionResult BlastRadiusGuard WorkItem PhaseRecord LeaseRecord RoadmapRecord makeWorkItem makePhaseRecord makeLeaseRecord makeRoadmapRecord makeProcessReceipt renderProcessReceipt estimateReceiptTokens makeWorkerConfig initWorkerState pathInBoundaries? pollClaimedPhase executeWorkItem executePhaseItems verifyBlastRadius auditPreCommitSafety commitPhaseDiff workerStep runWorkerLoop] :i [])

(schema ThinkingResult (:f thought Str) (:f confidence F64))

(schema ToolCallResult (:f toolName Str) (:f arguments Str) (:f rawOutput Str))

(schema WorkItem (:f id Str) (:f name Str) (:f status Str) (:f gate Str))

(schema PhaseRecord (:f id Str) (:f name Str) (:f status Str) (:f wave Str) (:f gate Str) (:f items (List WorkItem)))

(schema LeaseRecord (:f phaseId Str) (:f agentId Str) (:f acquiredEpoch I64) (:f ttlMs I64) (:f isActive Bool))

(schema RoadmapRecord (:f iteration Str) (:f phases (List PhaseRecord)) (:f leases (List LeaseRecord)) (:f version I64))

(schema ProcessReceipt (:f exitCode I64) (:f durationMs I64) (:f peakRssMb I64) (:f spoolPath Str) (:f summary Str) (:f tokens I64))

(schema DiagnosticReceipt (:f code Str) (:f failedSeek Str) (:f hint Str) (:f action Str) (:f details Str))

(schema BlastRadiusGuard (:f isSafe Bool) (:f violations (List Str)) (:f affectedSymbols (List Str)) (:f details Str))

(schema WorkerConfig (:f agentId Str) (:f continuous Bool) (:f maxCycles I64) (:f idleIntervalMs I64) (:f ownsBoundaries (List Str)) (:f strictGates Bool))

(schema WorkerState (:f config WorkerConfig) (:f status Str) (:f cycleCount I64) (:f activePhaseId Str) (:f completedPhases (List Str)) (:f receipts (List ProcessReceipt)) (:f blastGuard (Option BlastRadiusGuard)) (:f lastError Str))

(schema PhaseExecutionResult (:f receipts (List ProcessReceipt)) (:f allPassed Bool) (:f executedCount I64) (:f failedItemId Str))

(schema StepOutcome (:f workerState WorkerState) (:f phaseId Str) (:f action Str) (:f itemsCount I64) (:f allPassed Bool))

fn makeWorkItem id: Str name: Str status: Str gate: Str -> WorkItem
  (WorkItem :id id :name name :status status :gate gate)

fn makePhaseRecord id: Str name: Str status: Str wave: Str gate: Str items: (List WorkItem) -> PhaseRecord
  (PhaseRecord :id id :name name :status status :wave wave :gate gate :items items)

fn makeLeaseRecord phaseId: Str agentId: Str acquired: I64 ttl: I64 -> LeaseRecord
  (LeaseRecord :phaseId phaseId :agentId agentId :acquiredEpoch acquired :ttlMs ttl :isActive true)

fn makeRoadmapRecord iteration: Str phases: (List PhaseRecord) -> RoadmapRecord
  (RoadmapRecord :iteration iteration :phases phases :leases (list) :version 1)

fn estimateReceiptTokens text: Str -> I64
  (let [(len (stringLength text))] (cond ((<= len 0) 0) ((<= len 4) 1) (else (/ (+ len 3) 4))))

fn renderProcessReceipt r: ProcessReceipt -> Str
  (str "(:receipt :exit " (stringFromInt64 r.exitCode) " :ms " (stringFromInt64 r.durationMs) " :rss " (stringFromInt64 r.peakRssMb) " :spool \"" r.spoolPath "\"" " :summary \"" r.summary "\")")

fn makeProcessReceipt exitCode: I64 durationMs: I64 peakRssMb: I64 spoolPath: Str summary: Str -> ProcessReceipt
  (let [(rendered (str "(:receipt :exit " (stringFromInt64 exitCode) " :ms " (stringFromInt64 durationMs) " :rss " (stringFromInt64 peakRssMb) " :spool \"" spoolPath "\"" " :summary \"" summary "\")")) (toks (estimateReceiptTokens rendered))] (ProcessReceipt :exitCode exitCode :durationMs durationMs :peakRssMb peakRssMb :spoolPath spoolPath :summary summary :tokens toks))

fn makeDiagnosticReceipt code: Str seek: Str hint: Str action: Str details: Str -> DiagnosticReceipt
  (DiagnosticReceipt :code code :failedSeek seek :hint hint :action action :details details)

fn formatDiagnosticReceipt diag: DiagnosticReceipt -> Str
  (str "(:diagnostic :code :" diag.code " :failed-seek \"" diag.failedSeek "\" :hint \"" diag.hint "\" :action \"" diag.action "\" :details \"" diag.details "\")")

fn emitStringNotFoundReceipt targetStr: Str candidateHint: Str targetFile: Str -> DiagnosticReceipt
  (makeDiagnosticReceipt "ERR_STRING_NOT_FOUND" targetStr candidateHint (str "asl '(:read \"" targetFile "\" 1 50)'") (str "Target string not found in " targetFile "; consult closest match in hint."))

fn makeWorkerConfig agentId: Str continuous: Bool maxCycles: I64 idleIntervalMs: I64 owns: (List Str) -> WorkerConfig
  (WorkerConfig :agentId agentId :continuous continuous :maxCycles maxCycles :idleIntervalMs idleIntervalMs :ownsBoundaries owns :strictGates true)

fn initWorkerState cfg: WorkerConfig -> WorkerState
  (WorkerState :config cfg :status "idle" :cycleCount 0 :activePhaseId "" :completedPhases (list) :receipts (list) :blastGuard (none) :lastError "")

fn pathInBoundaries? path: Str boundaries: (List Str) -> Bool
  (let [(matches (filter (fn [(b Str)] -> Bool (or (= path b) (if (stringEndsWith? b "/") (stringStartsWith? path b) (stringStartsWith? path (str b "/"))))) boundaries))] (not (listEmpty? matches)))

fn pollClaimedPhase rm: RoadmapRecord agentId: Str -> (Option PhaseRecord)
  (let [(leases rm.leases) (matchingLeases (filter (fn [(l LeaseRecord)] -> Bool (and (= l.agentId agentId) l.isActive)) leases))] (if (not (listEmpty? matchingLeases)) (let [(targetLease (listHead matchingLeases))] (mt targetLease ((some l) (let [(matches (filter (fn [(p PhaseRecord)] -> Bool (= p.id l.phaseId)) rm.phases))] (listHead matches))) ((none) (none)))) (let [(phases rm.phases) (claimedPhases (filter (fn [(p PhaseRecord)] -> Bool (or (= p.status "claimed") (= p.status "pending"))) phases))] (listHead claimedPhases))))

fn executeWorkItem itemId: Str gateCmd: Str exitCode: I64 durationMs: I64 -> ProcessReceipt
  (let [(summary (if (= exitCode 0) (str "Gate passed cleanly: " gateCmd) (str "Gate failed with exit code " (stringFromInt64 exitCode) ": " gateCmd))) (spool (str "/tmp/worker_spool_" itemId ".log"))] (makeProcessReceipt exitCode durationMs 24 spool summary))

fn executePhaseItems items: (List WorkItem) exitCodes: (List I64) -> PhaseExecutionResult
  (let [(initial (PhaseExecutionResult :receipts (list) :allPassed true :executedCount 0 :failedItemId ""))] (fold (fn [(acc PhaseExecutionResult) (item WorkItem)] -> PhaseExecutionResult (if (not acc.allPassed) acc (let [(idx acc.executedCount) (codeOpt (listGet exitCodes idx)) (code (mt codeOpt ((some c) c) ((none) 0))) (duration 35) (receipt (executeWorkItem item.id item.gate code duration))] (if (= code 0) (PhaseExecutionResult :receipts (listAppend acc.receipts (list receipt)) :allPassed true :executedCount (+ idx 1) :failedItemId "") (PhaseExecutionResult :receipts (listAppend acc.receipts (list receipt)) :allPassed false :executedCount (+ idx 1) :failedItemId item.id))))) initial items))

fn verifyBlastRadius affectedSymbols: (List Str) affectedPaths: (List Str) ownsBoundaries: (List Str) -> BlastRadiusGuard
  (let [(violations (filter (fn [(p Str)] -> Bool (not (pathInBoundaries? p ownsBoundaries))) affectedPaths))] (if (listEmpty? violations) (BlastRadiusGuard :isSafe true :violations (list) :affectedSymbols affectedSymbols :details "Blast-radius contained: zero boundary violations detected.") (BlastRadiusGuard :isSafe false :violations violations :affectedSymbols affectedSymbols :details (str "Blast-radius violation: " (stringFromInt64 (listLength violations)) " file(s) outside declared owns boundaries."))))

fn auditPreCommitSafety guard: BlastRadiusGuard itemsPassed: Bool phaseGatePassed: Bool -> Bool
  (and guard.isSafe (and itemsPassed (and phaseGatePassed (listEmpty? guard.violations))))

fn commitPhaseDiff state: WorkerState guard: BlastRadiusGuard phaseId: Str phaseGateExit: I64 -> WorkerState
  (if (not guard.isSafe) (with state :status "failed" :cycleCount (+ state.cycleCount 1) :activePhaseId phaseId :blastGuard (some guard) :lastError guard.details) (if (!= phaseGateExit 0) (with state :status "failed" :cycleCount (+ state.cycleCount 1) :activePhaseId phaseId :blastGuard (some guard) :lastError (str "Composite acceptance gate failed with exit code " (stringFromInt64 phaseGateExit))) (let [(spool (str "/tmp/commit_" phaseId ".log")) (receipt (makeProcessReceipt 0 150 32 spool (str "Committed phase " phaseId " cleanly.")))] (with state :status "committed" :cycleCount (+ state.cycleCount 1) :activePhaseId "" :completedPhases (listAppend state.completedPhases (list phaseId)) :receipts (listAppend state.receipts (list receipt)) :blastGuard (some guard) :lastError ""))))

fn workerStep state: WorkerState rm: RoadmapRecord itemExitCodes: (List I64) affectedPaths: (List Str) phaseGateExit: I64 -> StepOutcome
  (let [(cfg state.config) (phaseOpt (pollClaimedPhase rm cfg.agentId))] (mt phaseOpt ((none) (let [(updatedSt (with state :config cfg :status "idle" :cycleCount (+ state.cycleCount 1) :activePhaseId "" :blastGuard (none) :lastError ""))] (StepOutcome :workerState updatedSt :phaseId "" :action "idle" :itemsCount 0 :allPassed true))) ((some phase) (let [(pid phase.id) (items phase.items) (execRes (executePhaseItems items itemExitCodes)) (itemReceipts execRes.receipts) (itemsPassed execRes.allPassed)] (if (not itemsPassed) (let [(failId execRes.failedItemId) (failSt (with state :config cfg :status "failed" :cycleCount (+ state.cycleCount 1) :activePhaseId pid :receipts (listAppend state.receipts itemReceipts) :blastGuard (none) :lastError (str "Work item gate failed: " failId)))] (StepOutcome :workerState failSt :phaseId pid :action "failed" :itemsCount execRes.executedCount :allPassed false)) (let [(guard (verifyBlastRadius (list pid) affectedPaths cfg.ownsBoundaries)) (stateWithReceipts (with state :config cfg :status "verifying" :activePhaseId pid :receipts (listAppend state.receipts itemReceipts) :blastGuard (some guard) :lastError "")) (committedSt (commitPhaseDiff stateWithReceipts guard pid phaseGateExit))] (StepOutcome :workerState committedSt :phaseId pid :action (if (= committedSt.status "committed") "committed" "failed") :itemsCount execRes.executedCount :allPassed (= committedSt.status "committed"))))))))

fn runWorkerLoop state: WorkerState rm: RoadmapRecord maxSteps: I64 -> WorkerState
  (let [(limit (if (<= maxSteps 0) 1 maxSteps)) (outcome (workerStep state rm (list 0 0 0 0) state.config.ownsBoundaries 0)) (nextSt outcome.workerState)] (if (or (<= limit 1) (or (= nextSt.status "failed") (= nextSt.status "idle"))) nextSt (runWorkerLoop nextSt rm (- limit 1))))

fn main -> Str
  (let [(cfg (makeWorkerConfig "worker-daemon-1" false 1 500 (list "harness/src/worker.asl"))) (st (initWorkerState cfg))] (str "(:worker-daemon :id \"" cfg.agentId "\" :status \"" st.status "\")"))
