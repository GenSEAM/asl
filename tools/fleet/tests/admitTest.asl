(module asl-tools/fleet/tests/admitTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js) (asl-tools/fleet/mutate :a mu)])

; (:m :ref FABLE-GATE-ADMIT :do "machine-wide admission seen from the slot ledger: three forked pools (three sessions) put 3N sleep children through one token dir with N tokens, and the ledger, read here by its own parser, shows 3N claims, 3N releases and never more than N open; a dead holder's token is reclaimed with a ledger row; a live holder queues a job until its deadline and it never runs; a mutant waits out a load above the cap and is not run; without a :tokens row the pool is half the cores. Children are sleeps and shells in their own groups, every run is bounded, scratch is removed")

(schema Ev
  (:f ev String)
  (:f tok Int64)
  (:f owner Int64)
  (:f ns Int64))

fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/admitTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! sh argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv "." (fr/childEnv (list))) (fr/limits 60 16))

fn ! setup dir: String config: String -> Bool
  (let [(_ (sh (list "rm" "-rf" dir)))
        (_ (sh (list "mkdir" "-p" dir)))]
    (if (stringEmpty? config) (fileExists? dir) (ok? (fileWrite (str dir "/config.asn") config))))

fn ! cleanup dir: String -> Bool
  (= (sh (list "rm" "-rf" dir)).exit 0)

fn intAfter line: String key: String -> Int64
  (match (stringIndexOf line key)
    ((none) -1)
    ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listHead (stringSplit (optionOr (stringSlice line (+ i (stringLength key)) (stringLength line)) "") " ")) "") ")" "")) -1)))

fn evOf acc: (List Ev) line: String -> (List Ev)
  (if (not (stringStartsWith? line "(:slot :ev :"))
    acc
    (let [(name (optionOr (listHead (stringSplit (optionOr (stringSlice line 12 (stringLength line)) "") " ")) ""))]
      (listAppend acc (list (Ev :ev name :tok (intAfter line ":tok ") :owner (intAfter line ":owner ") :ns (intAfter line ":ns "))))))

fn ! ledger dir: String -> (List Ev)
  (listSortBy (fn [(e Ev)] -> Int64 e.ns) (fold evOf (list) (stringLines (resultOr (fileReadString (str dir "/slots.log")) ""))))

fn countOf evs: (List Ev) name: String -> Int64
  (listLength (filter (fn [(e Ev)] -> Bool (= e.ev name)) evs))

fn peakOf evs: (List Ev) -> Int64
  (pairSecond (fold (fn [(acc (Pair Int64 Int64)) (e Ev)] -> (Pair Int64 Int64)
                      (let [(open (if (= e.ev "claim") (+ (pairFirst acc) 1) (max 0 (- (pairFirst acc) 1))))]
                        (pair open (max open (pairSecond acc)))))
                    (pair 0 0) evs))

fn ! poolBad dir: String n: Int64 -> Int64
  (let [(jobs (map (fn [(i Int64)] -> fr/Job (fr/job (list "sleep" "1") "/" (fr/childEnv (list)))) (range 0 n)))
        (done (fr/runPoolLimited jobs n (fr/heavy (fr/limits 60 8) "writer" dir)))]
    (+ (- n (listLength done)) (listLength (filter (fn [(d fr/Done)] -> Bool (or (!= d.exit 0) (!= d.verdict "exit"))) done))))

fn ! drive! f: fr/Forked -> fr/ForkEnd
  (let [(s (fr/forkAdvance! f))]
    (match s.end
      ((some e) e)
      ((none) (do (sleepMs 50) (drive! s.fork)))))

fn ! endOf r: (Result fr/Forked String) -> fr/ForkEnd
  (match r
    ((ok f) (drive! f))
    ((err e) (fr/ForkEnd :exit -2 :verdict "forkFailed" :desc 0 :note e)))

