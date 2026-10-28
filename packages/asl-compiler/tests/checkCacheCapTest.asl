(module asl-compiler/tests/checkCacheCapTest
  :x [runTests]
  :i [(asl-compiler/checkCache :a cc) (asl-tools/fleet/run :a fr)])

; (:m :ref CHECK-VERDICT-CAP :do "a scratch cache of 80 verdicts with ascending mtimes swept at cap 50 keeps the 50 newest; the real ~/.asl/cache/check is never touched")
fn ! verdict! dir: String i: Int64 -> Bool
  (let [(path (str dir "/k" (stringFromInt64 (+ 100 i)) ".verdict"))]
    (and (ok? (fileWrite path (cc/encodeVerdict "k" (cc/Verdict :exitCode 0 :body ""))))
         (ok? (fileUtime path (- (nowNs) (* (- 80 i) 60000000000))))))

fn ! testSweep dir: String -> Bool
  (let [(made (listLength (filter (fn [(i Int64)] -> Bool (verdict! dir i)) (range 0 80))))
        (other (fileWrite (str dir "/notes.txt") "kept"))
        (removed (cc/sweepWith! dir 50))
        (left (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList dir) (list))))
        (again (cc/sweepWith! dir 50))]
    (do (assert (= made 80) (str "80 verdicts written: " (stringFromInt64 made)))
        (assert (= removed 30) (str "the sweep removes the 30 over the cap: " (stringFromInt64 removed)))
        (assert (<= (listLength left) 50) (str "the cache ends at the cap of 50: " (stringFromInt64 (listLength left))))
        (assert (listContains? left "k179.verdict") "the newest verdict stays")
        (assert (listContains? left "k130.verdict") "the 50th newest stays")
        (refute (listContains? left "k129.verdict") "the 51st newest goes")
        (refute (listContains? left "k100.verdict") "the oldest goes")
        (assert (fileExists? (str dir "/notes.txt")) "a file that is not a verdict is left alone")
        (assert (= again 0) "a cache at its cap loses nothing more")
        (refute (fileExists? (str dir "/sweep.lock")) "the sweep releases its lock")
        true))

fn ! testLockHeld dir: String -> Bool
  (let [(_w (verdict! dir 0))
        (_x (verdict! dir 1))
        (_l (fileWrite (str dir "/sweep.lock") "1"))
        (blocked (cc/sweepWith! dir 1))
        (count (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList dir) (list)))))]
    (do (assert (= blocked 0) "a held lock stops a second sweep")
        (assert (= count 2) (str "and nothing is removed under it: " (stringFromInt64 count)))
        true))

fn testCapOf -> Bool
  (do (assert (= (cc/capOf "(:aslConfig)\n(:check :cacheCap 50)\n") 50) "the (:check :cacheCap N) row sets the cap")
      (assert (= (cc/capOf "(:aslConfig)\n") (cc/defaultCap)) "no row means the default")
      (assert (= (cc/capOf "(:check :cacheCap lots)") (cc/defaultCap)) "a word is no cap")
      (assert (= (cc/capOf "(:check :cacheCap 0)") (cc/defaultCap)) "nor is zero")
      (assert (= (cc/defaultCap) 20000) "the default is 20000 verdicts")
      true)

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslCheckCacheCap." (stringFromInt64 (procSelf))))
        (sweepDir (str work "/sweep"))
        (lockDir (str work "/lock"))
        (made (and (ok? (dirCreate sweepDir)) (ok? (dirCreate lockDir))))
        (swept (if made (testSweep sweepDir) false))
        (locked (if made (testLockHeld lockDir) false))
        (caps (testCapOf))
        (cleaned (fr/runGuarded (list "/bin/rm" "-rf" work) "/" (fr/childEnv (list)) (fr/limits 60 4)))]
    (do (assert made (str "the scratch caches under " work " are created"))
        (assert swept "80 verdicts swept at cap 50 keep the 50 newest")
        (assert locked "a held sweep lock is respected")
        (assert caps "the cap row parses")
        (assert (= cleaned.exitCode 0) "the scratch caches are removed")
        true))
