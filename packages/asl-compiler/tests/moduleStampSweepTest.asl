(module asl-compiler/tests/moduleStampSweepTest
  :x [runTests]
  :i [(asl-compiler/checkCache :a cc) (asl-tools/fleet/run :a fr)])

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "the module body stamps under DIR/modules are swept by the same cap and oldest-first policy as the top level of a scratch cache; the real ~/.asl/cache/check is never touched")
fn ! stamp! dir: String i: Int64 -> Bool
  (let [(path (str dir "/m" (stringFromInt64 (+ 100 i)) ".verdict"))]
    (and (ok? (fileWrite path "aslBodyStamp 1\nm\n"))
         (ok? (fileUtime path (- (nowNs) (* (- 10 i) 60000000000))))))

fn ! verdictNames dir: String -> (List String)
  (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList dir) (list)))

fn ! testModulesSwept dir: String -> Bool
  (let [(mods (str dir "/modules"))
        (madeTop (listLength (filter (fn [(i Int64)] -> Bool (stamp! dir i)) (range 0 2))))
        (madeMods (listLength (filter (fn [(i Int64)] -> Bool (stamp! mods i)) (range 0 6))))
        (removed (cc/sweepWith! dir 4))
        (left (verdictNames mods))
        (top (verdictNames dir))]
    (do (assert (= madeTop 2) (str "2 top-level stamps written: " (stringFromInt64 madeTop)))
        (assert (= madeMods 6) (str "6 module stamps written: " (stringFromInt64 madeMods)))
        (assert (= removed 2) (str "the sweep removes the 2 module stamps over the cap: " (stringFromInt64 removed)))
        (assert (= (listLength left) 4) (str "the modules dir ends at the cap of 4: " (stringFromInt64 (listLength left))))
        (assert (listContains? left "m105.verdict") "the newest module stamp stays")
        (refute (listContains? left "m101.verdict") "the second oldest module stamp goes")
        (refute (listContains? left "m100.verdict") "the oldest module stamp goes")
        (assert (= (listLength top) 2) "the top level under its cap loses nothing")
        (refute (fileExists? (str mods "/sweep.lock")) "the modules sweep releases its lock")
        true))

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslModuleStampSweep." (stringFromInt64 (procSelf))))
        (dir (str work "/cache"))
        (made (ok? (dirCreate (str dir "/modules"))))
        (swept (if made (testModulesSwept dir) false))
        (cleaned (fr/runGuarded (list "/bin/rm" "-rf" work) "/" (fr/childEnv (list)) (fr/limits 60 4)))]
    (do (assert made (str "the scratch cache under " work " is created"))
        (assert swept "module stamps are swept at the cap, oldest first")
        (assert (= cleaned.exitCode 0) "the scratch cache is removed")
        true))
