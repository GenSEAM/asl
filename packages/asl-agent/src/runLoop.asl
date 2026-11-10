(module aslAgent/runLoop
  :x [ownedDigest! commitLanded! commitFields withUnbacked redGateOf specCheckRun! modelFamily specTargets specCheckWanted? journalModel LoopSetup LoopRun ProviderRun withState withProcs withWritten withCommitMessage withOwnsRejections withPlan writtenPaths noteParseTurn headDecision! stateFor withHeadState withTurnContext withFindings withPrefetch withBaseline baselineGreen! firstTurnPrefetch wallSeconds setup! setupWatched! head! finish! runLoopWith! runLoopWithProvider! runLoopWithProviderWatched! LoopOpen openRun openDone loopOpen! loopHead! loopFinish! usageTotalsPlus withUsageTotals usageIntOf batchingPlus withBatching]
  :i [(aslAgent/loopState :a s) (aslAgent/loop :a lp)
      (aslAgent/context :a ctx) (aslAgent/journal :a jr)
      (aslAgent/gitOps :a go) (aslAgent/runOps :a ro) (aslAgent/reply :a rp)
      (aslAgent/core :a c) (aslAgent/gates :a g) (asl-json/json :a j)
      (aslAgent/providers :a pv) (aslAgent/agentConfig :a ac) (aslAgent/aslOps :a ao)
      (asl-tools/vcs/vcs :a vcs)])

schema LoopRun
  (:f state s/LoopState) (:f procs ro/Procs) (:f written jr/Written) (:f session String)
  (:f commitMessage (Option String)) (:f parseDefects Int64) (:f lastDefect Bool) (:f lastDefectTurn (Option Int64))
  (:f parseDefectStreak Int64)

schema ProviderRun
  (:f run LoopRun)
  (:f provider pv/Provider)
  (:f history (List j/Json))

enum LoopSetup
  (ready LoopRun)
  (early s/RunResult)

; (:m :ref SE3-POOL-DRIVER :do "what opening a provider run gives back: the run to step, or the finished result of a setup that stopped early")
enum LoopOpen
  (openRun ProviderRun)
  (openDone s/RunResult)

fn withState run: LoopRun state: s/LoopState -> LoopRun
  (LoopRun :state state :procs run.procs :written run.written :session run.session
    :commitMessage run.commitMessage :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn :parseDefectStreak run.parseDefectStreak)

fn withProcs run: LoopRun procs: ro/Procs -> LoopRun
  (LoopRun :state run.state :procs procs :written run.written :session run.session
    :commitMessage run.commitMessage :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn :parseDefectStreak run.parseDefectStreak)

fn withWritten run: LoopRun written: jr/Written -> LoopRun
  (LoopRun :state run.state :procs run.procs :written written :session run.session
    :commitMessage run.commitMessage :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn :parseDefectStreak run.parseDefectStreak)

fn writtenPaths written: jr/Written -> (List String)
  (match written.files
    ((some files) (map pairFirst files))
    ((none) (list)))

; (:m :ref LEON-TURN-RUNAWAY-20261017 :do "parseDefects is a lifetime count of non-actionable replies across the whole session; a long, mostly-healthy run can accumulate a handful of early slips without ever being stuck, so the cap that actually catches a model looping on inert prose has to reset on any turn that was not a defect, not alarm on a scattered lifetime total")
fn noteParseTurn run: LoopRun turn: Int64 defect: Bool -> LoopRun
  (LoopRun :state run.state :procs run.procs :written run.written :session run.session
    :commitMessage run.commitMessage :parseDefects (if defect (+ run.parseDefects 1) run.parseDefects)
    :lastDefect defect :lastDefectTurn (if defect (some turn) run.lastDefectTurn)
    :parseDefectStreak (if defect (+ run.parseDefectStreak 1) 0))

fn withCommitMessage run: LoopRun message: (Option String) -> LoopRun
  (LoopRun :state run.state :procs run.procs :written run.written :session run.session
    :commitMessage message :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn :parseDefectStreak run.parseDefectStreak)

fn coreHostZero -> j/Json
  (j/jobj (list (pair "calls" (j/jint 0)) (pair "cases" (j/jint 0)) (pair "sec" (j/jfloat 0.0)) (pair "built" (j/jint 0))))

fn ! absoluteRoot! root: String -> String
  (resultOr (realPath (if (stringEmpty? root) "." root)) (jr/pathNorm root))

fn ! journalOf env: s/LoopEnv -> (Option String)
  (if (and (not (stringEmpty? env.rootDir)) (not (stringEmpty? env.journalPath)))
    (some (jr/pathRel env.journalPath (absoluteRoot! env.rootDir))) (some env.journalPath))

fn coreZero -> j/Json
  (j/jobj (list (pair "built" (j/jint 0)) (pair "calls" (j/jint 0)) (pair "cases" (j/jint 0)) (pair "sec" (j/jfloat 0.0))))

fn ! emptyResult env: s/LoopEnv sid: String status: String error: (Option String) turns: Int64 patch: (Option String) restored: (List String) preflight: (Option j/Json) message: (Option String) commitMissing: (Option Bool) -> s/RunResult
  (emptyResultWith env sid status error turns patch restored preflight message commitMissing (list))

; (:m :ref LEON-CAPS :do "a result built after the baseline pass ran carries that pass's vacuous gates; the setup rejections come before the baseline runs, so they have none to report")
fn ! emptyResultWith env: s/LoopEnv sid: String status: String error: (Option String) turns: Int64 patch: (Option String) restored: (List String) preflight: (Option j/Json) message: (Option String) commitMissing: (Option Bool) vacuous: (List String) -> s/RunResult
  (s/RunResult :status status :unbacked 0 :unbackedClaims (list) :gates (list)
    :turns turns :escalate none
    :needsConfirm none :error error
    :sessionId sid :session sid
    :journal (journalOf env) :findings (list) :parseDefect false :parseDefectTurn none
    :modeHint env.modeHint :deliver none :phases (list) :contextTokens env.contextTokens
    :patch patch :restored restored :written (list)
    :batching (j/jobj (list (pair "ops" (j/jint 0)) (pair "single" (j/jint 0)) (pair "turns" (j/jint 0))))
    :gatesGreen none :commit none :commitError none :commitMissing commitMissing
    :queueWaitSec none :execSec none :usage none :signal none :ownsRejected (list)
    :planSummary none :coreHost (if (= status "escalated") (coreZero) (j/jobj (list))) :openPossible (list) :gatePreflight preflight :message message :vacuousGates vacuous :specCheck none)

