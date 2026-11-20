(module asl-tools/coord/tests/storeTest
  :x [runTests]
  :i [(asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref FK-STORE :do "every store dir is a scratch dir under this worktree's .asl/cache, never ~/.asl/run/coord, and is removed by the test that made it")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/storeTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! sh argv: (List String) timeoutS: Int64 -> fr/Done
  (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits timeoutS 4))

fn ! cleanup dir: String -> Unit
  (let [(_ (sh (list "rm" "-rf" dir) 60))] ())

fn task id: String owns: (List String) after: (List String) -> st/Task
  (st/Task :id id :owns owns :reads (list) :gate "" :channel "leon" :model "flash" :base "main" :after after :st "queued" :epoch 0 :receipt "")

fn leaseOr r: (Result String String) -> st/Lease
  (match r
    ((ok text) (resultOr (st/parseLease text) (st/Lease :id "" :holder "" :epoch -1 :at 0 :beat 0 :ttl 0 :owns (list) :reads (list))))
    ((err _) (st/Lease :id "" :holder "" :epoch -1 :at 0 :beat 0 :ttl 0 :owns (list) :reads (list))))

fn errText r: (Result String String) -> String
  (match r ((ok _) "") ((err e) e))

fn ! unitRow! dir: String id: String -> st/Task
  (match (st/readUnits! dir)
    ((ok units) (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id id)) units) (task "" (list) (list))))
    ((err _) (task "" (list) (list))))

; (:m :ref FK-STORE :do "the store binary is prepared once into a kept native binary (BIN-NO-PERSIST: asl run compiles per run) and every child execs it directly through fr/runPoolLimited")
fn ! storeBinary! -> String
  (let [(d (fr/runOneLimited (fr/job (list (fr/nativeCli!) "run" "asl/tools/nativeTest.asl" "prepare" "asl/tools/coord/store.asl") "." (fr/childEnv (list)))
                             (fr/limits 600 64)))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "/")) (map stringTrim (stringLines d.out))))]
    (if (= d.exit 0) (optionOr (listGet lines (- (listLength lines) 1)) "") ""))

fn ! testOverlapRefused -> Bool
  (let [(dir (scratch "owns"))
        (_ (cleanup dir))
        (putA (st/put! dir (task "A" (list "pkg/a") (list))))
        (putB (st/put! dir (task "B" (list "pkg/a/x.asl") (list))))
        (putC (st/put! dir (task "C" (list "pkg/b") (list))))
        (bad (st/put! dir (task "D" (list "../escape") (list))))
        (a (leaseOr (st/claim! dir "A" "h1" 60000)))
        (b (st/claim! dir "B" "h2" 60000))
        (next (leaseOr (st/claimNext! dir "h2" 60000)))
        (none (st/claimNext! dir "h3" 60000))
        (done (st/commit! dir "A" a.epoch "ok"))
        (b2 (leaseOr (st/claim! dir "B" "h2" 60000)))
        (rowA (unitRow! dir "A"))
        (_ (cleanup dir))]
    (do (assert (and (ok? putA) (and (ok? putB) (ok? putC))) (str "three units put: " (errText putA) (errText putB) (errText putC)))
        (assert (stringContains? (errText bad) ":why owns") (str "an :owns path escaping the root is refused at put: " (errText bad)))
        (assert (and (= a.id "A") (= a.epoch 1)) (str "A claimed with epoch 1: " a.id " " a.epoch))
        (assert (stringContains? (errText b) ":why owns :by \"A\" :path \"pkg/a/x.asl\"") (str "B under A's live :owns is refused naming A: " (errText b)))
        (assert (= next.id "C") (str "the next claim skips the blocked B and takes the disjoint C: " next.id))
        (assert (= (errText none) "(:none)") (str "with A and C held, B is not claimable by anyone: " (errText none)))
        (assert (ok? done) (str "A committed with its epoch: " (errText done)))
        (assert (and (= rowA.st "done") (= rowA.receipt "ok")) (str "A row is done with its receipt: " rowA.st " " rowA.receipt))
        (assert (and (= b2.id "B") (= b2.epoch 1)) (str "after A commits, B is claimable: " b2.id " " b2.epoch))
        true))

