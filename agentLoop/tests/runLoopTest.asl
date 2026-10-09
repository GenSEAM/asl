(module asl/agentLoop/tests/runLoopTest
  :x [runTests]
  :i [(asl/agentLoop/runLoop :a rl) (asl/agentLoop/loopState :a s)
      (asl/agentLoop/providers :a pv) (asl/agentLoop/gates :a g) (asl-json/json :a j)
      (asl/agentLoop/tests/loopRunFixture :a f) (asl/agentLoop/plan :a p) (asl/agentLoop/core :a c)
      (asl/agentLoop/journal :a jr) (asl/agentLoop/runOps :a ro) (asl-proc/coreProcess :a cp)])

fn fakeTurn prompt: String system: String -> pv/Turn
  (pv/Turn :provider (pv/scriptProvider "loopRunTest" (list) 0)
    :reply (ok none) :meta (pv/TurnMeta :timing none :usage none :served none :finish none :truncated false))

fn fakeAdvice prompt: String system: String -> (Result (Option String) String)
  (ok none)

fn fakeId -> String
  "loopRunTest"

fn fakeNow -> Float64
  1.0

fn fakeSleep ms: Int64 -> Bool
  true

fn ! tempRoot -> String
  (let [path (str (optionOr (envGet "TMPDIR") "/tmp") "/loopRunTest_" (stringFromInt64 (procSelf)))]
    (do (dirCreate path) (resultOr (realPath path) path)))

fn ! fixtureJournal id: String -> (List String)
  (let [path "asl/agentLoop/tests/loopRunFixtures.asn"
        line (optionOr (listHead (filter (fn [candidate] (stringContains? candidate (str ":id \"" id "\""))) (f/scenarioLines! path))) "")
        scenario (mt (p/planTree line) ((ok nodes) (optionOr (listHead nodes) (p/sexpAtom "nil"))) ((err _) (p/sexpAtom "nil")))]
    (map f/argStr (c/restOf (f/listOf (f/field scenario ":journal")))))

fn makeEnv id: String task: String root: String journal: String budget: Int64 wall: (Option Int64) gates: (List String) resume: (Option j/Json) -> s/LoopEnv
  (makeEnvWith (some id) task root journal budget wall gates resume)

fn makeEnvWith sid: (Option String) task: String root: String journal: String budget: Int64 wall: (Option Int64) gates: (List String) resume: (Option j/Json) -> s/LoopEnv
  (s/LoopEnv :provider fakeTurn :task task :modeHint (some "implement") :owns (list) :gates gates
    :rootDir root :budget budget :journalPath journal :maxRetries 0 :sessionId sid
    :base (some "") :contextTokens (some 24000) :model (some "loop-run-fixture")
    :gateTimeout (some 10) :wallBudget wall :resume resume :intent (some "patch") :plan false :specCheck false
    :next fakeTurn :advise fakeAdvice :review fakeAdvice :newId fakeId :now fakeNow :sleep fakeSleep)

schema Final
  (:f turn Int64)
  (:f status String)
  (:f escalate (Option String))
  (:f gates (List g/GateResult))
  (:f lastGates (Map String j/Json))
  (:f deliver (Option String))
  (:f error (Option String))
  (:f retries j/Json)
  (:f phases (List String))
  (:f batching j/Json)
  (:f written (List String))
  (:f findings (List j/Json))
  (:f unbacked (List j/Json))
  (:f writesPersisted Bool)
  (:f commitRequested Bool)
  (:f hasTiming Bool)
  (:f queueWaitSec Float64)
  (:f execSec Float64)
  (:f usage j/Json)
  (:f signal (Option String))

fn finalState base: s/LoopState f: Final -> s/LoopState
  (s/LoopState
    :turn f.turn
    :contextTokens base.contextTokens
    :core base.core
    :wallBudget base.wallBudget
    :intent base.intent
    :plan base.plan
    :mode base.mode
    :sizingModel base.sizingModel
    :explicitContext base.explicitContext
    :transcriptChars base.transcriptChars
    :readCap base.readCap
    :startHead base.startHead
    :turnsWithoutEvidence base.turnsWithoutEvidence
    :readStreak base.readStreak
    :phases f.phases
    :deliver f.deliver
    :gatewayIntent base.gatewayIntent
    :researchKind base.researchKind
    :turnFacts base.turnFacts
    :reinforceWhy base.reinforceWhy
    :advisorCalls base.advisorCalls
    :advisorAsked base.advisorAsked
    :gateSigHistory base.gateSigHistory
    :executedSteps base.executedSteps
    :workspaceGen base.workspaceGen
    :failureCounts base.failureCounts
    :ownsRejections base.ownsRejections
    :scope base.scope
    :signalName f.signal
    :runStarted base.runStarted
    :vendorRetryCount base.vendorRetryCount
    :vendorWaitUsed base.vendorWaitUsed
    :seenEvidence base.seenEvidence
    :turnEvidence base.turnEvidence
    :writeTurn base.writeTurn
    :coverage base.coverage
    :writesPersisted f.writesPersisted
    :wroteSinceGate base.wroteSinceGate
    :allReceipts base.allReceipts
    :allGateResults f.gates
    :needsConfirmList base.needsConfirmList
    :escalateReceipt f.escalate
    :findingsList f.findings
    :possibleOpen base.possibleOpen
    :possibleNotices base.possibleNotices
    :status f.status
    :error f.error
    :totalQueueWaitSec f.queueWaitSec
    :totalExecSec f.execSec
    :usageTotals f.usage
    :batching f.batching
    :hasTiming f.hasTiming
    :basePrompt base.basePrompt
    :briefCount base.briefCount
    :code base.code
    :commitRequested f.commitRequested
    :declaredOps base.declaredOps
    :fetched base.fetched
    :header base.header
    :history base.history
    :lastGates f.lastGates
    :missingGateIntro base.missingGateIntro
    :patchErr base.patchErr
    :placeholderBriefs base.placeholderBriefs
    :prefetch base.prefetch
    :priorIds base.priorIds
    :resumePatchPath base.resumePatchPath
    :retries f.retries
    :runUnbackedClaims f.unbacked
    :specChecksDone base.specChecksDone
    :startTurn base.startTurn
    :taskLines base.taskLines
    :unparsable base.unparsable
    :vendorBounds base.vendorBounds
    :window base.window
    :writtenFiles f.written)

