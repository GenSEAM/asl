(module asl-tools/coord/tests/conductorStage
  :x [main]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref REVIEW-DEFER :do "the fake write tree is a git repo of its own with one commit on main, so commit counts read it and not the worktree the test runs in")
; (:m :ref CONDUCTOR :do "the fixture stage child of conductorTest: write, review and merge are fakes steered by argv (--sleep MS, --claim 1, --verdict V, --tokens N, --cost MICRO, --failsig S, --die 1, --tiers T (review), --mergefail N: the first N merge starts fail with --failsig, --writefail N: only the first N write starts fail with --failsig, 0 = all), gates is the conductor's own gatesRes; every start is appended to <store>/starts.log")
fn res ok: Int64 wt: String branch: String model: String tokens: Int64 cost: Int64 claim: Int64 sig: String verdict: String -> cd/Res
  (cd/Res :tiers "" :ok ok :wt wt :branch branch :model model :tokens tokens :costMicro cost :claimedGreen claim :sig sig :ms 1 :exit 0 :asserts 0 :verdict verdict)

fn ! fakeRes args: (List String) dir: String stage: String id: String -> cd/Res
  (cond
    ((= stage "write")
      (let [(wt (str dir "/wt-" id))
            (_ (dirCreate wt))
            (_ (if (fileExists? (str wt "/.git")) "" (resultOr (fr/shellOut (str "cd " wt " && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base") 60000) "")))
            (n (listLength (filter (fn [(l String)] -> Bool (= l (str id " write"))) (stringLines (resultOr (fileReadString (str dir "/starts.log")) "")))))
            (cap (st/intOpt args "writefail" 0))
            (sig (if (or (= cap 0) (<= n cap)) (st/opt args "failsig" "") ""))]
        (res (if (stringEmpty? sig) 1 0) wt (str "sh/" id) "fakeWriter" (st/intOpt args "tokens" 100) (st/intOpt args "cost" 2500) (st/intOpt args "claim" 0) sig "")))
    ((= stage "review")
      (with (res 0 "" "" "fakeReviewer" (st/intOpt args "tokens" 50) (st/intOpt args "cost" 1000) 0 (st/opt args "failsig" "") (st/opt args "verdict" "pass")) :tiers (st/opt args "tiers" "")))
    (else
      (let [(starts (listLength (filter (fn [(l String)] -> Bool (= l (str id " merge"))) (stringLines (resultOr (fileReadString (str dir "/starts.log")) "")))))]
        (if (<= starts (st/intOpt args "mergefail" 0))
          (res 0 "" "" "" 0 0 0 (st/opt args "failsig" "train red") "")
          (let [(_ (fileAppend (str dir "/merged.log") (str id "\n")))]
            (res 1 "" "" "" 0 0 0 "" ""))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(stage (optionOr (listGet args 1) ""))
        (id (optionOr (listGet args 2) ""))
        (dir (st/opt args "store" ""))
        (_ (fileAppend (str dir "/starts.log") (str id " " stage "\n")))
        (_ (sleepMs (st/intOpt args "sleep" 0)))]
    (if (= (st/intOpt args "die" 0) 1) (ok 1)
      (match (cd/loadUnit! dir id)
        ((none) (ok 2))
        ((some pr)
          (let [(r (if (= stage "gates") (cd/gatesRes 300 (cd/gateCheckS dir) "" (pairFirst pr) (pairSecond pr)) (fakeRes args dir stage id)))]
            (match (cd/writeRes! dir id stage r) ((ok _) (ok 0)) ((err _) (ok 1))))))))