fn ! testCap -> Bool
  (let [(dir (scratch "cap"))
        (n 2)
        (ready (setup dir (str "(:jobserver :tokens " n ")\n")))
        (forks (map (fn [(k Int64)] -> (Result fr/Forked String)
                      (fr/forkLimited! (str dir "/pool" k ".log") (fr/limits 120 32) (fn [] -> Int64 (poolBad dir n))))
                    (range 0 3)))
        (ends (map endOf forks))
        (evs (ledger dir))
        (held (js/heldCount dir))
        (owners (listLength (fold (fn [(acc (List Int64)) (e Ev)] -> (List Int64) (if (or (!= e.ev "claim") (listContains? acc e.owner)) acc (cons e.owner acc))) (list) evs)))
        (_ (cleanup dir))]
    (do (assert ready "token dir with 2 tokens written")
        (assert (listAll? (fn [(e fr/ForkEnd)] -> Bool (and (= e.exit 0) (= e.verdict ""))) ends)
                (str "each of the three pools ran its N children to exit 0: " (stringJoin (map (fn [(e fr/ForkEnd)] -> String (str e.exit e.verdict e.note)) ends) " ")))
        (assert (= (countOf evs "claim") (* 3 n)) (str "the ledger holds one claim per child, 3N: " (countOf evs "claim")))
        (assert (= (countOf evs "release") (* 3 n)) (str "and one release per child: " (countOf evs "release")))
        (assert (= owners 3) (str "the claims come from three processes: " owners))
        (assert (<= (peakOf evs) n) (str "open claims never exceed N=2 across the three pools: peak " (peakOf evs)))
        (assert (= (peakOf evs) n) (str "and reach N, the pools queue and are not serialized: peak " (peakOf evs)))
        (assert (listAll? (fn [(e Ev)] -> Bool (and (>= e.tok 0) (< e.tok n))) evs) "every row names a token below N")
        (assert (= held 0) (str "no token is left held: " held))
        true))

fn ! testDefault -> Bool
  (let [(dir (scratch "default"))
        (ready (setup dir ""))
        (cores (resultOr (cpuCount) 1))
        (bare (js/tokenCount dir))
        (_ (fileWrite (str dir "/config.asn") "(:jobserver :tokens 3)\n"))
        (row (js/tokenCount dir))
        (_ (cleanup dir))]
    (do (assert ready "empty token dir made")
        (assert (= bare (if (> cores 1) (/ cores 2) 1)) (str "without a :tokens row N is half the cores, at least 1: " bare " of " cores))
        (assert (= row 3) (str "the :tokens row of config.asn sets N: " row))
        true))

fn ! testStale -> Bool
  (let [(dir (scratch "stale"))
        (ready (setup dir "(:jobserver :tokens 1)\n"))
        (gone (optionOr (stringToInt64 (stringTrim (sh (list "sh" "-c" "echo $$")).out)) 0))
        (_ (sh (list "mkdir" "-p" (str dir "/tokens"))))
        (wrote (ok? (fileWrite (str dir "/tokens/tok0") (str "(:tok :ownerPid " gone " :ownerStart \"\" :childPid 0 :startNs " (monotonicNs) " :class \"writer\")\n"))))
        (d (fr/runOneLimited (fr/job (list "sleep" "0.1") "/" (fr/childEnv (list))) (fr/heavy (fr/limits 30 8) "writer" dir)))
        (evs (ledger dir))
        (_ (cleanup dir))]
    (do (assert (and ready wrote (> gone 1)) "the only token is written as held by a process that has ended")
        (assert (and (= d.exit 0) (= d.verdict "exit")) (str "the queued child runs once the dead holder's token is reclaimed: " d.verdict " " d.out))
        (assert (= (map (fn [(e Ev)] -> String e.ev) evs) (list "reclaim" "claim" "release")) (str "the ledger shows reclaim, claim, release: " (stringJoin (map (fn [(e Ev)] -> String e.ev) evs) " ")))
        (assert (= (optionOr (listHead (map (fn [(e Ev)] -> Int64 e.owner) evs)) 0) gone) "the reclaim row names the dead holder")
        true))