fn final turn: Int64 status: String escalate: (Option String) gates: (List g/GateResult) lastGates: (Map String j/Json) retries: j/Json -> Final
  (Final :turn turn :status status :escalate escalate :gates gates :lastGates lastGates :deliver none :error none
    :retries retries :phases (list) :batching (j/jobj (list (pair "ops" (j/jint 0)) (pair "single" (j/jint 0)) (pair "turns" (j/jint 0))))
    :written (list) :findings (list) :unbacked (list) :writesPersisted false :commitRequested false :hasTiming false
    :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none)

fn ! resultLine path: String -> String
  (optionOr (listLast (filter (fn [row] (stringStartsWith? row "(:result ")) (stringLines (fileText path)))) "")

fn neverBody env: s/LoopEnv run: rl/LoopRun -> (Pair rl/LoopRun s/Step)
  (pair run (stop))

fn onState f: (fn [s/LoopEnv s/LoopState] -> (Pair s/LoopState s/Step)) -> (fn [s/LoopEnv rl/LoopRun] -> (Pair rl/LoopRun s/Step))
  (fn [env run] (mt (f env run.state) ((pair state step) (pair (rl/withState run state) step))))

fn countBody env: s/LoopEnv state: s/LoopState -> (Pair s/LoopState s/Step)
  (pair (rl/withHeadState state (+ state.turn 1) state.readStreak state.writesPersisted
    state.deliver state.allGateResults state.lastGates state.status state.signalName state.escalateReceipt state.runStarted) (stop))

fn gateMap cmd: String exit: j/Json turn: Int64 -> (Map String j/Json)
  (mapFromPairs (list (pair cmd (j/jarr (list (j/jint turn) (j/jobj (list (pair "cmd" (j/jstr cmd)) (pair "exit" exit))))))))

fn redGateBody env: s/LoopEnv state: s/LoopState -> (Pair s/LoopState s/Step)
  (if (>= state.turn 20)
    (pair state (stop))
    (pair (rl/withHeadState state state.turn (+ state.readStreak 1) false none (list (g/makeGateResult "false" 1 "" "" false 0))
      (gateMap "false" (j/jint 1) state.turn) "ok" none none state.runStarted) (nextTurn)))

fn escalatedBody env: s/LoopEnv state: s/LoopState -> (Pair s/LoopState s/Step)
  (pair (rl/withHeadState state 3 0 false none (list) (mapEmpty) "escalated" none none state.runStarted) (stop))

fn wallBody env: s/LoopEnv state: s/LoopState -> (Pair s/LoopState s/Step)
  (if (= state.turn 1)
    (pair (rl/withHeadState state 1 0 false (some "patch") (list) (mapEmpty) "ok" none none 0.0) (nextTurn))
    (pair state (stop)))

fn ! gitOk! args: (List String) -> Bool
  (mt (cp/exec! (cp/cmd "git" args))
    ((ok o) (= o.exitCode 0))
    ((err _) false))

fn ! fileText path: String -> String
  (mt (fileReadString path) ((ok content) content) ((err _) "ERR_READ"))

fn ! removeIfExists! path: String -> (Result Unit String)
  (mt (fileStat path)
    ((ok _) (pathRemove path))
    ((err _) (ok ())))

fn budgetFieldsMatch r: s/RunResult -> Bool
  (and (= r.status "escalated") (and (= r.unbacked 0)
  (and (listEmpty? r.unbackedClaims) (and (listEmpty? r.gates)
  (and (= r.turns 1) (and (= r.escalate (some (j/jstr "(:escalate :reason \"budget exhausted after 0 turns\")")))
  (and (none? r.needsConfirm) (and (none? r.error)
  (and (= r.sessionId "loopRun01") (and (= r.session "loopRun01")
  (and (stringEndsWith? (optionOr r.journal "") "loopRunTest-budget0.asn")
  (and (listEmpty? r.findings) (and (not r.parseDefect)
  (and (none? r.parseDefectTurn) (and (= r.modeHint (some "implement"))
  (and (none? r.deliver) (and (listEmpty? r.phases)
  (and (= r.contextTokens (some 24000)) (and (none? r.patch)
  (and (listEmpty? r.restored) (and (listEmpty? r.written)
  (and (= (j/jsonEmit r.batching) "{\"ops\":0,\"single\":0,\"turns\":0}")
  (and (none? r.gatesGreen) (and (none? r.commit)
  (and (none? r.commitError) (and (none? r.commitMissing)
  (and (none? r.queueWaitSec) (and (none? r.execSec)
  (and (none? r.usage) (and (none? r.signal)
  (and (listEmpty? r.ownsRejected) (and (none? r.planSummary)
  (and (= (j/jsonEmit r.coreHost) "{\"calls\":0,\"cases\":0,\"sec\":0.0,\"built\":0}")
  (and (listEmpty? r.openPossible) (and (none? r.gatePreflight) (none? r.message))))))))))))))))))))))))))))))))))))

fn rejectFieldsMatch r: s/RunResult -> Bool
  (and (= r.status "rejected") (and (= r.unbacked 0) (and (= r.turns 0)
    (and (= r.error (some "ERR_GATE_UNPARSABLE")) (and (= r.contextTokens (some 24000))
    (and (= r.session "loopRun02") (and (= r.sessionId "loopRun02")
    (and (= r.modeHint (some "implement")) (and (not r.parseDefect)
    (and (listEmpty? r.gates) (and (listEmpty? r.findings)
    (and (listEmpty? r.phases) (and (listEmpty? r.restored)
    (and (listEmpty? r.written) (and (none? r.message)
    (and (none? r.escalate) (and (none? r.patch)
    (and (none? r.gatesGreen) (and (none? r.commit)
    (and (none? r.commitError) (and (none? r.commitMissing)
    (and (none? r.queueWaitSec) (and (none? r.execSec)
    (and (none? r.usage) (and (none? r.signal)
    (and (listEmpty? r.ownsRejected) (and (none? r.planSummary)
    (and (listEmpty? r.openPossible) (none? r.parseDefectTurn)))))))))))))))))))))))))))))

