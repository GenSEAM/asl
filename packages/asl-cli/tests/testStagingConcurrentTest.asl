(module asl-cli/tests/testStagingConcurrentTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref STAGE-CONCURRENT-RUNS :do "asl test of a package outside the root restages it into outsidePkg/<digest> on every run; a run must not replace an unchanged staged file (a concurrent run reading it then hit a removed or half-cloned data file), a changed source must land by rename (a new file, never rewritten in place), and two runs started together both pass. A hidden hard link pins each first staged file, so its inode cannot be reused and a replaced file shows as a different inode")
fn ! fixtureRoot! -> String
  (str "/tmp/aslTestStagingConcurrentTest_" (stringFromInt64 (monotonicNs)))

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! testSource -> String
  (str
    "(module stageconcurrentfixture/theTest\n"
    "  :x [runTests]\n"
    "  :i [(stageconcurrentfixture/a :a oa)])\n"
    "\n"
    "fn ! runTests -> Bool\n"
    "  (do (assert (= (oa/valueA) 7) \"a resolves\")\n"
    "      (assert (= (resultOr (fileSize \"data/rows.bin\") 0) 65536) \"the staged data file is whole\")\n"
    "      true)\n")

fn moduleA body: String -> String
  (str "(module stageconcurrentfixture/a\n  :x [valueA]\n  :i [])\n\nfn valueA -> Int64\n  " body "\n")

fn ! aslTest! testPath: String -> fr/Job
  (fr/job (list (str (repoRoot!) "/bin/asl") "test" testPath) (repoRoot!) (fr/childEnv (list)))

fn ! runOne! testPath: String -> fr/Done
  (fr/runOneLimited (aslTest! testPath) (fr/limits 900 64))

fn ! pin! path: String link: String -> Bool
  (let [(d (fr/runOneLimited (fr/job (list "ln" "-f" "--" path link) "/" (fr/childEnv (list))) (fr/limits 30 4)))]
    (= d.exit 0))

fn ! inode! path: String -> String
  (let [(d (fr/runOneLimited (fr/job (list "ls" "-i" "--" path) "/" (fr/childEnv (list))) (fr/limits 30 4)))]
    (if (= d.exit 0) (optionOr (listHead (stringSplit (stringTrim d.out) " ")) "") ""))

fn ! leftovers! dir: String -> Int64
  (let [(d (fr/runOneLimited (fr/job (list "find" dir "-name" ".part.*" "-o" "-name" ".stage.*") "/" (fr/childEnv (list))) (fr/limits 60 4)))]
    (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines d.out))))

fn ! testStagingAcrossRuns! -> Bool
  (let [(root (fixtureRoot!))
        (made (dirCreate root))
        (wCfg (fileWrite (str root "/.asl.config.asn") "(:asl-config :workspace \"stageconcurrentfixture\"\n  :testData (\"data/rows.bin\"))\n"))
        (wA (fileWrite (str root "/a.asl") (moduleA "7")))
        (dd (dirCreate (str root "/data")))
        (wD (fileWrite (str root "/data/rows.bin") (stringRepeat "r" 65536)))
        (wIgn (fileWrite (str root "/.gitignore") "data/\n"))
        (wTest (fileWrite (str root "/theTest.asl") (testSource)))
        (gitInit (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))
        (stage (str (repoRoot!) "/.asl/cache/nativeTest/outsidePkg/" (bytesSha256 (stringToBytes (resultOr (realPath root) root)))))
        (testPath (str root "/theTest.asl"))
        (run1 (runOne! testPath))
        (probes (and (pin! (str stage "/data/rows.bin") (str stage "/.probeData")) (pin! (str stage "/a.asl") (str stage "/.probeA"))))
        (data1 (inode! (str stage "/.probeData")))
        (a1 (inode! (str stage "/.probeA")))
        (run2 (runOne! testPath))
        (data2 (inode! (str stage "/data/rows.bin")))
        (a2 (inode! (str stage "/a.asl")))
        (wA3 (fileWrite (str root "/a.asl") (moduleA "(+ 3 4)")))
        (run3 (runOne! testPath))
        (a3 (inode! (str stage "/a.asl")))
        (a3text (resultOr (fileReadString (str stage "/a.asl")) ""))
        (both (fr/runPoolLimited (list (aslTest! testPath) (aslTest! testPath)) 2 (fr/limits 900 64)))
        (left (leftovers! stage))
        (removed (fr/runOneLimited (fr/job (list "rm" "-rf" "--" root) "/" (fr/childEnv (list))) (fr/limits 60 4)))]
    (do
      (assert (and (ok? made) (and (ok? wCfg) (and (ok? wA) (and (ok? wD) (and (ok? wTest) (= gitInit.exit 0)))))) "fixture written")
      (assert (= run1.exit 0) (str "first run passes: " run1.out))
      (assert (and probes (and (not (stringEmpty? data1)) (not (stringEmpty? a1)))) (str "first run stages the data file and the module, each pinned by a hidden hard link: " data1 " " a1))
      (assert (= run2.exit 0) (str "second run passes: " run2.out))
      (assert (= data1 data2) (str "an unchanged data file is not replaced by the next run: inode " data1 " then " data2))
      (assert (= a1 a2) (str "an unchanged module is not replaced by the next run: inode " a1 " then " a2))
      (assert (ok? wA3) "the module source is edited")
      (assert (= run3.exit 0) (str "the run after the edit passes: " run3.out))
      (assert (stringContains? a3text "(+ 3 4)") "the edited module is staged")
      (refute (= a2 a3) (str "the edited module lands as a new file by rename, never rewritten in place under a reader: inode " a2 " then " a3))
      (assert (listAll? (fn [(d fr/Done)] -> Bool (= d.exit 0)) both) (str "two runs started together both pass: " (stringJoin (map (fn [(d fr/Done)] -> String (str d.exit)) both) " ")))
      (assert (= left 0) (str "no .part or .stage file is left in the staging dir: " left))
      (assert (= removed.exit 0) "fixture directory is removed")
      true))

fn ! runTests -> Bool
  (testStagingAcrossRuns!)
