(module asl-tools/coord/tests/conductorWireTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/reviewStage :a rs) (asl-tools/coord/ladder :a l) (asl-tools/coord/store :a st)
      (asl-tools/coord/conductorService :a cs) (asl-json/json :a j) (aslGateway/subPace :a sp) (aslGateway/localTime :a lt) (asl-tools/fleet/run :a fr)])

; (:m :ref COND3 :do "fakes only: gateway text, lane table, subscription text and a fake model call; no ~/.asl read, no network, store dirs are scratch dirs under this worktree's .asl/cache")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/conductorWireTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn gatewayText -> String
  (str "(:gateway :v 2 :models ("
       "(:model :id flashLow :provider agy :name \"g\") (:model :id orNemotronUltraFree :provider openrouter :name \"n\") (:model :id ocLongcat :provider okSub :name \"l\")"
       "(:model :id ocDeepseekFlash :provider midSub :name \"d\") (:model :id kmK31Pro :provider kimiCode :name \"k\") (:model :id zzNewModel :provider x :name \"z\")))")

fn lanesText unknown: String -> String
  (str "(:reviewLanes :v 1 :familyExtra \"(:f :match km :family moonshot)\" :unknown (" unknown ") :lanes ("
       "(:lane :alias flashLow :tier free :quality 0 :allowance 5) (:lane :alias orNemotronUltraFree :tier free :quality 0 :allowance 3)"
       "(:lane :alias ocLongcat :tier free :quality 0 :allowance 3) (:lane :alias ocDeepseekFlash :tier paid :quality 0 :allowance 5)"
       "(:lane :alias kmK31Pro :tier strong :quality 0 :allowance 3)))")

fn subsText used: String -> String
  (str "(:subscriptions :v 1 :updated \"2026-10-28\" :src \"fixture\"\n"
       "  (:sub :id midSub :renews \"2026-11-13\" :windows ((:monthly :resets \"2026-11-13\" :usedPercent " used " :src opencodeApi :at \"2026-10-28 11:50\")))\n"
       "  (:sub :id okSub :renews \"2026-11-13\" :windows ((:monthly :resets \"2026-11-13\" :usedPercent 20 :src opencodeApi :at \"2026-10-28 11:50\"))))\n")

fn ! pacesAt used: String -> (List sp/SubPace)
  (sp/paceSubs (lt/utcZone) (subsText used) "" (sp/parseTimeMs "2026-10-28 12:00"))

fn ! realCfgIn home: String lanes: String -> cd/RealCfg
  (cd/realCfg (list "--repo" "." "--home" home "--lanes" lanes) home)

; (:m :ref COND3 :do "coverage refusal: an alias with no family that the lane table does not list unknown is a startup problem; listing it clears the problem; a lane naming a missing alias or an alias without family is a problem; the run command refuses to start and exits 1")
fn ! testCoverage -> Bool
  (let [(refused (rs/startupProblems (gatewayText) (lanesText "")))
        (cleared (rs/startupProblems (gatewayText) (lanesText "zzNewModel")))
        (noKm (rs/startupProblems (gatewayText) (stringReplace (lanesText "zzNewModel") "(:f :match km :family moonshot)" "")))
        (badLane (rs/startupProblems (gatewayText) (stringReplace (lanesText "zzNewModel") "alias ocLongcat " "alias noSuchAlias ")))
        (home (scratch "home"))
        (_ (cleanup home))
        (_ (dirCreate (str home "/.asl")))
        (_ (fileWrite (str home "/.asl/gateway.asn") (gatewayText)))
        (_ (fileWrite (str home "/lanes.asn") (lanesText "")))
        (viaCfg (cd/startupProblemsFor (realCfgIn home (str home "/lanes.asn"))))
        (run (fr/runOneLimited (fr/job (list (fr/nativeCli!) "run" "asl/tools/coord/conductor.asl" "run" "--store" (str home "/store") "--repo" "." "--home" home "--lanes" (str home "/lanes.asn") "--refresh-min" "600") "." (fr/childEnv (list)))
                                   (fr/limits 150 64)))
        (_ (cleanup home))]
    (do (assert (stringContains? (stringJoin refused "|") "zzNewModel: no family and not listed unknown") (str "unlisted unknown alias is a problem: " (stringJoin refused "|")))
        (assert (listEmpty? cleared) (str "listing it unknown clears it: " (stringJoin cleared "|")))
        (assert (stringContains? (stringJoin noKm "|") "kmK31Pro") (str "without the km family row kmK31Pro has no family: " (stringJoin noKm "|")))
        (assert (stringContains? (stringJoin badLane "|") "noSuchAlias: not a gateway alias") (str "a lane must be a gateway alias: " (stringJoin badLane "|")))
        (assert (stringContains? (stringJoin viaCfg "|") "zzNewModel") "startupProblemsFor reads the home's gateway.asn and the lane file")
        (assert (and (= run.exit 1) (stringContains? run.out ":refuse")) (str "run refuses to start: exit " (stringFromInt64 run.exit) " " run.out))
        true))