fn stateFor env: s/LoopEnv -> s/LoopState
  (let [tokens (ctx/contextTokensFor env.model (match env.contextTokens ((some n) (j/jint n)) ((none) (j/jnull))) false)
        resumeTurn (match env.resume ((some resume) (intField resume "turn" 0)) ((none) 0))]
    (s/LoopState :turn resumeTurn :contextTokens (some tokens) :core (j/jobj (list)) :wallBudget env.wallBudget
      :intent env.intent :plan (j/jobj (list)) :mode "auto"
      :sizingModel (optionOr env.model "") :explicitContext (some? env.contextTokens)
      :transcriptChars (* tokens 4) :readCap (ctx/readPayloadChars tokens) :startHead ""
      :turnsWithoutEvidence 0 :readStreak 0 :phases (list) :deliver none :gatewayIntent (optionOr env.intent "auto")
      :researchKind false :turnFacts (j/jobj (list)) :reinforceWhy none :advisorCalls 0 :advisorAsked false
      :gateSigHistory (list) :executedSteps (mapEmpty) :workspaceGen 0 :failureCounts (mapEmpty)
      :ownsRejections (list) :scope (if (listEmpty? env.owns) (list "**") env.owns)
      :signalName none :runStarted (env.now) :vendorRetryCount 0 :vendorWaitUsed false
      :seenEvidence (mapEmpty) :turnEvidence (mapEmpty) :writeTurn (mapEmpty) :coverage (mapEmpty)
      :writesPersisted false :wroteSinceGate false :allReceipts (list) :allGateResults (list)
      :needsConfirmList (list) :escalateReceipt none :findingsList (list) :possibleOpen (mapEmpty)
      :possibleNotices 0 :status "ok" :error none :totalQueueWaitSec 0.0 :totalExecSec 0.0
      :usageTotals (j/jobj (list)) :batching (j/jobj (list (pair "ops" (j/jint 0)) (pair "single" (j/jint 0)) (pair "turns" (j/jint 0)))) :hasTiming false :basePrompt ""
      :briefCount 0 :code "" :commitRequested env.commit :declaredOps (list) :fetched (j/jobj (list))
      :header "" :history (list) :lastGates (mapEmpty) :missingGateIntro (list) :patchErr none
      :placeholderBriefs (mapEmpty) :doneNoWriteStreak 0 :malformedStreak 0 :notFoundStreak 0 :prefetch "" :baselineGreen (list) :priorIds (list) :resumePatchPath none
      :retries (j/jobj (list)) :runUnbackedClaims (list) :specChecksDone 0 :startTurn resumeTurn
      :taskLines "" :unparsable (j/jobj (list)) :vendorBounds (j/jobj (list))
      :window (j/jobj (list)) :writtenFiles (list)))
fn withTurnContext state: s/LoopState contextTokens: (Option Int64) readCap: Int64 wroteSinceGate: Bool -> s/LoopState
  (with state :contextTokens contextTokens :readCap readCap :wroteSinceGate wroteSinceGate)

fn withHeadState state: s/LoopState turn: Int64 readStreak: Int64 writesPersisted: Bool deliver: (Option String) gates: (List g/GateResult) lastGates: (Map String j/Json) status: String signal: (Option String) escalate: (Option String) started: Float64 -> s/LoopState
  (s/LoopState
      :turn turn
      :contextTokens state.contextTokens
      :core state.core
      :wallBudget state.wallBudget
      :intent state.intent
      :plan state.plan
      :mode state.mode
      :sizingModel state.sizingModel
      :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars
      :readCap state.readCap
      :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence
      :readStreak readStreak
      :phases state.phases
      :deliver deliver
      :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind
      :turnFacts state.turnFacts
      :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls
      :advisorAsked state.advisorAsked
      :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps
      :workspaceGen state.workspaceGen
      :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections
      :scope state.scope
      :signalName signal
      :runStarted started
      :vendorRetryCount state.vendorRetryCount
      :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence
      :turnEvidence state.turnEvidence
      :writeTurn state.writeTurn
      :coverage state.coverage
      :writesPersisted writesPersisted
      :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts
      :allGateResults gates
      :needsConfirmList state.needsConfirmList
      :escalateReceipt escalate
      :findingsList state.findingsList
      :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices
      :status status
      :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec
      :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals
      :batching state.batching
      :hasTiming state.hasTiming
      :basePrompt state.basePrompt
      :briefCount state.briefCount
      :code state.code
      :commitRequested state.commitRequested
      :declaredOps state.declaredOps
      :fetched state.fetched
      :header state.header
      :history state.history
      :lastGates lastGates
      :missingGateIntro state.missingGateIntro
      :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak
      :prefetch state.prefetch :baselineGreen state.baselineGreen
      :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath
      :retries state.retries
      :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone
      :startTurn state.startTurn
      :taskLines state.taskLines
      :unparsable state.unparsable
      :vendorBounds state.vendorBounds
      :window state.window
      :writtenFiles state.writtenFiles)

fn withOwnsRejections state: s/LoopState rejections: (List j/Json) -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan state.plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections rejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList state.needsConfirmList
      :escalateReceipt state.escalateReceipt :findingsList state.findingsList :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals :batching state.batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch state.prefetch :baselineGreen state.baselineGreen :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

; (:m :ref FREEBENCH-TOKENBUDGET-20261017 :do "usageTotals was declared on LoopState and threaded through every with* copier but never actually accumulated anywhere -- it stayed (j/jobj (list)) for the life of every run. usageTotalsPlus/withUsageTotals make it a real running sum, folded in once per turn in main.asl right after the provider reply's usage is known, so a per-case cumulative input-token cap has something real to check against")
fn usageIntOf totals: j/Json key: String -> Int64
  (intField totals key 0)

fn usageTotalsPlus totals: j/Json inputDelta: Int64 cachedDelta: Int64 outputDelta: Int64 -> j/Json
  (j/jobj (list
    (pair "inputTokens" (j/jint (+ (usageIntOf totals "inputTokens") inputDelta)))
    (pair "cachedTokens" (j/jint (+ (usageIntOf totals "cachedTokens") cachedDelta)))
    (pair "outputTokens" (j/jint (+ (usageIntOf totals "outputTokens") outputDelta)))))

fn withUsageTotals state: s/LoopState usageTotals: j/Json -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan state.plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList state.needsConfirmList
      :escalateReceipt state.escalateReceipt :findingsList state.findingsList :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals usageTotals :batching state.batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch state.prefetch :baselineGreen state.baselineGreen :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

; (:m :ref LEON-BATCHING-DEAD-20261018 :do "batching was declared on LoopState and threaded through every with* copier but never actually accumulated anywhere -- it stayed all-zero for the life of every run, so opTurns/opsPerTurn/singleOpShare were 0 on every receipt regardless of how many ops a turn actually ran. batchingPlus/withBatching make it a real running count, folded in once per turn in main.asl right after that turn's operations list is known, beside the usageTotals fold")
fn batchingPlus batching: j/Json opCount: Int64 -> j/Json
  (j/jobj (list
    (pair "ops" (j/jint (+ (intField batching "ops" 0) opCount)))
    (pair "single" (j/jint (+ (intField batching "single" 0) (if (= opCount 1) 1 0))))
    (pair "turns" (j/jint (+ (intField batching "turns" 0) 1)))))

fn withBatching state: s/LoopState batching: j/Json -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan state.plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList state.needsConfirmList
      :escalateReceipt state.escalateReceipt :findingsList state.findingsList :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals :batching batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch state.prefetch :baselineGreen state.baselineGreen :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

fn withPlan state: s/LoopState plan: j/Json -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList state.needsConfirmList
      :escalateReceipt state.escalateReceipt :findingsList state.findingsList :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals :batching state.batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch state.prefetch :baselineGreen state.baselineGreen :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

fn withFindings state: s/LoopState findings: (List j/Json) confirms: (List j/Json) -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan state.plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList confirms
      :escalateReceipt state.escalateReceipt :findingsList findings :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals :batching state.batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch state.prefetch :baselineGreen state.baselineGreen :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

; (:m :ref PREFETCH-WIRE)
fn withPrefetch state: s/LoopState prefetch: String -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan state.plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList state.needsConfirmList
      :escalateReceipt state.escalateReceipt :findingsList state.findingsList :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals :batching state.batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch prefetch :baselineGreen state.baselineGreen :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

; (:m :ref LEON-CAPS :do "setup computes the prefetch block once, capped by readCap; it rides the first turn of the run, and that turn's history text keeps it, so it is resent whole until the turn ages out of the kept window (8 turns) and collapses to a receipt line; a later turn's own prompt does not add it, and a resumed run, which setup leaves empty, sends none")
fn firstTurnPrefetch state: s/LoopState -> String
  (if (= state.turn (+ state.startTurn 1)) state.prefetch "")