; (:m :ref FK-STORE :do "reads take part as in the asl-mesh coord fully-disjoint rule: a unit reading under a held :owns is refused, a unit owning under a held :reads is refused, read beside read is allowed")
fn ! testReadClash -> Bool
  (let [(dir (scratch "reads"))
        (_ (cleanup dir))
        (_ (st/put! dir (task "R1" (list "lib/core") (list))))
        (_ (st/put! dir (with (task "R2" (list "app/two") (list)) :reads (list "lib/core/api.asl"))))
        (_ (st/put! dir (task "R3" (list "lib/core/api.asl") (list))))
        (_ (st/put! dir (with (task "R4" (list "app/four") (list)) :reads (list "lib/core"))))
        (r1 (leaseOr (st/claim! dir "R1" "h1" 60000)))
        (readUnderOwns (st/claim! dir "R2" "h2" 60000))
        (_ (st/commit! dir "R1" r1.epoch "ok"))
        (r2 (leaseOr (st/claim! dir "R2" "h2" 60000)))
        (ownsUnderRead (st/claim! dir "R3" "h3" 60000))
        (readBesideRead (leaseOr (st/claim! dir "R4" "h4" 60000)))
        (_ (cleanup dir))]
    (do (assert (= r1.epoch 1) (str "R1 claimed: " r1.epoch))
        (assert (stringContains? (errText readUnderOwns) ":why owns :by \"R1\" :path \"lib/core/api.asl\"") (str "a read under a held :owns is refused (read-write): " (errText readUnderOwns)))
        (assert (and (= r2.id "R2") (= r2.epoch 1)) (str "after R1 commits, R2 is claimable: " r2.id))
        (assert (stringContains? (errText ownsUnderRead) ":why owns :by \"R2\" :path \"lib/core/api.asl\"") (str "an :owns under a held :reads is refused (write-read): " (errText ownsUnderRead)))
        (assert (= readBesideRead.id "R4") (str "read beside read is allowed: " readBesideRead.id))
        true))

; (:m :ref FK-STORE-LOSTLEASE :do "a crash between the unit-row write and the lease write, injected by a read-only leases dir: the row says leased at epoch 1 with no lease, so the holder's heartbeat is refused as lost, the unit is reclaimable at once with epoch 2, and the epoch-1 release is refused")
fn ! testLostLease -> Bool
  (let [(dir (scratch "lost"))
        (_ (cleanup dir))
        (_ (st/put! dir (task "L" (list "pkg/l") (list))))
        (locked (sh (list "chmod" "555" (st/leasesDir dir)) 30))
        (broken (st/claim! dir "L" "crashed" 60000))
        (unlocked (sh (list "chmod" "755" (st/leasesDir dir)) 30))
        (row (unitRow! dir "L"))
        (leases (resultOr (st/readLeases! dir) (list)))
        (beat (st/heartbeat! dir "L" 1))
        (again (leaseOr (st/claim! dir "L" "next" 60000)))
        (stale (st/release! dir "L" 1))
        (_ (cleanup dir))]
    (do (assert (and (= locked.exit 0) (= unlocked.exit 0)) (str "leases dir made read-only and back: " locked.out unlocked.out))
        (assert (not (ok? broken)) (str "the claim fails when the lease cannot be written: " (errText broken)))
        (assert (and (= row.st "leased") (= row.epoch 1)) (str "the unit row was written first, at epoch 1: " row.st " " row.epoch))
        (assert (listEmpty? leases) (str "no lease file exists: " (listLength leases)))
        (assert (stringContains? (errText beat) ":why lost") (str "a heartbeat for the lost lease is refused: " (errText beat)))
        (assert (and (= again.holder "next") (= again.epoch 2)) (str "the unit is reclaimed at once with epoch 2: " again.holder " " again.epoch))
        (assert (stringContains? (errText stale) ":why epoch :have 1 :current 2") (str "the crashed epoch cannot release: " (errText stale)))
        true))

