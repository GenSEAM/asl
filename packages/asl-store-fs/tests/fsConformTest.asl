(module asl-store-fs/tests/fsConformTest
  :x [runTests]
  :i [(asl-store/types :a ty) (asl-store/wire :a w) (asl-store/conform :a cf) (asl-store/tests/loadSupport :a ld)
      (asl-store-fs/fs :a fs) (asl-store-fs/log :a lg) (asl-store-fs/wal :a wal)])

fn coreDir -> String
  "asl/packages/asl-store/conform"

fn fsDir -> String
  "asl/packages/asl-store-fs/conform"

; (:m :ref VS-CORE :do "every store lives in a scratch dir under the worktree's .asl/cache, never in ~/.asl, and is removed by an in-process tree walk")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/fsConformTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! rmTree! p: String -> Unit
  (match (fileStat p)
    ((err _) ())
    ((ok st) (let [(_ (if st.isDir (map (fn [(n String)] -> Unit (rmTree! (str p "/" n))) (resultOr (dirList p) (list))) (list)))
                   (_ (pathRemove p))]
               ())))

fn ! scripts! dir: String -> (List cf/Script)
  (match (ld/loadScripts! dir)
    ((ok xs) xs)
    ((err e) (do (eprintln e) (list))))

fn ! runOne! script: cf/Script segmentMax: Int64 recover: (fn [String Int64] -> lg/Recovered) wrap: (fn [(fn [ty/Op] -> ty/Reply)] -> (fn [ty/Op] -> ty/Reply)) -> cf/ScriptRun
  (let [(dir (scratch (str script.id "-" (stringFromInt64 segmentMax))))
        (_ (rmTree! dir))]
    (match (fs/fsOpenWith! dir segmentMax recover)
      ((err e) (cf/ScriptRun :id script.id :declared script.declared :executed 0 :failures (list (str "open " e))))
      ((ok st)
        (let [(run (cf/runEff script (fn [(op ty/Op)] -> ty/Reply ((wrap (fn [(o ty/Op)] -> ty/Reply (fs/fsCall! st o))) op)) (fn [(n String) (a String)] -> Bool (fs/fsFault! st n a))))
              (_ (rmTree! dir))]
          run))))

fn plain f: (fn [ty/Op] -> ty/Reply) -> (fn [ty/Op] -> ty/Reply)
  f

; (:m :ref VS-CORE :do "mutants wrap the adapter call and break one rule each: a CAS that ignores the expected revision, a TTL that never expires, a scan that comes back reversed")
fn staleCas f: (fn [ty/Op] -> ty/Reply) -> (fn [ty/Op] -> ty/Reply)
  (fn [(op ty/Op)] -> ty/Reply
    (match op
      ((ty/opCas k e v ttl now)
        (let [(cur (f (ty/opGet k now))) (rev (match cur ((ty/rValue r _ _) r) (_ 0)))]
          (f (ty/opCas k (if (= e 0) 0 rev) v ttl now))))
      (_ (f op))))

fn ttlIgnored f: (fn [ty/Op] -> ty/Reply) -> (fn [ty/Op] -> ty/Reply)
  (fn [(op ty/Op)] -> ty/Reply
    (match op
      ((ty/opGet k _) (f (ty/opGet k 0)))
      ((ty/opScan c p a l _) (f (ty/opScan c p a l 0)))
      (_ (f op))))

fn scanReversed f: (fn [ty/Op] -> ty/Reply) -> (fn [ty/Op] -> ty/Reply)
  (fn [(op ty/Op)] -> ty/Reply
    (match (f op)
      ((ty/rPage rows next) (ty/rPage (listReverse rows) next))
      (r r)))

fn tornKept text: String base: Int64 -> lg/Recovered
  (let [(r (lg/recoverSegment text base))] (lg/Recovered :rows r.rows :keep text :torn false :err r.err))

fn ! runAll! scripts: (List cf/Script) segmentMax: Int64 recover: (fn [String Int64] -> lg/Recovered) wrap: (fn [(fn [ty/Op] -> ty/Reply)] -> (fn [ty/Op] -> ty/Reply)) -> (List cf/ScriptRun)
  (map (fn [(s cf/Script)] -> cf/ScriptRun (runOne! s segmentMax recover wrap)) scripts)

