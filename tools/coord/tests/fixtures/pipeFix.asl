(module asl-tools/coord/tests/fixtures/pipeFix
  :x [scratch cleanup sh here repoIn unitIn cuIn seedUnit! stageChild! readResOf! listenWait! startHub! stopHub! hubSeen gatewayText lanesText]
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
                       (if (stringEmpty? file) "" (str " && cd " wt " && printf impl > " file " && git add -A && git -c user.email=t@example.invalid -c user.name=t commit -qm unit && echo madeOk"))
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

; (:m :do "stand-in hub (fixtures/hubVerdictStub.asl) started through fleet/run.asl guardStart!: own process group, lease, timeout; returns the pid, 0 when it did not come up")
fn ! startHub! root: String -> Int64
  (let [(h (here))
        (sock (str root "/hub.sock"))
        (g (fr/guardStart! (list (str h "/bin/asl") "run" (str h "/asl/tools/coord/tests/fixtures/hubVerdictStub.asl") sock (str root "/hubSeen.txt") (str root "/hubReply.txt")) h (fr/childEnv (list)) (fr/limits 900 50)))]
    (match g
      ((err _) 0)
      ((ok r) (if (listenWait! sock 1200) r.run.pid (do (fr/killTree! r.run.pid) 0)))))

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
