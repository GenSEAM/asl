(module asl-tools/coord/tests/fixtures/pipeFix
  :x [scriptNoopLeon! e2eRepo! scriptLeon! devCloneFor! e2eLaunch e2eCtx tosOf journalLines startHubFor! envFor prepare! receiptFor! verdictOf sigOf scratch cleanup sh here repoIn unitIn cuIn seedUnit! stageChild! readResOf! listenWait! startHub! stopHub! hubSeen gatewayText lanesText]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref PIPE-GATES :do "shared fixtures of the real-path pipeline tests: scratch dirs under this worktree's .asl/cache, a temp git repo with a gate script, a temp store, and the real stage child bin/asl run conductor.asl stage started only through fleet/run.asl under a timeout")
fn ! here -> String
  (resultOr (realPath ".") ".")

fn ! scratch tag: String name: String -> String
  (str (here) "/.asl/cache/" tag "-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! sh c: String -> String
  (resultOr (fr/shellOut c 60000) "")

; (:m :do "repo with main, check.sh (green when every named file holds impl) and an empty impl.txt-less base, so the gate sh check.sh impl.txt is red on the base; store, home and worktree dirs beside it")
fn ! repoIn root: String -> String
  (let [(repo (str root "/repo"))
        (made (sh (str "mkdir -p " repo " " root "/store/tasks " root "/home/.asl " root "/wts && cd " repo " && git init -q -b main && git config user.email t@example.invalid && git config user.name t"
                       " && printf 'for f in \"$@\"; do if [ \"$(cat $f 2>/dev/null)\" != impl ]; then echo \"(:gate :asserts 1 :failed 1)\"; echo \"FAIL check (1 asserts)\"; exit 1; fi; done\\necho \"(:gate :asserts 1 :failed 0)\"\\necho \"1 assertion(s) executed (1 passed)\"\\n' > check.sh"
                       " && printf 'for f in \"$@\"; do if [ \"$(cat $f 2>/dev/null)\" != impl ]; then echo \"(:gate :asserts 3 :failed 1)\"; echo \"FAIL check3 (3 asserts)\"; exit 1; fi; done\necho \"(:gate :asserts 3 :failed 0)\"\necho \"3 assertion(s) executed (3 passed)\"\n' > check3.sh"
                       " && printf a > a.txt && git add -A && git commit -qm c0 && echo madeOk")))]
    (if (stringContains? made "madeOk") repo ""))

fn unitIn id: String gate: String -> st/Task
  (st/Task :id id :owns (list "impl.txt") :reads (list) :gate gate :channel "free" :model "" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")

fn cuIn id: String stateName: String wt: String branch: String -> cd/CUnit
  (cd/CUnit :id id :st stateName :lane "free" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch branch :wt wt :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")

; (:m :do "store row and conductor row of one unit; wt is its worktree (a branch sh/ID with one commit of impl.txt holding impl when file is not empty)")
fn ! seedUnit! root: String u: st/Task stateName: String file: String -> String
  (let [(repo (str root "/repo"))
        (wt (str root "/wts/asex-" u.id))
        (made (sh (str "cd " repo " && git worktree add -q -b sh/" u.id " " wt " main"
                       (if (stringEmpty? file) "" (str " && cd " wt " && printf impl > " file " && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm '(:c :a t :do unit " u.id ")' && echo madeOk"))
                       (if (stringEmpty? file) " && echo madeOk" ""))))
        (_ (st/put! (str root "/store") u))
        (_ (cd/writeCUnit! (str root "/store") (cuIn u.id stateName wt (str "sh/" u.id))))]
    (if (stringContains? made "madeOk") wt ""))

; (:m :do "the real stage child: bin/asl run conductor.asl stage STAGE ID with the scratch store, bounded by sec seconds; env rows override the child's env")
fn ! stageChild! root: String stage: String id: String extra: (List String) env: (List String) sec: Int64 -> fr/Done
  (let [(h (here))]
    (fr/runOneLimited
      (fr/job (listAppend (list (str h "/bin/asl") "run" (str h "/asl/tools/coord/conductor.asl") "stage" stage id "--store" (str root "/store") "--repo" (str root "/repo") "--home" (str root "/home") "--worktrees" (str root "/wts") "--lanes" (str root "/home/lanes.asn")) extra) h (fr/childEnv env))
      (fr/limits sec 100)))

fn ! readResOf! root: String id: String stage: String -> (Result cd/Res String)
  (match (fileReadString (cd/runPath (str root "/store") id stage "asn"))
    ((err e) (err e))
    ((ok raw) (cd/parseRes raw)))

fn ! listenWait! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 50) (listenWait! path (- attempts 1)))))

