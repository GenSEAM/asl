(module asl/tools/coord/tests/stallTest
  :x [runTests]
  :i [(asl-tools/coord/stall :a sl) (asl-tools/fleet/run :a fr)])

; (:m :ref COND-STALL-AUTO :do "fixture journals for each stall class under a scratch dir in this worktree's .asl/cache, removed by the test; time is the now argument, so ages need no sleeping; the hooks only append to a log file, nothing is killed")
fn ! nowMs -> Int64
  (/ (nowNs) 1000000)

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/stallTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! put path: String text: String -> Bool
  (let [(_ (fr/runOneLimited (fr/job (list "mkdir" "-p" (optionOr (listHead (stringSplit (stringReverse path) "/")) "")) "." (fr/childEnv (list))) (fr/limits 30 4)))] true)

fn ! mk dir: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "mkdir" "-p" dir) "." (fr/childEnv (list))) (fr/limits 30 4)))] (= d.exit 0))

fn turn n: Int64 reply: String -> String
  (str "(:served :turn " (stringFromInt64 n) " :model \"m\")\n(:turn " (stringFromInt64 n) " :reply \"" reply "\")\n")

fn repeated count: Int64 reply: String -> String
  (stringJoin (map (fn [(i Int64)] -> String (turn i reply)) (range 1 (+ count 1))) "")

fn varied count: Int64 -> String
  (stringJoin (map (fn [(i Int64)] -> String (turn i (str "(:step :op read :file f" (stringFromInt64 i) ")"))) (range 1 (+ count 1))) "")

fn cfg -> sl/Cfg
  (sl/cfgOf "(:stall :stalledMin 20 :sameOp 10 :emptyReplies 4 :escalateAfter 2 :everyS 60)")

fn sig journal: String turnAge: Int64 writeAge: Int64 alive: Bool -> sl/Signal
  (sl/signalFrom journal turnAge writeAge alive)

fn min1 -> Int64
  60000

fn testConfig -> Bool
  (let [(off (sl/cfgOf ""))
        (on (cfg))
        (bad (sl/cfgOf "(:stall :sameOp 1)"))
        (unk (sl/cfgErrors "(:stall :bogus 3)"))]
    (do (assert (not off.on) "no row: no sweep")
        (assert (and on.on (and (= on.sameOp 10) (= on.stalledMin 20))) "a valid row is on with its values")
        (assert (not bad.on) "a value outside its range turns the row off")
        (assert (not (listEmpty? unk)) "an unknown key is an error")
        (assert (= (sl/cfgOf "(:stall)").emptyReplies 4) "defaults are the adopted ones")
        true))

fn testVerdicts -> Bool
  (let [(c (cfg))
        (okS (sig (varied 12) (* 2 (min1)) (* 2 (min1)) true))
        (loopS (sig (repeated 12 "(:step :op gate)") 0 0 true))
        (shortLoop (sig (repeated 9 "(:step :op gate)") 0 0 true))
        (emptyS (sig (str (varied 5) (repeated 4 "")) 0 0 true))
        (emptyShort (sig (str (varied 5) (repeated 3 "")) 0 0 true))
        (idle (sig (varied 5) (* 30 (min1)) (* 30 (min1)) true))
        (idleButWriting (sig (varied 5) (* 30 (min1)) (* 1 (min1)) true))
        (silent (sig "" (* 30 (min1)) (* 30 (min1)) true))
        (dead (sig (repeated 12 "(:step :op gate)") 0 0 false))]
    (do (assert (= (sl/verdictOf c okS) "ok") "varied ops with a fresh clock: ok")
        (assert (= (sl/verdictOf c loopS) "looping") "the same op 12 times in a row: looping")
        (assert (= loopS.sameOp 12) (str "the repeat streak is 12: " (stringFromInt64 loopS.sameOp)))
        (assert (= (sl/verdictOf c shortLoop) "ok") "9 repeats stay under sameOp 10")
        (assert (= (sl/verdictOf c emptyS) "looping") "4 empty replies in a row: looping")
        (assert (= emptyS.emptyRun 4) (str "the empty streak is 4: " (stringFromInt64 emptyS.emptyRun)))
        (assert (= (sl/verdictOf c emptyShort) "ok") "3 empty replies stay under emptyReplies 4")
        (assert (= (sl/verdictOf c idle) "stalled") "no turn and no write for 30 min: stalled")
        (assert (= (sl/verdictOf c idleButWriting) "ok") "no turn for 30 min but a write 1 min ago: ok")
        (assert (= (sl/verdictOf c silent) "stalled") "a session with no journal output at all: stalled")
        (assert (= (sl/verdictOf c dead) "dead") "a gone pid is dead even when the trail loops")
        true))

fn testAct -> Bool
  (let [(c (cfg))
        (first (sl/actOf c 0 "looping" "<step :op gate>"))
        (second (sl/actOf c 1 "stalled" ""))]
    (do (assert (stringEmpty? first.lane) "the first stall keeps the lane")
        (assert (= second.lane "strong") "the second stall of one unit escalates to strong")
        (assert (stringContains? first.note "(:stall :class looping :n 1 :op \"<step :op gate>\")") (str "the note carries class, count and op: " first.note))
        (assert (= (sl/stallCount "(:stall :unit \"A\" :class x)\n(:stall :unit \"AB\" :class x)\n(:stall :unit \"A\" :class y)\n" "A") 2) "stalls count per exact unit id")
        true))