fn resumeFieldsMatch r: s/RunResult -> Bool
  (and (= r.status "rejected") (and (= r.unbacked 0) (and (= r.turns 0)
    (and (= r.error (some "ERR_RESUME_PATCH")) (and (= r.contextTokens (some 24000))
    (and (= r.session "loopRun03") (and (= r.sessionId "loopRun03")
    (and (= (some (stringReplace (optionOr r.message "") "loopRunTest-resume.patch" "loop.patch")) (some "git apply loop.patch: error: No valid patches in input (allow with \"--allow-empty\")"))
    (and (= r.modeHint (some "implement")) (and (not r.parseDefect)
    (and (listEmpty? r.gates) (and (listEmpty? r.findings)
    (and (listEmpty? r.phases) (and (listEmpty? r.restored)
    (and (listEmpty? r.written) (and (none? r.escalate)
    (and (none? r.patch) (and (none? r.gatesGreen)
    (and (none? r.commit) (and (none? r.commitError)
    (and (none? r.commitMissing) (and (none? r.queueWaitSec)
    (and (none? r.execSec) (and (none? r.usage)
    (and (none? r.signal) (and (listEmpty? r.ownsRejected)
    (and (none? r.planSummary) (and (listEmpty? r.openPossible)
    (and (none? r.parseDefectTurn) (none? r.gatePreflight))))))))))))))))))))))))))))))

fn wrote turn: Int64 status: String gates: (List g/GateResult) lastGates: (Map String j/Json) phases: (List String) written: (List String) commitRequested: Bool -> Final
  (Final :turn turn :status status :escalate none :gates gates :lastGates lastGates :deliver none :error none
    :retries (j/jobj (list)) :phases phases
    :batching (j/jobj (list (pair "ops" (j/jint 1)) (pair "single" (j/jint 1)) (pair "turns" (j/jint 1))))
    :written written :findings (list) :unbacked (list) :writesPersisted (not (listEmpty? written)) :commitRequested commitRequested
    :hasTiming false :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none)

fn runWith run: rl/LoopRun state: s/LoopState written: jr/Written procs: ro/Procs message: (Option String) defects: (List (Pair Int64 Bool)) -> rl/LoopRun
  (fold (fn [acc d] (rl/noteParseTurn acc (pairFirst d) (pairSecond d)))
    (rl/LoopRun :state state :procs procs :written written :session run.session :commitMessage message
      :parseDefects run.parseDefects :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn)
    defects)

fn ! writeRun! run: rl/LoopRun rel: String text: String -> jr/Written
  (mt (jr/snapshotBeforeWrite run.written rel)
    ((err _) run.written)
    ((ok w) (do (fileWrite (str w.root "/" rel) text) w)))

fn ! writeBody text: String f: Final message: (Option String) defects: (List (Pair Int64 Bool)) -> (fn [s/LoopEnv rl/LoopRun] -> (Pair rl/LoopRun s/Step))
  (fn [env run]
    (pair (runWith run (finalState run.state f) (writeRun! run "subject.txt" text) run.procs message defects) (stop)))

fn ! gitOut! root: String args: (List String) -> String
  (mt (cp/exec! (cp/withCwd (cp/cmd "git" args) root)) ((ok o) (stringTrim o.stdout)) ((err _) "ERR_GIT"))

fn finishRow row: String -> Bool
  (listAny? (fn [prefix] (stringStartsWith? row prefix)) (list "(:result " "(:commit " "(:commitError " "(:commitMissing " "(:killed " "(:restoreToHead "))

fn ! finishRows! journal: String -> (List String)
  (filter finishRow (stringLines (fileText journal)))

fn ! scenarioRepo! tmp: String id: String dir: String -> (Option String)
  (let [line (optionOr (listHead (filter (fn [l] (stringContains? l (str ":id \"" id "\""))) (f/scenarioLines! "asl/agentLoop/tests/loopRunFixtures.asn"))) "")
        root (str tmp "/" dir)]
    (if (and (not (stringEmpty? line)) (f/buildScenarioRepo! root line)) (some (resultOr (realPath root) root)) none))

fn ! waitFile! path: String tries: Int64 -> Bool
  (cond
    ((mt (fileReadString path) ((ok s) (stringContains? s "\n")) ((err _) false)) true)
    ((<= tries 0) false)
    (else (do (sleepMs 20) (waitFile! path (- tries 1)))))

fn ! pidAlive! pid: Int64 tries: Int64 -> Bool
  (cond
    ((<= pid 0) false)
    ((err? (procKill pid "SIGCONT")) false)
    ((<= tries 0) true)
    (else (do (sleepMs 20) (pidAlive! pid (- tries 1)))))

fn ! spawnBody env: s/LoopEnv run: rl/LoopRun -> (Pair rl/LoopRun s/Step)
  (let [root run.written.root
        ctx (ro/makeRunCtx root (list "**") run.session 10 (list) root)
        out (ro/execManageOp! (c/parseKv "(:step :op \"manage\" :action \"spawn\" :id \"sleeper\" :cmd \"echo $$ > kill.pid; exec sleep 30\")") ctx run.procs "r1" (fn [rel pre mode] true))]
    (do
      (waitFile! (str root "/kill.pid") 250)
      (pair (runWith run (finalState run.state (wrote 1 "ok" (list) (mapEmpty) (list "scout") (list) false)) run.written out.procs none (list)) (stop))))

fn ! fixtureSha rows: (List String) -> String
  (optionOr (listHead (map (fn [r] (optionOr (stringSlice r 10 50) "")) (filter (fn [r] (stringStartsWith? r "(:commit \"")) rows))) "")

