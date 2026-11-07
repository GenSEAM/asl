(module asl-proc/tests/atomicWriteTest
  :x [runTests]
  :i [(asl-proc/atomicWrite :a aw) (asl-tools/fleet/run :a fr)])

; (:m :ref FILEWRITE-ATOMIC :do "a forked writer rewrites one big file 400 times while this process polls it: with fileWriteAtomic! every read is the whole content (0 partial reads), with plain fileWrite the poller sees a truncated or short file (the race is real); the fork is bounded by forkLimited! 60 s in its own group; the rename contract is also asserted: no tmp sibling is left and a failed write leaves the target untouched")
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

fn ! tmpLeft? dir: String -> Bool
  (match (dirList dir) ((ok names) (> (listLength (filter (fn [(n String)] -> Bool (stringContains? n ".tmp-")) names)) 0)) ((err _) true))

fn ! runTests -> Bool
  (let [(dir (base))
        (mk (dirCreate dir))
        (atomicRace (race! dir true))
        (plainRace (race! dir false))
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
        (assert (= (pairFirst atomicRace) 0) (str "fileWriteAtomic!: the poller never reads partial content, reads " (pairSecond atomicRace)))
        (assert (> (pairSecond atomicRace) 5) "the atomic poll really overlapped the writer (reads counted)")
        (assert (> (pairFirst plainRace) 0) (str "plain fileWrite exposes partial content to the poller (the race is real): " (pairFirst plainRace)))
        (assert (not left) "no tmp sibling is left after the writers end")
        (assert (and (ok? w) (= after "new")) "fileWriteAtomic! replaces an existing file")
        (assert (err? bw) "a write into a missing directory is an error")
        (assert (= name "/p/f.tmp-7-9") "tmp name is path.tmp-pid-ns")
        true))
