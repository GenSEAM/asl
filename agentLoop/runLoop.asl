(module asl/agentLoop/runLoop
  :x [LoopSetup LoopRun ProviderRun withState withProcs withWritten withCommitMessage withOwnsRejections withPlan writtenPaths noteParseTurn headDecision stateFor withHeadState withFindings wallSeconds setup! head! finish! runLoopWith! runLoopWithProvider!]
  :i [(asl/agentLoop/loopState :a s) (asl/agentLoop/loop :a lp)
      (asl/agentLoop/context :a ctx) (asl/agentLoop/journal :a jr)
      (asl/agentLoop/gitOps :a go) (asl/agentLoop/runOps :a ro) (asl/agentLoop/reply :a rp)
      (asl/agentLoop/core :a c) (asl/agentLoop/gates :a g) (asl-json/json :a j)
      (asl/agentLoop/providers :a pv)])

schema LoopRun
  (:f state s/LoopState) (:f procs ro/Procs) (:f written jr/Written) (:f session String)
  (:f commitMessage (Option String)) (:f parseDefects Int64) (:f lastDefect Bool) (:f lastDefectTurn (Option Int64))

schema ProviderRun
  (:f run LoopRun)
  (:f provider pv/Provider)
  (:f history (List j/Json))

enum LoopSetup
  (ready LoopRun)
  (early s/RunResult)

fn withState run: LoopRun state: s/LoopState -> LoopRun
  (LoopRun :state state :procs run.procs :written run.written :session run.session
    :commitMessage run.commitMessage :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn)

fn withProcs run: LoopRun procs: ro/Procs -> LoopRun
  (LoopRun :state run.state :procs procs :written run.written :session run.session
    :commitMessage run.commitMessage :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn)

fn withWritten run: LoopRun written: jr/Written -> LoopRun
  (LoopRun :state run.state :procs run.procs :written written :session run.session
    :commitMessage run.commitMessage :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn)

fn writtenPaths written: jr/Written -> (List String)
  (mt written.files
    ((some files) (map pairFirst files))
    ((none) (list)))

fn noteParseTurn run: LoopRun turn: Int64 defect: Bool -> LoopRun
  (LoopRun :state run.state :procs run.procs :written run.written :session run.session
    :commitMessage run.commitMessage :parseDefects (if defect (+ run.parseDefects 1) run.parseDefects)
    :lastDefect defect :lastDefectTurn (if defect (some turn) run.lastDefectTurn))

fn withCommitMessage run: LoopRun message: (Option String) -> LoopRun
  (LoopRun :state run.state :procs run.procs :written run.written :session run.session
    :commitMessage message :parseDefects run.parseDefects
    :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn)

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
    :planSummary none :coreHost (if (= status "escalated") (coreZero) (j/jobj (list))) :openPossible (list) :gatePreflight preflight :message message)

fn taskByte bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet bs i) -1)

fn taskWordByte b: Int64 -> Bool
  (or (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))
    (or (and (>= b 48) (<= b 57)) (or (= b 95) (> b 127))))

fn taskCommitAt bs: Bytes n: Int64 i: Int64 -> Bool
  (and (= (taskByte bs n i) 99)
    (and (= (taskByte bs n (+ i 1)) 111)
      (and (= (taskByte bs n (+ i 2)) 109)
        (and (= (taskByte bs n (+ i 3)) 109)
          (and (= (taskByte bs n (+ i 4)) 105)
            (and (= (taskByte bs n (+ i 5)) 116)
              (and (not (taskWordByte (taskByte bs n (- i 1))))
                (not (taskWordByte (taskByte bs n (+ i 6)))))))))))

fn taskCommitScan bs: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    false
    (or (taskCommitAt bs n i) (taskCommitScan bs n (+ i 1))))

fn taskRequestsCommit task: String -> Bool
  (let [bs (stringToBytes (stringLower task))]
    (taskCommitScan bs (bytesLength bs) 0))

