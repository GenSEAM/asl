(module aslAgent/tests/commitGuardWireTest
  :x [runTests]
  :i [(aslAgent/runLoop :a rl) (aslAgent/loopState :a s)
      (aslAgent/providers :a pv) (aslAgent/gates :a g) (asl-json/json :a j)
      (aslAgent/tests/loopRunFixture :a f) (aslAgent/plan :a p) (aslAgent/core :a c)
      (aslAgent/journal :a jr) (aslAgent/runOps :a ro) (asl-tools/fleet/run :a fr) (asl-tools/vcs/vcs :a vcs)])

fn fakeTurn prompt: String system: String -> pv/Turn
  (pv/Turn :provider (pv/scriptProvider "loopRunTest" (list) 0)
    :reply (ok none) :meta (pv/TurnMeta :timing none :usage none :served none :finish none :truncated false))

fn fakeAdvice prompt: String system: String -> (Result (Option String) String)
  (ok none)

fn fakeGrade role: String system: String text: String -> (Result (Option String) String)
  (ok none)

fn fakeId -> String
  "loopRunTest"

fn fakeNow -> Float64
  1.0

fn fakeSleep ms: Int64 -> Bool
  true

fn makeEnv id: String task: String root: String journal: String budget: Int64 wall: (Option Int64) gates: (List String) resume: (Option j/Json) -> s/LoopEnv
  (makeEnvWith (some id) task root journal budget wall gates resume)

fn makeEnvWith sid: (Option String) task: String root: String journal: String budget: Int64 wall: (Option Int64) gates: (List String) resume: (Option j/Json) -> s/LoopEnv
  (s/LoopEnv :provider fakeTurn :task task :modeHint (some "implement") :owns (list) :gates gates
    :rootDir root :budget budget :inputTokenBudget 0 :journalPath journal :maxRetries 0 :sessionId sid
    :base (some "") :contextTokens (some 24000) :model (some "loop-run-fixture")
    :gateTimeout (some 10) :wallBudget wall :resume resume :intent (some "patch") :plan false :specCheck false :commit false
    :next fakeTurn :advise fakeAdvice :review fakeAdvice :grade fakeGrade :newId fakeId :now fakeNow :sleep fakeSleep)

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
    :placeholderBriefs base.placeholderBriefs :doneNoWriteStreak base.doneNoWriteStreak :malformedStreak base.malformedStreak :notFoundStreak base.notFoundStreak
    :prefetch base.prefetch
    :baselineGreen base.baselineGreen
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

fn wrote turn: Int64 status: String gates: (List g/GateResult) lastGates: (Map String j/Json) phases: (List String) written: (List String) commitRequested: Bool -> Final
  (Final :turn turn :status status :escalate none :gates gates :lastGates lastGates :deliver none :error none
    :retries (j/jobj (list)) :phases phases
    :batching (j/jobj (list (pair "ops" (j/jint 1)) (pair "single" (j/jint 1)) (pair "turns" (j/jint 1))))
    :written written :findings (list) :unbacked (list) :writesPersisted (not (listEmpty? written)) :commitRequested commitRequested
    :hasTiming false :queueWaitSec 0.0 :execSec 0.0 :usage (j/jobj (list)) :signal none)

fn runWith run: rl/LoopRun state: s/LoopState written: jr/Written procs: ro/Procs message: (Option String) defects: (List (Pair Int64 Bool)) -> rl/LoopRun
  (fold (fn [acc d] (rl/noteParseTurn acc (pairFirst d) (pairSecond d)))
    (rl/LoopRun :state state :procs procs :written written :session run.session :commitMessage message
      :parseDefects run.parseDefects :lastDefect run.lastDefect :lastDefectTurn run.lastDefectTurn
      :parseDefectStreak run.parseDefectStreak)
    defects)

fn ! writeRun! run: rl/LoopRun rel: String text: String -> jr/Written
  (match (jr/snapshotBeforeWrite run.written rel)
    ((err _) run.written)
    ((ok w) (do (fileWrite (str w.root "/" rel) text) w)))

; (:m :ref SPAWN-SAFETY :do "every child of this test starts through asl/tools/fleet/run.asl with a timeout and a descendant limit")
fn ! viaFleet! argv: (List String) cwd: String -> fr/Done
  (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits 60 16))

fn ! gitOut! root: String args: (List String) -> String
  (let [(d (viaFleet! (cons "git" args) root))]
    (if (= d.exit 0) (stringTrim d.out) "ERR_GIT"))

fn ! gitOk! args: (List String) -> Bool
  (= (viaFleet! (cons "git" args) ".").exit 0)


