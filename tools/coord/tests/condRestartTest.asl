(module asl-tools/coord/tests/condRestartTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (tools/remote/vps :a vps) (tools/remote/coordDeps :a cdp)])

; (:m :ref COND-GRACEFUL-RESTART :do "the restart file drains the conductor loop: an in-flight stage finishes and is journalled, nothing new starts (no admission, no next stage), the loop ends; a stage past the grace deadline is left running and recorded as left; the next start resumes from the rows; stores are scratch dirs under .asl/cache, stages are the conductorStage fixture")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/condRestartTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! fixtureBinary! -> String
  (let [(d (fr/runOneLimited (fr/job (list (fr/nativeCli!) "run" "asl/tools/nativeTest.asl" "prepare" "asl/tools/coord/tests/conductorStage.asl") "." (fr/childEnv (list)))
                             (fr/limits 600 64)))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "/")) (map stringTrim (stringLines d.out))))]
    (if (= d.exit 0) (optionOr (listGet lines (- (listLength lines) 1)) "") ""))

fn greenGate -> String
  (str (fr/stubHostPath) " test green3.asl")

fn task id: String owns: (List String) -> st/Task
  (st/Task :id id :owns owns :reads (list) :gate (greenGate) :channel "leon" :model "fake" :base "main" :after (list) :st "queued" :epoch 0 :receipt "")

; (:m :do "write of A sleeps 2.5 s (finishes inside the grace), write of C sleeps 300 s (outlives the grace and the cold start of the restart CLI, which the test waits for with C already writing, and the conductor stageSec of 900 outlives both)")
fn sleepFor stage: String id: String -> (List String)
  (cond
    ((and (= stage "write") (= id "A")) (list "--sleep" "2500"))
    ((and (= stage "write") (= id "C")) (list "--sleep" "300000"))
    (else (list)))

fn ! ctxOf dir: String bin: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "condRestartTest" :ttlMs 600000 :maxWait 400 :maxSame 3 :stageSec 900 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (listAppend (list bin "stage" stage u.id "--store" dir) (sleepFor stage u.id)))
          :pace (cd/fixedPace 4 4))

fn ! cuOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (cd/CUnit :id "" :st "absent" :lane "" :fails -1 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await ""))

fn ! readOr dir: String name: String -> String
  (resultOr (fileReadString (str dir "/" name)) "")

fn ! tickUntil! ctx: cd/Ctx dir: String id: String st: String max: Int64 -> Bool
  (let [(c (cuOf dir id))]
    (cond
      ((and (= c.st st) (= c.launched 1)) true)
      ((<= max 0) false)
      (else (let [(_ (cd/tick! ctx)) (_ (sleepMs 50))] (tickUntil! ctx dir id st (- max 1))))))

fn ! up? pid: Int64 -> Bool
  (and (> pid 0) (resultOr (procAlive? pid) false))

; (:m :do "A is writing when the restart file appears and B is queued after it: one loop pass waits for A's write, records it, launches neither A's gates nor B, ends the loop and removes the file; a normal drain then merges both")
fn ! testDrain bin: String -> Bool
  (let [(dir (scratch "drain"))
        (_ (cleanup dir))
        (putA (st/put! dir (task "A" (list "p/a"))))
        (ctx (ctxOf dir bin))
        (writing (tickUntil! ctx dir "A" "writing" 40))
        (asked (cd/requestRestart! dir 60))
        (putB (st/put! dir (task "B" (list "p/b"))))
        (t0 (/ (nowNs) 1000000))
        (more (cd/loopOnce! ctx (fn [] -> (List (Pair String Int64)) (list)) (fn [] -> Unit ()) false))
        (ms (- (/ (nowNs) 1000000) t0))
        (a (cuOf dir "A"))
        (b (cuOf dir "B"))
        (starts (readOr dir "starts.log"))
        (journal (readOr dir "journal.asn"))
        (fileLeft (fileExists? (cd/restartPath dir)))
        (ticks (cd/drain! ctx 600))
        (a2 (cuOf dir "A"))
        (b2 (cuOf dir "B"))
        (starts2 (readOr dir "starts.log"))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert (and (ok? putA) (and writing (and asked (ok? putB)))) "A is writing and the restart file is written")
        (assert (not more) "the loop pass under a restart file ends the loop")
        (assert (and (= a.st "gating") (= a.launched 0)) (str "A's write finished and was applied, its gates not launched: " a.st " launched " (stringFromInt64 a.launched)))
        (assert (and (stringContains? starts "A write") (not (stringContains? starts "A gates"))) (str "no next stage started for A: " starts))
        (assert (and (not (stringContains? starts "B ")) (not (= b.st "writing"))) (str "B was not admitted after the file: " b.st " / " starts))
        (assert (stringContains? journal "(:restart :finished (\"A\") :left () ") (str "the restart row records A as finished: " journal))
        (assert (not fileLeft) "the restart file is removed when the loop ends")
        (assert (< ms 120000) (str "the drain ended once nothing was in flight: " (stringFromInt64 ms) " ms"))
        (assert (and (= a2.st "merged") (= b2.st "merged")) (str "the next start resumes A's gates and admits B: " a2.st " " b2.st))
        (assert (and (stringContains? starts2 "A gates") (stringContains? starts2 "B write")) "the resumed run launched what the drain held back")
        true))