fn stateFor env: s/LoopEnv -> s/LoopState
  (let [tokens (ctx/contextTokensFor env.model (mt env.contextTokens ((some n) (j/jint n)) ((none) (j/jnull))) false)
        resumeTurn (mt env.resume ((some resume) (intField resume "turn" 0)) ((none) 0))]
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
      :briefCount 0 :code "" :commitRequested (taskRequestsCommit env.task) :declaredOps (list) :fetched (j/jobj (list))
      :header "" :history (list) :lastGates (mapEmpty) :missingGateIntro (list) :patchErr none
      :placeholderBriefs (mapEmpty) :prefetch "" :priorIds (list) :resumePatchPath none
      :retries (j/jobj (list)) :runUnbackedClaims (list) :specChecksDone 0 :startTurn resumeTurn
      :taskLines "" :unparsable (j/jobj (list)) :vendorBounds (j/jobj (list))
      :window (j/jobj (list)) :writtenFiles (list)))
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
      :placeholderBriefs state.placeholderBriefs
      :prefetch state.prefetch
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
      :placeholderBriefs state.placeholderBriefs :prefetch state.prefetch :priorIds state.priorIds
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
      :placeholderBriefs state.placeholderBriefs :prefetch state.prefetch :priorIds state.priorIds
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
      :placeholderBriefs state.placeholderBriefs :prefetch state.prefetch :priorIds state.priorIds
      :resumePatchPath state.resumePatchPath :retries state.retries :runUnbackedClaims state.runUnbackedClaims
      :specChecksDone state.specChecksDone :startTurn state.startTurn :taskLines state.taskLines
      :unparsable state.unparsable :vendorBounds state.vendorBounds :window state.window
      :writtenFiles state.writtenFiles)


fn preflightJson bad: (List (List (Pair String go/RVal))) -> j/Json
  (j/jarr (map (fn [rec]
    (j/jobj (map (fn [field] (pair (pairFirst field) (s/gitRValJson (pairSecond field)))) rec))) bad))

fn stringField obj: j/Json key: String fallback: String -> String
  (mt (j/jsonGet obj key)
    ((some v) (mt v ((j/jstr s) s) ((j/jnum _) fallback) ((j/jint _) fallback) ((j/jbool _) fallback) ((j/jnull) fallback) ((j/jarr _) fallback) (_ fallback)))
    ((none) fallback))

fn intField obj: j/Json key: String fallback: Int64 -> Int64
  (mt (j/jsonGet obj key)
    ((some v) (mt v ((j/jint n) n) (_ fallback)))
    ((none) fallback))

fn wallSeconds elapsed: Float64 -> String
  (stringFromInt64 (optionOr (float64ToInt64 (ctx/pyRound elapsed 0)) 0))

fn ! resumeJournal! path: (Option String) journal: String -> Bool
  (mt path
    ((some patchPath) (ok? (jr/journalWrite journal (str "(:resumeApplied \"" (c/escapeAsn patchPath) "\")\n"))))
    ((none) true))

fn ! startHead! rootDir: String -> (Result (Option String) String)
  (mt (jr/git! rootDir (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok o) (ok (if (= o.exitCode 0) (some (ctx/pyStrip o.stdout)) none))))

fn ! setup! env: s/LoopEnv -> LoopSetup
  (let [state (stateFor env)
        sid (optionOr env.sessionId (env.newId))
        rootDir (absoluteRoot! env.rootDir)]
    (mt (startHead! rootDir)
      ((err e) (early (emptyResult env sid "failed" (some e) 0 none (list) none none none)))
      ((ok head) (setupAt! env state sid rootDir head))))

