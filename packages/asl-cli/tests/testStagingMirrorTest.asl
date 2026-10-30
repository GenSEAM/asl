(module asl-cli/tests/testStagingMirrorTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref INBOXFIX-STALESTAGE-20261028 :do "asl test stages a package into outsidePkg/<digest>; a module deleted from the package between two runs must be absent from that staging dir on the second run, while the kept module and the declared :testData file stay")
fn ! fixtureRoot! -> String
  (str "/tmp/aslTestStagingMirrorTest_" (stringFromInt64 (monotonicNs)))

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! testSource -> String
  (str
    "(module stagemirrorfixture/theTest\n"
    "  :x [runTests]\n"
    "  :i [(stagemirrorfixture/a :a oa)])\n"
    "\n"
    "fn ! runTests -> Bool\n"
    "  (do (assert (= (oa/valueA) 7) \"a resolves\") true)\n")

fn ! runAslTest! testPath: String -> fr/Done
  (fr/runOneLimited (fr/job (list (str (repoRoot!) "/bin/asl") "test" testPath) (repoRoot!) (fr/childEnv (list))) (fr/limits 900 64))

fn ! testDeletedModuleLeavesStaging! -> Bool
  (let [(root (fixtureRoot!))
        (made (dirCreate root))
        (wCfg (fileWrite (str root "/.asl.config.asn") "(:asl-config :workspace \"stagemirrorfixture\"\n  :testData (\"data/keep.txt\"))\n"))
        (wA (fileWrite (str root "/a.asl") "(module stagemirrorfixture/a\n  :x [valueA]\n  :i [])\n\nfn valueA -> Int64\n  7\n"))
        (wB (fileWrite (str root "/b.asl") "(module stagemirrorfixture/b\n  :x [valueB]\n  :i [])\n\nfn valueB -> Int64\n  8\n"))
        (dd (dirCreate (str root "/data")))
        (wD (fileWrite (str root "/data/keep.txt") "k\n"))
        (wIgn (fileWrite (str root "/.gitignore") "data/\n"))
        (wTest (fileWrite (str root "/theTest.asl") (testSource)))
        (gitInit (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))
        (stage (str (repoRoot!) "/.asl/cache/nativeTest/outsidePkg/" (bytesSha256 (stringToBytes (resultOr (realPath root) root)))))
        (run1 (runAslTest! (str root "/theTest.asl")))
        (b1 (ok? (fileReadString (str stage "/b.asl"))))
        (rm (pathRemove (str root "/b.asl")))
        (run2 (runAslTest! (str root "/theTest.asl")))
        (b2 (ok? (fileReadString (str stage "/b.asl"))))
        (bPkg2 (ok? (fileReadString (str stage "/stagemirrorfixture/b.asl"))))
        (a2 (ok? (fileReadString (str stage "/stagemirrorfixture/a.asl"))))
        (d2 (ok? (fileReadString (str stage "/stagemirrorfixture/data/keep.txt"))))
        (removed (pathRemove root))]
    (do
      (assert (and (ok? made) (and (ok? wCfg) (and (ok? wA) (and (ok? wB) (and (ok? wD) (and (ok? wTest) (= gitInit.exit 0))))))) "fixture written")
      (assert (= run1.exit 0) (str "first run passes: " run1.out))
      (assert b1 "first run stages b.asl")
      (assert (ok? rm) "b.asl deleted from the source")
      (assert (= run2.exit 0) (str "second run passes: " run2.out))
      (assert (not b2) "second run: b.asl is absent from the flat staging dir")
      (assert (not bPkg2) "second run: b.asl is absent from the workspace-named staging dir")
      (assert a2 "the kept module stays staged")
      (assert d2 "the declared :testData file stays staged")
      (assert (ok? removed) "fixture directory is removed")
      true))

fn ! runTests -> Bool
  (testDeletedModuleLeavesStaging!)