fn failing runs: (List cf/ScriptRun) -> (List String)
  (map (fn [(r cf/ScriptRun)] -> String r.id) (filter (fn [(r cf/ScriptRun)] -> Bool (not (listEmpty? r.failures))) runs))

fn executed runs: (List cf/ScriptRun) -> Int64
  (fold (fn [(a Int64) (r cf/ScriptRun)] -> Int64 (+ a r.executed)) 0 runs)

fn declared runs: (List cf/ScriptRun) -> Int64
  (fold (fn [(a Int64) (r cf/ScriptRun)] -> Int64 (+ a r.declared)) 0 runs)

fn firstFailure runs: (List cf/ScriptRun) -> String
  (optionOr (listHead (fold (fn [(a (List String)) (r cf/ScriptRun)] -> (List String) (listAppend a r.failures)) (list) runs)) "")

fn frame stream: String seq: Int64 v: String -> String
  (wal/formatWalFrame (wal/makeWalEntry seq 1 (wal/opLogAppend) stream v))

fn ! recoveryFacts -> (List String)
  (let [(f0 (frame "s" 0 "a")) (f1 (frame "s" 1 "b")) (f2 (frame "s" 2 "c"))
        (clean (lg/recoverSegment (str f0 "\n" f1 "\n") 0))
        (partial (lg/recoverSegment (str f0 "\n" (optionOr (stringSlice f1 0 20) "")) 0))
        (lastBad (lg/recoverSegment (str f0 "\n" "garbage\n") 0))
        (midBad (lg/recoverSegment (str f0 "\n" "garbage\n" f2 "\n") 0))
        (gap (lg/recoverSegment (str f0 "\n" f2 "\n") 0))
        (empty (lg/recoverSegment "" 5))]
    (listAppend
      (if (and (stringEmpty? clean.err) (and (not clean.torn) (= (listLength clean.rows) 2))) (list) (list "clean segment"))
      (listAppend
        (if (and (stringEmpty? partial.err) (and partial.torn (and (= (listLength partial.rows) 1) (= partial.keep (str f0 "\n"))))) (list) (list "unterminated tail is torn and dropped"))
        (listAppend
          (if (and (stringEmpty? lastBad.err) (and lastBad.torn (= (listLength lastBad.rows) 1))) (list) (list "a corrupt last line is torn"))
          (listAppend
            (if (stringStartsWith? midBad.err "logCorrupt") (list) (list "a corrupt line with records after it is refused"))
            (listAppend
              (if (stringStartsWith? gap.err "logCorrupt") (list) (list "a sequence gap is refused"))
              (if (and (stringEmpty? empty.err) (and (not empty.torn) (listEmpty? empty.rows))) (list) (list "empty segment"))))))))

fn ! diskFacts! -> (List String)
  (let [(dir (scratch "disk")) (_ (rmTree! dir))]
    (match (fs/fsOpen! dir 2)
      ((err e) (list (str "open " e)))
      ((ok st)
        (let [(appended (map (fn [(v String)] -> ty/Reply (fs/fsCall! st (ty/opAppend "s" v 1))) (list "a" "b" "c" "d" "e")))
              (segs (resultOr (dirList (str dir "/log/s")) (list)))
              (torn (fs/fsFault! st "tearLogTail" "s"))
              (afterTorn (fs/fsCall! st (ty/opAppend "s" "f" 2)))
              (lastSeg (resultOr (fileReadString (str dir "/log/s/000000000004.seg")) ""))
              (_ (fs/fsCall! st (ty/opPut (ty/Key :collection "c" :id "d/e") "v" 0 1)))
              (reopened (match (fs/fsOpen! dir 2) ((ok s2) (fs/fsCall! s2 (ty/opGet (ty/Key :collection "c" :id "d/e") 1))) ((err e) (ty/rErr "open" e))))
              (_ (fileWrite (str dir "/kv/c/d/e.row") (stringToBytes "not a row")))
              (damaged (fs/fsCall! st (ty/opGet (ty/Key :collection "c" :id "d/e") 1)))
              (_ (rmTree! dir))]
          (listAppend
            (if (= (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".seg")) segs)) 3) (list) (list (str "segments rolled every 2 records: " (stringJoin segs ","))))
            (listAppend
              (if (and torn (match afterTorn ((ty/rAppended 5) true) (_ false))) (list) (list "torn append after five records"))
              (listAppend
                (if (and (stringContains? lastSeg "\"f\"") (not (stringContains? lastSeg "(WalEntry :seq 99"))) (list) (list "a torn tail is physically truncated by the next append"))
                (listAppend
                  (match reopened ((ty/rValue 1 "v" 0) (list)) (_ (list "a reopened store sees the row")))
                  (match damaged ((ty/rErr "rowCorrupt" _) (list)) (_ (list "a damaged row file is rowCorrupt, not absent")))))))))))