fn ! setupAt! env: s/LoopEnv state: s/LoopState sid: String rootDir: String head: (Option String) -> LoopSetup
  (let [timeout (optionOr env.gateTimeout 10)
        header (mt env.resume
          ((some resume) (str "(:turn " (stringFromInt64 (intField resume "turn" 0)) " :answer \""
            (c/escapeAsn (stringField resume "answer" "")) "\")\n(:transport :subprocess :transportWhy \"ASL_TRANSPORT=subprocess\")\n"))
          ((none) (lp/sessionHeader sid env.task (optionOr env.modeHint "")
            (optionOr env.intent "auto") rootDir env.owns env.gates
            (optionOr env.base "") (optionOr env.model "") "default" ":transport :subprocess :transportWhy \"ASL_TRANSPORT=subprocess\""
            (stringFromInt64 timeout) (stringFromInt64 (optionOr env.contextTokens 24000))
            (mt env.wallBudget ((some n) (stringFromInt64 n)) ((none) "")) env.plan)))
        preflight (go/gatePreflight! env.gates rootDir none)
        fresh (jr/newWritten rootDir head)
        patchState (mt env.resume
          ((some _) (mt (jr/applyResumePatch fresh rootDir env.journalPath sid)
            ((err e) (pair fresh (pair none (some e)))) ((ok applied) applied)))
          ((none) (pair fresh (pair none none))))
        applied (pairFirst (pairSecond patchState))
        patchError (pairSecond (pairSecond patchState))]
    (do
      (jr/journalWrite env.journalPath header)
      (resumeJournal! applied env.journalPath)
      (cond
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
          (ready (LoopRun
            :state (withHeadState state state.turn state.readStreak (some? applied)
              state.deliver state.allGateResults state.lastGates state.status state.signalName
              state.escalateReceipt state.runStarted)
            :procs (ro/newProcs) :written (pairFirst patchState) :session sid :commitMessage none :parseDefects 0 :lastDefect false :lastDefectTurn none))))))

fn latestRed entry: j/Json -> Bool
  (mt entry
    ((j/jobj _) (mt (optionOr (j/jsonGet entry "exit") (j/jnull))
      ((j/jint n) (!= n 0)) ((j/jnum x) (!= x 0.0)) ((j/jfloat x) (!= x 0.0)) (_ true)))
    ((j/jarr items)
      (mt (listHead (if (listEmpty? items) (list) (c/restOf items)))
        ((some gate) (mt (optionOr (j/jsonGet gate "exit") (j/jnull)) ((j/jint n) (!= n 0)) ((j/jnum x) (!= x 0.0)) ((j/jfloat x) (!= x 0.0)) (_ true)))
        ((none) true)))
    (_ true))

fn redGateOf gates: (List String) lastGates: (Map String j/Json) -> Bool
  (listAny? (fn [cmd] (mt (mapGet lastGates cmd) ((some entry) (latestRed entry)) ((none) false))) gates)

fn declaredGatesGreen gates: (List String) lastGates: (Map String j/Json) -> Bool
  (lp/finalGatesGreen (map (fn [cmd] (mt (mapGet lastGates cmd) ((some entry) (if (latestRed entry) "0" "1")) ((none) "0"))) gates))

fn headDecision env: s/LoopEnv state: s/LoopState -> String
  (let [runTurns (max 0 (- state.turn state.startTurn))
        elapsed (- (env.now) state.runStarted)
        noWriteTurnLimit (min (* (int64ToFloat64 env.budget) 0.5) (int64ToFloat64 (ctx/noWriteTurns)))]
    (lp/loopBoundary (redGateOf env.gates state.lastGates) state.readStreak (ctx/readStreakEscalate)
      (optionOr state.deliver "") state.writesPersisted (int64ToFloat64 runTurns) noWriteTurnLimit
      (optionOr env.wallBudget 0) elapsed 0.5 (+ state.turn 1) env.budget))

fn ! journalSignal! env: s/LoopEnv turn: Int64 signal: String reason: String -> Bool
  (do
    (jr/journalWrite env.journalPath (str "(:turn " (stringFromInt64 turn) " :signal :" signal " :reason \"" (c/escapeAsn reason) "\")\n"))
    true)