fn ! testFencing -> Bool
  (let [(dir (scratch "fence"))
        (_ (cleanup dir))
        (_ (st/put! dir (task "U" (list "pkg/u") (list))))
        (first (leaseOr (st/claim! dir "U" "old" 300)))
        (beat (st/heartbeat! dir "U" first.epoch))
        (held (st/claim! dir "U" "new" 60000))
        (_ (sleepMs 700))
        (second (leaseOr (st/claim! dir "U" "new" 60000)))
        (staleRelease (st/release! dir "U" first.epoch))
        (staleCommit (st/commit! dir "U" first.epoch "late"))
        (staleBeat (st/heartbeat! dir "U" first.epoch))
        (rowHeld (unitRow! dir "U"))
        (release (st/release! dir "U" second.epoch))
        (rowQueued (unitRow! dir "U"))
        (third (leaseOr (st/claim! dir "U" "next" 60000)))
        (commit (st/commit! dir "U" third.epoch "ok"))
        (after (st/claim! dir "U" "late" 60000))
        (rowDone (unitRow! dir "U"))
        (_ (cleanup dir))]
    (do (assert (= first.epoch 1) (str "first claim has epoch 1: " first.epoch))
        (assert (ok? beat) (str "the holder heartbeats with its epoch: " (errText beat)))
        (assert (stringContains? (errText held) ":why held :holder \"old\" :epoch 1") (str "a live lease refuses a second claimer: " (errText held)))
        (assert (and (= second.epoch 2) (= second.holder "new")) (str "after the TTL the unit is reclaimed with epoch+1: " second.epoch " " second.holder))
        (assert (stringContains? (errText staleRelease) ":why epoch :have 1 :current 2") (str "a release with the old epoch is refused: " (errText staleRelease)))
        (assert (stringContains? (errText staleCommit) ":why epoch :have 1 :current 2") (str "a commit with the old epoch is refused: " (errText staleCommit)))
        (assert (stringContains? (errText staleBeat) ":why epoch") (str "a heartbeat with the old epoch is refused: " (errText staleBeat)))
        (assert (and (= rowHeld.st "leased") (= rowHeld.epoch 2)) (str "the stale calls left the new holder's lease in place: " rowHeld.st " " rowHeld.epoch))
        (assert (ok? release) (str "the current holder releases: " (errText release)))
        (assert (and (= rowQueued.st "queued") (= rowQueued.epoch 2)) (str "release requeues and keeps the epoch: " rowQueued.st " " rowQueued.epoch))
        (assert (= third.epoch 3) (str "the epoch stays monotonic across a release: " third.epoch))
        (assert (ok? commit) (str "the current holder commits: " (errText commit)))
        (assert (stringContains? (errText after) ":why done") (str "a done unit is not claimable: " (errText after)))
        (assert (and (= rowDone.st "done") (= rowDone.receipt "ok")) (str "the unit row is done with the receipt: " rowDone.st " " rowDone.receipt))
        true))