fn preflightJson bad: (List (List (Pair String go/RVal))) -> j/Json
  (j/jarr (map (fn [rec]
    (j/jobj (map (fn [field] (pair (pairFirst field) (s/gitRValJson (pairSecond field)))) rec))) bad))

fn stringField obj: j/Json key: String fallback: String -> String
  (match (j/jsonGet obj key)
    ((some v) (match v ((j/jstr s) s) ((j/jnum _) fallback) ((j/jint _) fallback) ((j/jbool _) fallback) ((j/jnull) fallback) ((j/jarr _) fallback) (_ fallback)))
    ((none) fallback))

fn intField obj: j/Json key: String fallback: Int64 -> Int64
  (match (j/jsonGet obj key)
    ((some v) (match v ((j/jint n) n) (_ fallback)))
    ((none) fallback))

fn wallSeconds elapsed: Float64 -> String
  (stringFromInt64 (optionOr (float64ToInt64 (ctx/pyRound elapsed 0)) 0))

fn ! resumeJournal! path: (Option String) journal: String -> Bool
  (match path
    ((some patchPath) (ok? (jr/journalWrite journal (str "(:resumeApplied \"" (c/escapeAsn patchPath) "\")\n"))))
    ((none) true))

fn ! startHead! rootDir: String -> (Result (Option String) String)
  (match (jr/git! rootDir (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok o) (ok (if (= o.exitCode 0) (some (ctx/pyStrip o.stdout)) none))))

; (:m :ref PREFETCH-WIRE :do "no subprocess runner is available this early in setup; a large :owns file (over prefetchWholeBytes) is simply skipped, small ones still prefetch whole")
fn noOutline f: String -> (Pair Int64 String)
  (pair 1 "")

; (:m :ref LEON-CAPS :do "the task's gates run once before the first turn, in the run root, with the run's gate timeout; a gate that exits 0 here is green before any edit, so a later green of it proves nothing about the change and the end status lists it as vacuous; a resumed run skips this because its root may already carry edits")
fn ! baselineGreen! gates: (List String) rootDir: String timeout: Int64 parent: (Option Int64) -> (List String)
  (let [rows (go/runGatesWatched! (map (fn [p] (pair (stringFromInt64 (+ (pairFirst p) 1)) (pairSecond p))) (enumerate gates)) rootDir timeout none parent)]
    (map (fn [row] (rowText row "cmd"))
      (filter (fn [row] (= (rowExit row) 0)) rows)))

fn rowText row: (List (Pair String go/RVal)) key: String -> String
  (match (listHead (filter (fn [p] (= (pairFirst p) key)) row))
    ((some p) (match (pairSecond p) ((go/rStr v) v) (_ "")))
    ((none) ""))

fn rowExit row: (List (Pair String go/RVal)) -> Int64
  (match (listHead (filter (fn [p] (= (pairFirst p) "exit")) row))
    ((some p) (match (pairSecond p) ((go/rInt v) v) (_ 1)))
    ((none) 1))

fn withBaseline state: s/LoopState green: (List String) -> s/LoopState
  (s/LoopState
      :turn state.turn :contextTokens state.contextTokens :core state.core
      :wallBudget state.wallBudget :intent state.intent :plan state.plan :mode state.mode
      :sizingModel state.sizingModel :explicitContext state.explicitContext
      :transcriptChars state.transcriptChars :readCap state.readCap :startHead state.startHead
      :turnsWithoutEvidence state.turnsWithoutEvidence :readStreak state.readStreak
      :phases state.phases :deliver state.deliver :gatewayIntent state.gatewayIntent
      :researchKind state.researchKind :turnFacts state.turnFacts :reinforceWhy state.reinforceWhy
      :advisorCalls state.advisorCalls :advisorAsked state.advisorAsked :gateSigHistory state.gateSigHistory
      :executedSteps state.executedSteps :workspaceGen state.workspaceGen :failureCounts state.failureCounts
      :ownsRejections state.ownsRejections :scope state.scope :signalName state.signalName
      :runStarted state.runStarted :vendorRetryCount state.vendorRetryCount :vendorWaitUsed state.vendorWaitUsed
      :seenEvidence state.seenEvidence :turnEvidence state.turnEvidence :writeTurn state.writeTurn
      :coverage state.coverage :writesPersisted state.writesPersisted :wroteSinceGate state.wroteSinceGate
      :allReceipts state.allReceipts :allGateResults state.allGateResults :needsConfirmList state.needsConfirmList
      :escalateReceipt state.escalateReceipt :findingsList state.findingsList :possibleOpen state.possibleOpen
      :possibleNotices state.possibleNotices :status state.status :error state.error
      :totalQueueWaitSec state.totalQueueWaitSec :totalExecSec state.totalExecSec
      :usageTotals state.usageTotals :batching state.batching :hasTiming state.hasTiming
      :basePrompt state.basePrompt :briefCount state.briefCount :code state.code
      :commitRequested state.commitRequested :declaredOps state.declaredOps :fetched state.fetched
      :header state.header :history state.history :lastGates state.lastGates
      :missingGateIntro state.missingGateIntro :patchErr state.patchErr
      :placeholderBriefs state.placeholderBriefs :doneNoWriteStreak state.doneNoWriteStreak :malformedStreak state.malformedStreak :notFoundStreak state.notFoundStreak :prefetch state.prefetch :baselineGreen green :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)

; (:m :ref LEON-CAPS :do "the unbacked gate or count claims of the final reply replace any earlier set; they are the claims the end status counts")
fn withUnbacked state: s/LoopState claims: (List j/Json) -> s/LoopState
  (with state :runUnbackedClaims claims)

fn ! setup! env: s/LoopEnv -> LoopSetup
  (setupWatched! env none)

; (:m :ref LEON-ORPHAN-RESIDUE :do "the calling CLI pid reaches the baseline gates, so a dead parent kills them like the per-turn gates")
fn ! setupWatched! env: s/LoopEnv parent: (Option Int64) -> LoopSetup
  (let [state (let [s0 (stateFor env)] (if (some? env.contextTokens) s0 (with s0 :contextTokens (some (ctx/contextTokensFor! env.model (j/jnull) false)))))
        sid (optionOr env.sessionId (env.newId))
        rootDir (absoluteRoot! env.rootDir)]
    (match (startHead! rootDir)
      ((err e) (early (emptyResult env sid "failed" (some e) 0 none (list) none none none)))
      ((ok head) (setupAt! env state sid rootDir head parent))))

