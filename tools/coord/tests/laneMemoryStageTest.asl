(module asl-tools/coord/tests/laneMemoryStageTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "the real review stage child (bin/asl run conductor.asl stage review UNIT --lane-ttl-sec 3600, then the :until of every row is rewritten to 1 instead of waiting out a window) against a stand-in hub (fixtures/hubStatusStub.asl) that answers HTTP 400 with a JSON insufficient-credits body: review A calls the hub and stores laneDead rows with cause credits and the lead key lane:credits, review B inside the ttl makes no hub call, review C after the ttl calls again; so the realReview wiring and the flag plumbing are both gated")
fn ! startStatusHub! root: String -> Int64
  (let [(h (pf/here))
        (sock (str root "/hub.sock"))
        (g (fr/guardStart! (list (str h "/bin/asl") "run" (str h "/asl/tools/coord/tests/fixtures/hubStatusStub.asl") sock (str root "/hubSeen.txt") (str root "/hubReply.txt") "400" "100") h (fr/childEnv (list)) (fr/limits 460 50)))]
    (match g
      ((err _) 0)
      ((ok r) (if (pf/listenWait! sock 1200) r.run.pid (do (fr/killTree! r.run.pid) 0)))))

fn calls root: String -> Int64
  (listLength (stringSplit (pf/hubSeen root) "\n----\n"))

fn countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "expiry without a clock: every :until N in the ledger becomes :until 1, so review C sees an elapsed window at any load")
fn digitEnd seg: String i: Int64 -> Int64
  (if (and (< i (stringLength seg)) (stringContains? "0123456789" (optionOr (stringSlice seg i (+ i 1)) ""))) (digitEnd seg (+ i 1)) i)

fn untilOne seg: String -> String
  (str "1" (optionOr (stringSlice seg (digitEnd seg 0) (stringLength seg)) ""))

fn ! expireAll! path: String -> Bool
  (let [(parts (stringSplit (resultOr (fileReadString path) "") " :until "))
        (out (str (optionOr (listHead parts) "") (stringJoin (map (fn [(g String)] -> String (str " :until " (untilOne g))) (listDrop parts 1)) "")))]
    (ok? (fileWrite path out)))

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "the flock gate: 6 forked writers each remember one distinct lane for 4 rounds against one ledger; under the lock every lane survives, without it read-modify-write rounds drop each other's rows")
fn ! writerRound! dir: String i: Int64 -> Int64
  (fold (fn [(acc Int64) (k Int64)] -> Int64
          (match (cd/rememberDeadLanes! dir 3600 1000000 (list (str "(:laneUnavailable :lane w" (stringFromInt64 i) "k" (stringFromInt64 k) " :why \"w\" :unit \"U\")")))
            ((ok _) acc) ((err _) (+ acc 1))))
        0 (list 0 1 2 3))

fn ! testLockedWriters -> Bool
  (let [(dir (pf/scratch "laneLock" "s"))
        (_ (pf/cleanup dir))
        (_ (dirCreate dir))
        (errs (parMap (fn [(i Int64)] -> Int64 (writerRound! dir i)) (list 0 1 2 3 4 5) 6))
        (text (resultOr (fileReadString (str dir "/laneDead.asn")) ""))
        (n (countOf text "(:laneDead "))
        (_ (pf/cleanup dir))]
    (do (assert (= (fold (fn [(a Int64) (e Int64)] -> Int64 (+ a e)) 0 errs) 0) "no locked write failed")
        (assert (= n 24) (str "every writer's rows survive the concurrent read-modify-write: " (stringFromInt64 n) " of 24"))
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "laneMem" "s"))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (prep (pf/prepare! root))
        (_ (fileWrite (str root "/hubReply.txt") "HTTP 400 {\"error\":{\"message\":\"Insufficient credits. Add credits to continue.\",\"code\":\"insufficient_credits\"}}"))
        (hub (startStatusHub! root))
        (env (pf/envFor root))
        (uA (pf/unitIn "LA" "sh check.sh impl.txt"))
        (uB (pf/unitIn "LB" "sh check.sh impl.txt"))
        (uC (pf/unitIn "LC" "sh check.sh impl.txt"))
        (wts (list (pf/seedUnit! root uA "reviewing" "impl.txt") (pf/seedUnit! root uB "reviewing" "impl.txt") (pf/seedUnit! root uC "reviewing" "impl.txt")))
        (rcpts (and (pf/receiptFor! root "LA") (and (pf/receiptFor! root "LB") (pf/receiptFor! root "LC"))))
        (flag (list "--lane-ttl-sec" "3600"))
        (dA (pf/stageChild! root "review" "LA" flag env 400))
        (nA (calls root))
        (resA (pf/readResOf! root "LA" "review"))
        (deadA (resultOr (fileReadString (str root "/store/laneDead.asn")) ""))
        (leadA (resultOr (fileReadString (str root "/lead/stream.asn")) ""))
        (dB (pf/stageChild! root "review" "LB" flag env 400))
        (nB (calls root))
        (resB (pf/readResOf! root "LB" "review"))
        (_ (expireAll! (str root "/store/laneDead.asn")))
        (dC (pf/stageChild! root "review" "LC" flag env 400))
        (nC (calls root))
        (_ (pf/stopHub! hub))
        (_ (pf/cleanup root))
        (_ (fr/stubRemove!))]
    (do (assert (and (not (stringEmpty? repo)) (and prep (and (> hub 0) rcpts))) "fixture: repo, store, status hub up, three reviewing units")
        (assert (and (= dA.exit 0) (> nA 1)) (str "review A: the stage child exits 0 and reaches the hub: " (stringFromInt64 dA.exit) " calls " (stringFromInt64 nA) " " dA.out))
        (assert (and (> (countOf deadA "(:laneDead ") 0) (stringContains? deadA ":cause credits") (not (stringContains? deadA ":cause permanent"))) (str "review A stores the dead lanes with cause credits, the JSON why kept whole: " deadA))
        (assert (stringContains? leadA "lane") (str "review A raised a lane warn in the lead stream: " leadA))
        (assert (stringContains? leadA ":credits") (str "the lead key carries the cause credits, not permanent: " leadA))
        (assert (= (pf/verdictOf resA) "block") (str "review A with every lane dead blocks: " (pf/verdictOf resA) " " (pf/sigOf resA)))
        (assert (and (= nB nA) (= dB.exit 0)) (str "review B inside the ttl makes no hub call: " (stringFromInt64 nA) " -> " (stringFromInt64 nB)))
        (assert (and (= (pf/verdictOf resB) "block") (stringContains? (pf/sigOf resB) "no live lane")) (str "review B blocks naming the dead lanes: " (pf/sigOf resB)))
        (assert (and (> nC nB) (= dC.exit 0)) (str "review C after the ttl calls the hub again: " (stringFromInt64 nB) " -> " (stringFromInt64 nC)))
        (assert (testLockedWriters) "concurrent writers keep every row")
        true))
