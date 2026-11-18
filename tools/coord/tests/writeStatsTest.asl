(module asl/tools/coord/tests/writeStatsTest
  :x [runTests]
  :i [(asl-tools/coord/writeStats :a ws)])

; (:m :ref WRITE-OUTCOME-STATS :do "fixture journal in a scratch dir under this worktree's .asl/cache, removed by the test; time is the --now argument; the invalid-UTF-8 row is built from bytes with a 0xFF inside; the tool's main runs in process, no CLI is spawned")
fn now -> Int64
  10000000000

fn scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/writeStatsTest-" (stringFromInt64 (procSelf)))

fn t unit: String from: String to: String stage: String model: String verdict: String ago: Int64 -> String
  (str "(:t :unit \"" unit "\" :from " from " :to " to " :stage " stage " :model \"" model "\" :tokens 0 :costUsd 0.000000 :verdict \"" verdict "\" :ms 5 :at " (stringFromInt64 (- (now) ago)) ")\n")

fn stopV tail: String -> String
  (str "fail: (:agent :status :failed :receipt (:agentReceipt :status :escalated :stop " tail " :lastStep (:turn 12 :op \\\"read\\\") :streak 12))")

fn goodRows -> String
  (str (t "A" "writing" "gating" "write" "leon" "written" 1000)
       (t "B" "writing" "gating" "write" "leon" "written" 2000)
       (t "C" "writing" "ready" "write" "synDs41Flash" (stopV "readStreak") 3000)
       (t "D" "writing" "ready" "write" "synDs41Flash" "stalled" 4000)
       (t "E" "writing" "ready" "write" "" "stalled" 5000)
       (t "F" "writing" "ready" "write" "synDs41Flash" (str "tierHop paid->strong: " (stopV "readStreak")) 6000)
       (t "G" "writing" "ready" "write" "leon" (stopV "gateIntegrity") 7000)
       (t "H" "writing" "ready" "write" "synDs41Flash" "boom: x" 8000)
       (t "A" "claim" "writing" "claim" "" "admitted" 9000)
       (t "A" "reviewing" "merging" "review" "" "pass" 10000)
       (t "B" "reviewing" "merging" "review" "" "pass" 11000)
       (t "C" "reviewing" "ready" "review" "" "fail: ovhGptOss120b: no" 12000)
       (t "D" "reviewing" "ready" "review" "" "deferred" 13000)
       (t "X" "merging" "merged" "merge" "" "merged" 14000)
       (t "X" "merging" "merged" "merge" "" "merged" 15000)
       (t "Y" "merging" "merged" "merge" "" "merged" 16000)
       (t "Z" "merging" "ready" "merge" "" "mergeRedFix 1/2: train red: x" 17000)
       (t "W" "merging" "blocked" "merge" "" "no" 18000)
       (t "V" "merging" "ready" "merge" "" "again" 19000)
       (t "OLD" "writing" "gating" "write" "leon" "written" 90000000)
       (t "OLD" "merging" "merged" "merge" "" "merged" 90000000))

fn cat3 a: Bytes mid: (List Int64) c: Bytes -> Bytes
  (let [(la (bytesLength a)) (lm (listLength mid)) (lc (bytesLength c))
        (b (bytesAlloc (+ la (+ lm lc))))
        (_ (map (fn [(i Int64)] -> Int64 (do (bytesSet b i (bytesGet a i)) i)) (range 0 la)))
        (_ (fold (fn [(i Int64) (v Int64)] -> Int64 (do (bytesSet b (+ la i) v) (+ i 1))) 0 mid))
        (_ (map (fn [(i Int64)] -> Int64 (do (bytesSet b (+ la (+ lm i)) (bytesGet c i)) i)) (range 0 lc)))]
    b)

fn ! writeJournal! dir: String -> Bool
  (let [(bad (t "BAD" "writing" "ready" "write" "leon" "written" 1500))
        (cutAt (optionOr (stringIndexOf bad "written") 0))
        (head (optionOr (stringSlice bad 0 cutAt) ""))
        (rest (optionOr (stringSlice bad cutAt (stringLength bad)) ""))
        (trunc (optionOr (stringSlice (t "TR" "writing" "ready" "write" "leon" "written" 1600) 0 90) ""))
        (pre (str (goodRows) trunc "\nhello\n\n"))
        (bytes (cat3 (stringToBytes (str pre head)) (list 255) (stringToBytes rest)))]
    (and (resultOk? (dirCreate dir)) (resultOk? (fileWrite (str dir "/journal.asn") bytes))))

fn resultOk? r: (Result Unit String) -> Bool
  (match r ((ok _) true) ((err _) false))

fn ! cleanup! dir: String -> Unit
  (let [(_ (pathRemove (str dir "/journal.asn"))) (_ (pathRemove dir))] ())

fn report dir: String hours: Int64 -> String
  (match (ws/reportFor dir hours (now)) ((ok s) s) ((err e) e))

fn has s: String part: String -> Bool
  (stringContains? s part)