; (:m :do "stand-in hub (fixtures/hubVerdictStub.asl) started through fleet/run.asl guardStart! in its own process group with a lease; the stub also exits on its own after sec seconds or its request cap (hubDeadlineTest); returns the pid, 0 when it did not come up")
fn ! startHubFor! root: String sec: Int64 -> Int64
  (let [(h (here))
        (sock (str root "/hub.sock"))
        (g (fr/guardStart! (list (str h "/bin/asl") "run" (str h "/asl/tools/coord/tests/fixtures/hubVerdictStub.asl") sock (str root "/hubSeen.txt") (str root "/hubReply.txt") (stringFromInt64 sec) "50") h (fr/childEnv (list)) (fr/limits (+ sec 60) 50)))]
    (match g
      ((err _) 0)
      ((ok r) (if (listenWait! sock 1200) r.run.pid (do (fr/killTree! r.run.pid) 0)))))

fn ! startHub! root: String -> Int64
  (startHubFor! root 300)

fn ! stopHub! pid: Int64 -> Bool
  (do (if (> pid 0) (fr/killTree! pid) 0) true)

fn ! hubSeen root: String -> String
  (resultOr (fileReadString (str root "/hubSeen.txt")) "")

fn gatewayText -> String
  (str "(:gateway :v 2 :models ("
       "(:model :id flashLow :provider agy :name \"g\") (:model :id orNemotronUltraFree :provider openrouter :name \"n\") (:model :id ocLongcat :provider okSub :name \"l\")"
       "(:model :id ocDeepseekFlash :provider midSub :name \"d\") (:model :id kmK31Pro :provider kimiCode :name \"k\") (:model :id zzNewModel :provider x :name \"z\")))")

fn lanesText -> String
  (str "(:reviewLanes :v 1 :familyExtra \"(:f :match km :family moonshot)\" :unknown (zzNewModel) :lanes ("
       "(:lane :alias flashLow :tier free :quality 0 :allowance 5) (:lane :alias orNemotronUltraFree :tier free :quality 0 :allowance 3)"
       "(:lane :alias ocLongcat :tier free :quality 0 :allowance 3) (:lane :alias ocDeepseekFlash :tier paid :quality 0 :allowance 5)"
       "(:lane :alias kmK31Pro :tier strong :quality 0 :allowance 3)))")

; (:m :ref PIPE-GATES :do "review-stage helpers shared by reviewRealTest and the probe: the child env (own HOME, hub.asn naming the stand-in, native CLI cache kept so the child does not cold-build), the home files, a proven receipt and the verdict and signature of a stage row")
fn ! envFor root: String -> (List String)
  (list (str "HOME=" root "/home") (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))) "ASL_GATEWAY_URL=http://127.0.0.1:1/v1/chat/completions" (str "ASL_GATEWAY_CONFIG=" root "/home/.asl/gateway.asn"))

