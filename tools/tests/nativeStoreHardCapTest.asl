(module asl-tools/tests/nativeStoreHardCapTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-cli/src/nativeBuild :a nb) (asl-tools/nativeTest :a nt)])

; (:m :ref NATIVETEST-CACHE-GC-NODE2 :do "scratch stores under /tmp only, never ~/.asl; each case removes its own dir before it returns its failure text (empty is a pass) and runTests asserts one case at a time, so a red case leaves nothing behind")
fn hex c: String -> String
  (stringRepeat c 64)

fn ! slot! cDir: String c: String ageMin: Int64 -> String
  (let [(dir (str cDir "/" (hex "a") "/" (hex c)))
        (at (- (nowNs) (* ageMin 60000000000)))
        (_ (dirCreate (str cDir "/" (hex "a"))))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/bin") (stringRepeat "x" 4000)))
        (_ (fileUtime (str dir "/bin") at))
        (_ (fileUtime dir at))]
    dir)

fn ! ageTree! path: String at: Int64 -> Bool
  (do (fold (fn [(acc Bool) (n String)] -> Bool (ageTree! (str path "/" n) at)) true (resultOr (dirList path) (list)))
      (ok? (fileUtime path at)))

fn ! fresh! work: String name: String -> String
  (let [(cDir (str work "/" name))
        (_ (dirCreate cDir))]
    (resultOr (realPath cDir) cDir))

fn problems claims: (List (Pair Bool String)) -> String
  (stringJoin (map (fn [(c (Pair Bool String))] -> String (pairSecond c)) (filter (fn [(c (Pair Bool String))] -> Bool (not (pairFirst c))) claims)) "; ")

fn ! oldestFirst! work: String -> String
  (let [(cDir (fresh! work "oldest"))
        (s1 (slot! cDir "1" 600)) (s2 (slot! cDir "2" 500)) (s3 (slot! cDir "3" 400))
        (s4 (slot! cDir "4" 300)) (s5 (slot! cDir "5" 200)) (s6 (slot! cDir "6" 100))
        (one (nc/treeBytes! s1))
        (n (nt/sweepStoreHardWith! cDir (+ (* 3 one) 1) 600000000000))
        (row (resultOr (fileReadString (str cDir "/sweeps.asn")) ""))
        (out (problems (list (pair (= n 3) (str "evicted " (stringFromInt64 n)))
                             (pair (not (or (fileExists? s1) (or (fileExists? s2) (fileExists? s3)))) "three oldest stayed")
                             (pair (and (fileExists? s4) (and (fileExists? s5) (fileExists? s6))) "three newest went")
                             (pair (stringContains? row ":kind hard") "receipt lacks kind")
                             (pair (stringContains? row ":entries 3") "receipt lacks entries")
                             (pair (stringContains? row (str ":freedBytes " (stringFromInt64 (* 3 one)))) "receipt lacks bytes"))))
        (_ (pathRemove cDir))]
    out)

fn ! leaseKept! work: String -> String
  (let [(cDir (fresh! work "live"))
        (leased (slot! cDir "1" 600)) (old (slot! cDir "2" 500)) (young (slot! cDir "3" 2))
        (_ (nt/leaseSlot! leased))
        (_ (fileUtime (str leased "/lock") (- (nowNs) 36000000000000)))
        (_ (fileUtime leased (- (nowNs) 36000000000000)))
        (n (nt/sweepStoreHardWith! cDir 0 600000000000))
        (out (problems (list (pair (= n 1) (str "evicted " (stringFromInt64 n)))
                             (pair (fileExists? leased) "leased slot went")
                             (pair (fileExists? young) "young slot went")
                             (pair (not (fileExists? old)) "old slot stayed"))))
        (_ (pathRemove cDir))]
    out)

fn ! underCap! work: String -> String
  (let [(cDir (fresh! work "under"))
        (s1 (slot! cDir "1" 600)) (s2 (slot! cDir "2" 500))
        (n (nt/sweepStoreHardWith! cDir 1000000 600000000000))
        (out (problems (list (pair (= n 0) "something evicted")
                             (pair (and (fileExists? s1) (fileExists? s2)) "a slot went")
                             (pair (not (fileExists? (str cDir "/sweeps.asn"))) "a receipt row for nothing"))))
        (_ (pathRemove cDir))]
    out)

fn ! underMarker! work: String -> String
  (let [(cDir (fresh! work "building"))
        (s1 (slot! cDir "1" 600)) (s2 (slot! cDir "2" 500)) (s3 (slot! cDir "3" 400))
        (_ (fileWrite (str cDir "/building." (stringFromInt64 (procSelf))) ""))
        (one (nc/treeBytes! s1))
        (n (nt/sweepStoreBounded! cDir 0 3600000000000 (+ one 1) 600000000000))
        (again (nt/sweepStoreBounded! cDir 0 3600000000000 0 600000000000))
        (out (problems (list (pair (= n 2) (str "hard sweep evicted " (stringFromInt64 n)))
                             (pair (fileExists? s3) "newest went")
                             (pair (not (or (fileExists? s1) (fileExists? s2))) "older stayed")
                             (pair (= again 0) "second sweep not held by the mark")
                             (pair (not (fileExists? (str cDir "/swept"))) "soft mark written under a marker"))))
        (_ (pathRemove cDir))]
    out)

fn ! softAndHard! work: String -> String
  (let [(cDir (fresh! work "both"))
        (s1 (slot! cDir "1" 600)) (s2 (slot! cDir "2" 500)) (s3 (slot! cDir "3" 5))
        (one (nc/treeBytes! s1))
        (n (nt/sweepStoreBounded! cDir (+ one 1) 3600000000000 100000000 600000000000))
        (out (problems (list (pair (= n 2) (str "soft pass evicted " (stringFromInt64 n)))
                             (pair (fileExists? s3) "young slot went")
                             (pair (fileExists? (str cDir "/swept")) "soft mark missing"))))
        (_ (pathRemove cDir))]
    out)

