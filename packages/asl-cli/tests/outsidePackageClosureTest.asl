(module asl-cli/tests/outsidePackageClosureTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref NATIVETEST-OUTSIDE-CLOSURE-20261020 :do "asl test of a file outside the toolchain root, belonging to its own package (its own .asl.config.asn, two sibling modules, one importing the other), must resolve that package's full transitive import closure the same way asl check does; a single-file content-hash copy breaks the sibling import, so this fixture's test module imports a module that itself imports another module, exercising transitivity, not just a direct import")

fn ! fixtureRoot! -> String
  (str "/tmp/aslOutsidePkgClosureTest_" (stringFromInt64 (monotonicNs)))

fn ! configSource -> String
  "(:asl-config :workspace \"outsidepkgclosurefixture\"\n  :testData (\"data/ignored\"))\n"

fn ! aSource -> String
  (str
    "(module outsidepkgclosurefixture/a\n"
    "  :x [valueA]\n"
    "  :i [])\n"
    "\n"
    "fn valueA -> Int64\n"
    "  7\n")

fn ! bSource -> String
  (str
    "(module outsidepkgclosurefixture/b\n"
    "  :x [valueB]\n"
    "  :i [(outsidepkgclosurefixture/a :a oa)])\n"
    "\n"
    "fn valueB -> Int64\n"
    "  (* (oa/valueA) 5)\n")

fn ! testSource -> String
  (str
    "(module outsidepkgclosurefixture/theTest\n"
    "  :x [runTests]\n"
    "  :i [(outsidepkgclosurefixture/a :a oa) (outsidepkgclosurefixture/b :a ob)])\n"
    "\n"
    "fn ! runTests -> Bool\n"
    "  (do\n"
    "    (assert (= (oa/valueA) 7) \"direct sibling import resolves\")\n"
    "    (assert (= (ob/valueB) 35) \"transitive sibling import resolves\")\n"
    "    (assert (= (resultOr (fileReadString \"outsidepkgclosurefixture/data/rows.txt\") \"\") \"42\\n\") \"a data file of the package opens by its workspace-qualified path\")\n"
    "    (assert (stringContains? (resultOr (fileReadString \"outsidepkgclosurefixture/a.asl\") \"\") \"valueA\") \"a .asl source of the package opens as text by its workspace-qualified path\")\n"
    "    (assert (= (resultOr (fileReadString \"outsidepkgclosurefixture/data/ignored/big.txt\") \"\") \"9\\n\") \"a git-ignored data directory the package declares in :testData opens by its workspace-qualified path\")\n"
    "    (assert (= (resultOr (fileReadString \"data/ignored/big.txt\") \"\") \"9\\n\") \"a git-ignored declared data file opens relative to the package root\")\n"
    "    (assert (stringContains? (resultOr (fileReadString \"a.asl\") \"\") \"valueA\") \"a .asl source of the package opens as text relative to the package root\")\n"
    "    true)\n")

fn ! writeFile! path: String content: String -> (Result Unit String)
  (fileWrite path content)

fn ! buildFixture! root: String -> (Result String String)
  (let [(made (dirCreate root))]
    (match made
      ((err e) (err (str "cannot create " root ": " e)))
      ((ok _)
        (let [(wCfg (writeFile! (str root "/.asl.config.asn") (configSource)))
              (wA (writeFile! (str root "/a.asl") (aSource)))
              (wB (writeFile! (str root "/b.asl") (bSource)))
              (testPath (str root "/theTest.asl"))
              (dataDir (dirCreate (str root "/data")))
              (wData (writeFile! (str root "/data/rows.txt") "42\n"))
              (ignDir (dirCreate (str root "/data/ignored")))
              (wIgn (writeFile! (str root "/data/ignored/big.txt") "9\n"))
              (wGitIgnore (writeFile! (str root "/.gitignore") "data/ignored/\n"))
              (gitInit (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))
              (wTest (writeFile! testPath (testSource)))]
          (match wCfg
            ((err e) (err (str "cannot write .asl.config.asn: " e)))
            ((ok _)
              (match wA
                ((err e) (err (str "cannot write a.asl: " e)))
                ((ok _)
                  (match wB
                    ((err e) (err (str "cannot write b.asl: " e)))
                    ((ok _)
                      (match wTest
                        ((err e) (err (str "cannot write theTest.asl: " e)))
                        ((ok _) (if (= gitInit.exit 0) (ok testPath) (err (str "git init failed: " gitInit.out)))))))))))))))

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

; (:m :ref NOSELFHOST-OUTSIDECLOSURE-20261023 :do "the asl test child starts through asl/tools/fleet/run.asl with a timeout and descendant limit (spawnSafety), not a bare processRun; Done.out carries stdout and stderr together")
fn ! runAslTest! binAsl: String testPath: String -> fr/Done
  (fr/runOneLimited (fr/job (list binAsl "test" testPath) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testOutsidePackageClosureResolves! -> Bool
  (let [(root (fixtureRoot!))
        (builtR (buildFixture! root))]
    (match builtR
      ((err e) (assert false (str "fixture setup failed: " e)))
      ((ok testPath)
        (let [(binAsl (str (repoRoot!) "/bin/asl"))
              (result (runAslTest! binAsl testPath))
              (removed (pathRemove root))]
          (do
            (assert (= result.exit 0) (str "asl test on an externally-rooted package resolves its sibling imports and exits 0: " result.out))
            (assert (stringContains? result.out "assertion(s) executed") "the outside-package suite reports executed assertions")
            (assert (not (stringContains? (str result.out) "ERR_UNRESOLVED_IMPORT")) "no unresolved-import error for the sibling module")
            (assert (ok? removed) "fixture directory is removed")
            true)))))

; (:m :ref NATIVETEST-CACHE-KEY-IMPORTS-20261022 :do "a closure-load failure used to be cached keyed on the suite file alone, so editing only a module the suite imports kept serving the stale failure; the retired spelling is assembled from pieces so this file itself stays valid under the strict reader")
fn brokenASource -> String
  (str
    "(module outsidepkgclosurefixture/a\n"
    "  :x [valueA]\n"
    "  :i [])\n"
    "\n"
    "fn valueA -> Int64\n"
    "  (" "mt (some 7) ((some x) x) ((none) 0))\n")

fn ! testImportEditInvalidatesVerdict! -> Bool
  (let [(root (fixtureRoot!))
        (builtR (buildFixture! root))]
    (match builtR
      ((err e) (assert false (str "fixture setup failed: " e)))
      ((ok testPath)
        (let [(binAsl (str (repoRoot!) "/bin/asl"))
              (aPath (str root "/a.asl"))
              (broke (fileWrite aPath (brokenASource)))
              (first (runAslTest! binAsl testPath))
              (fixed (fileWrite aPath (aSource)))
              (second (runAslTest! binAsl testPath))
              (removed (pathRemove root))]
          (do
            (assert (ok? broke) "the imported module is broken first")
            (assert (not (= first.exit 0)) "a suite whose import fails to load fails")
            (assert (ok? fixed) "only the imported module is then repaired")
            (assert (= second.exit 0) (str "after editing only the imported module the cached failure is not served: " second.out))
            (assert (stringContains? second.out "assertion(s) executed") "the repaired suite reports executed assertions")
            (assert (ok? removed) "fixture directory is removed")
            true)))))

fn ! runTests -> Bool
  (and (testOutsidePackageClosureResolves!) (testImportEditInvalidatesVerdict!))