fn ! prepare! root: String -> Bool
  (let [(_ (dirCreate (str root "/home/.asl")))
        (_ (dirCreate (str root "/store/runs")))
        (a (fileWrite (str root "/home/.asl/gateway.asn") (str (gatewayText) "\n")))
        (b (fileWrite (str root "/home/lanes.asn") (str (lanesText) "\n")))
        (c (fileWrite (str root "/home/.asl/hub.asn") (str "(:hub :sock \"" root "/hub.sock\" :class \"lead\")\n")))
        (d (fileWrite (str root "/hubReply.txt") "(:verdict :pass :defects () :model m)"))]
    (and (ok? a) (and (ok? b) (and (ok? c) (ok? d)))))

fn ! receiptFor! root: String id: String -> Bool
  (ok? (fileWrite (cd/runPath (str root "/store") id "receipt" "asn") (str "(:receipt \"" id "\" :gates ((:gate \"g\" :exit 0 :executed 3)) :redBefore ((:gate \"g\" :exit 1 :executed 0)))\n")))

fn verdictOf r: (Result cd/Res String) -> String
  (match r ((ok x) x.verdict) ((err e) (str "noRow: " e)))

fn sigOf r: (Result cd/Res String) -> String
  (match r ((ok x) x.sig) ((err _) ""))

; (:m :ref PIPE-E2E-HERMETIC :do "fixtures of the whole-cycle test: a temp repo that also carries a hub-client stub and an ignored bin/asl, which is the scripted Leon (the conductor starts Leon as REPO/bin/asl with an (:agent ...) form; the stand-in adds :backend script/e2e so the real Leon loop runs against a fixture of replies, every other call passes to the real bin/asl); a dev clone with a recording train stand-in; the stage launch argv with a temp HOME; a Ctx")
fn escTurn s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn ! e2eRepo! root: String -> String
  (let [(repo (repoIn root))
        (made (if (stringEmpty? repo) ""
                (sh (str "cd " repo " && mkdir -p asl/packages/asl-agent/src && printf 'fn hubAsnPath -> String\n  \"\"\n' > asl/packages/asl-agent/src/providers.asl"
                         " && printf '(:aslConfig :agentLoop (:specCheck false :baseline false))\n' > .asl.config.asn"
                         " && printf '.asl/\ntests/\nbin/\n' >> .git/info/exclude && git add -A && git commit -qm c1 && echo madeOk"))))]
    (if (stringContains? made "madeOk") repo ""))

; (:m :do "replies: one scripted Leon turn each; the wrapper copies the fixture into the worktree it runs in (its cwd), then runs the real Leon on it")
fn ! scriptLeon! root: String replies: (List String) -> Bool
  (let [(h (here))
        (fixture (str root "/leonFixture.asn"))
        (turns (stringJoin (map (fn [(pr (Pair Int64 String))] -> String (str "    (:turn :num " (stringFromInt64 (+ (pairFirst pr) 1)) " :reply \"" (escTurn (pairSecond pr)) "\")\n")) (enumerate replies)) ""))
        (_ (fileWrite fixture (str "(:script :id \"e2e\" :mode :scout\n  :turns (\n" turns "  )\n)\n")))
        (exports (stringJoin (map (fn [(r String)] -> String (str "  export " r "\n")) (fr/cacheEnv!)) ""))
        (body (str "#!/bin/sh\ncase \"$1\" in\n\"(:agent\"*)\n  mkdir -p \"$PWD/tests/fixtures/agentLoop/mvp\" && cp " fixture " \"$PWD/tests/fixtures/agentLoop/mvp/e2e.asn\"\n"
                   exports "  F=\"${1%)}\"\n  " h "/bin/asl \"$F :backend \\\"script/e2e\\\")\"\n  C=$?\n  echo '(:servedBy :model \"kmK31Pro\")'\n  exit $C ;;\n*) exec " h "/bin/asl \"$@\" ;;\nesac\n"))
        (_ (dirCreate (str root "/repo/bin")))
        (w (fileWrite (str root "/repo/bin/asl") body))
        (c (sh (str "chmod 755 " root "/repo/bin/asl && echo chmodOk")))]
    (and (ok? w) (stringContains? c "chmodOk")))