; (:m :ref NATIVETEST-CACHE-GC-NODE2 :do "the real pin check of nativeTest decides, through a slot listed unpinned whose hold appeared after the scan")
fn ! recheckPins! work: String -> String
  (let [(cDir (fresh! work "recheck"))
        (s1 (slot! cDir "1" 600))
        (scanned (list (nc/storeEntry! (list s1) false)))
        (_ (fileWrite (str cDir "/holds.probe") ""))
        (kept (nc/sweepEntriesWith! scanned 0 600000000000 (fn [(e nc/StoreEntry)] -> Bool (nt/entryPinnedNow! (list (str s1 "/bin")) e))))
        (kept? (fileExists? s1))
        (gone (nc/sweepEntriesWith! scanned 0 600000000000 (fn [(e nc/StoreEntry)] -> Bool (nt/entryPinnedNow! (list) e))))
        (out (problems (list (pair (= (pairSecond kept) 0) "a held entry was removed")
                             (pair kept? "the held slot is gone")
                             (pair (= (pairSecond gone) 1) "an unheld entry stayed"))))
        (_ (pathRemove cDir))]
    out)

fn ! rotates! work: String -> String
  (let [(cDir (fresh! work "rows"))
        (path (str cDir "/rows.asn"))
        (_ (fileWrite path (stringJoin (map (fn [(i Int64)] -> String (str "(:sweep :n " (stringFromInt64 i) ")")) (range 0 300)) "\n")))
        (_ (nt/rotateRows! path 200))
        (rows (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit (resultOr (fileReadString path) "") "\n")))
        (out (problems (list (pair (= (listLength rows) 200) (str "rows " (stringFromInt64 (listLength rows))))
                             (pair (= (optionOr (listHead rows) "") "(:sweep :n 100)") "oldest rows stayed"))))
        (_ (pathRemove cDir))]
    out)

fn suitePaths n: Int64 -> (List String)
  (listTake (map (fn [(s String)] -> String (str "asl/tools/tests/fixtures/prepareAll/suite" s ".asl")) (list "A" "B" "C" "D")) n)

fn ! slotsLeft! cDir: String -> Int64
  (listLength (nt/slotEntries! cDir))

; (:m :ref NATIVETEST-CACHE-GC-NODE2 :do "prepareAllIn at k workers builds in forked workers that exit; the holds must still pin every slot until releaseHold!")
fn ! heldUntilRun! work: String name: String n: Int64 k: Int64 -> String
  (let [(cDir (fresh! work name))
        (built (nt/prepareAllIn cDir (suitePaths n) (nt/fingerprint) k))
        (bins (map (fn [(b nt/Built)] -> String (optionOr b.binary "")) built))
        (_ (ageTree! cDir (- (nowNs) 36000000000000)))
        (_ (nt/sweepStoreHardWith! cDir 0 600000000000))
        (during (slotsLeft! cDir))
        (_ (nt/releaseHold! cDir))
        (_ (nt/sweepStoreHardWith! cDir 0 600000000000))
        (after (slotsLeft! cDir))
        (out (problems (list (pair (= (listLength bins) n) "builds missing")
                             (pair (= during n) (str "slots held during the run phase " (stringFromInt64 during) " of " (stringFromInt64 n)))
                             (pair (= after 0) (str "slots left after release " (stringFromInt64 after))))))
        (_ (pathRemove cDir))]
    out)

fn ! configRead! work: String -> String
  (let [(cDir (fresh! work "cfg"))
        (_ (fileWrite (str cDir "/.asl.config.asn") "(:aslConfig :native (:storeHardCap 3G :storeHardMinAge 5m))\n"))
        (out (problems (list (pair (= (nb/defaultStoreHardCap) 8589934592) "default is not 8G")
                             (pair (= (nb/storeHardCapFor! cDir) 3221225472) "storeHardCap unread")
                             (pair (= (nb/storeHardMinAgeNs! cDir) 300000000000) "storeHardMinAge unread"))))
        (_ (pathRemove cDir))]
    out)

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslNtHardCap." (stringFromInt64 (procSelf))))
        (made (dirCreate work))
        (a (oldestFirst! work)) (b (leaseKept! work)) (c (underCap! work)) (d (underMarker! work))
        (e (softAndHard! work)) (f (recheckPins! work)) (g (rotates! work))
        (h (heldUntilRun! work "held4" 4 4)) (i (heldUntilRun! work "held1" 2 1))
        (j (configRead! work))
        (_ (pathRemove work))]
    (do (assert (ok? made) "the scratch store exists")
        (assert (stringEmpty? a) (str "oldest first to the cap: " a))
        (assert (stringEmpty? b) (str "a live lease and a young slot stay: " b))
        (assert (stringEmpty? c) (str "under the cap nothing goes: " c))
        (assert (stringEmpty? d) (str "the hard sweep runs under a build marker: " d))
        (assert (stringEmpty? e) (str "with no marker the soft pass runs: " e))
        (assert (stringEmpty? f) (str "the removal rechecks the real pin: " f))
        (assert (stringEmpty? g) (str "receipts keep 200 rows: " g))
        (assert (stringEmpty? h) (str "k=4 holds pin slots until release: " h))
        (assert (stringEmpty? i) (str "k=1 holds pin slots until release: " i))
        (assert (stringEmpty? j) (str "config rows are read: " j))
        true))
