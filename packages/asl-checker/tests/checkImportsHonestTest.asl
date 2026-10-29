(module asl-checker/tests/checkImportsHonestTest
  :x [runTests]
  :i [(asl-checker/checkCached :a cc) (asl-checker/types :a ty) (asl-tools/fleet/run :a fr)])

; (:m :ref CHECK-IMPORTS-HONEST :do "an importer of a module with a type error is not ok, names that module, and counts what it checked and what it summarised; a clean closure is stamped in a scratch dir and summarised on the next run, an edited dependency or a dirty closure is checked again")
fn brokenSrc -> String
  "(module lib/broken :x [half] :i [])\n\nfn half x: Int64 -> Int64\n  (str x \"/2\")\n"

fn fineSrc n: Int64 -> String
  (str "(module lib/fine :x [twice] :i [])\n\nfn twice x: Int64 -> Int64\n  (* x " (stringFromInt64 n) ")\n")

fn importerSrc name: String dep: String fnName: String -> String
  (str "(module " name " :x [main] :i [(lib/" dep " :a d)])\n\nfn main -> Int64\n  (d/" fnName " 4)\n")

fn ! verdictOf! path: String cache: cc/Cache -> (Pair cc/Verdict cc/Cache)
  (let [(r (cc/checkFileCached! path (list) cache))]
    (pair (resultOr (pairFirst r) (cc/Verdict :diags (list) :checked -1 :summarised -1)) (pairSecond r)))

fn ! setup! ws: String -> Bool
  (and (ok? (dirCreate (str ws "/lib")))
       (and (ok? (fileWrite (str ws "/.asl.config.asn") "(:asl-config :workspace \"checkImportsHonest\" :version \"1.0.0\")\n"))
            (and (ok? (fileWrite (str ws "/lib/broken.asl") (brokenSrc)))
                 (and (ok? (fileWrite (str ws "/lib/fine.asl") (fineSrc 2)))
                      (and (ok? (fileWrite (str ws "/bad.asl") (importerSrc "bad" "broken" "half")))
                           (and (ok? (fileWrite (str ws "/good.asl") (importerSrc "good" "fine" "twice")))
                                (ok? (fileWrite (str ws "/also.asl") (importerSrc "also" "fine" "twice")))))))))

fn ! testBroken ws: String -> Bool
  (let [(v (pairFirst (verdictOf! (str ws "/bad.asl") (cc/emptyCache))))
        (inDep (filter (fn [(d ty/Diagnostic)] -> Bool (stringEndsWith? d.path "/lib/broken.asl")) v.diags))]
    (do (assert (> (listLength v.diags) 0) "an importer of a module with a type error is not ok")
        (assert (= (listLength inDep) (listLength v.diags)) "every diagnostic names the broken dependency, not the importer")
        (assert (= (optionOr (optionMap (fn [(d ty/Diagnostic)] -> Int64 d.line) (listHead inDep)) 0) 4) "the diagnostic points at the dependency's line 4")
        (assert (= (cc/countsText v) "(:checked 2 :summarised 0)") (str "the importer and its dependency are both checked: " (cc/countsText v)))
        true))

fn ! testClean ws: String -> Bool
  (let [(v (pairFirst (verdictOf! (str ws "/good.asl") (cc/emptyCache))))]
    (do (assert (listEmpty? v.diags) "an importer of a clean module stays ok")
        (assert (= (cc/countsText v) "(:checked 2 :summarised 0)") (str "a clean closure is checked in full: " (cc/countsText v)))
        true))

fn ! testShared ws: String -> Bool
  (let [(first (verdictOf! (str ws "/good.asl") (cc/emptyCache)))
        (second (pairFirst (verdictOf! (str ws "/also.asl") (pairSecond first))))]
    (do (assert (listEmpty? second.diags) "a second importer of a checked module stays ok")
        (assert (= (cc/countsText second) "(:checked 1 :summarised 1)") (str "a module checked earlier in the run is summarised: " (cc/countsText second)))
        true))

fn ! testStamps ws: String stamps: String -> Bool
  (let [(id "cli-0000000000000000000000000000000000000000000000000000000000000001")
        (cold (pairFirst (verdictOf! (str ws "/good.asl") (cc/stampCacheAt stamps id))))
        (written (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList stamps) (list)))))
        (warm (pairFirst (verdictOf! (str ws "/good.asl") (cc/stampCacheAt stamps id))))
        (otherChecker (pairFirst (verdictOf! (str ws "/good.asl") (cc/stampCacheAt stamps "cli-0000000000000000000000000000000000000000000000000000000000000002"))))
        (edited (fileWrite (str ws "/lib/fine.asl") (fineSrc 3)))
        (afterEdit (pairFirst (verdictOf! (str ws "/good.asl") (cc/stampCacheAt stamps id))))
        (dirty1 (pairFirst (verdictOf! (str ws "/bad.asl") (cc/stampCacheAt stamps id))))
        (dirty2 (pairFirst (verdictOf! (str ws "/bad.asl") (cc/stampCacheAt stamps id))))]
    (do (assert (= (cc/countsText cold) "(:checked 2 :summarised 0)") (str "the first run checks the dependency body: " (cc/countsText cold)))
        (assert (= written 1) (str "a clean closure writes one stamp: " (stringFromInt64 written)))
        (assert (= (cc/countsText warm) "(:checked 1 :summarised 1)") (str "the next run summarises the stamped dependency: " (cc/countsText warm)))
        (assert (= (cc/countsText otherChecker) "(:checked 2 :summarised 0)") (str "another checker build does not trust the stamp: " (cc/countsText otherChecker)))
        (assert (ok? edited) "the dependency is edited")
        (assert (= (cc/countsText afterEdit) "(:checked 2 :summarised 0)") (str "an edited dependency is checked again: " (cc/countsText afterEdit)))
        (assert (and (> (listLength dirty1.diags) 0) (> (listLength dirty2.diags) 0)) "a dirty closure is never stamped, so every run reports it")
        (assert (= (cc/countsText dirty2) "(:checked 2 :summarised 0)") (str "the broken dependency is checked on every run: " (cc/countsText dirty2)))
        true))

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslCheckImportsHonest." (stringFromInt64 (procSelf))))
        (ws (str work "/ws"))
        (stamps (str work "/stamps"))
        (made (setup! ws))
        (broken (if made (testBroken ws) false))
        (clean (if made (testClean ws) false))
        (shared (if made (testShared ws) false))
        (stamped (if made (testStamps ws stamps) false))
        (cleaned (fr/runGuarded (list "/bin/rm" "-rf" work) "/" (fr/childEnv (list)) (fr/limits 60 4)))]
    (do (assert made (str "the scratch workspace under " work " is created"))
        (assert broken "an importer of a broken module fails naming it")
        (assert clean "an importer of a clean module passes")
        (assert shared "a shared dependency is checked once per run")
        (assert stamped "clean closures are stamped and stale stamps are not trusted")
        (assert (= cleaned.exitCode 0) "the scratch workspace is removed")
        true))
