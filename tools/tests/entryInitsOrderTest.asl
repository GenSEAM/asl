(module asl-tools/tests/entryInitsOrderTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref NT-CACHE-ABS-PATH-KEY :do "the entry object must not depend on which units were cached when it was built: in a private store q is compiled first, then a suite importing p and q is built with p at llc and q cached, then the suite slots are dropped and the suite is built again with every unit cached; the second build must find the entry object of the first, so the set of objects stays the same. With inits in settle order the first build keys the entry on (q p), the second on (p q), and one more object appears")

fn ! fixtureName! -> String
  (str "tools/tests/tmpEntryInits" (stringFromInt64 (monotonicNs)))

fn lib dir: String leaf: String fnName: String step: String -> String
  (str "(module " dir "/" leaf "\n  :x [" fnName "]\n  :i [])\n\nfn " fnName " xs: (List Int64) -> (List Int64)\n  (map (fn [(x Int64)] -> Int64 (+ x " step ")) xs)\n")

fn warmSuite dir: String -> String
  (str "(module " dir "/warmTest\n  :x [runTests]\n  :i [(" dir "/q :a oq)])\n\nfn ! runTests -> Bool\n  (do\n    (assert (= (listLength (oq/addTwo (list 1 2))) 2) \"q runs\")\n    true)\n")

fn bothSuite dir: String -> String
  (str "(module " dir "/bothTest\n  :x [runTests]\n  :i [(" dir "/p :a op) (" dir "/q :a oq)])\n\nfn ! runTests -> Bool\n  (do\n    (assert (= (listLength (oq/addTwo (op/addOne (list 1 2)))) 2) \"p and q run\")\n    true)\n")

fn ! runSuite! cache: String path: String -> fr/Done
  (let [(root (resultOr (realPath ".") "."))]
    (fr/runOneLimited (fr/job (list (str root "/bin/asl") "test" path) root (fr/childEnv (list (str "ASL_NATIVE_TEST_CACHE=" cache)))) (fr/limits 900 64)))

fn ! objectsIn cache: String -> (List String)
  (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".o")) (resultOr (dirList (str cache "/modules")) (list))))

fn ! dropSlots! cache: String -> Bool
  (fold (fn [(acc Bool) (n String)] -> Bool (and acc (ok? (pathRemove (str cache "/" n)))))
        true
        (filter (fn [(n String)] -> Bool (= (stringLength n) 64)) (resultOr (dirList cache) (list))))

fn ! runTests -> Bool
  (let [(dir (fixtureName!))
        (cache (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/entryInitsOrderTest.XXXXXX" 5000) "")))
        (made (dirCreate dir))
        (wrote (and (ok? (fileWrite (str dir "/p.asl") (lib dir "p" "addOne" "1")))
                    (and (ok? (fileWrite (str dir "/q.asl") (lib dir "q" "addTwo" "2")))
                         (and (ok? (fileWrite (str dir "/warmTest.asl") (warmSuite dir)))
                              (ok? (fileWrite (str dir "/bothTest.asl") (bothSuite dir)))))))
        (warm (runSuite! cache (str dir "/warmTest.asl")))
        (afterWarm (objectsIn cache))
        (mixed (runSuite! cache (str dir "/bothTest.asl")))
        (afterMixed (objectsIn cache))
        (dropped (dropSlots! cache))
        (cached (runSuite! cache (str dir "/bothTest.asl")))
        (afterCached (objectsIn cache))
        (removed (and (ok? (pathRemove dir)) (and (stringStartsWith? cache "/tmp/entryInitsOrderTest.") (ok? (pathRemove cache)))))]
    (do
      (assert (and (ok? made) wrote) "fixture modules are written inside the workspace")
      (assert (stringStartsWith? cache "/tmp/entryInitsOrderTest.") "a private store is made")
      (assert (= warm.exit 0) (str "the suite importing q alone passes: " warm.out))
      (assert (= mixed.exit 0) (str "the suite importing p and q passes with q cached: " mixed.out))
      (assert (> (listLength afterMixed) (listLength afterWarm)) "the second suite compiled units beside the cached q")
      (assert dropped "the suite slots are dropped, the objects stay")
      (assert (= cached.exit 0) (str "the same suite passes again from cached objects: " cached.out))
      (assert (stringContains? cached.out "assertion(s) executed") "the rebuilt suite reports executed assertions")
      (assert (= afterCached afterMixed) (str "a build with every unit cached reuses the entry object built beside a compile; new objects: "
                                              (stringJoin (filter (fn [(n String)] -> Bool (not (listContains? afterMixed n))) afterCached) " ")))
      (assert removed "fixture and private store are removed")
      true))