fn ! logOf path: String -> String
  (match (fileReadString path) ((ok t) t) ((err _) ""))

fn ! hooks log: String -> sl/Hooks
  (sl/Hooks :kill (fn [(id String)] -> Unit (let [(_ (fileAppend log (str "kill " id "\n")))] ()))
            :requeue (fn [(id String) (lane String) (note String)] -> Unit (let [(_ (fileAppend log (str "requeue " id " " lane " " note "\n")))] ())))

fn ! unitDir! root: String id: String journal: String -> String
  (let [(wt (str root "/wt/" id))
        (jd (str wt "/.asl/run/agentLoop"))
        (_ (mk jd))
        (_ (fileWrite (str jd "/s1.journal") journal))]
    wt)

fn ! testSweep -> Bool
  (let [(root (scratch "sweep"))
        (_ (cleanup root))
        (store (str root "/store"))
        (_ (mk store))
        (log (str root "/log.txt"))
        (hs (hooks log))
        (now (nowMs))
        (loopWt (unitDir! root "LOOP" (repeated 12 "(:step :op gate)")))
        (goodWt (unitDir! root "GOOD" (varied 6)))
        (idleWt (unitDir! root "IDLE" (varied 3)))
        (deadWt (unitDir! root "DEAD" (varied 3)))
        (p (fn [(id String) (wt String) (alive Bool)] -> sl/Probe (sl/Probe :id id :lane "leon" :wt wt :alive alive :sinceMs 0)))
        (probes (list (p "LOOP" loopWt true) (p "GOOD" goodWt true) (p "DEAD" deadWt false)))
        (none (sl/sweep! store now probes hs))
        (_ (fileWrite (str store "/ladder.asn") "(:writers :minFreeMb 2000)\n(:stall :stalledMin 20 :sameOp 10 :emptyReplies 4 :escalateAfter 2 :everyS 60)\n"))
        (rows (sl/sweep! store now probes hs))
        (again (sl/sweep! store (+ now 1000) probes hs))
        (later (sl/sweep! store (+ now 120000) (list (p "LOOP" loopWt true)) hs))
        (idle (sl/sweep! store (+ now 7200000) (list (p "IDLE" idleWt true)) hs))
        (text (logOf log))
        (stalls (logOf (sl/stallsPath store)))
        (_ (cleanup root))]
    (do (assert (listEmpty? none) "without a (:stall ...) row the sweep does nothing")
        (assert (= (listLength rows) 2) (str "the looping and the dead unit are acted on, the good one is not: " (stringJoin rows " ")))
        (assert (stringContains? text "kill LOOP\n") "the looping unit's tree is killed through the hook")
        (assert (stringContains? text "kill DEAD\n") "the dead unit is requeued through the same hook")
        (assert (not (stringContains? text "GOOD")) "an ok unit is never touched")
        (assert (stringContains? text "requeue LOOP leon (:stall :class looping :n 1") "first stall: requeued on its own lane with the class note")
        (assert (listEmpty? again) "a second sweep inside everyS does nothing")
        (assert (= (listLength later) 1) "a sweep after everyS acts again")
        (assert (stringContains? text "requeue LOOP strong (:stall :class looping :n 2") "the second stall of LOOP escalates to the strong lane")
        (assert (= (listLength idle) 1) "a unit with a journal older than stalledMin and no write is stalled")
        (assert (stringContains? stalls "(:stall :unit \"IDLE\" :class stalled ") "the stall row names unit and class")
        true))

fn ! testWrites -> Bool
  (let [(root (scratch "writes"))
        (_ (cleanup root))
        (_ (mk (str root "/src")))
        (_ (mk (str root "/.asl/cache")))
        (_ (fileWrite (str root "/src/a.asl") "a"))
        (_ (fileWrite (str root "/.asl/cache/hot") "x"))
        (w (sl/newestWrite! root))
        (empty (sl/newestWrite! (str root "/nonexistent")))
        (only (str root "-only"))
        (_ (mk (str only "/.asl/cache")))
        (_ (fileWrite (str only "/.asl/cache/hot") "x"))
        (hidden (sl/newestWrite! only))
        (_ (cleanup root))
        (_ (cleanup only))]
    (do (assert (> w 0) "a file under src has a write time")
        (assert (<= w (+ (nowMs) 5000)) "the write time is not in the future")
        (assert (= empty 0) "a missing tree has no write")
        (assert (= hidden 0) "a tree whose only file is under .asl has no write")
        true))

fn ! runTests -> Bool
  (do (assert (testConfig) "config rows: off without a row, ranges, unknown keys")
      (assert (testVerdicts) "verdicts: ok, looping, empty streak, stalled, silent, dead")
      (assert (testAct) "acts: lane kept, escalation after K, note text, per-unit count")
      (assert (testSweep) "sweep: acts per verdict through the hooks, rate limit, escalation, rows")
      (assert (testWrites) "newest write walk skips .asl")
      true)