; (:m :ref LEON-COMMIT-VIA-VCS :do "a scripted Leon run that writes one owned path and asks for a commit: an unbalanced .asl ends commitError with the guard rows and HEAD unchanged; a good file commits exactly that path and journals the commit")
fn ! gitIn! root: String args: (List String) -> Bool
  (= (viaFleet! (cons "git" (listAppend (list "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)) root).exit 0)

fn ! repoAt! base: String name: String -> String
  (let [dir (str base "/" name)
        _ (dirCreate dir)]
    (do (assert (gitIn! dir (list "init" "-q" "-b" "main")) (str name ": init"))
        (assert (ok? (fileWrite (str dir "/base.txt") "base\n")) (str name ": base file"))
        (assert (gitIn! dir (list "add" "-A")) (str name ": add"))
        (assert (gitIn! dir (list "commit" "-q" "-m" "base")) (str name ": base commit"))
        (resultOr (realPath dir) dir)))

fn ! writeAt! rel: String text: String f: Final message: (Option String) -> (fn [s/LoopEnv rl/LoopRun] -> (Pair rl/LoopRun s/Step))
  (fn [env run]
    (pair (runWith run (finalState run.state f) (writeAtRun! run rel text) run.procs message (list)) (stop)))

fn ! writeAtRun! run: rl/LoopRun rel: String text: String -> jr/Written
  (match (jr/snapshotBeforeWrite run.written rel)
    ((err _) run.written)
    ((ok w) (do (fileWrite (str w.root "/" rel) text) w)))

; (:m :ref LEON-COMMIT-VIA-VCS :do "the run commit goes through the tool tree of the env: a stub tree whose bin/asl logs every call and answers each checked file ok is the only checker that can pass, so the commit lands only when env.toolRoot reaches the guard, and the log shows the check ran with the commit root as cwd")
fn ! toolTree! base: String -> String
  (let [dir (str base "/toolTree")
        _a (dirCreate dir)
        _b (dirCreate (str dir "/bin"))
        _c (fileWrite (str dir "/bin/asl") "#!/bin/sh\nD=\"$(dirname \"$0\")\"\necho \"cwd=$PWD args=$*\" >> \"$D/calls.log\"\nshift\nfor a in \"$@\"; do echo \"ok $a:\"; done\n")
        _d (fileChmod (str dir "/bin/asl") 493)]
    dir)

fn ! journalText path: String -> String
  (resultOr (fileReadString path) "")

fn ! runTests -> Bool
  (let [base (str (optionOr (envGet "TMPDIR") "/tmp") "/commitGuardWireTest_" (stringFromInt64 (procSelf)))
        _ (dirCreate base)
        msg "(:c :a tests :do fixture :g test)"
        bad (repoAt! base "bad")
        hBad (gitOut! bad (list "rev-parse" "HEAD"))
        rBad (rl/runLoopWith! (makeEnv "wireBad" "commit the broken file" bad (str bad "/loop.asn") 2 none (list) none)
               (writeAt! "bad.asl" "(module fx/bad\n  :x [f]\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "bad.asl") true) (some msg)))
        good (repoAt! base "good")
        hGood (gitOut! good (list "rev-parse" "HEAD"))
        _stray (fileWrite (str good "/stray.txt") "not written by the run\n")
        rGood (rl/runLoopWith! (makeEnv "wireGood" "commit the note" good (str good "/loop.asn") 2 none (list) none)
                (writeAt! "note.txt" "a note\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "note.txt") true) (some msg)))
        tool (repoAt! base "tool")
        stubTree (toolTree! base)
        rTool (rl/runLoopWith! (with (makeEnv "wireTool" "commit through the tool tree" tool (str tool "/loop.asn") 2 none (list) none) :toolRoot stubTree)
                (writeAt! "tool.asl" "(module fx/tool\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n" (wrote 1 "ok" (list) (mapEmpty) (list "implement") (list "tool.asl") true) (some msg)))
        tooled (viaFleet! (list "test" "-f" (str stubTree "/bin/calls.log")) ".")
        toolLog (resultOr (fileReadString (str stubTree "/bin/calls.log")) "")
        shown (gitOut! good (list "show" "--name-only" "--format=" "HEAD"))
        status (gitOut! good (list "status" "--porcelain"))]
    (do
      (assert (some? rBad.commitError) "an unbalanced owned file ends commitError")
      (assert (stringContains? (optionOr rBad.commitError "") ":rule :balance") (str "with the guard rows in the error: " (optionOr rBad.commitError "")))
      (assert (none? rBad.commit) "and no commit sha")
      (assert (= (gitOut! bad (list "rev-parse" "HEAD")) hBad) "HEAD unchanged after the refusal")
      (assert (stringContains? (journalText (str bad "/loop.asn")) "(:commitError ") "the journal has the commitError row")
      (assert (some? rGood.commit) (str "a good write commits: " (optionOr rGood.commitError "")))
      (assert (!= (gitOut! good (list "rev-parse" "HEAD")) hGood) "HEAD moved")
      (assert (= shown "note.txt") (str "exactly the written path is committed: " shown))
      (assert (stringContains? status "?? stray.txt") "an unwritten stray file stays untracked")
      (assert (stringContains? (journalText (str good "/loop.asn")) "(:commit \"") "the journal has the commit row")
      (assert (stringContains? (rl/commitFields (pair (some "abc") (some "indexStale"))) " :commit \"abc\" :commitIndexStale true") "the result line carries commitIndexStale beside the sha")
      (assert (= (rl/commitFields (pair (some "abc") none)) " :commit \"abc\"") "a plain commit prints no stale flag")
      (let [stale (rl/commitLanded! (makeEnv "wireStale" "stale" good (str good "/loopStale.asn") 2 none (list) none) good (vcs/VcsReceipt :code 0 :text "(:vcs :op :commit :status :done :indexStale true)"))]
        (match stale
          ((ok pr) (do (assert (= (pairSecond pr) (some "indexStale")) "an :indexStale landing is flagged in the commit pair")
                       (assert (some? (pairFirst pr)) "and still returns the sha")))
          ((err e) (assert false (str "commitLanded! failed: " e)))))
      (assert (and (= tooled.exit 0) (some? rTool.commit)) (str "with env.toolRoot the commit lands through that tree: exit " (stringFromInt64 tooled.exit) " commit " (optionOr rTool.commit "none") " err " (optionOr rTool.commitError "")))
      (assert (and (stringContains? toolLog (str "cwd=" tool)) (stringContains? toolLog "tool.asl")) (str "the stub tree's binary checked the file with the commit root as cwd: " toolLog))
      (assert (= (shRm base) 0) "private base removed")
      true))

fn ! shRm path: String -> Int64
  (viaFleet! (list "rm" "-rf" path) ".").exit