; (:m :ref VS-CORE :do "a segment that cannot be read and a cursor file that does not parse are errors the caller sees: an unreadable last segment must not make append reuse offset 0, and a damaged cursor must not restart a consumer at 0")
fn ! ioFacts! -> (List String)
  (let [(dir (scratch "io")) (_ (rmTree! dir))]
    (match (fs/fsOpen! dir 2)
      ((err e) (list (str "open " e)))
      ((ok st)
        (let [(_ (fs/fsCall! st (ty/opAppend "s" "a" 1)))
              (seg (str dir "/log/s/000000000000.seg"))
              (_ (fileWrite (str dir "/log/s/cursor.k") (stringToBytes "junk")))
              (cur (fs/fsCall! st (ty/opCursor "s" "k")))
              (com (fs/fsCall! st (ty/opCommit "s" "k" 1)))
              (_ (pathRemove seg))
              (_ (dirCreate seg))
              (app (fs/fsCall! st (ty/opAppend "s" "b" 2)))
              (rd (fs/fsCall! st (ty/opRead "s" 0 10)))
              (_ (rmTree! dir))]
          (listAppend
            (match cur ((ty/rErr "cursorCorrupt" _) (list)) (_ (list "a damaged cursor file is cursorCorrupt")))
            (listAppend
              (match com ((ty/rErr "cursorCorrupt" _) (list)) (_ (list "commit over a damaged cursor is cursorCorrupt")))
              (listAppend
                (match app ((ty/rErr "io" _) (list)) (_ (list "append over an unreadable segment is err io")))
                (match rd ((ty/rErr "io" _) (list)) (_ (list "read of an unreadable segment is err io"))))))))))

fn ! runTests -> Bool
  (let [(core (scripts! (coreDir)))
        (own (scripts! (fsDir)))
        (every (listAppend core own))
        (small (runAll! every 2 (lg/defaultRecover) plain))
        (large (runAll! every 1000 (lg/defaultRecover) plain))
        (mStale (failing (runAll! core 1000 (lg/defaultRecover) staleCas)))
        (mTtl (failing (runAll! core 1000 (lg/defaultRecover) ttlIgnored)))
        (mScan (failing (runAll! core 1000 (lg/defaultRecover) scanReversed)))
        (mTorn (failing (runAll! own 1000 tornKept plain)))
        (recovery (recoveryFacts))
        (disk (listAppend (diskFacts!) (ioFacts!)))]
    (do (assert (= (listLength every) 13) "eleven shared scripts and two fs-only scripts load")
        (assert (and (listEmpty? (failing small)) (listEmpty? (failing large))) (str "fs adapter passes every script with segments of 2 and of 1000: " (firstFailure small) " " (firstFailure large)))
        (assert (and (> (executed small) 0) (and (= (executed small) (declared small)) (= (executed large) (declared large)))) "executed checks equal declared checks, nonzero, in both segment settings")
        (assert (listContains? mStale "kvCasStale") "an fs adapter that accepts a stale CAS fails kvCasStale")
        (assert (listContains? mTtl "kvTtlExpiry") "an fs adapter that ignores TTL fails kvTtlExpiry")
        (assert (listContains? mScan "kvScanOrderLimitCursor") "an fs adapter with unordered scans fails kvScanOrderLimitCursor")
        (assert (and (listContains? mTorn "logTornTail") (listContains? mTorn "logTornThenAppendMany")) "an fs adapter that keeps a torn tail in place fails both torn-tail scripts")
        (assert (listEmpty? recovery) (str "recoverSegment: " (stringJoin recovery "; ")))
        (assert (listEmpty? disk) (str "disk layout: " (stringJoin disk "; ")))
        true))
