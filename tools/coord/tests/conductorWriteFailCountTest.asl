(module asl-tools/coord/tests/conductorWriteFailCountTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref WRITE-FAIL-COUNT :do "consecutive write failures of one unit count up whatever the signature text (a write signature carries :turn and :reads that differ per attempt), so the unit reaches maxSame and blocks; a pool-lost failure in between does not count")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/conductorWriteFailCountTest-" (stringFromInt64 (procSelf)) "/" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ctxIn dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "conductorWriteFailCountTest" :ttlMs 600000 :maxWait 30 :maxSame 3 :stageSec 300 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "none"))
          :pace (cd/fixedPace 0 0))

fn unitAt id: String fails: Int64 sig: String -> cd/CUnit
  (cd/CUnit :id id :st "writing" :lane "solo" :fails fails :sig sig :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 1 :await "")

fn wsig turn: Int64 -> String
  (str "write ended :turn " (stringFromInt64 turn) " :op edit :reads (a" (stringFromInt64 turn) " b)")

fn ! testWriteCount -> Bool
  (let [(dir (scratch "a"))
        (_ (cleanup dir))
        (ctx (ctxIn dir))
        (a1 (cd/fail! ctx (unitAt "W1" 0 "") "write" "m" (wsig 1) 1))
        (a2 (cd/fail! ctx (with a1 :st "writing") "write" "m" (wsig 2) 1))
        (p (cd/fail! ctx (with a2 :st "writing") "write" "m" "pool unreachable: connect: io:111" 1))
        (a3 (cd/fail! ctx (with p :st "writing") "write" "m" (wsig 3) 1))
        (ls (cd/fail! ctx (unitAt "W2" 2 "ERR_X other") "write" "m" "leaseLost: lease ended before the pooled run did" 1))
        (st (cd/fail! ctx (unitAt "W3" 2 "ERR_X other") "write" "m" "stalled: no write for 30 min" 1))
        (i1 (cd/fail! ctx (unitAt "W4" 2 "ERR_X other") "write" "m" "worktree attach failed: fatal x" 1))
        (i2 (cd/fail! ctx (unitAt "W5" 2 "ERR_X other") "write" "m" "LEDGER_FORGED: a writer commit touches grades.asn" 1))
        (f1 (cd/fail! ctx (with (unitAt "W6" 0 "") :lane "free") "write" "m" (wsig 1) 1))
        (f2 (cd/fail! ctx (with f1 :st "writing") "write" "m" (wsig 2) 1))
        (f3 (cd/fail! ctx (with f2 :st "writing") "write" "m" "ERR_REPO_GIT: x" 1))
        (m1 (cd/fail! ctx (unitAt "W7" 0 "") "write" "m" (wsig 1) 1))
        (m2 (cd/fail! ctx (with m1 :st "writing") "write" "m" (wsig 2) 1))
        (m3 (cd/fail! ctx (with m2 :st "writing") "write" "m" "stalled: no write for 30 min" 1))
        (m4 (cd/fail! ctx (with m3 :st "writing") "write" "m" (wsig 3) 1))
        (n1 (cd/fail! ctx (unitAt "W8" 2 "ERR_X other") "write" "m" "stage died without a result" 1))
        (n2 (cd/fail! ctx (unitAt "W9" 2 "ERR_X other") "write" "m" "stage run row lost" 1))
        (n3 (cd/fail! ctx (unitAt "WA" 2 "ERR_X other") "write" "m" "stale branch recreate failed: fatal: x" 1))
        (n4 (cd/fail! ctx (unitAt "WB" 2 "stage died without a result") "write" "m" "stage died without a result" 1))
        (g1 (cd/fail! ctx (with (unitAt "WC" 0 "") :lane "free") "write" "m" (wsig 1) 1))
        (g2 (cd/fail! ctx (with g1 :st "writing") "write" "m" (wsig 2) 1))
        (g3 (cd/fail! ctx (with g2 :st "writing") "write" "m" "stage died without a result" 1))
        (d1 (cd/fail! ctx (unitAt "WD" 0 "") "write" "m" "stage died without a result" 1))
        (d2 (cd/fail! ctx (with d1 :st "writing") "write" "m" "stage died without a result" 1))
        (d3 (cd/fail! ctx (with d2 :st "writing") "write" "m" "stage died without a result" 1))
        (d4 (cd/fail! ctx (with d3 :st "writing") "write" "m" "stage died without a result" 1))
        (_ (cleanup dir))]
    (do (assert (and (= d1.fails 0) (= d2.fails 1) (= d3.fails 2)) (str "one died stage does not count, the same one twice in a row does: " (stringFromInt64 d1.fails) " " (stringFromInt64 d2.fails) " " (stringFromInt64 d3.fails)))
        (assert (and (= d4.fails 3) (= d4.st "blocked")) (str "a writer that always dies reaches blocked at the limit: " (stringFromInt64 d4.fails) " " d4.st))
        (assert (and (= n1.fails 2) (and (= n2.fails 2) (= n3.fails 2))) (str "a vanished stage, a lost run row and a stale branch failure leave the count: " (stringFromInt64 n1.fails) " " (stringFromInt64 n2.fails) " " (stringFromInt64 n3.fails)))
        (assert (= n4.fails 3) (str "the same infra signature repeating still counts: " (stringFromInt64 n4.fails)))
        (assert (and (= g3.st "ready") (= g3.lane "free") (= g3.fails 2)) (str "a free unit with two writer failures and a vanished stage stays on free: " g3.st " " g3.lane))
        (assert (and (= i1.fails 2) (= i2.fails 2)) (str "an infra signature leaves the count: " (stringFromInt64 i1.fails) " " (stringFromInt64 i2.fails)))
        (assert (and (= f3.st "ready") (= f3.lane "free") (= f3.fails 2)) (str "a free unit with two writer failures and one infra failure does not hop: " f3.st " " f3.lane " " (stringFromInt64 f3.fails)))
        (assert (and (= m3.fails 2) (= m4.st "blocked")) (str "write write stall write blocks at the limit: " (stringFromInt64 m3.fails) " " m4.st))
        (assert (= ls.fails 2) (str "a lease signature leaves the count: " (stringFromInt64 ls.fails)))
        (assert (= st.fails 2) (str "a stall signature leaves the count: " (stringFromInt64 st.fails)))
        (assert (and (= a1.st "ready") (= a1.fails 1)) (str "first write failure counts one: " a1.st " " (stringFromInt64 a1.fails)))
        (assert (and (= a2.st "ready") (= a2.fails 2)) (str "a second write failure with another signature counts two: " a2.st " " (stringFromInt64 a2.fails)))
        (assert (and (= p.fails 2) (= p.st "ready")) (str "a pool-lost failure in between leaves the count: " (stringFromInt64 p.fails)))
        (assert (and (= a3.fails 3) (= a3.st "blocked")) (str "the third counted failure reaches the limit and blocks: " a3.st " " (stringFromInt64 a3.fails)))
        true))

fn ! runTests -> Bool
  (do (assert (testWriteCount) "write failures count whatever the signature, pool-lost ones do not")
      true)
