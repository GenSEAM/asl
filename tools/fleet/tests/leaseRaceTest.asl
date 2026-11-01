(module asl-tools/fleet/tests/leaseRaceTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref FR-LEASE-REAPER-RACE :do "sleepers with a lease row each in a lease dir of this test's own and a snapshot taken after they started; times are passed in, so no sleep and no race. Race: a row written after the snapshot time keeps its live group and row, an older row whose owner is gone and whose recorded leader start time matches is reaped with its group. Reuse: a row whose leader pid is live with another start time, or has no recorded start time, is dropped and that process is untouched; an owner pid live with another start time is a gone owner, with the recorded one a live owner. Every sleeper is killed and reaped at the end")

fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/leaseRaceTest-" (stringFromInt64 (procSelf)))

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! sleeper! -> Int64
  (match (fr/spawnSep (list "sh" "-c" "exec sleep 60") "." (fr/childEnv (list)))
    ((ok r) r.pid)
    ((err _) -1))

fn leaseText pgid: Int64 owner: Int64 wroteNs: Int64 pgidBorn: Int64 ownerBorn: Int64 -> String
  (str "(:pgid " pgid " :ownerPid " owner " :startNs 1 :deadlineNs 0 :wroteNs " wroteNs " :pgidBorn " pgidBorn " :ownerBorn " ownerBorn ")\n")

fn legacyText pgid: Int64 owner: Int64 -> String
  (str "(:pgid " pgid " :ownerPid " owner " :startNs 1 :deadlineNs 0)\n")

fn ! tidy! pid: Int64 -> Bool
  (let [(_ (fr/killTree! pid))
        (_ (procWaitPid pid false))]
    (not (resultOr (procAlive? pid) false)))

fn ! alive? pid: Int64 -> Bool
  (resultOr (procAlive? pid) false)

; (:m :ref FR-LEASE-REAPER-RACE :do "a killed child stays a zombie until reaped and procAlive? reads a zombie as alive, so liveness after a reap is asked after a non-blocking wait, a short settle and a second wait")
fn ! aliveAfterReap! pid: Int64 -> Bool
  (let [(_ (procWaitPid pid true))
        (_ (sleepMs 200))
        (_ (procWaitPid pid true))]
    (alive? pid))

fn ! row dir: String pid: Int64 -> String
  (str dir "/" pid ".asn")

fn ! testRace -> Bool
  (let [(dir (scratch))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (a (sleeper!))
        (b (sleeper!))
        (snap (fr/procSnapshot))
        (me (procSelf))
        (_ (fileWrite (row dir a) (leaseText a 2000000000 2000 (fr/bornIn snap a) 0)))
        (first (fr/reapLeasesAt! dir snap me 1000))
        (aAlive (alive? a))
        (aRow (fileExists? (row dir a)))
        (_ (fileWrite (row dir b) (leaseText b 2000000000 500 (fr/bornIn snap b) 0)))
        (second (fr/reapLeasesAt! dir snap me 1000))
        (_ (procWaitPid b false))
        (bDead (not (alive? b)))
        (bRow (fileExists? (row dir b)))
        (aStill (alive? a))
        (aRowStill (fileExists? (row dir a)))
        (aGone (tidy! a))
        (bGone (tidy! b))
        (_ (cleanup dir))]
    (do (assert (and (> a 1) (> b 1)) "two sleepers started")
        (assert (and (= first 0) aAlive aRow) (str "a lease written after the snapshot keeps its live group and its row: reaped " (stringFromInt64 first)))
        (assert (and (= second 1) bDead (not bRow)) (str "an older lease with the recorded start time and a gone owner is reaped with its group: " (stringFromInt64 second)))
        (assert (and aStill aRowStill) "and the newer lease is still kept by the same pass")
        (assert (and aGone bGone) "both sleepers are gone at the end")
        true))

; (:m :ref FR-LEASE-REAPER-RACE :do "pid reuse: the leader pid of the row is live now but it started at another time (or the row records none): it is another process, the row is dropped and nothing is killed")
fn ! testReused -> Bool
  (let [(dir (scratch))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (c (sleeper!))
        (snap (fr/procSnapshot))
        (me (procSelf))
        (born (fr/bornIn snap c))
        (_ (fileWrite (row dir c) (leaseText c 2000000000 500 (- born 1000) 0)))
        (other (fr/reapLeasesAt! dir snap me 1000))
        (otherAlive (aliveAfterReap! c))
        (otherRow (fileExists? (row dir c)))
        (_ (fileWrite (row dir c) (legacyText c 2000000000)))
        (legacy (fr/reapLeasesAt! dir snap me 1000))
        (legacyAlive (aliveAfterReap! c))
        (legacyRow (fileExists? (row dir c)))
        (gone (tidy! c))
        (_ (cleanup dir))]
    (do (assert (> born 0) "the sleeper's start time is in the snapshot")
        (assert (and (= other 1) otherAlive (not otherRow)) (str "a row with another start time for a live pid is dropped and the process lives: " (stringFromInt64 other)))
        (assert (and (= legacy 1) legacyAlive (not legacyRow)) (str "a row without a recorded start time for a live pid is dropped and the process lives: " (stringFromInt64 legacy)))
        (assert gone "the sleeper is gone at the end")
        true))

; (:m :ref FR-LEASE-REAPER-RACE :do "the owner pid is live: with the recorded start time it is the owner (row kept), with another start time it is a reused pid, the owner is gone and the group is reaped")
fn ! testOwnerReuse -> Bool
  (let [(dir (scratch))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (d (sleeper!))
        (snap (fr/procSnapshot))
        (me (procSelf))
        (mine (fr/bornIn snap me))
        (_ (fileWrite (row dir d) (leaseText d me 500 (fr/bornIn snap d) mine)))
        (same (fr/reapLeasesAt! dir snap me 1000))
        (sameAlive (alive? d))
        (_ (fileWrite (row dir d) (leaseText d me 500 (fr/bornIn snap d) (- mine 1000))))
        (diff (fr/reapLeasesAt! dir snap me 1000))
        (_ (procWaitPid d false))
        (diffDead (not (alive? d)))
        (gone (tidy! d))
        (_ (cleanup dir))]
    (do (assert (> mine 0) "the test process start time is in the snapshot")
        (assert (and (= same 0) sameAlive) (str "an owner live with its recorded start time keeps the lease: " (stringFromInt64 same)))
        (assert (and (= diff 1) diffDead) (str "an owner pid live with another start time is a gone owner and the group is reaped: " (stringFromInt64 diff)))
        (assert gone "the sleeper is gone at the end")
        true))

fn ! runTests -> Bool
  (do (assert (testRace) "the reaper keeps a lease written after its snapshot")
      (assert (testReused) "a reused leader pid is never killed")
      (assert (testOwnerReuse) "a reused owner pid is a gone owner")
      true)
