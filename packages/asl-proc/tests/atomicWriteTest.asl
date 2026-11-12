(module asl-proc/tests/atomicWriteTest
  :x [runTests]
  :i [(asl-proc/atomicWrite :a aw) (asl-tools/fleet/run :a fr)])

fn ! base -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/atomicWriteTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! big -> String
  (stringRepeat "abcdefghij" 200000)

fn ! writer! path: String atomic: Bool n: Int64 -> Int64
  (if (<= n 0)
    0
    (do (if atomic (aw/fileWriteAtomic! path (big)) (fileWrite path (big)))
        (writer! path atomic (- n 1))))

fn ! poll! path: String want: Int64 f: fr/Forked partial: Int64 reads: Int64 stopOnPartial: Bool -> (Pair Int64 Int64)
  (let [(s (fr/forkAdvance! f))
        (len (match (fileReadString path) ((ok t) (stringLength t)) ((err _) -1)))
        (bad (if (and (>= len 0) (!= len want)) (+ partial 1) partial))]
    (match s.end
      ((some _) (pair bad (+ reads 1)))
      ((none) (if (and stopOnPartial (> bad 0))
                (let [(_ (fr/forkKill! s.fork "enough"))] (pair bad (+ reads 1)))
                (poll! path want s.fork bad (+ reads 1) stopOnPartial)))))

fn ! race! dir: String atomic: Bool -> (Pair Int64 Int64)
  (let [(path (str dir (if atomic "/a.txt" "/p.txt")))
        (seed (fileWrite path (big)))
        (want (stringLength (big)))]
    (match (fr/forkLimited! (str dir "/child.log") (fr/limits 60 8) (fn [] -> Int64 (writer! path atomic 400)))
      ((ok f) (poll! path want f 0 0 (not atomic)))
      ((err _) (pair -1 0))))

fn ! atomicRounds! dir: String left: Int64 partial: Int64 best: Int64 rounds: Int64 -> (List Int64)
  (if (or (<= left 0) (> best 5))
    (list partial best rounds)
    (let [(r (race! dir true))
          (p (if (< (pairFirst r) 0) (+ partial 1000000) (+ partial (pairFirst r))))]
      (atomicRounds! dir (- left 1) p (if (> (pairSecond r) best) (pairSecond r) best) (+ rounds 1))))

fn ! plainRounds! dir: String left: Int64 rounds: Int64 -> (Pair Int64 Int64)
  (let [(r (race! dir false))]
    (if (or (> (pairFirst r) 0) (<= left 1))
      (pair (pairFirst r) (+ rounds 1))
      (plainRounds! dir (- left 1) (+ rounds 1))))

fn ! linkAfter! dir: String atomic: Bool -> String
  (let [(path (str dir (if atomic "/la.txt" "/lp.txt")))
        (link (str path ".link"))
        (_ (fileWrite path "old"))
        (ln (fr/runOneLimited (fr/job (list "ln" path link) dir (fr/childEnv (list))) (fr/limits 30 4)))
        (_ (if atomic (aw/fileWriteAtomic! path "new") (fileWrite path "new")))]
    (if (= ln.exit 0) (resultOr (fileReadString link) "<unreadable>") (str "<ln failed " (stringFromInt64 ln.exit) ">")))

fn ! tmpLeft? dir: String -> Bool
  (match (dirList dir) ((ok names) (> (listLength (filter (fn [(n String)] -> Bool (stringContains? n ".tmp-")) names)) 0)) ((err _) true))

fn ! runTests -> Bool
  (let [(dir (base))
        (mk (dirCreate dir))
        (atomicLink (linkAfter! dir true))
        (atomicNow (resultOr (fileReadString (str dir "/la.txt")) "<absent>"))
        (plainLink (linkAfter! dir false))
        (atomicRace (atomicRounds! dir 3 0 0 0))
        (aPartial (optionOr (listGet atomicRace 0) -1))
        (aBest (optionOr (listGet atomicRace 1) 0))
        (aRounds (optionOr (listGet atomicRace 2) 0))
        (plainRace (plainRounds! dir 5 0))
        (left (tmpLeft? dir))
        (okPath (str dir "/ok.txt"))
        (_ (fileWrite okPath "old"))
        (w (aw/fileWriteAtomic! okPath "new"))
        (after (resultOr (fileReadString okPath) "<absent>"))
        (badPath (str dir "/nodir/x.txt"))
        (bw (aw/fileWriteAtomic! badPath "z"))
        (name (aw/tmpNameFor "/p/f" 7 9))
        (_ (pathRemove dir))]
    (do (assert (ok? mk) "scratch dir created")
        (assert (and (= atomicLink "old") (= atomicNow "new")) (str "fileWriteAtomic! replaces the target inode, never writes it in place: a hard link taken before keeps " atomicLink ", the path reads " atomicNow))
        (assert (= plainLink "new") (str "plain fileWrite writes the target inode in place, so the same hard link reads the new bytes (the control): " plainLink))
        (assert (= aPartial 0) (str "fileWriteAtomic!: the poller never reads partial content: partials " (stringFromInt64 aPartial) " over " (stringFromInt64 aRounds) " rounds, best overlap " (stringFromInt64 aBest) " reads"))
        (assert (> aBest 5) (str "the atomic poll overlapped the writer by more than 5 reads in one of at most 3 rounds (overlap is scheduler-bound, hence the rounds): best " (stringFromInt64 aBest) " over " (stringFromInt64 aRounds) " rounds"))
        (assert (> (pairFirst plainRace) 0) (str "plain fileWrite exposes partial content to the poller in one of at most 5 rounds (the race is real): partials " (stringFromInt64 (pairFirst plainRace)) " in round " (stringFromInt64 (pairSecond plainRace))))
        (assert (not left) "no tmp sibling is left after the writers end")
        (assert (and (ok? w) (= after "new")) "fileWriteAtomic! replaces an existing file")
        (assert (err? bw) "a write into a missing directory is an error")
        (assert (= name "/p/f.tmp-7-9") "tmp name is path.tmp-pid-ns")
        true))