fn ! setupAt! env: s/LoopEnv state: s/LoopState sid: String rootDir: String head: (Option String) parent: (Option Int64) -> LoopSetup
  (let [timeout (optionOr env.gateTimeout 10)
        header (match env.resume
          ((some resume) (str "(:turn " (stringFromInt64 (intField resume "turn" 0)) " :answer \""
            (c/escapeAsn (stringField resume "answer" "")) "\")\n(:transport :subprocess :transportWhy \"ASL_TRANSPORT=subprocess\")\n"))
          ((none) (lp/sessionHeader sid env.task (optionOr env.modeHint "")
            (optionOr env.intent "auto") rootDir env.owns env.gates
            (optionOr env.base "") (optionOr env.model "") "default" ":transport :subprocess :transportWhy \"ASL_TRANSPORT=subprocess\""
            (stringFromInt64 timeout) (stringFromInt64 (optionOr env.contextTokens 24000))
            (match env.wallBudget ((some n) (stringFromInt64 n)) ((none) "")) env.plan)))
        cfgText (ac/configText! rootDir)
        cfgProblems (ac/configProblems cfgText)
        baselineOn (!= (optionOr (ac/agentLoopValue cfgText ":baseline") "true") "false")
        preflight (go/gatePreflight! env.gates rootDir none)
        fresh (jr/newWritten rootDir head)
        resumeSha (match env.resume
          ((some _) (match (fileReadString (str (jr/splitExt env.journalPath) ".patch")) ((ok t) (some (bytesSha256 (stringToBytes t)))) ((err _) none)))
          ((none) none))
        patchState (match env.resume
          ((some _) (match (jr/applyResumePatch fresh rootDir env.journalPath sid)
            ((err e) (pair fresh (pair none (some e)))) ((ok applied) applied)))
          ((none) (pair fresh (pair none none))))
        applied (pairFirst (pairSecond patchState))
        patchError (pairSecond (pairSecond patchState))
        prefetchText (if (and (none? env.resume) (not (listEmpty? env.owns)))
                       (pairFirst (ctx/prefetchBlock! (some env.task) env.owns rootDir state.readCap 1 (list) noOutline))
                       "")]
    (do
      (jr/journalWrite env.journalPath header)
      (resumeJournal! applied env.journalPath)
      (if (and (some? applied) (some? resumeSha)) (ok? (jr/journalWrite env.journalPath (str "(:resumeBase :sha \"" (optionOr resumeSha "") "\")\n"))) true)
      (cond
        ((not (listEmpty? cfgProblems))
          (let [message (c/joinSep cfgProblems "; ")]
            (do
              (jr/journalWrite env.journalPath (str "(:configProblem \"" (c/escapeAsn message) "\")\n(:result :status :rejected :session \"" sid "\" :error :ERR_CONFIG :message \"" (c/escapeAsn message) "\")\n"))
              (early (emptyResult env sid "rejected" (some "ERR_CONFIG") 0 none (list) none (some message) none)))))
        ((not (listEmpty? preflight))
          (do
            (jr/journalWrite env.journalPath (str "(:gatePreflight " (go/formatGatePreflight preflight) ")\n(:result :status :rejected :session \"" sid "\" :error :ERR_GATE_UNPARSABLE)\n"))
            (early (emptyResult env sid "rejected" (some "ERR_GATE_UNPARSABLE") 0 none (list) (some (preflightJson preflight)) none none))))
        ((some? patchError)
          (let [message (optionOr patchError "")]
            (do
              (jr/journalWrite env.journalPath (str "(:resumePatch :error \"" (c/escapeAsn message) "\")\n(:result :status :rejected :session \"" sid "\" :error :ERR_RESUME_PATCH :message \"" (c/escapeAsn message) "\")\n"))
              (early (emptyResult env sid "rejected" (some "ERR_RESUME_PATCH") 0 none (list) none (some message) none)))))
        (else
          (let [green (if (and baselineOn (and (none? env.resume) (not (listEmpty? env.gates))))
                        (baselineGreen! env.gates rootDir (match env.wallBudget ((some w) (if (> w 0) (max 1 (min timeout w)) timeout)) ((none) timeout)) parent)
                        (list))
                _ (if (and baselineOn (and (none? env.resume) (not (listEmpty? env.gates)))) (ok? (jr/journalWrite env.journalPath (str "(:baseline :green (" (quoted green) ") :red (" (quoted (filter (fn [g] (not (listContains? green g))) env.gates)) "))\n"))) true)
                _inherited (if (and (none? env.resume) (not (stringEmpty? env.inheritedBase))) (ok? (jr/journalWrite env.journalPath (str "(:inheritedBase :sha \"" (c/escapeAsn env.inheritedBase) "\")\n"))) true)
                _skipped (if (and (not baselineOn) (and (none? env.resume) (not (listEmpty? env.gates)))) (ok? (jr/journalWrite env.journalPath "(:baseline :skipped :why \"config :agentLoop :baseline false\")\n")) true)]
          (ready (LoopRun
            :state (withBaseline (withPrefetch (withHeadState state state.turn state.readStreak (some? applied)
              state.deliver state.allGateResults state.lastGates state.status state.signalName
              state.escalateReceipt state.runStarted) prefetchText) green)
            :procs (ro/newProcs) :written (pairFirst patchState) :session sid :commitMessage none :parseDefects 0 :lastDefect false :lastDefectTurn none :parseDefectStreak 0)))))))

fn latestRed entry: j/Json -> Bool
  (match entry
    ((j/jobj _) (match (optionOr (j/jsonGet entry "exit") (j/jnull))
      ((j/jint n) (!= n 0)) ((j/jnum x) (!= x 0.0)) ((j/jfloat x) (!= x 0.0)) (_ true)))
    ((j/jarr items)
      (match (listHead (if (listEmpty? items) (list) (c/restOf items)))
        ((some gate) (match (optionOr (j/jsonGet gate "exit") (j/jnull)) ((j/jint n) (!= n 0)) ((j/jnum x) (!= x 0.0)) ((j/jfloat x) (!= x 0.0)) (_ true)))
        ((none) true)))
    (_ true))

fn redGateOf gates: (List String) lastGates: (Map String j/Json) -> Bool
  (listAny? (fn [cmd] (match (mapGet lastGates cmd) ((some entry) (latestRed entry)) ((none) false))) gates)

fn declaredGatesGreen gates: (List String) lastGates: (Map String j/Json) -> Bool
  (lp/finalGatesGreen (map (fn [cmd] (match (mapGet lastGates cmd) ((some entry) (if (latestRed entry) "0" "1")) ((none) "0"))) gates))

fn headDecision! env: s/LoopEnv state: s/LoopState parseDefects: Int64 -> String
  (let [runTurns (max 0 (- state.turn state.startTurn))
        elapsed (- (env.now) state.runStarted)
        noWriteTurnLimit (min (* (int64ToFloat64 env.budget) 0.5) (int64ToFloat64 (ctx/noWriteTurns)))]
    (lp/loopBoundary (redGateOf env.gates state.lastGates) state.readStreak (ctx/readStreakEscalateFor! env.rootDir)
      (optionOr state.deliver "") state.writesPersisted (int64ToFloat64 runTurns) noWriteTurnLimit
      (optionOr env.wallBudget 0) elapsed 0.5 (+ state.turn 1) env.budget parseDefects (ctx/parseDefectEscalateFor! env.rootDir)
      (usageIntOf state.usageTotals "inputTokens") env.inputTokenBudget))

fn ! journalSignal! env: s/LoopEnv turn: Int64 signal: String reason: String -> Bool
  (do
    (jr/journalWrite env.journalPath (str "(:turn " (stringFromInt64 turn) " :signal :" signal " :reason \"" (c/escapeAsn reason) "\")\n"))
    true)