; (:m :ref FK-STORE :do "the holder is a real process that claims and heartbeats every ttl/3 until the runner's 4 s timeout kills its tree; its lease must outlive it by the TTL, then expire, and the reclaim gets epoch+1 while the dead holder's late release is refused")
fn ! testKilledHolder bin: String -> Bool
  (let [(dir (scratch "killed"))
        (_ (cleanup dir))
        (_ (st/put! dir (task "K" (list "pkg/k") (list))))
        (victim (sh (list bin "claim" "--dir" dir "--id" "K" "--holder" "victim" "--ttl" "3000" "--hold" "600000") 4))
        (afterKill (st/claim! dir "K" "rescuer" 60000))
        (leases (resultOr (st/readLeases! dir) (list)))
        (dead (optionOr (listHead leases) (st/Lease :id "" :holder "" :epoch -1 :at 0 :beat 0 :ttl 0 :owns (list) :reads (list))))
        (_ (sleepMs 3300))
        (rescue (leaseOr (st/claim! dir "K" "rescuer" 60000)))
        (late (sh (list bin "release" "--dir" dir "--id" "K" "--epoch" "1") 30))
        (row (unitRow! dir "K"))
        (_ (cleanup dir))]
    (do (assert (= victim.verdict "timeout") (str "the holder was killed by the runner timeout: " victim.verdict " " victim.exit " " victim.out))
        (assert (and (= dead.holder "victim") (= dead.epoch 1)) (str "the killed holder's lease is on disk: " dead.holder " " dead.epoch))
        (assert (>= (- dead.beat dead.at) 1000000000) (str "the holder heartbeat while it lived: " (- dead.beat dead.at) " ns"))
        (assert (stringContains? (errText afterKill) ":why held :holder \"victim\"") (str "within the TTL the dead holder's lease still holds: " (errText afterKill)))
        (assert (and (= rescue.holder "rescuer") (= rescue.epoch 2)) (str "after expiry the unit is reclaimed with epoch 2: " rescue.holder " " rescue.epoch))
        (assert (= late.exit 1) (str "the dead holder's late release exits 1: " late.exit " " late.out))
        (assert (stringContains? late.out ":why epoch :have 1 :current 2") (str "and is refused by epoch: " late.out))
        (assert (and (= row.st "leased") (= row.epoch 2)) (str "the rescuer still holds the unit: " row.st " " row.epoch))
        true))

fn units -> (List st/Task)
  (listAppend
    (map (fn [(i Int64)] -> st/Task (task (str "d" i) (list (str "pkg/d" i)) (list))) (range 0 30))
    (listAppend
      (map (fn [(i Int64)] -> st/Task (task (str "s" i) (list (str "shared/s" i)) (list))) (range 0 6))
      (listAppend
        (map (fn [(i Int64)] -> st/Task (task (str "t" i) (list (str "shared/s" i "/file.asl")) (list))) (range 0 6))
        (list (task "c1" (list "chain/one") (list)) (task "c2" (list "chain/two") (list "c1")) (task "c3" (list "chain/three") (list "c2"))))))

fn lineIndex lines: (List String) needle: String -> Int64
  (optionOr (listFind (fn [(i Int64)] -> Bool (stringContains? (optionOr (listGet lines i) "") needle)) (range 0 (listLength lines))) -1)

fn hits lines: (List String) needle: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l needle)) lines))

fn claimed id: String -> String
  (str "(:claimed :unit \"" id "\" ")

fn committed id: String -> String
  (str "(:committed :unit \"" id "\" ")

fn ! disjointInTime? lines: (List String) a: String b: String -> Bool
  (or (> (lineIndex lines (claimed b)) (lineIndex lines (committed a)))
      (> (lineIndex lines (claimed a)) (lineIndex lines (committed b))))

fn ! ordered? lines: (List String) first: String next: String -> Bool
  (and (>= (lineIndex lines (committed first)) 0) (> (lineIndex lines (claimed next)) (lineIndex lines (committed first))))