; (:m :do "dev clone on branch dev of the temp repo, taken after the repo's last commit; its bin/asl records its argv in .git/trainArgs and merges the branch it is given (the one stand-in of a merge: a real train needs a full workspace)")
fn ! devCloneFor! root: String -> String
  (let [(dev (str root "/dev"))
        (made (sh (str "git clone -q " root "/repo " dev " && cd " dev " && git config user.email t@example.invalid && git config user.name t && git checkout -q -b dev && mkdir -p bin"
                       " && printf '#!/bin/sh\nif [ \"$1\" = audit ]; then echo \"(:audit :sub $2 :status :passed)\"; exit 0; fi\nD=$(cd \"$(dirname \"$0\")/..\" && pwd)\necho \"$@\" >> \"$D/.git/trainArgs\"\ngit -C \"$D\" merge --no-ff -q -m \"train $2\" \"$2\" || exit 1\nexit 0\n' > bin/asl && chmod 755 bin/asl && echo bin/asl >> .git/info/exclude && echo madeOk")))]
    (if (stringContains? made "madeOk") dev ""))

; (:m :do "stage child argv: the real conductor stage with its own HOME (hub.asn, gateway.asn, lanes), gateway env pointing nowhere so only the hub answers, the temp repo as repo and the dev clone as dev repo")
fn e2eLaunch root: String -> (fn [String st/Task cd/CUnit] -> (List String))
  (let [(h (here))]
    (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String)
      (listAppend (listAppend (list "/usr/bin/env" (str "HOME=" root "/home")) (fr/cacheEnv!))
        (list "ASL_GATEWAY_URL=http://127.0.0.1:1/v1/chat/completions" (str "ASL_GATEWAY_CONFIG=" root "/home/.asl/gateway.asn")
              (str h "/bin/asl") "run" (str h "/asl/tools/coord/conductor.asl") "stage" stage u.id "--store" (str root "/store") "--repo" (str root "/repo")
              "--dev-repo" (str root "/dev") "--dev" "dev" "--worktrees" (str root "/wts") "--home" (str root "/home") "--lanes" (str root "/home/lanes.asn")))))

fn e2eCtx root: String stageSec: Int64 -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "pipeE2eTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec stageSec :maxDesc 200
          :launch (e2eLaunch root) :pace (cd/fixedPace 4 4))

fn ! journalLines dir: String -> (List String)
  (match (fileReadString (cd/journalPath dir)) ((ok t) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines t))) ((err _) (list)))

; (:m :do "the :to states of one unit's transition rows, in journal order")
fn ! tosOf dir: String id: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit l ":to ") 1) "") " ")) ""))
       (filter (fn [(l String)] -> Bool (stringContains? l (str "(:t :unit \"" id "\" "))) (journalLines dir)))

; (:m :ref PIPE-E2E-HERMETIC :do "a Leon that exits 0 at once: it writes content into impl.txt when content is not empty (a wrong or right edit the driver then commits) and nothing otherwise, so the conductor's own noEdit and red-gate branches run, not Leon's")
fn ! scriptNoopLeon! root: String content: String -> Bool
  (let [(body (str "#!/bin/sh\ncase \"$1\" in\n\"(:agent\"*)\n" (if (stringEmpty? content) "" (str "  printf '" content "' > impl.txt\n")) "  echo '(:servedBy :model \"kmK31Pro\")'\n  exit 0 ;;\n*) exec " (here) "/bin/asl \"$@\" ;;\nesac\n"))
        (_ (dirCreate (str root "/repo/bin")))
        (w (fileWrite (str root "/repo/bin/asl") body))
        (c (sh (str "chmod 755 " root "/repo/bin/asl && echo chmodOk")))]
    (and (ok? w) (stringContains? c "chmodOk")))