; (:m :do "conductor restart (the CLI the deploy runs, here with a long grace, then the file is re-armed with a deadline 60 s in the past right before the loop, so the drain stops after one tick whatever the machine speed) while C's write sleeps 30 s: runLoop! returns 0 after the grace with C recorded as left and its stage still running; a refresh that writes the stop file bounds the loop if the restart file were ignored")
fn ! testDeadline bin: String -> Bool
  (let [(dir (scratch "deadline"))
        (_ (cleanup dir))
        (warm (fr/runOneLimited (fr/job (list (fr/nativeCli!) "run" "asl/tools/coord/conductor.asl" "restart" "--store" (scratch "deadlineWarm") "--grace-sec" "1") "." (fr/childEnv (list))) (fr/limits 600 64)))
        (_ (cleanup (scratch "deadlineWarm")))
        (putC (st/put! dir (task "C" (list "p/c"))))
        (ctx (ctxOf dir bin))
        (writing (tickUntil! ctx dir "C" "writing" 40))
        (cli (fr/runOneLimited (fr/job (list (fr/nativeCli!) "run" "asl/tools/coord/conductor.asl" "restart" "--store" dir "--grace-sec" "600") "." (fr/childEnv (list))) (fr/limits 600 64)))
        (row (readOr dir "restart"))
        (until (cd/restartUntil! dir))
        (graceMs (- until (/ (nowNs) 1000000)))
        (rearmed (cd/requestRestart! dir (- 0 60)))
        (t0 (/ (nowNs) 1000000))
        (code (cd/runLoop! ctx (fn [] -> (List (Pair String Int64)) (list)) (fn [] -> Unit (let [(_ (cd/requestStop! dir))] ())) 0 0 1))
        (ms (- (/ (nowNs) 1000000) t0))
        (c (cuOf dir "C"))
        (pid (match (cd/runRow dir "C" "write") ((some r) (pairFirst r)) ((none) -1)))
        (alive (up? pid))
        (journal (readOr dir "journal.asn"))
        (restartLeft (fileExists? (cd/restartPath dir)))
        (stopLeft (fileExists? (cd/stopPath dir)))
        (diag (str " / restartFile " (if restartLeft "yes" "no") " stopFile " (if stopLeft "yes" "no") " code " (stringFromInt64 code) " ms " (stringFromInt64 ms) " cst " c.st " launched " (stringFromInt64 c.launched) " alive " (if alive "yes" "no") " cli " (stringFromInt64 cli.exit) " rows " (stringFromInt64 (listLength (stringLines journal))) " starts [" (stringJoin (stringLines (readOr dir "starts.log")) ",") "] cRunRow " (match (cd/runRow dir "C" "write") ((some r) (str (stringFromInt64 (pairFirst r)) "/" (stringFromInt64 (pairSecond r)))) ((none) "none")) " bin " bin " binExists " (if (fileExists? bin) "yes" "no")))
        (stopped (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert (and (ok? putC) writing) "C is writing")
        (assert (and (= cli.exit 0) (stringContains? cli.out "(:restart :requested true)")) (str "conductor restart writes the file: " cli.out))
        (assert (and (>= graceMs 590000) (<= graceMs 600000)) (str "the CLI --grace-sec 600 sets the deadline 590 to 600 s ahead: " (stringFromInt64 graceMs) " ms"))
        (assert (and (stringContains? row ":untilMs ") (> until 0)) (str "the file carries its deadline: " row))
        (assert (and rearmed (= code 0)) (str "the loop ends with exit 0: " (stringFromInt64 code)))
        (assert (stringContains? journal "(:restart :finished ") (str "a restart row exists: the drain ran and was not preempted by the stop file" diag " / " journal))
        (assert (stringContains? journal "(:restart :finished () :left (\"C\") ") (str "C is recorded as left at the deadline: " journal diag))
        (assert (< ms 120000) (str "the drain stops at the grace deadline, not at C's end: " (stringFromInt64 ms) " ms"))
        (assert (and (= c.st "writing") (and (= c.launched 1) alive)) (str "C's stage is left running for the next start: " c.st " alive " (if alive "true" "false")))
        (assert (= stopped 1) "the fixture stops C's stage")
        true))

; (:m :do "vps sync --deploy runs conductor restart only when the deployed range touches asl/tools/coord")
fn ! testDeployRange -> Bool
  (do (assert (vps/coordTouched? "tools/remote/vps.asl\nasl/tools/coord/conductor.asl\n") "a coord path in the range restarts the conductor")
      (assert (vps/coordTouched? "asl/tools/fleet/run.asl\n") "without an import closure any changed path restarts (fails closed)")
      (assert (not (cdp/coordTouchedIn? "asl/tools/fleet/run.asl\nasl/tools/coordinate.asl\n" (list "asl/tools/coord/conductor.asl"))) "with a closure, paths outside asl/tools/coord/ and outside the closure do not")
      (assert (cdp/coordTouchedIn? "asl/tools/fleet/run.asl\n" (list "asl/tools/coord/conductor.asl" "asl/tools/fleet/run.asl")) "with a closure, a changed closure member outside asl/tools/coord/ does")
      (assert (not (vps/coordTouched? "")) "an empty range does not")
      true)

fn ! runTests -> Bool
  (let [(bin (fixtureBinary!))
        (stub (fr/stubHost!))]
    (do (assert (not (stringEmpty? stub)) "the stand-in host for declared-form gates is written")
        (assert (not (stringEmpty? bin)) "the fixture stage binary is prepared")
        (assert (testDrain bin) "a restart drains in-flight stages and launches nothing")
        (assert (testDeadline bin) "a restart past its grace exits 0 and leaves the stage")
        (assert (testDeployRange) "deploy restarts only on coord changes")
        (fr/stubRemove!)))
