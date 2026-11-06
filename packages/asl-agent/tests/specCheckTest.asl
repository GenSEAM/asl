(module aslAgent/tests/specCheckTest
  :x [runTests]
  :i [(aslAgent/runLoop :a rl) (aslAgent/loopState :a s)
      (aslAgent/providers :a pv) (aslAgent/gates :a g)
      (aslAgent/claimBacking :a cb) (aslAgent/agentConfig :a ac)
      (aslAgent/loop :a lp) (aslAgent/tests/gitInitKit :a kit)
      (asl-json/json :a j) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-CAPS :do "the fake grader is a closure that appends the (:graderServed ...) row a real gateway call would and returns a scripted verdict; the fake writer is a loop body that writes subject.txt once. These asserts prove the wiring (when the check runs, how a verdict, an error, a missing or equal model, and an opt-out change the end status and the journal), not any model's judgement")
fn fakeTurn prompt: String system: String -> pv/Turn
  (pv/Turn :provider (pv/scriptProvider "specCheckTest" (list) 0) :reply (ok none) :meta (pv/emptyMeta))

fn fakeAdvice prompt: String system: String -> (Result (Option String) String)
  (ok none)

fn fakeId -> String
  "specCheckTest"

fn fakeNow -> Float64
  1.0

fn fakeSleep ms: Int64 -> Bool
  true

fn ! tempRoot label: String -> String
  (let [path (str (optionOr (envGet "TMPDIR") "/tmp") "/specCheckTest_" label "_" (stringFromInt64 (procSelf)))]
    (do (dirCreate path) (resultOr (realPath path) path)))

fn ! fileText path: String -> String
  (resultOr (fileReadString path) "")

fn envWith root: String journal: String model: String specCheck: Bool grade: (fn [String String String] -> (Result (Option String) String)) gates: (List String) -> s/LoopEnv
  (s/LoopEnv :provider fakeTurn :task "make subject.txt say after" :modeHint (some "implement") :owns (list) :gates gates
    :rootDir root :budget 4 :inputTokenBudget 0 :journalPath journal :maxRetries 0 :sessionId (some "specCheckTest")
    :base (some "") :contextTokens (some 24000) :model (some model)
    :gateTimeout (some 10) :wallBudget none :resume none :intent (some "patch") :plan false :specCheck specCheck :commit false
    :next fakeTurn :advise fakeAdvice :review fakeAdvice :grade grade :newId fakeId :now fakeNow :sleep fakeSleep :toolRoot "")

fn withWrittenFiles st: s/LoopState files: (List String) -> s/LoopState
  (with st :writtenFiles files)

fn writerBody root: String servedRow: String journal: String -> (fn [s/LoopEnv rl/LoopRun] -> (Pair rl/LoopRun s/Step))
  (fn [env run]
    (let [state run.state
          _ (fileWrite (str root "/subject.txt") "after\n")
          _row (if (stringEmpty? servedRow) true (ok? (fileAppend journal servedRow)))
          next (withWrittenFiles (rl/withHeadState state 1 0 true (some "patch") (list) (mapEmpty) "ok" none none state.runStarted) (list "subject.txt"))]
      (pair (rl/withState run next) (stop))))

fn graderReplying journal: String model: String reply: String -> (fn [String String String] -> (Result (Option String) String))
  (fn [role system text]
    (do
      (if (stringEmpty? model) true (ok? (fileAppend journal (str "(:graderServed :model \"" model "\")\n"))))
      (ok (some reply))))

fn graderFailing message: String -> (fn [String String String] -> (Result (Option String) String))
  (fn [role system text] (err message))

fn neverGrader -> (fn [String String String] -> (Result (Option String) String))
  (fn [role system text] (err "the grader must not be called"))

fn ! repo label: String -> String
  (let [root (tempRoot label)
        _ (fileWrite (str root "/subject.txt") "before\n")]
    (do (kit/initGitRepo! root "specCheckTest" "spec-check@example.invalid") root))

fn ! resultRow journal: String -> String
  (optionOr (listLast (filter (fn [row] (stringStartsWith? row "(:result ")) (stringLines (fileText journal)))) "")

fn reasonsOf r: s/RunResult -> (List String)
  (match r.specCheck ((some v) v.reasons) ((none) (list)))

fn verdictOf r: s/RunResult -> String
  (match r.specCheck ((some v) v.verdict) ((none) "none"))

fn modelOf r: s/RunResult -> String
  (match r.specCheck ((some v) v.model) ((none) "none"))

fn gateRun cmd: String exit: Int64 out: String -> g/GateResult
  (g/makeGateResult cmd exit out "" false 0)

fn ! runTests -> Bool
  (let [metTrue "(:verdict :met true)"
        metFalse "(:verdict :met false :missing (\"subject.txt does not say after\"))"
        passRoot (repo "pass")
        passJ (str passRoot "/pass.asn")
        pass (rl/runLoopWith! (envWith passRoot passJ "writer-1" true (graderReplying passJ "grader-1" metTrue) (list)) (writerBody passRoot "" passJ))
        failRoot (repo "fail")
        failJ (str failRoot "/fail.asn")
        fail (rl/runLoopWith! (envWith failRoot failJ "writer-1" true (graderReplying failJ "grader-1" metFalse) (list)) (writerBody failRoot "" failJ))
        sameRoot (repo "same")
        sameJ (str sameRoot "/same.asn")
        same (rl/runLoopWith! (envWith sameRoot sameJ "writer-1" true (graderReplying sameJ "writer-1" metTrue) (list)) (writerBody sameRoot "" sameJ))
        servedRoot (repo "served")
        servedJ (str servedRoot "/served.asn")
        served (rl/runLoopWith! (envWith servedRoot servedJ "writer-1" true (graderReplying servedJ "writer-1" metTrue) (list))
                 (writerBody servedRoot "(:served :turn 1 :model \"served-writer\")\n" servedJ))
        errRoot (repo "err")
        errJ (str errRoot "/err.asn")
        errRun (rl/runLoopWith! (envWith errRoot errJ "writer-1" true (graderFailing "gateway down") (list)) (writerBody errRoot "" errJ))
        blindRoot (repo "blind")
        blindJ (str blindRoot "/blind.asn")
        blind (rl/runLoopWith! (envWith blindRoot blindJ "writer-1" true (graderReplying blindJ "" metTrue) (list)) (writerBody blindRoot "" blindJ))
        offRoot (repo "off")
        offJ (str offRoot "/off.asn")
        off (rl/runLoopWith! (envWith offRoot offJ "writer-1" false (neverGrader) (list)) (writerBody offRoot "" offJ))
        idleRoot (repo "idle")
        idleJ (str idleRoot "/idle.asn")
        idle (rl/runLoopWith! (envWith idleRoot idleJ "writer-1" true (neverGrader) (list))
                (fn [env run] (pair (rl/withState run (rl/withHeadState run.state 1 0 false none (list) (mapEmpty) "ok" none none run.state.runStarted)) (stop))))
        baseRoot (repo "baseline")
        baseJ (str baseRoot "/baseline.asn")
        baseCfg (ac/configText! baseRoot)
        _cfgOff (fileWrite (str baseRoot "/.asl.config.asn") "(:aslConfig :agentLoop (:baseline false))\n")
        baseOff (rl/runLoopWith! (envWith baseRoot baseJ "writer-1" false (neverGrader) (list "true")) (fn [env run] (pair run (stop))))
        baseOnRoot (repo "baselineOn")
        baseOnJ (str baseOnRoot "/baselineOn.asn")
        baseOn (rl/runLoopWith! (envWith baseOnRoot baseOnJ "writer-1" false (neverGrader) (list "true")) (fn [env run] (pair run (stop))))
        badRoot (repo "badConfig")
        badJ (str badRoot "/bad.asn")
        _cfgBad (fileWrite (str badRoot "/.asl.config.asn") "(:aslConfig :agentLoop (:readOutlineBytes 0 :baseline maybe))\n")
        bad (rl/runLoopWith! (envWith badRoot badJ "writer-1" false (neverGrader) (list "true")) (fn [env run] (pair run (stop))))
        retainRoot (tempRoot "retain")
        retainMain (str retainRoot "/main")
        retainTree (str retainRoot "/tree")
        retainJ (str retainTree "/retain.asn")
        retainReady (and (kitGit (list "init" "-q" retainMain))
          (and (kitGit (list "-C" retainMain "-c" "user.name=specCheckTest" "-c" "user.email=spec-check@example.invalid" "commit" "-q" "--allow-empty" "-m" "base"))
          (and (kitGit (list "-C" retainMain "worktree" "add" "-q" "--detach" retainTree))
          (and (ok? (fileWrite (str retainMain "/.asl") "a file where the retained journal directory belongs\n"))
          (and (ok? (fileWrite retainJ ""))
            (child (list "chmod" "444" retainJ) retainRoot))))))
        retain (rl/runLoopWith! (envWith retainTree retainJ "writer-1" false (neverGrader) (list "true")) (fn [env run] (pair run (stop))))
        noChanRoot (repo "nochan")
        noChanJ (str noChanRoot "/nochan.asn")
        noChan (rl/runLoopWith! (envWith noChanRoot noChanJ "writer-1" true (graderFailing "ERR_NO_GRADER_CHANNEL provider has no grader channel") (list)) (writerBody noChanRoot "" noChanJ))
        unkRoot (repo "unknown")
        unkJ (str unkRoot "/unknown.asn")
        unk (rl/runLoopWith! (envWith unkRoot unkJ "" true (graderReplying unkJ "grader-1" metTrue) (list)) (writerBody unkRoot "" unkJ))
        redRuns (list (gateRun "./bin/asl test asl/packages/asl-agent/tests/fooTest.asl" 1 "asl/packages/asl-agent/tests/fooTest.asl: 12 assertion(s) executed (11 passed)\n"))
        strCfg "(:aslConfig :doc \"see :agentLoop (:baseline false) here\" :agentLoop (:baseline true))"
        latestRuns (list (gateRun "./bin/asl test asl/packages/asl-agent/tests/fooTest.asl" 0 "asl/packages/asl-agent/tests/fooTest.asl: 12 assertion(s) executed (12 passed)\n"))
        reRuns (list (gateRun "./bin/asl test asl/packages/asl-agent/tests/fooTest.asl" 0 "fooTest.asl: 12 assertion(s) executed (12 passed)\n")
                     (gateRun "./bin/asl test asl/packages/asl-agent/tests/fooTest.asl" 0 "fooTest.asl: 13 assertion(s) executed (13 passed)\n"))
        claims (fn [reply declared runs] (cb/unbackedGateClaims reply declared runs))
        cfgText "(:aslConfig :readOutlineBytes 5 :other (:agentLoop 1) :agentLoop (:baseline false :doc \"mentions :readOutlineBytes 9\" :graderProfile \"p1\"))"]
    (do
      (assert (and (= pass.status "ok") (= (verdictOf pass) "pass") (= (modelOf pass) "grader-1") (none? (listHead (reasonsOf pass))))
        "a grader of another model that finds the task met keeps the status ok and records the verdict, model and no reasons")
      (assert (stringContains? (resultRow passJ) " :specCheck (:verdict pass :model \"grader-1\" :reasons ())")
        "the journal result row carries :specCheck (:verdict pass :model ... :reasons ())")
      (assert (and (= fail.status "needsReview") (= (verdictOf fail) "fail") (= (reasonsOf fail) (list "subject.txt does not say after")))
        "a not-met verdict makes the status needsReview with the grader's reasons, never ok")
      (assert (and (stringContains? (resultRow failJ) "(:result :status :needsReview") (stringContains? (resultRow failJ) " :specCheck (:verdict fail :model \"grader-1\" :reasons (\"subject.txt does not say after\"))"))
        "the journal result row records the needsReview status and the fail verdict")
      (assert (and (= (fileText (str failRoot "/subject.txt")) "after\n") (none? fail.commit) (listEmpty? fail.restored))
        "needsReview keeps the written change on disk instead of restoring it, and commits nothing")
      (assert (and (= same.status "needsReview") (= (verdictOf same) "fail")
                   (listAny? (fn [r] (stringContains? r "is the writer's model")) (reasonsOf same)))
        "a grader that is the writer's configured model is a fail even when it says met")
      (assert (and (= served.status "ok") (= (verdictOf served) "pass"))
        "the writer's model is the last served model in the journal, so a grader equal to the configured model but not to the served one passes")
      (assert (and (= errRun.status "needsReview") (= (verdictOf errRun) "fail")
                   (listAny? (fn [r] (stringContains? r "gateway down")) (reasonsOf errRun)))
        "a grader call that errors is a fail with the error as the reason, never a silent pass")
      (assert (and (= blind.status "needsReview") (= (verdictOf blind) "fail")
                   (listAny? (fn [r] (stringContains? r "reported no model")) (reasonsOf blind)))
        "a grader that reports no model cannot be shown to differ from the writer, so it is a fail")
      (assert (and (= off.status "ok") (none? off.specCheck) (not (stringContains? (resultRow offJ) ":specCheck")))
        "with env.specCheck false the grader is never called and no verdict is recorded")
      (assert (and (= idle.status "ok") (none? idle.specCheck))
        "a run that wrote nothing has no diff to grade, so no grader call is made")
      (assert (and (= (ac/agentLoopValue cfgText ":baseline") (some "false")) (= (ac/agentLoopValue cfgText ":graderProfile") (some "p1")))
        "config keys are read from the :agentLoop group, quotes removed")
      (assert (none? (ac/agentLoopValue cfgText ":readOutlineBytes"))
        "a key outside the :agentLoop group or inside a doc string is not read")
      (assert (and (listEmpty? (ac/configProblems "(:agentLoop (:readOutlineBytes 4096 :baseline true))"))
                   (= (listLength (ac/configProblems "(:agentLoop (:readOutlineBytes 0))")) 1)
                   (= (listLength (ac/configProblems "(:agentLoop (:baseline maybe :readOutlineBytes -3))")) 2))
        "a zero, negative or non-boolean :agentLoop value is a config problem; valid values and absent keys are not")
      (assert (and (= baseCfg "") (= baseOff.status "ok") (listEmpty? baseOff.vacuousGates)
                   (stringContains? (fileText baseJ) "(:baseline :skipped")
                   (not (stringContains? (fileText baseJ) "(:baseline :green")))
        "config :agentLoop (:baseline false) skips the baseline gate pass: nothing is run, nothing is marked vacuous, the journal says skipped")
      (assert (and (= baseOn.status "ok") (= baseOn.vacuousGates (list "true")) (stringContains? (fileText baseOnJ) "(:baseline :green (\"true\")"))
        "without the opt-out the baseline pass runs and a gate already green is marked vacuous")
      (assert (and (= bad.status "rejected") (= bad.error (some "ERR_CONFIG"))
                   (listAny? (fn [m] (stringContains? m ":readOutlineBytes must be a positive integer")) (list (optionOr bad.message "")))
                   (stringContains? (optionOr bad.message "") ":baseline must be true or false"))
        "an invalid :agentLoop config rejects the run before anything starts, naming each bad key")
      (assert retainReady "the retention-failure fixture builds a linked worktree")
      (assert (and (= retain.status "failed") (= retain.vacuousGates (list "true")))
        "a run that fails after the baseline pass still reports the vacuous gates")
      (assert (and (= (cb/executedAsserts "a.asl: 12 assertion(s) executed (12 passed)\n") (some 12))
                   (= (cb/executedAsserts "a: 3 assertion(s) executed (3 passed)\nb: 4 assertion(s) executed (4 passed)\n") (some 7))
                   (= (cb/executedAsserts "(:gate :cmd \"x\" :exit 0 :asserts 9 :failed 0)") (some 9))
                   (none? (cb/executedAsserts "no summary here")))
        "executed asserts are read from the runner summary, summed over suites, or from an :asserts anchor")
      (assert (and (= (cb/claimedCounts "all 12 assertions pass") (list 12)) (= (cb/claimedCounts "added 3 asserts") (list 3))
                   (listEmpty? (cb/claimedCounts "an assert statement")))
        "counts are the numbers attached to assertion words")
      (assert (and (= (cb/suiteTokens "runLoopTest and asl/packages/asl-agent/tests/gateIntegrityTest.asl pass") (list "runLoopTest" "gateIntegrityTest"))
                   (listEmpty? (cb/suiteTokens "the Test harness")))
        "suite tokens are Test-suffixed names with path and .asl removed")
      (assert (listEmpty? (claims "fooTest passes with 12 assertions executed." (list) latestRuns))
        "a claim naming a gate that ran with exactly the executed assertion count is backed")
      (assert (= (claims "fooTest passes with 13 assertions executed." (list) latestRuns) (list "fooTest passes with 13 assertions executed."))
        "a claim with a count the gate did not execute is unbacked")
      (assert (= (claims "barTest passed." (list) latestRuns) (list "barTest passed."))
        "a claim naming a gate that never ran this session is unbacked")
      (assert (listEmpty? (claims "I added 3 asserts to fooTest" (list) latestRuns))
        "a sentence that does not say it ran or passed is not a claim")
      (assert (and (listEmpty? (claims "12 assertions executed" (list) latestRuns)) (= (listLength (claims "7 assertions executed" (list) latestRuns)) 1))
        "a bare count is checked against every gate run of the session")
      (assert (= (listLength (claims "fooTest passes with 12 assertions executed." (list) reRuns)) 1)
        "only the latest run of a gate backs a claim")
      (assert (and (= (listLength (claims "grep -qx green subject.txt passed" (list "grep -qx green subject.txt") (list))) 1)
                   (listEmpty? (claims "grep -qx green subject.txt passed" (list "grep -qx green subject.txt") (list (gateRun "grep -qx green subject.txt" 0 "")))))
        "a declared gate command named in a claim must have been run")
      (assert (and (= (cb/unbackedGateClaims "fooTest passed" (list) redRuns) (list "fooTest passed"))
                   (= (listLength (cb/unbackedGateClaims "12 assertions executed" (list) redRuns)) 1))
        "a gate whose latest run exited non-zero backs neither a pass claim nor an executed-count claim")
      (assert (and (= noChan.status "needsReview") (= (verdictOf noChan) "skipped") (= (reasonsOf noChan) (list "noGrader"))
                   (stringContains? (resultRow noChanJ) " :specCheck (:verdict skipped :reason noGrader)"))
        "a provider with no grader channel yields verdict skipped and needsReview, never a silent ok")
      (assert (and (= unk.status "needsReview") (listAny? (fn [r] (stringContains? r "writer model is unknown")) (reasonsOf unk)))
        "a writer whose model cannot be resolved is a fail, not a pass")
      (assert (= (ac/agentLoopValue strCfg ":baseline") (some "true"))
        "a :agentLoop named inside a string literal does not open the group")
      (assert (and (= (listLength (ac/configProblems "(:agentLoop (:baseline true :graderIntent))")) 1)
                   (listEmpty? (ac/configProblems "(:agentLoop (:baseline true))")))
        "a key with no value is a config problem")
      (assert (and (= (lp/handBackRestore "needsReview" false) false) (= (lp/handBackRestore "failed" false) true))
        "needsReview is the one non-ok status whose work is kept")
      true))

; (:m :ref LEON-CAPS :do "every child start goes through asl/tools/fleet/run.asl with a timeout and a descendant limit, as the spawnSafety rule requires")
fn ! child argv: (List String) cwd: String -> Bool
  (= (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits 20 8)).exit 0)

fn ! kitGit args: (List String) -> Bool
  (child (cons "git" args) ".")
