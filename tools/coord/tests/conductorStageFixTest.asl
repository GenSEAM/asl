(module asl-tools/coord/tests/conductorStageFixTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref REVIEW-BLOCK-REASON :do "a blocked review writes block: REASON into its journal row, the bare word when the stage has no signature; and GATE-CACHE-FAULT: a gate that dies on the native cache runs once more and a second fault is gateInfra, never the cache text")
fn ! journalOf root: String -> String
  (resultOr (fileReadString (cd/journalPath (str root "/store"))) "")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "stageFixTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 4 4))

fn resOf verdict: String sig: String -> cd/Res
  (cd/Res :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict verdict :tiers "")

fn ! blockOf! root: String id: String sig: String -> Bool
  (let [(dir (str root "/store"))
        (u (pf/unitIn id "sh check.sh impl.txt"))
        (_ (st/put! dir u))
        (_ (cd/writeCUnit! dir (pf/cuIn id "reviewing" "" (str "sh/" id))))
        (c (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" "")))
        (_ (cd/finish! (ctxFor root) u c (resOf "block" sig)))]
    true)

fn ! testBlock -> Bool
  (let [(root (pf/scratch "stageFix" "block"))
        (_ (pf/cleanup root))
        (_ (dirCreate (str root "/store/tasks")))
        (_ (blockOf! root "B1" "reviewDefects: 2 findings, first: the gate was weakened"))
        (_ (blockOf! root "B2" ""))
        (j (journalOf root))
        (rows (stringLines j))
        (rowOf (fn [(id String)] -> String (optionOr (listFind (fn [(l String)] -> Bool (and (stringContains? l (str "(:t :unit \"" id "\" ")) (stringContains? l ":to blocked"))) rows) "NOROW")))
        (r1 (rowOf "B1"))
        (r2 (rowOf "B2"))
        (_ (pf/cleanup root))]
    (do (assert (stringContains? r1 ":verdict \"block: reviewDefects: 2 findings, first: the gate was weakened\"") (str "a review block journals its reason: " r1))
        (assert (stringContains? r2 ":verdict \"block\"") (str "a block without a signature stays the bare word: " r2))
        (assert (and (= (cd/blockVerdict "") "block") (= (cd/blockVerdict "why") "block: why")) "blockVerdict")
        true))

fn ! testGateRetry -> Bool
  (let [(root (pf/scratch "stageFix" "gate"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (fault "echo \"ERR_NATIVE_UNSUPPORTED: cannot write /h/.asl/run/nativeTest/a/b.part.o: No such file or directory\"")
        (once (str "echo x >> n1; if [ $(wc -l < n1) -lt 2 ]; then " fault "; exit 1; fi; echo \"(:gate :asserts 1 :failed 0)\"; exit 0"))
        (always (str "echo x >> n2; " fault "; exit 1"))
        (plain "echo x >> n3; echo \"(:gate :asserts 1 :failed 1)\"; echo \"FAIL one\"; exit 1")
        (d1 (cd/gateRunRetry! once root 60))
        (d2 (cd/gateRunRetry! always root 60))
        (d3 (cd/gateRunRetry! plain root 60))
        (runs (fn [(f String)] -> Int64 (listLength (stringLines (stringTrim (resultOr (fileReadString (str root "/" f)) ""))))))
        (n1 (runs "n1"))
        (n2 (runs "n2"))
        (n3 (runs "n3"))
        (_ (pf/cleanup root))]
    (do (assert (and (= d1.exit 0) (= n1 2)) (str "a cache fault runs the gate once more and the second run answers: exit " (stringFromInt64 d1.exit) " runs " (stringFromInt64 n1)))
        (assert (and (= n2 2) (not (stringContains? d2.out "ERR_NATIVE_UNSUPPORTED")) (stringStartsWith? d2.out "gateInfra:")) (str "a second fault is gateInfra without the cache text: " d2.out " runs " (stringFromInt64 n2)))
        (assert (and (= n3 1) (stringContains? d3.out "FAIL one")) (str "an ordinary red gate is not retried: runs " (stringFromInt64 n3)))
        true))

; (:m :ref GATE-CACHE-FAULT :do "through the gating stage: gatesRes retries a gate that hit the cache fault once and a unit whose second run passes is green")
fn ! testGateWire -> Bool
  (let [(root (pf/scratch "stageFix" "wire"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (repo (pf/repoIn root))
        (fault "echo \"ERR_NATIVE_UNSUPPORTED: cannot write /h/b.part.o: No such file or directory\"")
        (gate (str "echo x >> ../gn; if [ $(wc -l < ../gn) -lt 2 ]; then " fault "; exit 1; fi; echo \"(:gate :asserts 1 :failed 0)\"; exit 0"))
        (u (pf/unitIn "GW1" gate))
        (c (with (pf/cuIn "GW1" "gating" repo "sh/GW1") :lane "free"))
        (r (cd/gatesRes 60 60 "" u c))
        (n (listLength (stringLines (stringTrim (resultOr (fileReadString (str root "/gn")) "")))))
        (_ (pf/cleanup root))]
    (do (assert (and (= r.exit 0) (= n 2) (not (stringContains? r.sig "ERR_NATIVE_UNSUPPORTED"))) (str "the gating stage retries a cache fault once: exit " (stringFromInt64 r.exit) " runs " (stringFromInt64 n) " " r.sig))
        true))

; (:m :ref GATE-CACHE-FAULT-FIX :do "the fault text beside a green exit stays green, beside a real FAIL line it hides nothing, a second fault alone becomes gateInfra with the other lines kept; gateInfra creates no fix round: the gates stage repeats without a model, the third in a row blocks, no prior note and no debt")
fn ! testFaultKinds -> Bool
  (let [(root (pf/scratch "stageFix" "kinds"))
        (_ (pf/cleanup root))
        (_ (dirCreate (str root "/store/tasks")))
        (fault "echo \"ERR_NATIVE_UNSUPPORTED: cannot write /h/b.part.o: No such file or directory\"")
        (green (str "echo x >> ng; " fault "; echo \"(:gate :asserts 2 :failed 0)\"; exit 0"))
        (mixed (str "echo x >> nm; " fault "; echo \"FAIL one (ERR_ASSERT: nope)\"; exit 1"))
        (d1 (cd/gateRunRetry! green root 60))
        (d2 (cd/gateRunRetry! mixed root 60))
        (runs (fn [(f String)] -> Int64 (listLength (stringLines (stringTrim (resultOr (fileReadString (str root "/" f)) ""))))))
        (dir (str root "/store"))
        (ctx (ctxFor root))
        (u (pf/unitIn "GI" "sh check.sh impl.txt"))
        (_ (st/put! dir u))
        (c0 (with (pf/cuIn "GI" "gating" "" "sh/GI") :lane "free"))
        (infra "gateInfra: native test cache fault (a .part.o file vanished), not a model failure")
        (g1 (cd/fail! ctx c0 "gates" "m" infra 1))
        (g2 (cd/fail! ctx g1 "gates" "m" infra 1))
        (g3 (cd/fail! ctx g2 "gates" "m" infra 1))
        (prior (resultOr (fileReadString (cd/failHeadPath dir "GI")) "NONE"))
        (priorTxt (resultOr (fileReadString (str dir "/runs/GI-prior.txt")) "NONE"))
        (res (cd/gateDoneRes (fr/Done :idx 0 :exit 1 :out (str infra "\nFAIL other") :ms 1 :verdict "exit")))
        (_ (pf/cleanup root))]
    (do (assert (and (= d1.exit 0) (and (= (runs "ng") 1) (and (stringContains? d1.out "asserts 2") (not (stringStartsWith? d1.out "gateInfra:"))))) (str "a green gate with the fault text stays green and is not rerun: " (stringFromInt64 d1.exit) " " (stringFromInt64 (runs "ng"))))
        (assert (and (= d2.exit 1) (stringContains? d2.out "FAIL one") (not (stringStartsWith? d2.out "gateInfra:")) (= (runs "nm") 1)) (str "a real FAIL beside the fault text is kept and not hidden: " d2.out))
        (assert (and (= g1.st "gating") (= g2.st "gating") (= g3.st "blocked")) (str "gateInfra repeats the gates stage twice and the third blocks: " g1.st " " g2.st " " g3.st))
        (assert (and (= prior "NONE") (= priorTxt "NONE")) (str "gateInfra leaves no debt and no prior note: " prior " " priorTxt))
        (assert (stringStartsWith? res.sig "gateInfra:") (str "the gate signature is the gateInfra line: " res.sig))
        true))

; (:m :ref GATE-INFRA-RUN :do "gateInfra is counted in a row from the journal and never in c.fails: from fails 2 one gateInfra neither blocks nor changes rung or fails, three in a row block, a gates row in between restarts the count; a handoffConflict blocks at once, and a real FAIL beside the cache text is the signature")
fn ! testInfraRun -> Bool
  (let [(root (pf/scratch "stageFix" "infra"))
        (_ (pf/cleanup root))
        (_ (dirCreate (str root "/store/tasks")))
        (dir (str root "/store"))
        (ctx (ctxFor root))
        (infra "gateInfra: native test cache fault (a .part.o file vanished), not a model failure")
        (two (fn [(id String)] -> cd/CUnit (with (pf/cuIn id "gating" "" (str "sh/" id)) :fails 2)))
        (a1 (cd/fail! ctx (two "GJ") "gates" "m" infra 1))
        (b1 (cd/fail! ctx (two "GK") "gates" "m" infra 1))
        (b2 (cd/fail! ctx b1 "gates" "m" infra 1))
        (b3 (cd/fail! ctx b2 "gates" "m" infra 1))
        (c1 (cd/fail! ctx (two "GL") "gates" "m" infra 1))
        (_ (fileAppend (cd/journalPath dir) "(:t :unit \"GL\" :from gating :to awaitReview :stage gates :model \"\" :tokens 0 :costUsd 0 :verdict \"pass\" :ms 1 :at 5)\n"))
        (c2 (cd/fail! ctx c1 "gates" "m" infra 1))
        (c3 (cd/fail! ctx c2 "gates" "m" infra 1))
        (h (cd/fail! ctx (with (pf/cuIn "GH" "writing" "" "sh/GH") :lane "free") "write" "m" "handoffConflict: sh/X does not apply onto main: x" 1))
        (res (cd/gateDoneRes (fr/Done :idx 0 :exit 1 :out "native step: ERR_NATIVE_UNSUPPORTED: cannot write /h/b.part.o: No such file or directory\nFAIL one: the unit check failed" :ms 1 :verdict "exit")))
        (_ (pf/cleanup root))]
    (do (assert (and (= a1.st "gating") (= a1.fails 2) (= a1.lane "free")) (str "from fails 2 one gateInfra neither blocks nor spends a rung: " a1.st " " (stringFromInt64 a1.fails) " " a1.lane))
        (assert (and (= b2.st "gating") (= b3.st "blocked") (stringContains? b3.sig "gateInfra") (= b3.fails 2)) (str "three in a row block with the gateInfra reason, fails untouched: " b2.st " " b3.st " " (stringFromInt64 b3.fails)))
        (assert (and (= c1.st "gating") (= c2.st "gating") (= c3.st "gating")) (str "gateInfra, a gates row, gateInfra, gateInfra is not blocked: " c3.st))
        (assert (and (= h.st "blocked") (stringStartsWith? h.sig "handoffConflict:") (= h.lane "free")) (str "a handoffConflict blocks at once without a rung change: " h.st " " h.lane))
        (assert (and (stringContains? res.sig "FAIL one") (not (stringContains? res.sig "ERR_NATIVE_UNSUPPORTED"))) (str "a real FAIL beside the cache text is the signature: " res.sig))
        true))

fn ! runTests -> Bool
  (do (assert (testBlock) "a review block journals its reason")
      (assert (testGateRetry) "a native cache fault runs the gate once more")
      (assert (testInfraRun) "gateInfra counted in a row, not in fails; handoffConflict blocks at once")
      (assert (testFaultKinds) "cache fault kinds and gateInfra never create a fix round")
      (assert (testGateWire) "gatesRes retries a cache fault once")
      true)