fn testClassifiers -> Bool
  (do (assert (= (ws/writeClass "written") "written") "written")
      (assert (= (ws/writeClass "stalled") "stalled") "stalled")
      (assert (= (ws/writeClass (stopV "readStreak")) "readStreak") "stop word after :stop")
      (assert (= (ws/writeClass (str "tierHop paid->strong: " (stopV "gateIntegrity"))) "gateIntegrity") "tierHop carries the stop word")
      (assert (= (ws/writeClass "boom: x") "boom") "first word, colon dropped")
      (assert (= (ws/writeClass "") "other") "empty verdict is other")
      (assert (= (ws/stopWord "a :stop readStreak) b") "readStreak") "stop word ends at a paren")
      (assert (ws/validUtf8? "plain \u{e9} ok") "valid multibyte")
      (assert (not (ws/validUtf8? (bytesToStringRaw))) "lone 0xFF is invalid")
      (match (ws/parseRow (t "U" "writing" "gating" "write" "m" "written" 5))
        ((some r) (assert (and (= r.unit "U") (and (= r.stage "write") (and (= r.model "m") (and (= r.to "gating") (= r.verdict "written"))))) "row fields"))
        ((none) (assert false "a whole row parses")))
      (assert (isNone (ws/parseRow "(:t :unit \"U\" :verdict \"written")) "truncated row does not parse")
      true)

fn bytesToStringRaw -> String
  "a\xffb"

fn isNone o: (Option ws/Row) -> Bool
  (match o ((none) true) ((some _) false))

fn testReport -> Bool
  (let [(dir (scratch))
        (wrote (writeJournal! dir))
        (r (report dir 24))]
    (do (assert wrote "fixture written")
        (assert (has r ":hours 24 :from 9913600000 :to 10000000000 :skipped 3") (str "window and skipped: " r))
        (assert (has r "(:write :n 8 :written 2 :pct 25 (:stop (readStreak 2) (stalled 2) (boom 1) (gateIntegrity 1)))") (str "write: " r))
        (assert (has r "(:m \"leon\" :ok 2 :fail 1)") "model leon")
        (assert (has r "(:m \"synDs41Flash\" :ok 0 :fail 4)") "model synDs")
        (assert (has r "(:m \"unknown\" :ok 0 :fail 1)") "model unknown")
        (assert (has r "(:review :n 4 :pass 2 :fail 1 :other 1)") "review")
        (assert (has r "(:merge :n 6 :merged 3 :red 1 :blocked 1 :retry 1)") "merge")
        (assert (has r "(:units :merged 2)") "distinct merged units")
        (assert (has (report dir 30) "(:write :n 9 :written 3") "a wider window takes the old row")
        (assert (has (report dir 30) "(:units :merged 3)") "the old merged unit joins in a wider window")
        (cleanup! dir)
        true))

; (:m :ref REVIEW-CLIP-FALSE-FAIL :do "start rows are no reviews; a 0 ms written row within 5 s of an earlier written row of its unit is a repeat, counted apart")
fn tm unit: String stage: String verdict: String ms: Int64 at: Int64 -> String
  (str "(:t :unit \"" unit "\" :from a :to b :stage " stage " :model \"m\" :tokens 0 :costUsd 0.000000 :verdict \"" verdict "\" :ms " (stringFromInt64 ms) " :at " (stringFromInt64 at) ")\n")

fn testStartRepeat -> Bool
  (let [(dir (str (scratch) "S"))
        (a (- (now) 100000))
        (rows (str (tm "A" "write" "written" 4000 a) (tm "A" "write" "written" 0 (+ a 1000)) (tm "B" "write" "written" 0 (+ a 50000))
                   (tm "A" "review" "start" 0 (+ a 10000)) (tm "A" "review" "start" 0 (+ a 11000)) (tm "A" "review" "pass" 700 (+ a 12000))))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/journal.asn") (stringToBytes rows)))
        (r (report dir 24))]
    (do (assert (has r "(:review :n 1 :pass 1 :fail 0 :other 0)") (str "start rows are not reviews: " r))
        (assert (has r "(:started :review 2)") "starts counted apart")
        (assert (has r "(:rewrites :n 2)") (str "every written 0 ms row is a rewrite, near or far: " r))
        (assert (has r "(:write :n 3 :written 1 :pct 33") (str "rewrites are not written: " r))
        (cleanup! dir)
        true))

fn testEmptyAndMissing -> Bool
  (let [(dir (str (scratch) "E"))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/journal.asn") ""))
        (r (report dir 24))
        (code (ws/main (list "--store" dir "--hours" "24" "--now" "10000000000")))
        (miss (ws/main (list "--store" (str (scratch) "Nope"))))
        (usage (ws/main (list)))
        (err (match (ws/reportFor (str (scratch) "Nope") 24 (now)) ((err e) e) ((ok _) "")))]
    (do (assert (has r ":skipped 0") "empty journal skips nothing")
        (assert (has r "(:write :n 0 :written 0 :pct 0 (:stop ))") (str "zero writes, no division: " r))
        (assert (has r "(:merge :n 0 :merged 0 :red 0 :blocked 0 :retry 0)") "zero merges")
        (assert (= code (ok 0)) "main on an empty journal exits 0")
        (assert (= miss (ok 1)) "main on a missing store exits non-zero")
        (assert (= usage (ok 2)) "main without --store is a usage error")
        (assert (stringStartsWith? err "(:writeStats :error ") (str "missing store is an ASN error row: " err))
        (cleanup! dir)
        true))

fn ! runTests -> Bool
  (do (assert (testClassifiers) "classifiers and row parsing")
      (assert (testReport) "end to end on the fixture journal")
      (assert (testStartRepeat) "start rows and repeat writes")
      (assert (testEmptyAndMissing) "empty journal and missing store")
      true)