fn ! testDeadline -> Bool
  (let [(dir (scratch "deadline"))
        (ready (setup dir "(:jobserver :tokens 1)\n"))
        (_ (sh (list "mkdir" "-p" (str dir "/tokens"))))
        (wrote (ok? (fileWrite (str dir "/tokens/tok0") (str "(:tok :ownerPid " (procSelf) " :ownerStart \"\" :childPid 0 :startNs " (monotonicNs) " :class \"writer\")\n"))))
        (d (fr/runOneLimited (fr/job (list "sh" "-c" (str "touch " dir "/ran")) "/" (fr/childEnv (list))) (fr/heavy (fr/limits 2 8) "writer" dir)))
        (ran (fileExists? (str dir "/ran")))
        (claims (countOf (ledger dir) "claim"))
        (_ (cleanup dir))]
    (do (assert (and ready wrote) "the only token is held by a live process")
        (assert (= d.verdict "tokenWait") (str "a job queued behind a live holder ends at its deadline with verdict tokenWait: " d.verdict))
        (assert (not ran) "the job was never started")
        (assert (= claims 0) (str "and claimed nothing: " claims))
        true))

fn ! git dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))) (fr/limits 60 8))

fn ! testLoadGate -> Bool
  (let [(root (scratch "load"))
        (cfg (str root "/js"))
        (wt (str root "/repo"))
        (sc (str root "/mutants"))
        (ready (setup cfg (str "(:jobserver :tokens 2 :maxLoadPerCore 2 :loadWaitS 1 :loadSource \"" cfg "/loadavg\")\n")))
        (_ (sh (list "mkdir" "-p" wt)))
        (_ (git wt (list "init" "--quiet" "-b" "main")))
        (_ (fileWrite (str wt "/f.txt") "a = 1\n"))
        (_ (git wt (list "add" "f.txt")))
        (made (git wt (list "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false" "commit" "--quiet" "-m" "c0")))
        (lim (fr/heavy (fr/limits 60 16) "" cfg))
        (m (mu/mutant "f.txt" "a = 1" "a = 2"))
        (_ (fileWrite (str cfg "/loadavg") "99999.00 50.00 20.00 3/900 4242\n"))
        (t0 (monotonicNs))
        (over (mu/mutantRunIn! wt sc (str root "/cliCache") m "grep -q 'a = 2' f.txt" lim))
        (waitedMs (/ (- (monotonicNs) t0) 1000000))
        (copies (listLength (mu/mutantDirs! sc)))
        (_ (fileWrite (str cfg "/loadavg") "0.01 50.00 20.00 3/900 4242\n"))
        (under (mu/mutantRunIn! wt sc (str root "/cliCache") m "grep -q 'a = 2' f.txt" lim))
        (_ (cleanup root))]
    (do (assert (and ready (= made.exit 0)) (str "config and fixture repository written: " made.out))
        (assert (= over.verdict "loadWait") (str "above the load cap a mutant is not run and says loadWait: " over.verdict " " over.out))
        (assert (and (not over.applied) (not over.red)) "it is neither applied nor red")
        (assert (stringContains? over.out "(:fleetRun :verdict :loadWait :load1x100 9999900 ") (str "the receipt carries the load read: " over.out))
        (assert (>= waitedMs 1000) (str "it queued for the configured :loadWaitS first: " waitedMs))
        (assert (= copies 0) (str "no mutant copy was made: " copies))
        (assert (and under.applied (= under.verdict "pass")) (str "under the cap the same mutant runs in its copy: " under.verdict " " under.out))
        true))

fn ! runTests -> Bool
  (do (assert (testDefault) "default N")
      (assert (testCap) "3N children under N tokens")
      (assert (testStale) "stale slot recovery")
      (assert (testDeadline) "queue deadline")
      (assert (testLoadGate) "load gate")
      true)