fn ! head! env: s/LoopEnv state: s/LoopState parseDefects: Int64 -> (Pair s/LoopState s/Step)
  (let [decision (headDecision! env state parseDefects)
        nextTurn (+ state.turn 1)]
    (cond
      ((= decision "budget")
        (pair (withHeadState state nextTurn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "turnBudget")
          (some (str "(:escalate :reason \"budget exhausted after " (stringFromInt64 state.turn) " turns\")")) state.runStarted) (stop)))
      ((= decision "wallBudget")
        (do
        (journalSignal! env state.turn "wallBudget" (str (wallSeconds (- (env.now) state.runStarted)) " s spent of the " (stringFromInt64 (optionOr env.wallBudget 0)) " s wall budget after " (stringFromInt64 state.turn) " turns"))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "wallBudget")
          (some (str "(:escalate :reason \"wall budget of " (stringFromInt64 (optionOr env.wallBudget 0)) " s spent after " (stringFromInt64 state.turn) " turns\")")) state.runStarted) (stop))))
      ((= decision "readStreak")
        (do
        (journalSignal! env state.turn "readStreak" (str (stringFromInt64 state.readStreak) " turns without a write while a gate is red"))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "readStreak")
          (some (str "(:escalate :reason \"" (stringFromInt64 state.readStreak) " turns without a write while a gate is red\")")) state.runStarted) (stop))))
      ((= decision "parseDefect")
        (do
        (journalSignal! env state.turn "parseDefect" (str (stringFromInt64 parseDefects) " replies in a row with no actionable operation and nothing written"))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "parseDefect")
          (some (str "(:escalate :reason \"" (stringFromInt64 parseDefects) " replies in a row with no actionable operation and nothing written\")")) state.runStarted) (stop))))
      ((= decision "tokenBudget")
        (do
        (journalSignal! env state.turn "tokenBudget" (str (stringFromInt64 (usageIntOf state.usageTotals "inputTokens")) " cumulative input tokens reached the " (stringFromInt64 env.inputTokenBudget) " token budget"))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "tokenBudget")
          (some (str "(:escalate :reason \"" (stringFromInt64 (usageIntOf state.usageTotals "inputTokens")) " cumulative input tokens reached the " (stringFromInt64 env.inputTokenBudget) " token budget\")")) state.runStarted) (stop))))
      ((= decision "noWriteTurns")
        (do
        (journalSignal! env state.turn "noWrite" (str "nothing written by turn " (stringFromInt64 state.turn) " of " (stringFromInt64 env.budget)))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "noWrite")
          (some (str "(:escalate :reason \"nothing written by turn " (stringFromInt64 state.turn) " of " (stringFromInt64 env.budget) "\")")) state.runStarted) (stop))))
      ((= decision "noWriteWall")
        (do
        (journalSignal! env state.turn "noWrite" (str "nothing written by " (wallSeconds (- (env.now) state.runStarted)) " s of the " (stringFromInt64 (optionOr env.wallBudget 0)) " s wall budget"))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "noWrite")
          (some (str "(:escalate :reason \"nothing written by " (wallSeconds (- (env.now) state.runStarted)) " s of the " (stringFromInt64 (optionOr env.wallBudget 0)) " s wall budget\")")) state.runStarted) (stop))))
      (else
        (pair (withHeadState state nextTurn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates state.status state.signalName state.escalateReceipt state.runStarted) (proceed)))))

fn phasesText phases: (List String) -> String
  (c/joinSep phases " ")

fn batchingInt batching: j/Json key: String -> String
  (stringFromInt64 (intField batching key 0))

fn quoted xs: (List String) -> String
  (c/joinSep (map (fn [x] (str "\"" (c/escapeAsn x) "\"")) xs) " ")

fn stripColons s: String -> String
  (if (stringStartsWith? s ":") (stripColons (optionOr (stringSlice s 1 (stringLength s)) "")) s)

fn usageAny usage: j/Json -> Bool
  (match usage ((j/jobj kvs) (listAny? (fn [kv] (ctx/pyTruthy (pairSecond kv))) kvs)) (_ false))

fn usageInt usage: j/Json key: String -> String
  (stringFromInt64 (intField usage key 0))

fn ! journaled! env: s/LoopEnv text: String value: T -> (Result T String)
  (match (jr/journalWrite env.journalPath text)
    ((err e) (err e))
    ((ok _) (ok value)))

fn ! killRun! env: s/LoopEnv run: LoopRun rootDir: String -> (Result (List String) String)
  (let [state run.state
        runCtx (ro/makeRunCtx rootDir state.scope run.session (optionOr env.gateTimeout 10) (list) rootDir)]
    (match (ro/killSpawned! runCtx run.procs (fn [rel pre mode] true))
      ((err e) (err e))
      ((ok out)
        (if (listEmpty? out.killed)
          (ok (list))
          (journaled! env (str "(:killed (" (quoted out.killed) "))\n") out.killed)))))

fn ! headSha! rootDir: String -> (Result String String)
  (match (jr/git! rootDir (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok o) (ok (ctx/pyStrip o.stdout))))

fn ! committed! env: s/LoopEnv rootDir: String -> (Result (Pair (Option String) (Option String)) String)
  (match (headSha! rootDir)
    ((err e) (err e))
    ((ok sha) (journaled! env (str "(:commit \"" sha "\")\n") (pair (some sha) none))))

fn ! commitFailed! env: s/LoopEnv why: String -> (Result (Pair (Option String) (Option String)) String)
  (journaled! env (str "(:commitError \"" (c/escapeAsn why) "\")\n") (pair none (some why)))

fn ! relativeTo path: String rootDir: String -> String
  (if (stringStartsWith? path "/") (jr/pathRel path rootDir) (jr/pathNorm path))