; (:m :ref COND3 :do "allowances come from subPace: midSub at 58 percent is over its pace, at 20 it is under; a lane on okSub is under pace; the lane without a subscription keeps its default; a raised allowance is a rising lane")
fn ! testAllowance -> Bool
  (let [(over (rs/allowanceMap (gatewayText) (lanesText "zzNewModel") (pacesAt "58")))
        (under (rs/allowanceMap (gatewayText) (lanesText "zzNewModel") (pacesAt "20")))
        (get (fn [(m (List (Pair String Int64))) (a String)] -> Int64 (pairSecond (optionOr (listFind (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) a)) m) (pair "" -1)))))
        (rising (rs/risingLanes over under))
        (flat (rs/risingLanes under under))]
    (do (assert (< (get over "ocDeepseekFlash") (get under "ocDeepseekFlash")) (str "midSub over pace gives fewer calls than under pace: " (stringFromInt64 (get over "ocDeepseekFlash")) " vs " (stringFromInt64 (get under "ocDeepseekFlash"))))
        (assert (> (get under "ocLongcat") 0) "okSub lane has allowance")
        (assert (= (get over "flashLow") 5) "a lane whose provider has no usable subscription keeps its default")
        (assert (= rising (list "ocDeepseekFlash")) (str "only the lane whose allowance rose is rising: " (stringJoin rising ",")))
        (assert (listEmpty? flat) "an unchanged allowance wakes nothing")
        true))

fn ! park dir: String id: String lane: String await: String -> Unit
  (let [(_ (cd/writeCUnit! dir (cd/CUnit :id id :st "awaitReview" :lane lane :fails 0 :sig "" :waited 0 :parked 1 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await await)))] ())

fn ! snapAfter marker: String -> (fn [] -> (List (Pair String Int64)))
  (fn [] -> (List (Pair String Int64))
    (if (fileExists? marker) (list (pair "kmK31Pro" 5) (pair "ocDeepseekFlash" 0) (pair "strong" 5) (pair "paid" 0))
      (list (pair "kmK31Pro" 0) (pair "ocDeepseekFlash" 0) (pair "strong" 0) (pair "paid" 0))))

