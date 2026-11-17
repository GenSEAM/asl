(module asl-tools/coord/tests/writerAdmitTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref WRITER-ADMIT-DECOUPLE :do "writer admission without a CPU token, merging units holding no scheduler slot, and the (:readyHold) status row and (:idle) journal row that say why ready units wait; stores are scratch dirs under this worktree's .asl/cache with a fake jobserver dir and meminfo, the launch is /usr/bin/true through run.asl's spawnSep, so no stage and no host starts")

fn ! ctxFor dir: String slots: Int64 perLane: Int64 -> cd/Ctx
  (cd/Ctx :dir dir :holder "writerAdmitTest" :ttlMs 3600000 :maxWait 50 :maxSame 3 :stageSec 30 :maxDesc 20
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace slots perLane))

; (:m :do "a store with a jobserver of tokens tokens, held of them held by this live process, MemAvailable memMb, and the ladder text with JS and MI replaced by the jobserver dir and the meminfo path")
fn ! storeOf root: String name: String tokens: Int64 held: Int64 memMb: Int64 ladder: String -> String
  (let [(dir (str root "/" name))
        (js (str dir "/js"))
        (_ (dirCreate dir))
        (_ (dirCreate (str dir "/tasks")))
        (_ (dirCreate (str js "/tokens")))
        (_ (fileWrite (str js "/config.asn") (str "(:cfg :tokens " (stringFromInt64 tokens) ")\n")))
        (_ (map (fn [(i Int64)] -> Bool (ok? (fileWrite (str js "/tokens/tok" (stringFromInt64 i)) (str "(:tok :ownerPid " (stringFromInt64 (procSelf)) " :cls train)\n")))) (range 0 held)))
        (_ (fileWrite (str dir "/mi") (str "MemTotal: 16000000 kB\nMemAvailable: " (stringFromInt64 (* memMb 1024)) " kB\n")))
        (_ (fileWrite (str dir "/ladder.asn") (str (stringReplace (stringReplace ladder "JS" (str "\"" js "\"")) "MI" (str "\"" dir "/mi\"")) "\n")))]
    dir)

fn ! ready! dir: String id: String lane: String -> st/Task
  (let [(u (with (pf/unitIn id "true") :channel lane :owns (list (str "p/" id ".txt"))))
        (_ (st/put! dir u))
        (_ (cd/writeCUnit! dir (with (pf/cuIn id "ready" "" "") :lane lane)))]
    u)

fn ! row! dir: String c: cd/CUnit -> Bool
  (ok? (cd/writeCUnit! dir c))

fn ! stOf dir: String id: String -> String
  (match (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) ((some c) c.st) ((none) "absent"))

fn ! claims dir: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (listGet (stringSplit l "\"") 1) ""))
       (filter (fn [(l String)] -> Bool (stringContains? l " :stage claim ")) (stringLines (resultOr (fileReadString (cd/journalPath dir)) ""))))

fn ! idleRows dir: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:idle ")) (stringLines (resultOr (fileReadString (cd/journalPath dir)) "")))

fn countOf counts: (List (Pair String Int64)) k: String -> Int64
  (optionOr (listHead (map (fn [(p (Pair String Int64))] -> Int64 (pairSecond p)) (filter (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) k)) counts))) -1)

fn ladderOf extra: String -> String
  (str "(:writers :minFreeMb 2000 :warmFirst false :jobserver JS :meminfo MI" extra ")")

fn merging id: String -> cd/CUnit
  (with (pf/cuIn id "merging" "" (str "sh/" id)) :lane "m" :launched 1)