fn distinct xs: (List String) -> (List String)
  (fold (fn [acc x] (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

; (:m :ref LEON-COMMIT-VIA-VCS :do "the guard's checks run by env.toolRoot's bin/asl (the tool tree the run was given, the binary Leon itself runs; empty means the commit root), so a fresh worktree needs no host build of its own; Leon's writes are committed through the vcs layer: vcs/commit! stages exactly the paths the run wrote, commitGuard judges the blobs that land, and a refusal ends the run commitError with the guard receipt (HEAD unchanged); the layer never uses warn here; :indexStale true lands the commit but leaves a journal row and a flag on the commit row so the stale shared index is visible")
fn ! commitWritten! env: s/LoopEnv run: LoopRun rootDir: String message: String -> (Result (Pair (Option String) (Option String)) String)
  (let [paths (distinct (map (fn [p] (relativeTo p rootDir))
    (listAppend run.state.writtenFiles (writtenPaths run.written))))]
    (if (listEmpty? paths)
      (commitFailed! env "the run wrote no path to commit")
      (commitLanded! env rootDir (vcs/commitWith! rootDir rootDir env.toolRoot paths message "commit"))))

; (:m :ref LEON-COMMIT-VIA-VCS :do "a landed vcs receipt becomes the run commit pair; :indexStale true keeps the sha and puts indexStale in the second slot, which commitFields prints as :commitIndexStale true on the result line the conductor reads, and the journal row stays")
fn ! commitLanded! env: s/LoopEnv rootDir: String r: vcs/VcsReceipt -> (Result (Pair (Option String) (Option String)) String)
  (if (= r.code 0)
    (if (stringContains? r.text ":indexStale true")
      (match (headSha! rootDir)
        ((err e) (err e))
        ((ok sha) (journaled! env (str "(:commit \"" sha "\")\n(:commitIndexStale \"" sha "\")\n") (pair (some sha) (some "indexStale")))))
      (committed! env rootDir))
    (commitFailed! env r.text))

fn commitFields commit: (Pair (Option String) (Option String)) -> String
  (match (pairFirst commit)
    ((some sha) (str " :commit \"" sha "\"" (match (pairSecond commit) ((some _) " :commitIndexStale true") ((none) ""))))
    ((none) (match (pairSecond commit) ((some why) (str " :commitError \"" (c/escapeAsn why) "\"")) ((none) ""))))

fn ! commit! env: s/LoopEnv run: LoopRun rootDir: String status: String gatesGreen: Bool -> (Result (Pair (Option String) (Option String)) String)
  (let [message (optionOr run.commitMessage "")]
    (if (or (stringEmpty? message) (or (!= status "ok") (not gatesGreen)))
      (ok (pair none none))
      (let [invalid (rp/commitMessageError message)]
        (match (if (some? invalid) (rp/commitNamesHead! message rootDir) (ok false))
          ((err e) (err e))
          ((ok namesHead)
            (cond
              (namesHead (committed! env rootDir))
              ((some? invalid) (commitFailed! env (str "the commit message is not a valid (:c ...) ASN line: " (optionOr invalid ""))))
              (else (commitWritten! env run rootDir message))))))))

fn specText spec: (Option s/SpecVerdict) -> String
  (match spec
    ((some v) (cond
                ((= v.verdict "skipped") " :specCheck (:verdict skipped :reason noGrader)")
                ((= v.verdict "unavailable") (str " :specCheck (:verdict unavailable :reviewer unavailable :reasons (" (quoted v.reasons) "))"))
                (else (str " :specCheck (:verdict " v.verdict " :model \"" (c/escapeAsn v.model) "\" :reasons (" (quoted v.reasons) "))"))))
    ((none) ""))

fn modelOfLine line: String -> (Option String)
  (match (stringIndexOf line ":model \"")
    ((none) none)
    ((some k)
      (let [rest (optionOr (stringSlice line (+ k 8) (stringLength line)) "")]
        (match (stringIndexOf rest "\"")
          ((some e) (some (optionOr (stringSlice rest 0 e) "")))
          ((none) none)))))

; (:m :ref LEON-CAPS :do "the model named on the last journal row that starts with tag: (:served ...) rows come from the writer's turns, (:graderServed ...) rows from the spec-check call; empty when the journal holds none")
fn journalModel text: String tag: String -> String
  (fold (fn [acc line] (if (stringStartsWith? line tag) (optionOr (modelOfLine line) acc) acc)) "" (stringLines text))

; (:m :ref LEON-SPECCHECK-REVIEWER-DOWN :do "a reviewer call the gateway could not serve (no upstream answered, a breaker open, a 5xx) is no verdict on the diff: it ends needsReview with :reviewer unavailable, and a green gated run is not failed by it alone")
fn reviewerUnavailable? message: String -> Bool
  (listAny? (fn [m] (stringContains? message m))
    (list "ERR_NO_UPSTREAM" "no model answered" "circuit breaker open" "Gateway HTTP error 502" "Gateway HTTP error 503" "Gateway HTTP error 504"))

fn modelFamily name: String -> String
  (let [lower (stringLower name)
        base (optionOr (listLast (stringSplit lower "/")) lower)
        noKimi (if (stringStartsWith? base "kimi-") (optionOr (stringSlice base 5 (stringLength base)) base) base)]
    (if (stringEndsWith? noKimi "-thinking")
      (optionOr (stringSlice noKimi 0 (- (stringLength noKimi) 9)) noKimi)
      noKimi))

fn specFail model: String reasons: (List String) -> s/SpecVerdict
  (s/SpecVerdict :verdict "fail" :model model :reasons reasons)

; (:m :ref LEON-DONE-WITHOUT-WIRING :do "specTargets is the distinct union of the files this run wrote and the owned files that differ from HEAD, so a continuation run that writes nothing on top of a restored patch still grades the dirty tree; specCheckWanted? is the guard that runs the check only at an ok finish with at least one target")
fn specTargets written: (List String) dirty: (List String) -> (List String)
  (distinct (listAppend written dirty))

fn specCheckWanted? specCheck: Bool status: String targets: (List String) -> Bool
  (and specCheck (and (= status "ok") (not (listEmpty? targets))))

; (:m :ref LEON-CAPS :do "the diff is graded against the task by the env.grade channel, a gateway role other than the writer's; a reviewer error, an unreadable reply, a grader that reports no model, a grader that is the writer's own model, an unknown writer model, and a not-met verdict are all fail; a provider with no grader channel is skipped, which still ends needsReview, never a silent pass")
fn ! specCheckRun! env: s/LoopEnv run: LoopRun rootDir: String written: (List String) -> s/SpecVerdict
  (let [state run.state
        review (ctx/runSpecCheck! env.grade (some env.task) rootDir run.written.startHead written
                 (map ctx/pyStr state.runUnbackedClaims) (list) env.gates (j/jobj (mapPairs state.lastGates)))
        after (resultOr (fileReadString env.journalPath) "")
        grader (journalModel after "(:graderServed ")
        servedWriter (journalModel after "(:served ")
        writer (if (stringEmpty? servedWriter) (optionOr env.model "") servedWriter)]
    (match review
      ((err e) (specFail grader (list (str "spec check could not run: " e))))
      ((ok verdict)
        (match verdict
          ((ctx/reviewError m)
            (cond
              ((stringContains? m "ERR_NO_GRADER_CHANNEL") (s/SpecVerdict :verdict "skipped" :model "" :reasons (list "noGrader")))
              ((reviewerUnavailable? m) (s/SpecVerdict :verdict "unavailable" :model "" :reasons (list m)))
              (else (specFail grader (list m)))))
          ((ctx/reviewVerdict met missing)
            (cond
              ((not met) (specFail grader (if (listEmpty? missing) (list "the grader found the task unmet") missing)))
              ((stringEmpty? grader) (specFail grader (list "the grader reported no model, so it cannot be shown to differ from the writer")))
              ((stringEmpty? writer) (specFail grader (list "the writer model is unknown, so the grader cannot be shown to differ")))
              ((= (modelFamily grader) (modelFamily writer)) (specFail grader (list (str "the grader model " grader " is the writer's model"))))
              (else (s/SpecVerdict :verdict "pass" :model grader :reasons (list)))))))))

fn resultText state: s/LoopState session: String status: String unbacked: Int64 commit: (Pair (Option String) (Option String)) commitMissing: Bool preserve: Bool patch: (Option String) restored: (List String) spec: (Option s/SpecVerdict) -> String
  (let [claims (map ctx/pyStr state.runUnbackedClaims)
        findings (map ctx/pyStr state.findingsList)
        usage state.usageTotals
        batching state.batching]
    (str "(:result :status :" status
      (if (stringEmpty? session) "" (str " :session \"" session "\""))
      " :unbacked " (stringFromInt64 unbacked)
      (if (listEmpty? claims) "" (str " :unbackedClaims (" (quoted claims) ")"))
      " :contextTokens " (stringFromInt64 (optionOr state.contextTokens 0))
      (match state.error ((some e) (str " :error :" (stripColons e))) ((none) ""))
      (commitFields commit)
      (if commitMissing " :commitMissing true" "")
      (match state.deliver ((some d) (if (stringEmpty? d) "" (str " :deliver :" d))) ((none) ""))
      " :phases (" (phasesText state.phases) ")"
      (if preserve " :gatesGreen true" "")
      (if (listEmpty? state.baselineGreen) "" (str " :vacuousGates (" (quoted state.baselineGreen) ")"))
      (specText spec)
      (if (listEmpty? findings) "" (str " :findings (" (c/joinSep findings " ") ")"))
      (if state.hasTiming (str " :queueWaitSec " (ctx/floatRepr state.totalQueueWaitSec) " :execSec " (ctx/floatRepr state.totalExecSec)) "")
      (if (usageAny usage) (str " :usage (:input " (usageInt usage "inputTokens") " :cached " (usageInt usage "cachedTokens") " :output " (usageInt usage "outputTokens") ")") "")
      " :batching (:turns " (batchingInt batching "turns") " :ops " (batchingInt batching "ops") " :singleOp " (batchingInt batching "single") ")"
      (jr/handBackFields patch restored) (jr/writtenField state.writtenFiles) ")\n"))

fn ! finalResult env: s/LoopEnv run: LoopRun status: String unbacked: Int64 commit: (Pair (Option String) (Option String)) commitMissing: Bool preserve: Bool patch: (Option String) restored: (List String) spec: (Option s/SpecVerdict) -> s/RunResult
  (let [state run.state
        usage state.usageTotals]
    (s/RunResult
      :status status :unbacked unbacked :unbackedClaims state.runUnbackedClaims
      :gates state.allGateResults :turns state.turn
      :escalate (match state.escalateReceipt ((some receipt) (some (j/jstr receipt))) ((none) none))
      :needsConfirm (if (listEmpty? state.needsConfirmList) none (some (j/jarr state.needsConfirmList)))
      :error state.error :sessionId run.session :session run.session
      :journal (journalOf env) :findings state.findingsList :parseDefect run.lastDefect
      :parseDefectTurn run.lastDefectTurn
      :modeHint env.modeHint :deliver state.deliver :phases state.phases :contextTokens state.contextTokens
      :patch patch :restored restored :written (distinct (listAppend state.writtenFiles (writtenPaths run.written))) :batching state.batching
      :gatesGreen (if preserve (some true) none)
      :commit (pairFirst commit) :commitError (if (some? (pairFirst commit)) none (pairSecond commit))
      :commitMissing (if commitMissing (some true) none)
      :queueWaitSec (if state.hasTiming (some state.totalQueueWaitSec) none)
      :execSec (if state.hasTiming (some state.totalExecSec) none)
      :usage (if (usageAny usage) (some usage) none) :signal state.signalName
      :ownsRejected state.ownsRejections
      :planSummary (match (j/jsonGet state.plan "steps") ((some _) (some state.plan)) ((none) none))
      :coreHost (coreHostZero) :openPossible (list)
      :gatePreflight none :message none :vacuousGates state.baselineGreen :specCheck spec))

fn ! failedAfterKill! env: s/LoopEnv run: LoopRun rootDir: String e: String -> s/RunResult
  (match (jr/handBack run.written rootDir env.journalPath run.session true run.written.startHead)
    ((err handErr) (emptyResultWith env run.session "failed" (some handErr) run.state.turn none (list) none none none run.state.baselineGreen))
    ((ok hand) (emptyResultWith env run.session "failed" (some e) run.state.turn (pairFirst (pairSecond hand)) (pairSecond (pairSecond hand)) none none none run.state.baselineGreen)))

; (:m :ref LEON-OK-WITHOUT-CHANGE :do "a run with declared gates and an :owns brief ends ok only when its final tree differs from its start: handBack's patch is none when every write was rejected or reverted, so green baseline gates cannot carry the verdict. A resumed run that restored a patch must also end with a patch other than the restored one (LEON-DONE-WITHOUT-WIRING); the restored patch's sha is journaled as :resumeBase at setup. Findings deliveries are exempt")
fn ! resumeBaseSha! journalPath: String -> (Option String)
  (match (listHead (filter (fn [l] (stringStartsWith? l "(:resumeBase :sha \"")) (stringLines (resultOr (fileReadString journalPath) ""))))
    ((some l) (let [rest (c/sliceOf l 19 (stringLength l))] (some (c/sliceOf rest 0 (optionOr (stringIndexOf rest "\"") 0)))))
    ((none) none))

fn withNoChange run: LoopRun state: s/LoopState -> LoopRun
  (with run :state (with state :signalName (some "noChange")))

; (:m :ref RAWREPLAY-RED :do "digest of the owned dirty state: git diff --binary HEAD limited to owns plus the untracked files under owns; the lower rung's handoff passes it as :inheritedBase and the run journals it as (:inheritedBase :sha ...)")
fn ! ownedDigest! owns: (List String) root: String -> String
  (let [diff (optionOr (go/gitText! (listAppend (list "git" "diff" "--binary" "HEAD" "--") owns) root) "")
        untracked (optionOr (go/gitText! (listAppend (list "git" "ls-files" "--others" "--exclude-standard" "--") owns) root) "")
        paths (filter (fn [p] (not (stringEmpty? p))) (stringLines untracked))
        contents (map (fn [p] (str p "\n" (resultOr (fileReadString (str root "/" p)) ""))) paths)]
    (bytesSha256 (stringToBytes (str diff "\n" (stringJoin contents "\n")))))

fn ! inheritedBaseSha! journalPath: String -> (Option String)
  (match (listHead (filter (fn [l] (stringStartsWith? l "(:inheritedBase :sha \"")) (stringLines (resultOr (fileReadString journalPath) ""))))
    ((some l) (let [rest (c/sliceOf l 22 (stringLength l))] (some (c/sliceOf rest 0 (optionOr (stringIndexOf rest "\"") 0)))))
    ((none) none))

fn ! refusedWrite? journalPath: String -> Bool
  (listAny? (fn [l] (and (stringStartsWith? l "(:op :turn ")
                         (and (not (stringContains? l " :status ok"))
                              (listAny? (fn [n] (stringContains? l (str " :name \"" n "\""))) (list "write" "edit" "txn" "delete")))))
            (stringLines (resultOr (fileReadString journalPath) "")))

fn withInheritedChange run: LoopRun state: s/LoopState -> LoopRun
  (with run :state (with state :signalName (some "inheritedChange")))

; (:m :ref RAWREPLAY-RED :do "7de069c5874e6633: a session that wrote nothing is not noChange only when the lower rung that changed the owned files handed that state over explicitly: the run's (:inheritedBase :sha D) row equals the current owned dirty digest and no write of its own was refused; a dirty tree with no marker, a mismatching marker, a clean tree or a refused write stays noChange/needsReview (LEON-OK-WITHOUT-CHANGE)")
fn ! inheritedHolds? env: s/LoopEnv rootDir: String -> Bool
  (match (inheritedBaseSha! env.journalPath)
    ((some sha) (and (= sha (ownedDigest! env.owns rootDir)) (not (refusedWrite? env.journalPath))))
    ((none) false))

fn ! noChangeEnd? env: s/LoopEnv state: s/LoopState rootDir: String status: String patch: (Option String) inherited: Bool -> Bool
  (if (and (= status "ok") (and (not (listEmpty? env.gates)) (and (not (listEmpty? env.owns)) (!= (optionOr state.deliver "") "findings"))))
    (match patch
      ((none) (not inherited))
      ((some p)
        (match (resumeBaseSha! env.journalPath)
          ((some sha) (= sha (bytesSha256 (stringToBytes (resultOr (fileReadString (str rootDir "/" p)) "")))))
          ((none) false))))
    false)

; (:m :ref LEON-FAIL-STATUS :do "stale ad-hoc findings data does not fail a run that wrote its owned files and ended on green declared gates, and a downgrade to failed writes a verdict line naming the cause")
fn ! finish! env: s/LoopEnv run: LoopRun -> s/RunResult
  (let [state run.state
        rootDir (absoluteRoot! env.rootDir)
        findings (map ctx/pyStr state.findingsList)
        wroteGreen (and (not (listEmpty? env.gates)) (and (declaredGatesGreen env.gates state.lastGates) (and (!= (optionOr state.deliver "") "findings") (not (listEmpty? (distinct (listAppend state.writtenFiles (writtenPaths run.written))))))))
        outcome (stringSplit (lp/finalOutcome state.status (optionOr state.deliver "") (and (not (listEmpty? findings)) (not wroteGreen))
          (listAny? (fn [f] (stringContains? f ":claim")) findings) (listLength state.runUnbackedClaims) 0) "|")
        status0 (c/firstOf outcome)
        finalUnbacked (optionOr (stringToInt64 (optionOr (listGet outcome 1) "")) 0)
        failed (fn [e patch restored] (emptyResultWith env run.session "failed" (some e) state.turn patch restored none none none state.baselineGreen))]
    (match (killRun! env run rootDir)
      ((err e) (failedAfterKill! env run rootDir e))
      ((ok _)
        (let [written (distinct (listAppend state.writtenFiles (writtenPaths run.written)))
              _why (if (and (= status0 "failed") (= state.status "ok")) (ok? (jr/journalWrite env.journalPath (str "(:verdict :failed :why \"findings without a claim, and no green declared gate over written files\" :findings " (stringFromInt64 (listLength findings)) ")\n"))) true)
              dirty (resultOr (go/changedOwnedFiles! env.owns rootDir none) (list))
              targets (specTargets written dirty)
              spec (if (specCheckWanted? env.specCheck status0 targets)
                     (some (specCheckRun! env run rootDir targets))
                     none)
              finalStatus (match spec ((some v) (if (listContains? (list "fail" "skipped" "unavailable") v.verdict) "needsReview" status0)) ((none) status0))
              gatesGreen (declaredGatesGreen env.gates state.lastGates)
              preserveGreen (and gatesGreen (not (listEmpty? env.gates)))
              preserve (lp/preserveFiles finalStatus (optionOr state.escalateReceipt "")
                (intField state.retries "gates" 0) (intField state.retries "steps" 0) run.parseDefects preserveGreen)
              restore (lp/handBackRestore finalStatus preserve)]
          (match (jr/handBack run.written rootDir env.journalPath run.session restore run.written.startHead)
            ((err e) (failed e none (list)))
            ((ok hand)
              (let [patch (pairFirst (pairSecond hand))
                    restored (pairSecond (pairSecond hand))
                    inherited (inheritedHolds? env rootDir)
                    noChange (noChangeEnd? env state rootDir finalStatus patch inherited)
                    endStatus (if noChange "needsReview" finalStatus)
                    _noChange (if noChange (journalSignal! env state.turn "noChange" "no persisted change versus the start of the run, or none beyond the restored patch") true)
                    inheritedEnd (and (not noChange) (and inherited (and (none? patch) (= finalStatus "ok") (not (listEmpty? env.gates)))))
                    _inheritedNote (if inheritedEnd (journalSignal! env state.turn "inheritedChange" (str "no work in this session; the ok rests on changes inherited from a lower rung in " (stringJoin dirty " "))) true)
                    run2 (cond (noChange (withNoChange run state)) (inheritedEnd (withInheritedChange run state)) (else run))]
                (match (commit! env run2 rootDir endStatus gatesGreen)
                  ((err e) (failed e patch restored))
                  ((ok commit)
                    (let [commitMissing (and (= endStatus "ok") (and state.commitRequested (and (none? run.commitMessage) state.writesPersisted)))]
                      (match (journaled! env (str (if commitMissing "(:commitMissing true)\n" "")
                            (ctx/coreStatsLine (coreHostZero))
                            (resultText run2.state run.session endStatus finalUnbacked commit commitMissing preserve patch restored spec)) true)
                        ((err e) (failed e patch restored))
                        ((ok _) (finalResult env run2 endStatus finalUnbacked commit commitMissing preserve patch restored spec)))))))))))))

fn ! runBody! env: s/LoopEnv run: LoopRun body: (fn [s/LoopEnv LoopRun] -> (Pair LoopRun s/Step)) -> LoopRun
  (match (head! env run.state run.parseDefectStreak)
    ((pair current step)
      (let [headed (withState run current)]
        (match step
          ((proceed)
            (match (body env headed)
              ((pair next nextStep)
                (let [_cp (jr/checkpoint! next.written (absoluteRoot! env.rootDir) env.journalPath next.session next.state.turn)]
                  (match nextStep ((stop) next) ((nextTurn) (runBody! env next body)) ((proceed) (runBody! env next body)))))))
          ((nextTurn) headed)
          ((stop) headed)))))

; (:m :ref LEON-PREFIX-CACHE-TOOLMEMO :do "cleanup! is the one exit every run path reaches, early stop, success and failure, so the read memo scope ends here; it opens in the ready branches after setup")
fn ! cleanup! env: s/LoopEnv sid: String -> (Result Bool String)
  (let [_memoEnded (ao/memoRunEnd! (absoluteRoot! env.rootDir) sid)]
    (match (jr/retainJournal env.journalPath env.rootDir sid)
      ((err e) (err e)) ((ok _) (ok true))))

fn ! runLoopWith! env: s/LoopEnv body: (fn [s/LoopEnv LoopRun] -> (Pair LoopRun s/Step)) -> s/RunResult
  (match (setup! env)
    ((early result)
      (match (cleanup! env result.session)
        ((err e) (emptyResult env result.session "failed" (some e) result.turns none (list) none none none))
        ((ok _) result)))
    ((ready run)
      (let [_memoBegun (ao/memoRunBeginIfOn! (absoluteRoot! env.rootDir) run.session)
            finished (runBody! env run body)
            result (finish! env finished)]
        (match (cleanup! env finished.session)
          ((err e) (emptyResultWith env finished.session "failed" (some e) finished.state.turn none (list) none none none finished.state.baselineGreen))
          ((ok _) result)))))

; (:m :ref SE3-POOL-DRIVER :do "the provider run as three steps a driver can interleave: loopOpen! (setup, early results already cleaned up), loopHead! (the head decision of one turn), loopFinish! (finish and cleanup); runBodyWithProvider! and runLoopWithProviderWatched! are composed from them and behave as before")
fn ! loopOpen! env: s/LoopEnv provider: pv/Provider parent: (Option Int64) -> LoopOpen
  (match (setupWatched! env parent)
    ((early result)
      (match (cleanup! env result.session)
        ((err e) (openDone (emptyResult env result.session "failed" (some e) result.turns none (list) none none none)))
        ((ok _) (openDone result))))
    ((ready run)
      (let [_memoBegun (ao/memoRunBeginIfOn! (absoluteRoot! env.rootDir) run.session)]
        (openRun (ProviderRun :run run :provider provider :history run.state.history)))))

fn ! loopHead! env: s/LoopEnv wrapped: ProviderRun -> (Pair ProviderRun s/Step)
  (match (head! env wrapped.run.state wrapped.run.parseDefectStreak)
    ((pair current step)
      (pair (ProviderRun :run (withState wrapped.run current) :provider wrapped.provider :history wrapped.history) step)))

fn ! loopFinish! env: s/LoopEnv finished: ProviderRun -> s/RunResult
  (let [completed finished.run
        result (finish! env completed)]
    (match (cleanup! env completed.session)
      ((err e) (emptyResultWith env completed.session "failed" (some e) completed.state.turn none (list) none none none completed.state.baselineGreen))
      ((ok _) result)))

fn ! runBodyWithProvider! env: s/LoopEnv wrapped: ProviderRun body: (fn [s/LoopEnv ProviderRun] -> (Pair ProviderRun s/Step)) -> ProviderRun
  (match (loopHead! env wrapped)
    ((pair headed step)
      (match step
        ((proceed)
          (match (body env headed)
            ((pair next nextStep)
              (let [_cp (jr/checkpoint! next.run.written (absoluteRoot! env.rootDir) env.journalPath next.run.session next.run.state.turn)]
                (match nextStep ((stop) next) ((nextTurn) (runBodyWithProvider! env next body)) ((proceed) (runBodyWithProvider! env next body)))))))
        ((nextTurn) headed)
        ((stop) headed))))

fn ! runLoopWithProvider! env: s/LoopEnv provider: pv/Provider body: (fn [s/LoopEnv ProviderRun] -> (Pair ProviderRun s/Step)) -> s/RunResult
  (runLoopWithProviderWatched! env provider none body)

fn ! runLoopWithProviderWatched! env: s/LoopEnv provider: pv/Provider parent: (Option Int64) body: (fn [s/LoopEnv ProviderRun] -> (Pair ProviderRun s/Step)) -> s/RunResult
  (match (loopOpen! env provider parent)
    ((openDone result) result)
    ((openRun wrapped) (loopFinish! env (runBodyWithProvider! env wrapped body))))