fn ! finishPathTests tmp: String -> Bool
  (let [subject "grep -q green subject.txt"
        greenRoot (optionOr (scenarioRepo! tmp "writeGreenGate" "writeGreenGate") "")
        greenJournal (str greenRoot "/loop.asn")
        greenResult (rl/runLoopWith! (makeEnv "loopRun06" "deterministic scripted task writeGreenGate" greenRoot greenJournal 2 none (list subject) none)
          (writeBody "green\n" (wrote 1 "ok" (list (g/makeGateResult subject 0 "" "" false 0)) (gateMap subject (j/jint 0) 1) (list "implement" "grade") (list "subject.txt") false) none (list)))
        redRoot (optionOr (scenarioRepo! tmp "redGateRetryExhausted" "redGateRetryExhausted") "")
        redJournal (str redRoot "/loop.asn")
        redGate (g/makeGateResult "false" 1 "" "" false 0)
        redResult (rl/runLoopWith! (makeEnv "loopRun07" "deterministic scripted task redGateRetryExhausted" redRoot redJournal 2 none (list "false") none)
          (fn [env run]
            (if (= run.state.turn 1)
              (pair (runWith run (finalState run.state (wrote 1 "ok" (list redGate) (gateMap "false" (j/jint 1) 1) (list "implement" "grade") (list "subject.txt") false))
                (writeRun! run "subject.txt" "red\n") run.procs none (list)) (nextTurn))
              (pair (runWith run (finalState run.state (wrote run.state.turn "ok" (list redGate redGate) (gateMap "false" (j/jint 1) 2) (list "implement" "grade") (list "subject.txt") false))
                run.written run.procs none (list)) (nextTurn)))))
        commitRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitMessage") "")
        commitJournal (str commitRoot "/loop.asn")
        commitText "(:c :a tests :do fixture :g test)"
        commitResult (rl/runLoopWith! (makeEnv "loopRun17" "Please commit the fixture change" commitRoot commitJournal 2 none (list) none)
          (writeBody "commit\n" (wrote 2 "ok" (list) (mapEmpty) (list "implement") (list "subject.txt") true) (some commitText) (list)))
        commitSha (gitOut! commitRoot (list "rev-parse" "HEAD"))
        invalidRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitInvalid") "")
        invalidBase (gitOut! invalidRoot (list "rev-parse" "HEAD"))
        invalidJournal (str invalidRoot "/loop.asn")
        invalidResult (rl/runLoopWith! (makeEnv "loopRunE1" "invalid commit message" invalidRoot invalidJournal 2 none (list) none)
          (writeBody "commit\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "subject.txt") true) (some "fix things") (list)))
        headRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitHead") "")
        headBase (gitOut! headRoot (list "rev-parse" "HEAD"))
        headJournal (str headRoot "/loop.asn")
        headResult (rl/runLoopWith! (makeEnv "loopRunE2" "commit names HEAD" headRoot headJournal 2 none (list) none)
          (writeBody "commit\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "subject.txt") true) (some (optionOr (stringSlice headBase 0 10) "")) (list)))
        emptyRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitEmpty") "")
        emptyJournal (str emptyRoot "/loop.asn")
        emptyResult (rl/runLoopWith! (makeEnv "loopRunE3" "nothing to commit" emptyRoot emptyJournal 2 none (list) none)
          (onState (fn [env state] (pair (finalState state (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list) true)) (stop)))))
        emptyCommit (rl/runLoopWith! (makeEnv "loopRunE4" "nothing to commit" emptyRoot (str emptyRoot "/empty.asn") 2 none (list) none)
          (fn [env run] (pair (runWith run (finalState run.state (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list) true)) run.written run.procs (some commitText) (list)) (stop))))
        redCommitRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitRed") "")
        redCommitBase (gitOut! redCommitRoot (list "rev-parse" "HEAD"))
        redCommitResult (rl/runLoopWith! (makeEnv "loopRunE5" "red gate blocks commit" redCommitRoot (str redCommitRoot "/loop.asn") 2 none (list "false") none)
          (writeBody "commit\n" (wrote 1 "ok" (list redGate) (gateMap "false" (j/jint 1) 1) (list "implement") (list "subject.txt") true) (some commitText) (list)))
        missingRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitMissing") "")
        missingJournal (str missingRoot "/loop.asn")
        missingResult (rl/runLoopWith! (makeEnv "loopRunE6" "commit asked without a message" missingRoot missingJournal 2 none (list) none)
          (writeBody "commit\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "subject.txt") true) none (list)))
        defectRoot (optionOr (scenarioRepo! tmp "commitMessage" "parseDefect") "")
        defectResult (rl/runLoopWith! (makeEnv "loopRunE7" "parse defect spent" defectRoot (str defectRoot "/loop.asn") 5 none (list "false") none)
          (writeBody "kept\n" (Final :turn 2 :status "escalated" :escalate (some "(:escalate :reason \"exhausted 0 claims retries\")")
            :gates (list (g/makeGateResult "false" 0 "" "" false 0)) :lastGates (gateMap "false" (j/jint 0) 1) :deliver none :error none
            :retries (j/jobj (list)) :phases (list) :batching (j/jobj (list)) :written (list "subject.txt") :findings (list) :unbacked (list)
            :writesPersisted true :commitRequested false :hasTiming false :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none) none (list (pair 1 true) (pair 2 true))))
        recoveredRoot (optionOr (scenarioRepo! tmp "commitMessage" "parseRecovered") "")
        recoveredResult (rl/runLoopWith! (makeEnv "loopRunE12" "parse defect then a clean turn" recoveredRoot (str recoveredRoot "/loop.asn") 5 none (list) none)
          (writeBody "recovered\n" (wrote 3 "ok" (list) (mapEmpty) (list "implement") (list "subject.txt") false) none
            (list (pair 1 false) (pair 2 true) (pair 3 false))))
        keptRoot (optionOr (scenarioRepo! tmp "commitMessage" "preserved") "")
        keptResult (rl/runLoopWith! (makeEnv "loopRunE8" "preserved claims escalation" keptRoot (str keptRoot "/loop.asn") 5 none (list "false") none)
          (writeBody "kept\n" (Final :turn 1 :status "escalated" :escalate (some "(:escalate :reason \"exhausted 0 claims retries\")")
            :gates (list redGate (g/makeGateResult "false" 0 "" "" false 0)) :lastGates (gateMap "false" (j/jint 0) 1) :deliver none :error none
            :retries (j/jobj (list)) :phases (list) :batching (j/jobj (list)) :written (list "subject.txt") :findings (list) :unbacked (list)
            :writesPersisted true :commitRequested false :hasTiming false :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none) none (list)))
        noGateRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitNoGate") "")
        noGateBase (gitOut! noGateRoot (list "rev-parse" "HEAD"))
        noGateResult (rl/runLoopWith! (makeEnv "loopRunE9" "declared gate with no lastGates entry blocks commit" noGateRoot (str noGateRoot "/loop.asn") 2 none (list "false") none)
          (writeBody "commit\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "subject.txt") true) (some commitText) (list)))
        noWriteCommitRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitNoWrite") "")
        noWriteCommitResult (rl/runLoopWith! (makeEnv "loopRunE10" "commit requested without any write" noWriteCommitRoot (str noWriteCommitRoot "/loop.asn") 2 none (list) none)
          (fn [env run] (pair (runWith run (finalState run.state (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list) true)) run.written run.procs none (list)) (stop))))
        newFileRoot (optionOr (scenarioRepo! tmp "commitMessage" "commitNewFile") "")
        newFileJournal (str newFileRoot "/loop.asn")
        newFileResult (rl/runLoopWith! (makeEnv "loopRunE11" "commit a newly created untracked file" newFileRoot newFileJournal 2 none (list) none)
          (fn [env run] (pair (runWith run (finalState run.state (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "newFile.txt") true))
            (writeRun! run "newFile.txt" "brand new\n") run.procs (some commitText) (list)) (stop))))
        killRoot (optionOr (scenarioRepo! tmp "commitMessage" "kill") "")
        killJournal (str killRoot "/loop.asn")
        killResult (rl/runLoopWith! (makeEnv "loopRunK" "spawned process outlives the body" killRoot killJournal 2 none (list) none) spawnBody)
        killPid (optionOr (stringToInt64 (stringTrim (fileText (str killRoot "/kill.pid")))) 0)
        greenFixture (fixtureJournal "writeGreenGate")
        redFixture (fixtureJournal "redGateRetryExhausted")
        commitFixture (filter finishRow (fixtureJournal "commitMessage"))]
    (do
      (assert (not (stringEmpty? greenRoot)) "writeGreenGate builds its recorded repo")
      (assert (= (finishRows! greenJournal) (filter finishRow greenFixture)) "writeGreenGate finish rows match the recorded fixture")
      (assert (= greenResult.patch (some "loop.patch")) "an ok run hands back the patch of its threaded writes")
      (assert (= (fileText (str greenRoot "/subject.txt")) "green\n") "an ok run keeps its writes")
      (assert (= (finishRows! redJournal) (filter finishRow redFixture)) "redGateRetryExhausted finish rows match the recorded fixture")
      (assert (= redResult.restored (list "subject.txt")) "a budget escalation restores the written file")
      (assert (= (fileText (str redRoot "/subject.txt")) "fixed scripted subject\n") "a budget escalation puts the original bytes back")
      (assert (= redResult.turns 3) "redGateRetryExhausted reports its terminal turn")
      (assert (= (map (fn [r] (stringReplace r commitSha "<sha>")) (finishRows! commitJournal)) (map (fn [r] (stringReplace r (fixtureSha commitFixture) "<sha>")) commitFixture)) "commitMessage finish rows match the recorded fixture up to the sha")
      (assert (= commitResult.commit (some commitSha)) "an ok run commits with its message and reports the sha")
      (assert (= (gitOut! commitRoot (list "log" "-1" "--format=%s")) commitText) "the commit carries the run's message")
      (assert (= (gitOut! commitRoot (list "show" "HEAD:subject.txt")) "commit") "the commit holds the written file")
      (assert (= (finishRows! invalidJournal) (list "(:commitError \"the commit message is not a valid (:c ...) ASN line: the message must be one (:c ...) form\")"
        "(:result :status :ok :session \"loopRunE1\" :unbacked 0 :contextTokens 24000 :commitError \"the commit message is not a valid (:c ...) ASN line: the message must be one (:c ...) form\" :phases (implement) :batching (:turns 1 :ops 1 :singleOp 1) :patch \"loop.patch\" :written (\"subject.txt\"))")) "an invalid commit message journals :commitError and never reaches git")
      (assert (= invalidResult.commitError (some "the commit message is not a valid (:c ...) ASN line: the message must be one (:c ...) form")) "an invalid commit message is the result's commitError")
      (assert (= (gitOut! invalidRoot (list "rev-parse" "HEAD")) invalidBase) "an invalid commit message leaves HEAD alone")
      (assert (= headResult.commit (some headBase)) "a message naming HEAD records HEAD as the commit")
      (assert (= (gitOut! headRoot (list "rev-parse" "HEAD")) headBase) "a message naming HEAD makes no new commit")
      (assert (stringContains? (fileText headJournal) (str "(:commit \"" headBase "\")")) "a message naming HEAD journals the commit")
      (assert (none? emptyResult.commitError) "a run without a commit message records no commit error")
      (assert (= emptyCommit.commitError (some "the run wrote no path to commit")) "a commit message with no written path is a commit error")
      (assert (none? redCommitResult.commit) "a red declared gate blocks the commit")
      (assert (= (gitOut! redCommitRoot (list "rev-parse" "HEAD")) redCommitBase) "a red declared gate leaves HEAD alone")
      (assert (= (finishRows! missingJournal) (list "(:commitMissing true)"
        "(:result :status :ok :session \"loopRunE6\" :unbacked 0 :contextTokens 24000 :commitMissing true :phases (implement) :batching (:turns 1 :ops 1 :singleOp 1) :patch \"loop.patch\" :written (\"subject.txt\"))")) "a commit asked without a message journals commitMissing before the result")
      (assert (= missingResult.commitMissing (some true)) "a commit asked without a message reports commitMissing")
      (assert (none? defectResult.gatesGreen) "a parse defect does not preserve files")
      (assert (= defectResult.restored (list "subject.txt")) "a parse defect escalation restores the written file")
      (assert defectResult.parseDefect "a run that spent a parse defect reports parseDefect true")
      (assert (= defectResult.parseDefectTurn (some 2)) "a run whose final turn is a parse defect reports that turn")
      (assert (not recoveredResult.parseDefect) "a run that recovered from a parse defect reports parseDefect false")
      (assert (= recoveredResult.parseDefectTurn (some 2)) "a run that recovered from a parse defect reports the turn of its last defect, not its final turn")
      (assert (not keptResult.parseDefect) "a run that never spent a parse defect reports parseDefect false")
      (assert (none? keptResult.parseDefectTurn) "a run that never spent a parse defect reports no parseDefectTurn")
      (assert (= (filter (fn [row] (listAny? (fn [prefix] (stringStartsWith? row prefix)) (list "(:commitMissing " "(:coreHost " "(:result "))) (stringLines (fileText missingJournal)))
        (list "(:commitMissing true)" "(:coreHost :calls 0 :cases 0 :sec 0.0 :built 0)"
          "(:result :status :ok :session \"loopRunE6\" :unbacked 0 :contextTokens 24000 :commitMissing true :phases (implement) :batching (:turns 1 :ops 1 :singleOp 1) :patch \"loop.patch\" :written (\"subject.txt\"))"))
        "finish! journals the zero coreHost row after commitMissing and before the result")
      (assert (= keptResult.gatesGreen (some true)) "a preserved claims escalation reports gatesGreen")
      (assert (listEmpty? keptResult.restored) "a preserved claims escalation restores nothing")
      (assert (= (fileText (str keptRoot "/subject.txt")) "kept\n") "a preserved claims escalation keeps the written file")
      (assert (none? noGateResult.commit) "a declared gate with no lastGates entry blocks the commit")
      (assert (= (gitOut! noGateRoot (list "rev-parse" "HEAD")) noGateBase) "a declared gate with no lastGates entry leaves HEAD alone")
      (assert (none? noWriteCommitResult.commitMissing) "commitRequested without any write is not commitMissing")
      (assert (= newFileResult.commit (some (gitOut! newFileRoot (list "rev-parse" "HEAD")))) "a commit of a newly created file succeeds")
      (assert (= (gitOut! newFileRoot (list "show" "HEAD:newFile.txt")) "brand new") "the commit includes the newly created untracked file")
      (assert (> killPid 0) "the spawned process recorded its pid")
      (assert (stringContains? (fileText killJournal) "(:killed (\"loopRunK-sleeper\"))") "finish! journals the processes it killed")
      (assert (not (pidAlive! killPid 50)) "finish! kills a process the body left running")
      (assert (= killResult.status "ok") "killing a leftover process keeps the run ok")
      true))

fn ! runTests -> Bool
  (do
    (let [tmp (tempRoot)
        budgetJournal (str tmp "/loopRunTest-budget0.asn")
        preflightJournal (str tmp "/loopRunTest-preflight.asn")
        resumeJournal (str tmp "/loopRunTest-resume.asn")
        patch (str tmp "/loopRunTest-resume.patch")
        budgetEnv (makeEnv "loopRun01" "deterministic scripted task budget0" tmp budgetJournal 0 none (list) none)
        rejectEnv (makeEnv "loopRun02" "deterministic scripted task preflightReject" tmp preflightJournal 2 none (list "(") none)
        noWriteEnv (makeEnv "loopRun04" "head no write test" tmp (str tmp "/loopRunTest-head.asn") 4 none (list) none)
        redEnv (makeEnv "loopRun06" "red gate streak integration" tmp (str tmp "/loopRunTest-red.asn") 30 none (list "false") none)
        bodyEnv (makeEnv "loopRun05" "body stepping test" tmp (str tmp "/loopRunTest-body.asn") 4 none (list) none)
        bodyResult (rl/runLoopWith! bodyEnv (onState countBody))
        redResult (rl/runLoopWith! redEnv (onState redGateBody))
        escalatedEnv (makeEnv "loopRun07" "escalated without receipt" tmp (str tmp "/loopRunTest-escalated.asn") 9 none (list) none)
        escalatedResult (rl/runLoopWith! escalatedEnv (onState escalatedBody))
        baseState (rl/stateFor noWriteEnv)
        gateEnv (makeEnv "loopRun11" "declared gate head" tmp (str tmp "/loopRunTest-gate.asn") 40 none (list "false") none)
        redGate (g/makeGateResult "false" 1 "" "" false 0)
        greenGate (g/makeGateResult "false" 0 "" "" false 0)
        streakState (fn [streak] (rl/withHeadState baseState 1 streak false none (list redGate) (gateMap "false" (j/jint 1) 1) "ok" none none baseState.runStarted))
        healedState (rl/withHeadState baseState 2 12 false none (list redGate greenGate) (gateMap "false" (j/jint 0) 2) "ok" none none baseState.runStarted)
        undeclaredState (rl/withHeadState baseState 1 12 false none (list redGate) (gateMap "other" (j/jint 1) 1) "ok" none none baseState.runStarted)
        timeoutState (rl/withHeadState baseState 1 12 false none (list) (gateMap "false" (j/jnull) 1) "ok" none none baseState.runStarted)
        noWriteState (rl/withHeadState baseState 2 0 false (some "patch") (list) (mapEmpty) "ok" none none baseState.runStarted)
        patchState (fn [turn] (rl/withHeadState baseState turn 0 false (some "patch") (list) (mapEmpty) "ok" none none baseState.runStarted))
        budget10Env (makeEnv "loopRun12" "no write share" tmp (str tmp "/loopRunTest-share.asn") 10 none (list) none)
        budget60Env (makeEnv "loopRun13" "no write cap" tmp (str tmp "/loopRunTest-cap.asn") 60 none (list) none)
        retainRoot (str tmp "/retain")
        retainMain (str retainRoot "/main")
        retainTree (str retainRoot "/tree")
        retainJournalPath (str retainTree "/loopRunTest-retain.asn")
        retainReady (and (gitOk! (list "init" "-q" retainMain))
          (and (gitOk! (list "-C" retainMain "-c" "user.name=loopRunTest" "-c" "user.email=loopRunTest@localhost" "commit" "-q" "--allow-empty" "-m" "base"))
          (and (gitOk! (list "-C" retainMain "worktree" "add" "-q" "--detach" retainTree))
          (and (ok? (fileWrite (str retainMain "/.asl") "a file where the retained journal directory belongs\n"))
          (and (ok? (fileWrite retainJournalPath ""))
            (mt (cp/exec! (cp/cmd "chmod" (list "444" retainJournalPath))) ((ok o) (= o.exitCode 0)) ((err _) false)))))))
        retainEnv (makeEnv "loopRun10" "retain failure" retainTree retainJournalPath 2 none (list "(") none)
        retainResult (rl/runLoopWith! retainEnv neverBody)
        wallEnv (makeEnv "loopRun09" "no write wall" tmp (str tmp "/loopRunTest-wall.asn") 10 (some 2) (list) none)
        wallResult (rl/runLoopWith! wallEnv (onState wallBody))
        resumeEnv (makeEnv "loopRun03" "deterministic scripted task resumePatchReject" tmp resumeJournal 2 none (list)
          (some (j/jobj (list (pair "answer" (j/jstr "")) (pair "history" (j/jarr (list)))
            (pair "note" (j/jstr "")) (pair "reply" (j/jstr "")) (pair "turn" (j/jint 0))))))
        resumeGoodJournal (str tmp "/loopRunTest-resumeGood.asn")
        resumeGoodPatch (str tmp "/loopRunTest-resumeGood.patch")
        resumeGoodEnv (makeEnv "loopRun08" "successful resume" tmp resumeGoodJournal 9 none (list)
          (some (j/jobj (list (pair "answer" (j/jstr "continue")) (pair "history" (j/jarr (list)))
            (pair "note" (j/jstr "")) (pair "reply" (j/jstr "continue")) (pair "turn" (j/jint 7))))))
        budgetResult (rl/runLoopWith! budgetEnv neverBody)
        budgetJournalText (stringReplace (fileText budgetJournal) tmp "<root>")
        rejectResult (rl/runLoopWith! rejectEnv neverBody)
        rejectJournalText (stringReplace (fileText preflightJournal) tmp "<root>")
        claimsReceipt "(:escalate :reason \"exhausted 0 claims retries\")"
        healedJournal (str tmp "/loopRunTest-healed.asn")
        healedResult (rl/runLoopWith! (makeEnv "loopRunA" "healed gate preserves" tmp healedJournal 5 none (list "false") none)
          (onState (fn [env state] (pair (finalState state (final 1 "escalated" (some claimsReceipt) (list redGate greenGate) (gateMap "false" (j/jint 0) 1) (j/jobj (list)))) (stop)))))
        gateRetryJournal (str tmp "/loopRunTest-gateRetry.asn")
        gateRetryResult (rl/runLoopWith! (makeEnv "loopRunB" "gate retry spent" tmp gateRetryJournal 5 none (list "false") none)
          (onState (fn [env state] (pair (finalState state (final 1 "escalated" (some claimsReceipt) (list greenGate) (gateMap "false" (j/jint 0) 1) (j/jobj (list (pair "gates" (j/jint 1)))))) (stop)))))
        stepRetryJournal (str tmp "/loopRunTest-stepRetry.asn")
        stepRetryResult (rl/runLoopWith! (makeEnv "loopRunB2" "step retry spent" tmp stepRetryJournal 5 none (list "false") none)
          (onState (fn [env state] (pair (finalState state (final 1 "escalated" (some claimsReceipt) (list greenGate) (gateMap "false" (j/jint 0) 1) (j/jobj (list (pair "steps" (j/jint 1)))))) (stop)))))
        lineJournal (str tmp "/loopRunTest-line.asn")
        lineResult (rl/runLoopWith! (makeEnv "loopRunC" "result line fields" tmp lineJournal 5 none (list) none)
          (onState (fn [env state] (pair (finalState state (Final :turn 1 :status "failed" :escalate none :gates (list) :lastGates (mapEmpty)
            :deliver (some "patch") :error (some "ERR_PROVIDER") :retries (j/jobj (list)) :phases (list "implement")
            :batching (j/jobj (list (pair "ops" (j/jint 2)) (pair "single" (j/jint 0)) (pair "turns" (j/jint 1))))
            :written (list) :findings (list) :unbacked (list) :writesPersisted false :commitRequested false
            :hasTiming true :queueWaitSec 1.5 :execSec 2.25
            :usage (j/jobj (list (pair "inputTokens" (j/jint 10)) (pair "cachedTokens" (j/jint 0)) (pair "outputTokens" (j/jint 3)))) :signal none)) (stop)))))
        colonJournal (str tmp "/loopRunTest-colon.asn")
        colonResult (rl/runLoopWith! (makeEnv "loopRunD" "leading colons stripped from error" tmp colonJournal 5 none (list) none)
          (onState (fn [env state] (pair (finalState state (Final :turn 1 :status "failed" :escalate none :gates (list) :lastGates (mapEmpty)
            :deliver none :error (some "::oddError") :retries (j/jobj (list)) :phases (list)
            :batching (j/jobj (list (pair "ops" (j/jint 0)) (pair "single" (j/jint 0)) (pair "turns" (j/jint 0))))
            :written (list) :findings (list) :unbacked (list) :writesPersisted false :commitRequested false
            :hasTiming false :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none)) (stop)))))
        anonJournal (str tmp "/loopRunTest-anon.asn")
        anonResult (rl/runLoopWith! (makeEnvWith none "generated session and findings" tmp anonJournal 5 none (list) none)
          (onState (fn [env state] (pair (finalState state (Final :turn 1 :status "ok" :escalate none :gates (list) :lastGates (mapEmpty)
            :deliver none :error none :retries (j/jobj (list)) :phases (list "scout")
            :batching (j/jobj (list (pair "ops" (j/jint 0)) (pair "single" (j/jint 0)) (pair "turns" (j/jint 0))))
            :written (list) :findings (list (j/jstr "(:findings (\"possible\"))")) :unbacked (list (j/jstr "claim a"))
            :writesPersisted false :commitRequested false :hasTiming false :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none)) (stop)))))]

    (mt (fileStat patch)
      ((ok _) false)
      ((err _)
        (mt (fileWrite patch (stringToBytes "not a git patch\n"))
          ((err _) false)
          ((ok _)
            (let [resumeResult (rl/runLoopWith! resumeEnv neverBody)
                  resumeRows (f/maskJournal tmp (map (fn [row] (stringReplace row "loopRunTest-resume.patch" "loop.patch"))
                    (filter (fn [row] (not (stringEmpty? row))) (stringLines (fileText resumeJournal)))))
                  resumeExpected (f/maskJournal "<root>" (fixtureJournal "resumePatchReject"))]
              (mt (pathRemove patch)
                ((err _) false)
                ((ok _)
                  (do
                    (assert (= (f/maskJournal tmp (filter (fn [row] (not (stringEmpty? row))) (stringLines budgetJournalText))) (f/maskJournal "<root>" (fixtureJournal "budget0"))) "budget0 journal bytes match recorded fixture")
                    (assert (budgetFieldsMatch budgetResult) "budget0 RunResult matches every typed fixture field")
                    (assert (= budgetResult.status "escalated") "budget0 fixture exits before body")
                    (assert (= budgetResult.turns 1) "budget0 fixture reports the synthetic boundary turn")
                    (assert (= (f/maskJournal tmp (filter (fn [row] (not (stringEmpty? row))) (stringLines rejectJournalText))) (f/maskJournal "<root>" (fixtureJournal "preflightReject"))) "preflightReject journal bytes match recorded fixture")
                    (assert (rejectFieldsMatch rejectResult) "preflightReject RunResult matches every typed fixture field")
                    (assert (= rejectResult.status "rejected") "preflightReject fixture exits before body")
                    (assert (= rejectResult.error (some "ERR_GATE_UNPARSABLE")) "preflightReject fixture returns its error")
                    (assert (= resumeRows resumeExpected) "resumePatchReject journal bytes match the recorded fixture")
                    (assert (resumeFieldsMatch resumeResult) "resumePatchReject RunResult matches every typed fixture field")
                    (assert (= resumeResult.status "rejected") "resumePatchReject fixture exits before body")
                    (assert (= resumeResult.error (some "ERR_RESUME_PATCH")) "resumePatchReject fixture returns its error")
                    (fileWrite (str tmp "/resume-good.txt") "before\n")
                    (fileWrite resumeGoodPatch "diff --git a/resume-good.txt b/resume-good.txt\n--- a/resume-good.txt\n+++ b/resume-good.txt\n@@ -1 +1 @@\n-before\n+after\n")
                    (let [resumeSetup (rl/setup! resumeGoodEnv)
                          resumeState (mt resumeSetup ((rl/ready resumed) resumed.state) ((rl/early _) (rl/stateFor resumeGoodEnv)))]
                      (do
                        (assert (mt resumeSetup ((rl/ready _) true) ((rl/early _) false)) "valid resume patch passes setup")
                        (assert (= resumeState.turn 7) "resume state starts at its recorded turn")
                        (assert resumeState.writesPersisted "resume state marks resumed writes persisted")
                        (assert (stringContains? (fileText resumeGoodJournal) "(:resumeApplied \"loopRunTest-resumeGood.patch\")") "successful resume journals the applied patch")
                        (assert (= (fileText (str tmp "/resume-good.txt")) "after\n") "successful resume applies patch inside its temporary root")))
                    (assert (= bodyResult.turns 2) "runLoopWith invokes the body then finalizes its updated state")
                    (assert (= (rl/headDecision gateEnv (streakState 11)) "continue") "a red declared gate below the readStreak limit continues")
                    (assert (= (rl/headDecision gateEnv (streakState 12)) "readStreak") "a red declared gate at readStreakEscalate escalates")
                    (assert (= (rl/headDecision gateEnv healedState) "continue") "a gate whose latest result is green is not red even after an earlier red result")
                    (assert (= (rl/headDecision gateEnv undeclaredState) "continue") "a red result for an undeclared gate does not count")
                    (assert (= (rl/headDecision gateEnv timeoutState) "readStreak") "a declared gate whose latest result has no exit code counts as red")
                    (assert (= (rl/headDecision budget10Env (patchState 4)) "continue") "no write before half the turn budget continues")
                    (assert (= (rl/headDecision budget10Env (patchState 5)) "noWriteTurns") "no write at half the turn budget escalates")
                    (assert (= (rl/headDecision budget60Env (patchState 19)) "continue") "no write below the noWriteTurns cap continues")
                    (assert (= (rl/headDecision budget60Env (patchState 20)) "noWriteTurns") "no write at the noWriteTurns cap escalates")
                    (assert (= (map rl/wallSeconds (list 0.5 1.5 2.5 3.49 3.5)) (list "0" "2" "2" "3" "4")) "wallSeconds rounds half to even like Python format .0f")
                    (assert (= escalatedResult.status "escalated") "a body may end the run escalated")
                    (assert (none? escalatedResult.escalate) "an escalated run without an escalate receipt reports none")
                    (assert retainReady "retain failure fixture builds a linked worktree")
                    (assert (= retainResult.status "failed") "a journal retention error fails the run")
                    (assert (= retainResult.error (some (str "OSError: permissionDenied: '" retainJournalPath "'"))) "a journal retention error is returned whole")
                    (assert (= (rl/headDecision noWriteEnv noWriteState) "noWriteTurns") "head! reads constructed persisted patch turns")
                    (assert (= redResult.status "escalated") "red gate read streak escalates through the loop")
                    (assert (= redResult.signal (some "readStreak")) "red gate final result retains the readStreak signal")
                    (assert (= redResult.escalate (some (j/jstr "(:escalate :reason \"12 turns without a write while a gate is red\")"))) "red gate final result retains the escalation reason")
                    (assert (= (listLength redResult.gates) 1) "red gate final result retains actual gate results")
                    (assert (stringContains? (fileText (str tmp "/loopRunTest-red.asn")) "(:turn 12 :signal :readStreak :reason \"12 turns without a write while a gate is red\")") "read streak journal records turn signal and reason")
                    (assert (= redResult.turns 12) "readStreak body call is recorded in the terminal turn")
                    (assert (= wallResult.status "escalated") "noWriteWall escalates through runLoopWith")
                    (assert (= wallResult.signal (some "noWrite")) "noWriteWall result retains its signal")
                    (assert (= wallResult.escalate (some (j/jstr "(:escalate :reason \"nothing written by 1 s of the 2 s wall budget\")"))) "noWriteWall result retains its Python-formatted reason")
                    (assert (= wallResult.turns 1) "noWriteWall body call is recorded in the terminal turn")
                    (assert (stringContains? (fileText (str tmp "/loopRunTest-wall.asn")) "(:turn 1 :signal :noWrite :reason \"nothing written by 1 s of the 2 s wall budget\")") "noWriteWall journal records its Python-formatted signal and reason")
                    (assert (= healedResult.gatesGreen (some true)) "a declared gate whose latest result is green counts green after an earlier red result")
                    (assert (stringContains? (resultLine healedJournal) " :gatesGreen true") "a preserved claims escalation journals :gatesGreen true")
                    (assert (none? gateRetryResult.gatesGreen) "a spent gate retry does not preserve files")
                    (assert (none? stepRetryResult.gatesGreen) "a spent step retry does not preserve files")
                    (assert (= (resultLine lineJournal) "(:result :status :failed :session \"loopRunC\" :unbacked 0 :contextTokens 24000 :error :ERR_PROVIDER :deliver :patch :phases (implement) :queueWaitSec 1.5 :execSec 2.25 :usage (:input 10 :cached 0 :output 3) :batching (:turns 1 :ops 2 :singleOp 0))") "the result line carries error, deliver, timing and usage in Python order")
                    (assert (= lineResult.queueWaitSec (some 1.5)) "timing reaches the result")
                    (assert (= (resultLine colonJournal) "(:result :status :failed :session \"loopRunD\" :unbacked 0 :contextTokens 24000 :error :oddError :phases () :batching (:turns 0 :ops 0 :singleOp 0))") "leading colons are stripped from the error before it is written as a keyword")
                    (assert (= (resultLine anonJournal) "(:result :status :failed :session \"loopRunTest\" :unbacked 1 :unbackedClaims (\"claim a\") :contextTokens 24000 :phases (scout) :findings ((:findings (\"possible\"))) :batching (:turns 0 :ops 0 :singleOp 0))") "the result line carries the generated session, unbacked claims and findings")
                    (assert (= anonResult.status "failed") "findings without a claim fail an ok run")
                    (assert (= anonResult.session "loopRunTest") "a generated session id reaches the result")
                    (finishPathTests tmp)
                    (assert (ok? (removeIfExists! tmp)) "the temporary test root is removed")
                    (assert (mt (fileStat tmp) ((ok _) false) ((err _) true)) "no temporary test root is left behind")
                    true))))))))))