fn ! runTests -> Bool
  (let [(root (pf/scratch "writerAdmit" "w"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (dTok (storeOf root "tok" 4 4 8000 (ladderOf "")))
        (_ (ready! dTok "R1" "free"))
        (_ (cd/tick! (ctxFor dTok 4 4)))
        (tokSt (stOf dTok "R1"))
        (tokClaims (claims dTok))
        (dNeed (storeOf root "need" 4 4 8000 (ladderOf " :needToken true")))
        (_ (ready! dNeed "R1" "free"))
        (needCounts (cd/readyHoldCounts! (ctxFor dNeed 4 4)))
        (_ (cd/tick! (ctxFor dNeed 4 4)))
        (needSt (stOf dNeed "R1"))
        (needClaims (claims dNeed))
        (badNeed (cd/wrErrors "(:writers :needToken maybe)"))
        (dMerge (storeOf root "merge" 4 0 8000 ""))
        (_ (map (fn [(id String)] -> Bool (row! dMerge (merging id))) (list "M1" "M2" "M3" "M4")))
        (_ (ready! dMerge "R1" "free"))
        (_ (cd/tick! (ctxFor dMerge 4 8)))
        (mergeSt (stOf dMerge "R1"))
        (dFix (storeOf root "fix" 4 0 8000 ""))
        (fixer (with (pf/cuIn "X1" "writing" "" "sh/X1") :lane "m" :launched 1 :sig "mergeRedFix 1/2: train red: a.asl"))
        (_ (row! dFix fixer))
        (_ (row! dFix (merging "M1")))
        (_ (ready! dFix "R1" "free"))
        (fixCounts (cd/readyHoldCounts! (ctxFor dFix 1 8)))
        (_ (cd/tick! (ctxFor dFix 1 8)))
        (fixSt (stOf dFix "R1"))
        (dMem (storeOf root "mem" 4 0 1000 (ladderOf "")))
        (_ (ready! dMem "R1" "free"))
        (memCounts (cd/readyHoldCounts! (ctxFor dMem 4 4)))
        (_ (cd/tick! (ctxFor dMem 4 4)))
        (memSt (stOf dMem "R1"))
        (dMix (storeOf root "mix" 4 4 8000 (ladderOf "")))
        (_ (map (fn [(p (Pair String String))] -> st/Task (ready! dMix (pairFirst p) (pairSecond p))) (list (pair "A1" "a") (pair "A2" "a") (pair "A3" "a") (pair "B1" "b") (pair "B2" "b"))))
        (mixCtx (ctxFor dMix 3 2))
        (mixCounts (cd/readyHoldCounts! mixCtx))
        (mixText (cd/readyHoldText! mixCtx))
        (mixStatus (cd/status! mixCtx))
        (_ (cd/tick! mixCtx))
        (mixClaims (listSort (claims dMix)))
        (dIdle (storeOf root "idle" 4 0 1000 (ladderOf " :idleMin 0")))
        (_ (ready! dIdle "R1" "free"))
        (idleCtx (ctxFor dIdle 4 4))
        (_ (cd/tick! idleCtx))
        (idle1 (listLength (idleRows dIdle)))
        (_ (cd/tick! idleCtx))
        (_ (cd/tick! idleCtx))
        (idle3 (idleRows dIdle))
        (idleOff (cd/wrErrors "(:writers :idleMin 99999)"))
        (_ (map (fn [(d String)] -> Int64 (cd/stopAll! (ctxFor d 1 1))) (list dTok dNeed dMerge dFix dMem dMix dIdle)))
        (_ (pf/cleanup root))]
    (do (assert (and (= tokSt "writing") (= tokClaims (list "R1"))) (str "every jobserver token held by a train, memory and a slot free: the writer is admitted: " tokSt " " (stringJoin tokClaims ",")))
        (assert (and (= needSt "ready") (listEmpty? needClaims)) (str "with :needToken true the same unit waits for a token as before: " needSt))
        (assert (= (countOf needCounts "token") 1) "and the status counts it under token")
        (assert (not (listEmpty? badNeed)) "a :needToken value other than true or false rejects the row")
        (assert (= mergeSt "writing") (str "four launched merging units with no model child leave the 4 slots free: " mergeSt))
        (assert (not (cd/slotHolder? (merging "M1"))) "a launched merging unit holds no slot")
        (assert (cd/slotHolder? fixer) "a running merge-red fix writer holds one")
        (assert (= fixSt "ready") (str "one slot, taken by the merge-red fix writer: the ready unit waits: " fixSt))
        (assert (= (countOf fixCounts "cap") 1) "and the status counts it under cap")
        (assert (= memSt "ready") (str "MemAvailable under the floor still holds the writer: " memSt))
        (assert (= (countOf memCounts "memory") 1) "and the status counts it under memory")
        (assert (and (= (countOf mixCounts "admit") 3) (and (= (countOf mixCounts "lane") 1) (= (countOf mixCounts "cap") 1))) (str "mixed store, 3 slots and 2 per lane: admit 3, lane 1, cap 1: " mixText))
        (assert (= mixClaims (list "A1" "A2" "B1")) (str "the claim admits exactly the units the status row lets through: " (stringJoin mixClaims ",")))
        (assert (stringContains? mixStatus "(:readyHold :ready 5 :slots 3 :free 3 :admit 3 :cap 1 :lane 1 ") (str "status prints the row: " mixText))
        (assert (stringContains? mixText " :disk ok)") (str "and the disk level: " mixText))
        (assert (= idle1 0) "the first idle tick only marks the episode")
        (assert (= (listLength idle3) 1) (str "one (:idle) row per episode: " (stringJoin idle3 " | ")))
        (assert (stringContains? (optionOr (listHead idle3) "") ":top memory ") (str "naming the top hold: " (optionOr (listHead idle3) "")))
        (assert (not (listEmpty? idleOff)) ":idleMin outside 0..10080 rejects the row")
        true))