fn ! head! env: s/LoopEnv state: s/LoopState -> (Pair s/LoopState s/Step)
  (let [decision (headDecision env state)
        nextTurn (+ state.turn 1)]
    (cond
      ((= decision "budget")
        (pair (withHeadState state nextTurn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" none
          (some (str "(:escalate :reason \"budget exhausted after " (stringFromInt64 state.turn) " turns\")")) state.runStarted) (stop)))
      ((= decision "readStreak")
        (do
        (journalSignal! env state.turn "readStreak" (str (stringFromInt64 state.readStreak) " turns without a write while a gate is red"))
        (pair (withHeadState state state.turn state.readStreak state.writesPersisted state.deliver
          state.allGateResults state.lastGates "escalated" (some "readStreak")
          (some (str "(:escalate :reason \"" (stringFromInt64 state.readStreak) " turns without a write while a gate is red\")")) state.runStarted) (stop))))
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
  (mt usage ((j/jobj kvs) (listAny? (fn [kv] (ctx/pyTruthy (pairSecond kv))) kvs)) (_ false))

fn usageInt usage: j/Json key: String -> String
  (stringFromInt64 (intField usage key 0))

fn ! journaled! env: s/LoopEnv text: String value: T -> (Result T String)
  (mt (jr/journalWrite env.journalPath text)
    ((err e) (err e))
    ((ok _) (ok value)))

fn ! killRun! env: s/LoopEnv run: LoopRun rootDir: String -> (Result (List String) String)
  (let [state run.state
        runCtx (ro/makeRunCtx rootDir state.scope run.session (optionOr env.gateTimeout 10) (list) rootDir)]
    (mt (ro/killSpawned! runCtx run.procs (fn [rel pre mode] true))
      ((err e) (err e))
      ((ok out)
        (if (listEmpty? out.killed)
          (ok (list))
          (journaled! env (str "(:killed (" (quoted out.killed) "))\n") out.killed)))))

fn ! headSha! rootDir: String -> (Result String String)
  (mt (jr/git! rootDir (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok o) (ok (ctx/pyStrip o.stdout))))

fn ! committed! env: s/LoopEnv rootDir: String -> (Result (Pair (Option String) (Option String)) String)
  (mt (headSha! rootDir)
    ((err e) (err e))
    ((ok sha) (journaled! env (str "(:commit \"" sha "\")\n") (pair (some sha) none))))

fn ! commitFailed! env: s/LoopEnv why: String -> (Result (Pair (Option String) (Option String)) String)
  (journaled! env (str "(:commitError \"" (c/escapeAsn why) "\")\n") (pair none (some why)))

fn ! relativeTo path: String rootDir: String -> String
  (if (stringStartsWith? path "/") (jr/pathRel path rootDir) (jr/pathNorm path))

fn distinct xs: (List String) -> (List String)
  (fold (fn [acc x] (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn ! commitWritten! env: s/LoopEnv run: LoopRun rootDir: String message: String -> (Result (Pair (Option String) (Option String)) String)
  (let [paths (distinct (map (fn [p] (relativeTo p rootDir))
    (listAppend run.state.writtenFiles (writtenPaths run.written))))]
    (if (listEmpty? paths)
      (commitFailed! env "the run wrote no path to commit")
      (mt (jr/git! rootDir (listAppend (list "ls-files" "--others" "--exclude-standard" "--") paths))
        ((err e) (err e))
        ((ok listed)
          (let [newFiles (filter (fn [f] (not (stringEmpty? f))) (map ctx/pyStrip (stringLines listed.stdout)))]
            (mt (if (listEmpty? newFiles) (ok 0) (mt (jr/git! rootDir (listAppend (list "add" "--") newFiles)) ((err e) (err e)) ((ok o) (ok o.exitCode))))
              ((err e) (err e))
              ((ok _)
                (mt (jr/git! rootDir (listAppend (list "commit" "-m" message "--") paths))
                  ((err e) (err e))
                  ((ok done)
                    (if (= done.exitCode 0)
                      (committed! env rootDir)
                      (commitFailed! env (ctx/pyStrip (if (stringEmpty? done.stderr) done.stdout done.stderr)))))))))))))

fn ! commit! env: s/LoopEnv run: LoopRun rootDir: String status: String gatesGreen: Bool -> (Result (Pair (Option String) (Option String)) String)
  (let [message (optionOr run.commitMessage "")]
    (if (or (stringEmpty? message) (or (!= status "ok") (not gatesGreen)))
      (ok (pair none none))
      (let [invalid (rp/commitMessageError message)]
        (mt (if (some? invalid) (rp/commitNamesHead! message rootDir) (ok false))
          ((err e) (err e))
          ((ok namesHead)
            (cond
              (namesHead (committed! env rootDir))
              ((some? invalid) (commitFailed! env (str "the commit message is not a valid (:c ...) ASN line: " (optionOr invalid ""))))
              (else (commitWritten! env run rootDir message))))))))

fn resultText state: s/LoopState session: String status: String unbacked: Int64 commit: (Pair (Option String) (Option String)) commitMissing: Bool preserve: Bool patch: (Option String) restored: (List String) -> String
  (let [claims (map ctx/pyStr state.runUnbackedClaims)
        findings (map ctx/pyStr state.findingsList)
        usage state.usageTotals
        batching state.batching]
    (str "(:result :status :" status
      (if (stringEmpty? session) "" (str " :session \"" session "\""))
      " :unbacked " (stringFromInt64 unbacked)
      (if (listEmpty? claims) "" (str " :unbackedClaims (" (quoted claims) ")"))
      " :contextTokens " (stringFromInt64 (optionOr state.contextTokens 0))
      (mt state.error ((some e) (str " :error :" (stripColons e))) ((none) ""))
      (mt (pairFirst commit)
        ((some sha) (str " :commit \"" sha "\""))
        ((none) (mt (pairSecond commit) ((some why) (str " :commitError \"" (c/escapeAsn why) "\"")) ((none) ""))))
      (if commitMissing " :commitMissing true" "")
      (mt state.deliver ((some d) (if (stringEmpty? d) "" (str " :deliver :" d))) ((none) ""))
      " :phases (" (phasesText state.phases) ")"
      (if preserve " :gatesGreen true" "")
      (if (listEmpty? findings) "" (str " :findings (" (c/joinSep findings " ") ")"))
      (if state.hasTiming (str " :queueWaitSec " (ctx/floatRepr state.totalQueueWaitSec) " :execSec " (ctx/floatRepr state.totalExecSec)) "")
      (if (usageAny usage) (str " :usage (:input " (usageInt usage "inputTokens") " :cached " (usageInt usage "cachedTokens") " :output " (usageInt usage "outputTokens") ")") "")
      " :batching (:turns " (batchingInt batching "turns") " :ops " (batchingInt batching "ops") " :singleOp " (batchingInt batching "single") ")"
      (jr/handBackFields patch restored) (jr/writtenField state.writtenFiles) ")\n"))

fn ! finalResult env: s/LoopEnv run: LoopRun status: String unbacked: Int64 commit: (Pair (Option String) (Option String)) commitMissing: Bool preserve: Bool patch: (Option String) restored: (List String) -> s/RunResult
  (let [state run.state
        usage state.usageTotals]
    (s/RunResult
      :status status :unbacked unbacked :unbackedClaims state.runUnbackedClaims
      :gates state.allGateResults :turns state.turn
      :escalate (mt state.escalateReceipt ((some receipt) (some (j/jstr receipt))) ((none) none))
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
      :planSummary (mt (j/jsonGet state.plan "steps") ((some _) (some state.plan)) ((none) none))
      :coreHost (coreHostZero) :openPossible (list)
      :gatePreflight none :message none))

fn ! failedAfterKill! env: s/LoopEnv run: LoopRun rootDir: String e: String -> s/RunResult
  (mt (jr/handBack run.written rootDir env.journalPath run.session true run.written.startHead)
    ((err handErr) (emptyResult env run.session "failed" (some handErr) run.state.turn none (list) none none none))
    ((ok hand) (emptyResult env run.session "failed" (some e) run.state.turn (pairFirst (pairSecond hand)) (pairSecond (pairSecond hand)) none none none)))

fn ! finish! env: s/LoopEnv run: LoopRun -> s/RunResult
  (let [state run.state
        rootDir (absoluteRoot! env.rootDir)
        findings (map ctx/pyStr state.findingsList)
        outcome (stringSplit (lp/finalOutcome state.status (optionOr state.deliver "") (not (listEmpty? findings))
          (listAny? (fn [f] (stringContains? f ":claim")) findings) (listLength state.runUnbackedClaims) 0) "|")
        finalStatus (c/firstOf outcome)
        finalUnbacked (optionOr (stringToInt64 (optionOr (listGet outcome 1) "")) 0)
        failed (fn [e patch restored] (emptyResult env run.session "failed" (some e) state.turn patch restored none none none))]
    (mt (killRun! env run rootDir)
      ((err e) (failedAfterKill! env run rootDir e))
      ((ok _)
        (let [gatesGreen (declaredGatesGreen env.gates state.lastGates)
              preserveGreen (and gatesGreen (not (listEmpty? env.gates)))
              preserve (lp/preserveFiles finalStatus (optionOr state.escalateReceipt "")
                (intField state.retries "gates" 0) (intField state.retries "steps" 0) run.parseDefects preserveGreen)
              restore (lp/handBackRestore finalStatus preserve)]
          (mt (jr/handBack run.written rootDir env.journalPath run.session restore run.written.startHead)
            ((err e) (failed e none (list)))
            ((ok hand)
              (let [patch (pairFirst (pairSecond hand))
                    restored (pairSecond (pairSecond hand))]
                (mt (commit! env run rootDir finalStatus gatesGreen)
                  ((err e) (failed e patch restored))
                  ((ok commit)
                    (let [commitMissing (and (= finalStatus "ok") (and state.commitRequested (and (none? run.commitMessage) state.writesPersisted)))]
                      (mt (journaled! env (str (if commitMissing "(:commitMissing true)\n" "")
                            (ctx/coreStatsLine (coreHostZero))
                            (resultText state run.session finalStatus finalUnbacked commit commitMissing preserve patch restored)) true)
                        ((err e) (failed e patch restored))
                        ((ok _) (finalResult env run finalStatus finalUnbacked commit commitMissing preserve patch restored)))))))))))))

fn ! runBody! env: s/LoopEnv run: LoopRun body: (fn [s/LoopEnv LoopRun] -> (Pair LoopRun s/Step)) -> LoopRun
  (mt (head! env run.state)
    ((pair current step)
      (let [headed (withState run current)]
        (mt step
          ((proceed)
            (mt (body env headed)
              ((pair next nextStep)
                (mt nextStep ((stop) next) ((nextTurn) (runBody! env next body)) ((proceed) (runBody! env next body))))))
          ((nextTurn) headed)
          ((stop) headed)))))

fn ! cleanup! env: s/LoopEnv sid: String -> (Result Bool String)
  (mt (jr/retainJournal env.journalPath env.rootDir sid)
    ((err e) (err e)) ((ok _) (ok true)))

fn ! runLoopWith! env: s/LoopEnv body: (fn [s/LoopEnv LoopRun] -> (Pair LoopRun s/Step)) -> s/RunResult
  (mt (setup! env)
    ((early result)
      (mt (cleanup! env result.session)
        ((err e) (emptyResult env result.session "failed" (some e) result.turns none (list) none none none))
        ((ok _) result)))
    ((ready run)
      (let [finished (runBody! env run body)
            result (finish! env finished)]
        (mt (cleanup! env finished.session)
          ((err e) (emptyResult env finished.session "failed" (some e) finished.state.turn none (list) none none none))
          ((ok _) result)))))

fn ! runBodyWithProvider! env: s/LoopEnv wrapped: ProviderRun body: (fn [s/LoopEnv ProviderRun] -> (Pair ProviderRun s/Step)) -> ProviderRun
  (mt (head! env wrapped.run.state)
    ((pair current step)
      (let [headed (ProviderRun :run (withState wrapped.run current) :provider wrapped.provider :history wrapped.history)]
        (mt step
          ((proceed)
            (mt (body env headed)
              ((pair next nextStep)
                (mt nextStep ((stop) next) ((nextTurn) (runBodyWithProvider! env next body)) ((proceed) (runBodyWithProvider! env next body))))))
          ((nextTurn) headed)
          ((stop) headed)))))

fn ! runLoopWithProvider! env: s/LoopEnv provider: pv/Provider body: (fn [s/LoopEnv ProviderRun] -> (Pair ProviderRun s/Step)) -> s/RunResult
  (mt (setup! env)
    ((early result)
      (mt (cleanup! env result.session)
        ((err e) (emptyResult env result.session "failed" (some e) result.turns none (list) none none none))
        ((ok _) result)))
    ((ready run)
      (let [finished (runBodyWithProvider! env (ProviderRun :run run :provider provider :history run.state.history) body)
            completed finished.run
            result (finish! env completed)]
        (mt (cleanup! env completed.session)
          ((err e) (emptyResult env completed.session "failed" (some e) completed.state.turn none (list) none none none))
          ((ok _) result)))))