; (:m :ref COND3 :do "wake on refresh: a refresh that raises kmK31Pro and the strong tier wakes the units parked on either and leaves a unit parked on a lane that did not rise; a second refresh that changes nothing wakes nobody; the refresh itself is called exactly once per round")
fn ! testRefreshWake -> Bool
  (let [(dir (scratch "wake"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (_ (park dir "P1" "review" "kmK31Pro")) (_ (park dir "P2" "review" "strong")) (_ (park dir "P3" "review" "ocDeepseekFlash"))
        (marker (str dir "/refreshed"))
        (ctx (cd/Ctx :dir dir :holder "t" :ttlMs 1000 :maxWait 5 :maxSame 3 :stageSec 5 :maxDesc 5
                     :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list)) :pace (cd/fixedPace 1 1)))
        (calls (str dir "/calls"))
        (refresh (fn [] -> Unit (let [(_ (fileWrite marker "1")) (_ (fileAppend calls "r\n"))] ())))
        (woken (cd/refreshWake! ctx (snapAfter marker) refresh))
        (parkedAfter (map (fn [(id String)] -> Int64 (let [(c (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (cd/CUnit :id "" :st "" :lane "" :fails 0 :sig "" :waited 0 :parked -1 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")))] c.parked)) (list "P1" "P2" "P3")))
        (again (cd/refreshWake! ctx (snapAfter marker) refresh))
        (refreshes (resultOr (fileReadString calls) ""))
        (_ (cleanup dir))]
    (do (assert (= woken 2) (str "two units woken: " (stringFromInt64 woken)))
        (assert (= parkedAfter (list 0 0 1)) (str "P1 and P2 unparked, P3 still parked: " (stringJoin (map stringFromInt64 parkedAfter) ",")))
        (assert (= again 0) "a refresh that changes nothing wakes nobody")
        (assert (= refreshes "r\nr\n") (str "refresh called once per round: " refreshes))
        true))

fn passCall alias: String prompt: String -> (Result String String)
  (ok "(:verdict :pass :defects () :model m)")

fn ! unit -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task "doc line" :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list))

; (:m :ref COND3 :do "the ladder through the stage wiring with a fake model call: with a red-before receipt two free lanes of two families merge; without a redBefore row it does not merge; with every free lane out of allowance the ruling awaits and carries the lane to wake")
fn ! testLadderWiring -> Bool
  (let [(good "(:receipt U1 :gates ((:gate g :exit 0 :executed 3)) :redBefore ((:gate g :exit 1 :executed 0)))")
        (bad "(:receipt U1 :gates ((:gate g :exit 0 :executed 3)))")
        (call (fn [(a String) (p String)] -> (Result String String) (passCall a p)))
        (merged (rs/reviewUnit! (gatewayText) (lanesText "zzNewModel") (pacesAt "20") "." "/nonexistent" (unit) "+ a" good call))
        (nored (rs/reviewUnit! (gatewayText) (lanesText "zzNewModel") (pacesAt "20") "." "/nonexistent" (unit) "+ a" bad call))
        (zero (stringReplace (lanesText "zzNewModel") ":allowance 5" ":allowance 0"))
        (zeroFree (stringReplace (stringReplace (stringReplace zero ":alias orNemotronUltraFree :tier free :quality 0 :allowance 3" ":alias orNemotronUltraFree :tier free :quality 0 :allowance 0") ":alias ocLongcat :tier free :quality 0 :allowance 3" ":alias ocLongcat :tier free :quality 0 :allowance 0") "x" "x"))
        (awaiting (rs/reviewUnit! (gatewayText) zeroFree (list) "." "/nonexistent" (unit) "+ a" good call))]
    (do (assert (match merged ((ok r) (= r.action "merge")) ((err _) false)) (str "two free reviewers pass with a redBefore receipt: " (match merged ((ok r) r.action) ((err e) e))))
        (assert (match merged ((ok r) (and (stringContains? r.models "+") (not (listEmpty? r.rows)))) ((err _) false)) "two models reviewed and a grade row came back")
        (assert (match nored ((ok r) (!= r.action "merge")) ((err _) true)) "without a redBefore row the ladder does not merge")
        (assert (match awaiting ((ok r) (and (= r.action "await") (not (stringEmpty? r.sig)))) ((err _) false)) (str "out-of-allowance free lanes await and name the lane: " (match awaiting ((ok r) (str r.action " " r.sig)) ((err e) e))))
        (assert (and (= (cd/rulingVerdict "merge") "pass") (= (cd/rulingVerdict "await") "defer")) "ruling maps to review verdicts")
        true))

; (:m :ref COND3 :do "the service unit runs the main worktree's conductor with the store and the dev repo, stops cooperatively and keeps stage children across a restart; the dev repo is cloned only when absent and the clone never touches the source checkout")
fn ! testService -> Bool
  (let [(lay (cs/layoutOf "/h"))
        (u (cs/unitText lay (cs/noConfig)))
        (full (cs/unitText lay (cs/ServiceConfig :lanes "/l.asn" :profile "strong" :keys "/k.asn" :ledger "/led" :ledgerBase "main")))
        (fromRow (cs/configOf (list "install" "--profile" "q") "(:conductorService :lanes \"/a.asn\" :profile \"p\" :ledgerBase \"origin/main\")"))
        (noRow (cs/configOf (list "install") "garbage ("))
        (root (scratch "svc"))
        (_ (cleanup root))
        (_ (dirCreate (str root "/asex-dev/.git")))
        (have (cs/devRepoSteps (cs/Layout :home root :repo (str root "/wt/main") :devRepo (str root "/asex-dev") :store (str root "/s") :source (str root "/asex"))))
        (_ (cleanup root))
        (missing (cs/devRepoSteps lay))]
    (do (assert (stringContains? u "ExecStart=/usr/bin/nice -n 10 /h/wt/main/bin/asl run asl/tools/coord/conductor.asl run --store /h/.asl/run/conductor --repo /h/wt/main --dev-repo /h/asex-dev --dev dev") (str "ExecStart: " u))
        (assert (stringContains? u "ExecStop=/h/wt/main/bin/asl run asl/tools/coord/conductor.asl stop --store /h/.asl/run/conductor") "ExecStop writes the stop file")
        (assert (and (stringContains? u "KillMode=process") (stringContains? u "Restart=always") (stringContains? u "WantedBy=default.target")) "service keeps children and restarts")
        (assert (stringContains? u "--dev dev\nExecStop=") "no config values: ExecStart ends at --dev dev as before")
        (assert (and (stringContains? full " --lanes /l.asn") (stringContains? full " --profile strong") (stringContains? full " --keys /k.asn") (stringContains? full " --ledger /led") (stringContains? full " --ledger-base main") (stringContains? full " --dev dev --lanes /l.asn --profile strong --keys /k.asn --ledger /led --ledger-base main\nExecStop=")) (str "all four values and the base reach ExecStart: " full))
        (assert (and (= fromRow.lanes "/a.asn") (= fromRow.profile "q") (= fromRow.keys "") (= fromRow.ledgerBase "origin/main")) "config row fills, an install flag overrides it")
        (assert (= noRow (cs/noConfig)) "an unreadable config row means no values")
        (assert (listEmpty? have) "an existing dev repo is not cloned again")
        (assert (= (map (fn [(s (List String))] -> String (stringJoin s " ")) missing) (list "git clone --quiet /h/asex /h/asex-dev" "git -C /h/asex-dev checkout --quiet -b dev origin/main")) "a missing dev repo is cloned from the source and branched dev")
        true))

; (:m :ref COND3 :do "failure signatures ignore ids: the same agent failure with two session ids has one key (so three such failures escalate, found by the VPS e2e where each retry had a fresh session id), a different failure has another")
fn testSigKey -> Bool
  (let [(a (cd/sigKey "(:agent :status :failed :session \"549dd31a29a9e6d1\" :journal \".asl/run/agentLoop/549dd31a29a9e6d1.journal\")"))
        (b (cd/sigKey "(:agent :status :failed :session \"0ca65e792b00a908\" :journal \".asl/run/agentLoop/0ca65e792b00a908.journal\")"))
        (c (cd/sigKey "(:agent :status :failed :session \"0ca65e792b00a908\" :reason timeout)"))]
    (do (assert (= a b) (str "two session ids, one key: " a " | " b))
        (assert (!= a c) "a different failure has a different key")
        (assert (stringContains? a "agent status failed") (str "the words stay: " a))
        true))

fn ! git dir: String argv: (List String) -> fr/Done
  (fr/runOne (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))))

; (:m :ref COND3 :do "a branch sh/UNIT left behind without a worktree is checked out again by the retried write; without the fix the retry fails on the existing branch three times and escalates")
fn ! testAttach -> Bool
  (let [(root (scratch "attach"))
        (repo (str root "/repo"))
        (_ (cleanup root))
        (_ (dirCreate root))
        (_ (dirCreate repo))
        (i (git repo (list "init" "--quiet")))
        (c (git repo (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "--quiet" "--allow-empty" "-m" "x")))
        (b (git repo (list "branch" "sh/U1")))
        (rc (cd/realCfg (list "--repo" repo "--worktrees" (str root "/wts")) root))
        (u (st/Task :id "U1" :owns (list) :reads (list) :gate "" :channel "free" :model "" :base "HEAD" :after (list) :st "queued" :epoch 0 :receipt ""))
        (r (cd/attachOrAdd rc u (str root "/wts/U1")))
        (_ (cleanup root))]
    (do (assert (ok? r) (str "attach existing branch: " r))
        true))

; (:m :ref COND3 :do "a worktree directory deleted behind git's back leaves a registration; the retried write prunes it and attaches again instead of failing on 'missing but already registered'")
fn ! testAttachMissing -> Bool
  (let [(root (scratch "attachMissing"))
        (repo (str root "/repo"))
        (_ (cleanup root))
        (_ (dirCreate root))
        (_ (dirCreate repo))
        (i (git repo (list "init" "--quiet")))
        (c (git repo (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "--quiet" "--allow-empty" "-m" "x")))
        (rc (cd/realCfg (list "--repo" repo "--worktrees" (str root "/wts")) root))
        (u (st/Task :id "U1" :owns (list) :reads (list) :gate "" :channel "free" :model "" :base "HEAD" :after (list) :st "queued" :epoch 0 :receipt ""))
        (first (cd/attachOrAdd rc u (str root "/wts/x")))
        (gone (fr/runOne (fr/job (list "rm" "-rf" (resultOr first "?")) root (fr/childEnv (list)))))
        (again (cd/attachOrAdd rc u (resultOr first "")))
        (_ (cleanup root))]
    (do (assert (ok? first) (str "first attach: " first))
        (assert (and (= gone.exit 0) (ok? again)) (str "attach after the directory vanished: " again))
        true))

; (:m :ref COND3 :do "a dev clone made by git clone lists origin and the train's audit consistency is red on that (workspaceIsolation), so the VPS merge never passed; the conductor drops the dev repo's remotes before the train")
fn ! testDropRemotes -> Bool
  (let [(root (scratch "dropRemotes"))
        (src (str root "/src"))
        (dev (str root "/dev"))
        (_ (cleanup root))
        (_ (dirCreate src))
        (i (git src (list "init" "--quiet")))
        (c (git src (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "--quiet" "--allow-empty" "-m" "x")))
        (cl (fr/runOne (fr/job (list "git" "clone" "--quiet" src dev) root (fr/childEnv (list)))))
        (before (stringTrim (git dev (list "remote")).out))
        (n (cd/dropRemotes! dev))
        (after (stringTrim (git dev (list "remote")).out))
        (_ (cleanup root))]
    (do (assert (= before "origin") (str "a clone has origin: " before))
        (assert (and (= n 1) (stringEmpty? after)) (str "no remote after: " after))
        true))

; (:m :ref COND3 :do "spend is wired from the gateway replies: the provider's usage keys (inputTokens, cachedTokens, outputTokens) sum to the review's tokens and Leon's :usage row sums to the write's; both were 0 for every journal row of the VPS e2e")
fn ! testSpend -> Bool
  (let [(usage (list (pair "inputTokens" (j/jint 100)) (pair "cachedTokens" (j/jint 60)) (pair "outputTokens" (j/jint 20))))]
    (do (assert (= (rs/tokenSum usage) 120) (str "review tokens: " (stringFromInt64 (rs/tokenSum usage))))
        (assert (= (cd/leonTokens "(:agent :done true :usage (:input 1000 :cached 400 :output 50) :batching (:turns 2))") 1050) "write tokens from Leon's usage row")
        (assert (= (cd/leonTokens "(:agent :done true)") 0) "no usage row, no spend")
        true))

; (:m :ref COND3 :do "the merge train's env pins ASL_E2E=0 even when the conductor itself runs under ASL_E2E=1")
fn ! testMergeEnv -> Bool
  (let [(env (cd/mergeEnv))]
    (do (assert (listContains? env "ASL_E2E=0") "ASL_E2E=0 is in the train env")
        (assert (not (listContains? env "ASL_E2E=1")) "no inherited ASL_E2E=1")
        true))

; (:m :ref COND4 :do "costUsd comes from the gateway rows' :costMicros per call: a priced alias costs its price per call, any unpriced call makes the cost -1 (the journal prints :priced false and adds 0)")
fn ! testCost -> Bool
  (let [(gw "(:gateway :models ((:model :id paidA :provider p :name \"vendor/a\" :costMicros 1000) (:model :id freeB :provider q :name \"b\" :tier free) (:model :id orNemotronUltraFree :provider r) (:model :id ocDeepseekFlash :provider o)))")
        (prices (rs/costRows gw (lanesText "zz")))
        (priced (rs/usageCost "(:usage :alias paidA :tokens 5 :costMicros 1000)\n(:usage :alias paidA :tokens 5 :costMicros 1000)\n"))
        (mixed (rs/usageCost "(:usage :alias paidA :tokens 5 :costMicros 1000)\n(:usage :alias freeB :tokens 5 :costMicros -1)\n"))]
    (do (assert (= (rs/usageCost "") 0) "no calls cost nothing")
        (assert (= priced 2000) (str "two priced calls: " (stringFromInt64 priced)))
        (assert (= mixed -1) "one unpriced call makes the cost unknown")
        (assert (and (listContains? prices (pair "paidA" 1000)) (listContains? prices (pair "vendor/a" 1000)) (listContains? prices (pair "freeB" 0))) "price rows by id and by name")
        (assert (= (cd/leonCost "(:agent :batching (:turns 4 :ops 5))" prices "vendor/a") 4000) "write cost = turns x price")
        (assert (= (cd/leonCost "(:agent :batching (:turns 4 :ops 5))" prices "b") 0) "a free-tier writer model costs 0, priced")
        (assert (and (listContains? prices (pair "orNemotronUltraFree" 0)) (listContains? prices (pair "ocDeepseekFlash" -1))) "free by the lane table is 0; a paid alias without a price stays unknown")
        (assert (= (cd/leonCost "(:agent)" prices "vendor/a") -1) "no turns is unknown")
        true))

; (:m :ref CONDUCTOR-VACUOUS-GATE :do "a Leon receipt whose :vacuousGates lists the unit gate makes the write vacuous unless the task says the gate is a regression guard")
fn testVacuousWrite -> Bool
  (let [(gate "./bin/asl test a/bTest.asl")
        (out (str "(:agent :status :ok :receipt (:agentReceipt :status :ok :phases (scout) :vacuousGates (\"" gate "\") :usage (:input 1)))"))
        (other "(:agent :status :ok :receipt (:agentReceipt :status :ok :vacuousGates (\"./bin/asl test c/dTest.asl\")))")]
    (do (assert (cd/vacuousWrite? out gate "add a flag") "the gate listed in :vacuousGates is vacuous")
        (assert (not (cd/vacuousWrite? other gate "add a flag")) "another gate listed is not this unit's")
        (assert (not (cd/vacuousWrite? "(:agent :status :ok :receipt (:agentReceipt :status :ok))" gate "add a flag")) "no :vacuousGates, not vacuous")
        (assert (not (cd/vacuousWrite? out gate "keep the gate green: it is a Regression Guard")) "a regression guard task may keep a green gate")
        (assert (not (cd/vacuousWrite? out "" "add a flag")) "no gate, nothing to call vacuous")
        (assert (cd/vacuousSig? (cd/vacuousSig gate)) "the vacuous signature is recognised")
        (assert (not (cd/vacuousSig? "noEdit")) "other write signatures are not")
        true))

fn ! commitFile repo: String file: String text: String msg: String -> Unit
  (let [(_ (fileWrite (str repo "/" file) text))
        (_ (git repo (list "add" file)))
        (_ (git repo (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "--quiet" "-m" msg)))]
    ())

; (:m :ref COND3 :do "a re-run unit's leftover sh/UNIT with an old base is rebased onto the unit's base when that is clean, and renamed -stale and recreated from the base when it conflicts; the work is never lost")
fn ! testStaleBranch -> Bool
  (let [(root (scratch "stale"))
        (_ (cleanup root))
        (repoA (str root "/a"))
        (repoB (str root "/b"))
        (_ (dirCreate repoA))
        (_ (dirCreate repoB))
        (mk (fn [(r String)] -> String
              (let [(_ (git r (list "init" "--quiet" "-b" "main")))
                    (_ (commitFile r "f.txt" "base\n" "c0"))
                    (_ (git r (list "branch" "sh/U1")))]
                r)))
        (_ (mk repoA))
        (_ (mk repoB))
        (u (st/Task :id "U1" :owns (list) :reads (list) :gate "" :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt ""))
        (_ (git repoA (list "checkout" "--quiet" "sh/U1")))
        (_ (commitFile repoA "g.txt" "g\n" "old work"))
        (_ (git repoA (list "checkout" "--quiet" "main")))
        (_ (commitFile repoA "h.txt" "h\n" "main moves"))
        (rcA (cd/realCfg (list "--repo" repoA "--worktrees" (str root "/wtsA")) root))
        (ra (cd/attachOrAdd rcA u (str root "/wtsA/x")))
        (pa (resultOr ra ""))
        (ancA (git pa (list "merge-base" "--is-ancestor" "main" "HEAD")))
        (hasG (fileExists? (str pa "/g.txt")))
        (_ (git repoB (list "checkout" "--quiet" "sh/U1")))
        (_ (commitFile repoB "f.txt" "old\n" "old work"))
        (_ (git repoB (list "checkout" "--quiet" "main")))
        (_ (commitFile repoB "f.txt" "main\n" "main edit"))
        (rcB (cd/realCfg (list "--repo" repoB "--worktrees" (str root "/wtsB")) root))
        (rb (cd/attachOrAdd rcB u (str root "/wtsB/x")))
        (pb (resultOr rb ""))
        (ancB (git pb (list "merge-base" "--is-ancestor" "main" "HEAD")))
        (branches (git repoB (list "branch" "--list" "sh/U1-stale-*")))
        (cleanB (git pb (list "status" "--porcelain")))
        (_ (cleanup root))]
    (do (assert (ok? ra) (str "attach A: " ra))
        (assert (and (= ancA.exit 0) hasG) "A: rebased onto main and the old work is kept")
        (assert (ok? rb) (str "attach B: " rb))
        (assert (= ancB.exit 0) "B: recreated from main")
        (assert (stringContains? branches.out "sh/U1-stale-") (str "B: the old branch is kept as -stale: " branches.out))
        (assert (stringEmpty? (stringTrim cleanB.out)) (str "B: no rebase left half done: " cleanB.out))
        true))

; (:m :ref COND5 :do "a failure signature is the first error-looking line, never a (:gateway :usage ...) accounting line (run5 of the VPS e2e took the trailing usage line as the signature)")
fn ! testGateSig -> Bool
  (let [(usage "(:gateway :usage :provider \"opencodeGo\" :alias \"ocBeamFree\" :outcome \"ok\")")
        (agent "(:agent :status :failed :receipt (:agentReceipt :status :needsReview))")]
    (do (assert (stringStartsWith? (cd/gateSig (str "starting\n" agent "\n" usage "\n")) "(:agent :status :failed") "the failed agent line wins over the trailing usage line")
        (assert (= (cd/gateSig (str "boom ERR_X here\n" usage "\n")) "boom ERR_X here") "ERR_ lines still come first")
        (assert (= (cd/gateSig (str "plain tail\n" usage "\n")) "plain tail") "with no error line, the last non-usage line")
        true))

fn ! runTests -> Bool
  (do (assert (testAttach) "retry attaches an existing branch")
      (assert (testAttachMissing) "a registered but missing worktree is pruned and attached")
      (assert (testDropRemotes) "the dev repo's remotes are dropped before a train")
      (assert (testSpend) "token spend from provider usage and Leon's usage row")
      (assert (testMergeEnv) "the train cannot start a nested e2e")
      (assert (testCost) "costUsd from gateway price rows, unpriced is -1")
      (assert (testVacuousWrite) "a gate green on the base makes the write vacuous")
      (assert (testStaleBranch) "a stale leftover branch is rebased or recreated")
      (assert (testGateSig) "gateSig ignores usage lines")
      (assert (testSigKey) "signature key ignores ids")
      (assert (testAllowance) "allowances from subPace")
      (assert (testRefreshWake) "refresh wakes the lanes that rose")
      (assert (testLadderWiring) "ladder wiring")
      (assert (testService) "service unit and dev repo steps")
      (assert (testCoverage) "coverage refusal")
      true)