; (:m :ref FK-STORE :do "n real claimer processes drain one queue through fr/runPoolLimited (120 s timeout, 4 descendants): each unit is granted once (epoch 1, one claimed row, one (:did ...) row across all children), units with overlapping :owns are never held at the same time, and :after chains run in order")
fn ! testConcurrent bin: String n: Int64 -> Bool
  (let [(dir (scratch (str "conc" n)))
        (_ (cleanup dir))
        (all (units))
        (puts (map (fn [(u st/Task)] -> Bool (ok? (st/put! dir u))) all))
        (jobs (map (fn [(i Int64)] -> fr/Job (fr/job (list bin "claim" "--dir" dir "--holder" (str "w" i) "--ttl" "30000" "--drain" "20") "." (fr/childEnv (list)))) (range 0 n)))
        (startNs (nowNs))
        (done (fr/runPoolLimited jobs n (fr/limits 120 4)))
        (wallMs (/ (- (nowNs) startNs) 1000000))
        (outs (stringJoin (map (fn [(d fr/Done)] -> String d.out) done) "\n"))
        (did (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:did ")) (stringLines outs)))
        (log (stringLines (resultOr (fileReadString (str dir "/log.asn")) "")))
        (rows (resultOr (st/readUnits! dir) (list)))
        (failed (filter (fn [(d fr/Done)] -> Bool (!= d.exit 0)) done))
        (holders (fold (fn [(acc (List String)) (h String)] -> (List String) (if (listContains? acc h) acc (cons h acc))) (list) (map (fn [(l String)] -> String (optionOr (listGet (stringSplit l ":holder ") 1) "")) did)))
        (_ (println (str "(:storeTest :claimers " n " :units " (listLength all) " :wallMs " wallMs " :holders " (listLength holders) ")")))
        (_ (cleanup dir))]
    (do (assert (listAll? (fn [(b Bool)] -> Bool b) puts) "every unit put")
        (assert (listEmpty? failed) (str "every claimer exits 0: " (stringJoin (map (fn [(d fr/Done)] -> String (str d.verdict " " d.exit " " d.out)) failed) " | ")))
        (assert (= (listLength rows) (listLength all)) (str "the store holds every unit row: " (listLength rows)))
        (assert (listAll? (fn [(u st/Task)] -> Bool (and (= u.st "done") (= u.epoch 1))) rows)
                (str "every unit done and granted exactly once (epoch 1): " (stringJoin (map (fn [(u st/Task)] -> String (str u.id ":" u.st ":" u.epoch)) (filter (fn [(u st/Task)] -> Bool (or (!= u.st "done") (!= u.epoch 1))) rows)) " ")))
        (assert (listAll? (fn [(u st/Task)] -> Bool (and (= (hits log (claimed u.id)) 1) (= (hits did (str "(:did :unit \"" u.id "\" ")) 1))) all)
                (str "each unit has one claimed row and one claimer reported it: " (stringJoin did " ")))
        (assert (= (listLength did) (listLength all)) (str "no claimer reported a unit outside the queue: " (listLength did)))
        (assert (listAll? (fn [(i Int64)] -> Bool (disjointInTime? log (str "s" i) (str "t" i))) (range 0 6))
                (str "overlapping :owns were never held together: " (stringJoin log " ")))
        (assert (and (ordered? log "c1" "c2") (ordered? log "c2" "c3")) (str ":after chain ran in order: " (stringJoin log " ")))
        (assert (> (listLength holders) 1) (str "more than one claimer took work, so claims raced: " (stringJoin holders " ")))
        true))

fn ! runTests -> Bool
  (let [(bin (storeBinary!))]
    (do (assert (not (stringEmpty? bin)) "the store CLI is prepared into a native binary")
        (assert (testOverlapRefused) "overlapping :owns refused while the holder lives")
        (assert (testReadClash) "reads clash with held owns both ways, not with reads")
        (assert (testLostLease) "a lease lost between the row and lease writes is reclaimable with epoch+1")
        (assert (testFencing) "stale-epoch release, commit and heartbeat are refused")
        (assert (testKilledHolder bin) "a killed holder expires and the unit is reclaimed with epoch+1")
        (assert (testConcurrent bin 8) "8 concurrent claimers claim each unit exactly once")
        (assert (testConcurrent bin 40) "40 concurrent claimers claim each unit exactly once")
        true))
