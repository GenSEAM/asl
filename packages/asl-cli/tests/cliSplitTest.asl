(module asl-cli/tests/cliSplitTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/nativeBuild :a nb)
      (asl/packages/asl-cli/src/irSplit :a ir)
      (asl-parser/ast :a a)
      (asl-checker/resolve :a r)])

; (:m :ref CLI-MODULE-OBJECTS :do "the CLI's cached link recompiles the bucket of every module an edit changes, so the modules sharing a bucket are compiled with it; over the real closure of native.asl, split the way a CLI build splits it, a one-module edit must reach few other modules, as a per-module object store would")
fn entry -> String
  "asl/packages/asl-cli/src/native.asl"

fn mangled name: String -> String
  (stringReplace (stringReplace (stringReplace name "-" "$2D") "/" "$2F") "." "$2E")

fn ! closureGroups! root: String -> (Result (List String) String)
  (match (fileReadString (str root "/" (entry)))
    ((err e) (err (str "cannot read " (entry) ": " e)))
    ((ok src) (match (a/parse src)
      ((err pe) (err (str (entry) ":" pe.line ": " pe.msg)))
      ((ok forms) (let [(summary (r/collectSummary forms (entry)))]
        (match (r/loadModuleDeps! (cons (r/parentDirOf (entry)) (list ".")) (r/mapValuesList summary.imports))
          ((err e) (err (str "the closure of " (entry) " does not load: " e)))
          ((ok closure) (ok (distinct (cons (mangled summary.name)
                                  (filter (fn [(g String)] -> Bool (stringContains? g "$2F"))
                                          (map (fn [(m r/ModuleSummary)] -> String (mangled m.name)) (mapValues closure)))))))))))))

fn distinct xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (= (listHead acc) (some x)) acc (cons x acc))) (list) (listSort xs)))

fn mates groups: (List String) n: Int64 g: String -> Int64
  (let [(home (ir/bucketOf g n))]
    (listLength (filter (fn [(o String)] -> Bool (= (ir/bucketOf o n) home)) groups)))

fn meanMatesX100 groups: (List String) n: Int64 -> Int64
  (if (listEmpty? groups) 0
    (/ (* 100 (fold (fn [(acc Int64) (g String)] -> Int64 (+ acc (mates groups n g))) 0 groups)) (listLength groups)))

fn cliBuckets -> Int64
  (let [(b (nb/Build :root "" :cache "" :tmp "" :lib "" :base "" :clangVersion "" :owner "" :deadlineNs 0 :maxDesc 0))]
    b.buckets)

fn ! testClosureSplit root: String -> Bool
  (match (closureGroups! root)
    ((err e) (do (assert false e) false))
    ((ok groups) (let [(n (cliBuckets))
                       (mean (meanMatesX100 groups n))
                       (edited (mangled "asl-cli/irSplit"))]
      (do (println (str "(:cliSplit :groups " (stringFromInt64 (listLength groups)) " :buckets " (stringFromInt64 n) " :meanMatesX100 " (stringFromInt64 mean) " :meanMatesX100At16 " (stringFromInt64 (meanMatesX100 groups 16)) " :irSplitMates " (stringFromInt64 (mates groups n edited)) ")"))
          (assert (> (listLength groups) 200) (str "the CLI closure holds its module groups: " (stringFromInt64 (listLength groups))))
          (assert (listContains? groups edited) "irSplit is in the CLI closure")
          (assert (<= mean 500) (str "a one-module edit recompiles at most 5 modules on average, not a large share of cli.ll: mean x100 " (stringFromInt64 mean) " over " (stringFromInt64 (listLength groups)) " groups in " (stringFromInt64 n) " buckets"))
          (assert (<= (mates groups n edited) 8) (str "an irSplit edit compiles a part shared with few modules: " (stringFromInt64 (mates groups n edited))))
          (assert (= (meanMatesX100 groups 0) 100) "one part per module recompiles the edited module alone")
          true))))

fn ! testConfigured root: String -> Bool
  (let [(dir (str root "/.asl/cache/cliSplitTest." (stringFromInt64 (procSelf))))
        (made (and (ok? (dirCreate dir)) (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"csfx\" :root true :native (:buckets 0))\n"))))
        (zero (nb/bucketsFor! dir))
        (_ (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"csfx\" :root true :native (:buckets 32))\n"))
        (some32 (nb/bucketsFor! dir))
        (_ (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"csfx\" :root true :native (:buckets -3))\n"))
        (bad (nb/bucketsFor! dir))
        (refused (nb/setup! dir (str dir "/cache") ""))
        (_ (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"csfx\" :root true :native (:buckets many))\n"))
        (word (nb/bucketsFor! dir))
        (cleaned (pathRemove dir))]
    (do (assert made (str "the config fixture " dir " was written"))
        (assert (= zero (ok 0)) (str ":native :buckets 0 keeps one part per module: " (stringFromInt64 (resultOr zero -1))))
        (assert (= some32 (ok 32)) (str ":native :buckets 32 is taken: " (stringFromInt64 (resultOr some32 -1))))
        (assert (match bad ((err e) (= e "ERR_CONFIG: :native :buckets must be 0..4096, got -3")) ((ok _) false)) "an out-of-range row is a config error, not the default")
        (assert (match word ((err e) (stringContains? e "must be an integer, got many")) ((ok _) false)) "a non-integer row is a config error")
        (assert (match refused ((err e) (stringContains? e ":native :buckets")) ((ok _) false)) "a build under a bad :buckets row fails with the config error before building")
        (assert (err? (nb/bucketsValue "4097")) "a bucket count above 4096 is refused")
        (assert (= (nb/defaultBuckets) (cliBuckets)) "a Build without a :buckets field uses the CLI default")
        (assert (ok? cleaned) "the config fixture was removed")
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))]
    (do (assert (testClosureSplit root) "the CLI closure split")
        (assert (testConfigured root) "the configured bucket count")
        true))
