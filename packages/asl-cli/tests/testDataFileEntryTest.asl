(module asl-cli/tests/testDataFileEntryTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref INBOXFIX-TESTDATAFILE-20261028 :do "a :testData entry naming one regular file stages exactly that file at its relative path (a sibling file of the same directory stays out); an entry that is neither a file nor a directory fails asl test with a message naming it instead of being dropped")
fn ! fixtureRoot! -> String
  (str "/tmp/aslTestDataFileEntryTest_" (stringFromInt64 (monotonicNs)))

fn ! configSource entry: String -> String
  (str "(:asl-config :workspace \"testdatafilefixture\"\n  :testData (\"" entry "\"))\n")

fn ! testSource -> String
  (str
    "(module testdatafilefixture/theTest\n"
    "  :x [runTests]\n"
    "  :i [])\n"
    "\n"
    "fn ! runTests -> Bool\n"
    "  (do\n"
    "    (assert (= (resultOr (fileReadString \"data/one.txt\") \"\") \"1\\n\") \"the file entry opens at its relative path\")\n"
    "    (assert (= (resultOr (fileReadString \"testdatafilefixture/data/one.txt\") \"\") \"1\\n\") \"the file entry opens by its workspace-qualified path\")\n"
    "    (assert (stringEmpty? (resultOr (fileReadString \"data/two.txt\") \"\")) \"a sibling file of the entry is not staged\")\n"
    "    true)\n")

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! buildFixture! root: String entry: String -> (Result String String)
  (match (dirCreate root)
    ((err e) (err (str "cannot create " root ": " e)))
    ((ok _)
      (let [(dataDir (dirCreate (str root "/data")))
            (w1 (fileWrite (str root "/data/one.txt") "1\n"))
            (w2 (fileWrite (str root "/data/two.txt") "2\n"))
            (wIgn (fileWrite (str root "/.gitignore") "data/\n"))
            (wCfg (fileWrite (str root "/.asl.config.asn") (configSource entry)))
            (testPath (str root "/theTest.asl"))
            (wTest (fileWrite testPath (testSource)))
            (gitInit (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))]
        (if (and (and (ok? w1) (ok? w2)) (and (and (ok? wIgn) (ok? wCfg)) (and (ok? wTest) (= gitInit.exit 0))))
          (ok testPath)
          (err "fixture files not written")))))

fn ! runAslTest! testPath: String -> fr/Done
  (fr/runOneLimited (fr/job (list (str (repoRoot!) "/bin/asl") "test" testPath) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testFileEntryStagesExactlyThatFile! -> Bool
  (let [(root (fixtureRoot!))]
    (match (buildFixture! root "data/one.txt")
      ((err e) (assert false (str "fixture setup failed: " e)))
      ((ok testPath)
        (let [(result (runAslTest! testPath))
              (removed (pathRemove root))]
          (do
            (assert (= result.exit 0) (str "a package whose :testData names one file stages it and exits 0: " result.out))
            (assert (stringContains? result.out "3 assertion(s) executed") (str "all three fixture assertions executed: " result.out))
            (assert (ok? removed) "fixture directory is removed")
            true)))))

fn ! testMissingEntryErrors! -> Bool
  (let [(root (fixtureRoot!))]
    (match (buildFixture! root "data/absent.txt")
      ((err e) (assert false (str "fixture setup failed: " e)))
      ((ok testPath)
        (let [(result (runAslTest! testPath))
              (removed (pathRemove root))]
          (do
            (assert (not (= result.exit 0)) (str "an entry that is neither file nor directory fails asl test: " result.out))
            (assert (stringContains? result.out "data/absent.txt") "the message names the entry")
            (assert (stringContains? result.out "neither a file nor a directory") "the message says why")
            (assert (ok? removed) "fixture directory is removed")
            true)))))

fn ! runTests -> Bool
  (and (testFileEntryStagesExactlyThatFile!) (testMissingEntryErrors!))
