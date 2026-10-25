(module asl-cli/tests/asl1CacheStampTest
  :x [runTests main]
  :i [(asl-cli/asl1Cache :a cache) (asl-cli/system :a sys)])

fn ! tempRoot -> String
  (str "/tmp/asl1CacheStampTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs)))

fn ! check condition: Bool message: String -> Bool
  (do (assert condition message) condition)

; (:m :ref WARMBUILD :do "probe waits past a 100 ms racy window so a stamp may be recorded; probeProd uses the production 2 s window")
fn ! probe stamps: String path: String -> (Result (Pair String Bool) String)
  (do (sleepMs 150)
      (cache/memoShaIn! stamps path (optionOr (listHead (cache/statFacts! (list path))) "") 100000000))

fn ! probeProd stamps: String path: String -> (Result (Pair String Bool) String)
  (cache/memoSha! stamps path (optionOr (listHead (cache/statFacts! (list path))) ""))

fn ! digestOf r: (Result (Pair String Bool) String) -> String
  (match r ((ok p) (pairFirst p)) ((err e) (str "ERR " e)))

fn ! hitOf r: (Result (Pair String Bool) String) -> Bool
  (match r ((ok p) (pairSecond p)) ((err _) false))

fn ! ageTo! path: String ageNs: Int64 -> Bool
  (ok? (fileUtime path (- (nowNs) ageNs)))

; (:m :ref WARMBUILD :do "one byte of a 4 KiB file differs: same size, new content")
fn body byte: String -> String
  (str byte (stringRepeat "a" 4095))

fn shaOfBody byte: String -> String
  (bytesSha256 (stringToBytes (body byte)))

fn ! restoreMtime! path: String mtimeNs: Int64 -> Bool
  (ok? (fileUtime path mtimeNs))

fn ! testBasics root: String stamps: String -> Bool
  (let [(file (str root "/dep.asl"))
        (wrote (ok? (fileWrite file (body "x"))))
        (aged (ageTo! file 10000000000))
        (first (probe stamps file))
        (second (probe stamps file))
        (mutated (ok? (fileWrite file (body "y"))))
        (agedAgain (ageTo! file 20000000000))
        (third (probe stamps file))
        (fourth (probe stamps file))
        (fresh (str root "/fresh.asl"))
        (freshWrote (ok? (fileWrite fresh (body "z"))))
        (freshFirst (probeProd stamps fresh))
        (freshSecond (probeProd stamps fresh))
        (missing (probe stamps (str root "/absent.asl")))]
    (do (check (and wrote (and aged (and mutated (and agedAgain freshWrote)))) "fixture files written")
        (check (and (= (digestOf first) (shaOfBody "x")) (not (hitOf first))) "the first digest of a file is computed from its content, not answered by a stamp")
        (check (and (= (digestOf second) (shaOfBody "x")) (hitOf second)) "an unchanged file is answered by its stamp and skips the re-hash")
        (check (and (= (digestOf third) (shaOfBody "y")) (not (hitOf third))) "changing one byte at the same size yields the new content digest and re-hashes")
        (check (and (= (digestOf fourth) (shaOfBody "y")) (hitOf fourth)) "the stamp follows the new content")
        (check (and (= (digestOf freshFirst) (shaOfBody "z")) (and (not (hitOf freshFirst)) (not (hitOf freshSecond)))) "a file modified within the racy window is never answered by a stamp")
        (check (err? missing) "an absent file is an error, not a stale stamp")
        true))

fn ! testForgedMtime root: String stamps: String -> Bool
  (let [(file (str root "/forged.asl"))
        (wrote (ok? (fileWrite file (body "p"))))
        (mtime (- (nowNs) 30000000000))
        (aged (restoreMtime! file mtime))
        (first (probe stamps file))
        (hit (probe stamps file))
        (rewrote (ok? (fileWrite file (body "q"))))
        (restored (restoreMtime! file mtime))
        (forged (probe stamps file))
        (grown (ok? (fileWrite file (str (body "q") "extra"))))
        (grownAged (restoreMtime! file mtime))
        (size (probe stamps file))]
    (do (check (and wrote (and aged (and rewrote (and restored (and grown grownAged))))) "forged-mtime fixture written")
        (check (hitOf hit) "the forged-mtime fixture starts with a live stamp")
        (check (and (= (digestOf forged) (shaOfBody "q")) (not (hitOf forged))) "same size and restored mtime with different content misses because ctime moved")
        (check (and (= (digestOf size) (bytesSha256 (stringToBytes (str (body "q") "extra")))) (not (hitOf size))) "a size-only change misses")
        (check (= (digestOf first) (shaOfBody "p")) "the forged-mtime fixture hashes its first content")
        true))

fn ! testInodeReplace root: String stamps: String -> Bool
  (let [(file (str root "/swap.asl"))
        (wrote (ok? (fileWrite file (body "m"))))
        (mtime (- (nowNs) 30000000000))
        (aged (restoreMtime! file mtime))
        (first (probe stamps file))
        (hit (probe stamps file))
        (copy (str root "/swap.copy"))
        (copied (sys/capture! (list "cp" "-p" file copy) (none)))
        (rewrote (ok? (fileWrite copy (body "n"))))
        (restored (restoreMtime! copy mtime))
        (moved (ok? (pathRename copy file)))
        (swapped (probe stamps file))]
    (do (check (and wrote (and aged (and (ok? copied) (and rewrote (and restored moved))))) "inode-replace fixture written")
        (check (and (hitOf hit) (= (digestOf first) (shaOfBody "m"))) "the inode-replace fixture starts with a live stamp")
        (check (and (= (digestOf swapped) (shaOfBody "n")) (not (hitOf swapped))) "cp -p then mv with the same size and mtime but new content misses")
        true))

fn ! testMalformed root: String stamps: String -> Bool
  (let [(file (str root "/mal.asl"))
        (wrote (ok? (fileWrite file (body "r"))))
        (aged (ageTo! file 30000000000))
        (facts (optionOr (listHead (cache/statFacts! (list file))) ""))
        (first (probe stamps file))
        (stampNames (filter (fn [(n String)] -> Bool (not (stringContains? n ".part."))) (resultOr (dirList stamps) (list))))
        (entries (filter (fn [(n String)] -> Bool (not (stringEmpty? n))) stampNames))
        (hits (map (fn [(n String)] -> Bool
                (and (ok? (fileWrite (str stamps "/" n) (str facts " " (stringRepeat "Z" 64) "\n")))
                     (hitOf (probe stamps file)))) entries))]
    (do (check (and wrote aged) "malformed-stamp fixture written")
        (check (not (listContains? hits true)) "a stamp whose digest is not 64 lowercase hex is rejected and the file is re-hashed")
        (check (= (digestOf (probe stamps file)) (shaOfBody "r")) "the re-hash of a rejected stamp yields the content digest")
        (check (not (stringEmpty? (digestOf first))) "the malformed-stamp fixture hashed")
        true))

fn ! testSweep root: String stamps: String -> Bool
  (let [(file (str root "/sweep.asl"))
        (wrote (ok? (fileWrite file (body "s"))))
        (aged (ageTo! file 30000000000))
        (dirMade (ok? (dirCreate stamps)))
        (oldPart (str stamps "/x.part.1x1"))
        (newPart (str stamps "/y.part.2x2"))
        (partsWritten (and (ok? (fileWrite oldPart "t")) (ok? (fileWrite newPart "t"))))
        (partAged (ageTo! oldPart 172800000000000))
        (probed (probe stamps file))]
    (do (check (and wrote (and aged (and dirMade (and partsWritten partAged)))) "sweep fixture written")
        (check (and (not (fileExists? oldPart)) (fileExists? newPart)) "a stamp part file older than a day is removed on the next record, a recent one stays")
        (check (ok? probed) "the sweep fixture hashed")
        true))

fn ! runTests -> Bool
  (let [(root (tempRoot))
        (stamps (str root ".stamps"))
        (made (ok? (dirCreate root)))
        (a (testBasics root stamps))
        (b (testForgedMtime root stamps))
        (c (testInodeReplace root stamps))
        (d (testMalformed root (str root ".stamps2")))
        (e (testSweep root (str root ".stamps3")))
        (cleaned (sys/capture! (list "rm" "-rf" root stamps (str root ".stamps2") (str root ".stamps3")) (none)))]
    (do (check made "temp root created")
        (check (ok? cleaned) "temp root and stamp dir removed")
        (and a (and b (and c (and d e))))))

fn ! main -> Bool
  (runTests)
