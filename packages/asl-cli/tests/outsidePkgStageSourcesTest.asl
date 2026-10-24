(module asl-cli/tests/outsidePkgStageSourcesTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref OUTSIDEPKG-STAGE-SOURCES-20261024 :do "staging a foreign package must copy only its .asl/.asn sources and link the rest: a 100MB sparse data file stays under 1MB of stage, the suite still reads it by its relative path, removing the stage leaves the original; the stage cache keeps the newest entries and never prunes a recently used or protected one; the native CLI cache prunes unreferenced cli-*/asl1-* directories")

fn ! tmpRoot! tag: String -> String
  (str "/tmp/aslStageSources_" tag "_" (stringFromInt64 (monotonicNs)))

fn ! sh! cwd: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv cwd (fr/childEnv (list))) (fr/limits 120 8))

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! mk! path: String -> Bool
  (ok? (dirCreate path))

fn ! duKb! path: String -> Int64
  (let [(d (sh! "/" (list "du" "-sk" path)))]
    (if (= d.exit 0) (optionOr (stringToInt64 (optionOr (listHead (stringSplit (stringTrim d.out) "\t")) "")) -1) -1))

fn ! testSource -> String
  (str
    "(module stagesourcesfixture/theTest\n"
    "  :x [runTests]\n"
    "  :i [(stagesourcesfixture/a :a oa)])\n"
    "\n"
    "fn ! runTests -> Bool\n"
    "  (do\n"
    "    (assert (= (oa/valueA) 7) \"sibling import resolves\")\n"
    "    (assert (= (resultOr (fileReadString \"data/small.txt\") \"\") \"42\\n\") \"a small data file opens by its relative path\")\n"
    "    (assert (= (resultOr (fileReadString \"stagesourcesfixture/data/small.txt\") \"\") \"42\\n\") \"a small data file opens by its workspace-qualified path\")\n"
    "    (assert (= (match (fileStat \"data/big.bin\") ((ok st) st.size) ((err _) -1)) 104857600) \"the 100MB data file is reachable by its relative path\")\n"
    "    (assert (= (match (fileStat \"stagesourcesfixture/data/big.bin\") ((ok st) st.size) ((err _) -1)) 104857600) \"the 100MB data file is reachable by its workspace-qualified path\")\n"
    "    (assert (ok? (fileWrite \"data/rw.txt\" \"changed\\n\")) \"the suite writes into its staged data file\")\n"
    "    (assert (ok? (fileWrite \"stagesourcesfixture/data/big.bin\" \"x\")) \"the suite truncates a staged large data file\")\n"
    "    true)\n")

fn ! buildFixture! root: String -> Bool
  (let [(dirs (and (mk! root) (mk! (str root "/data"))))
        (files (and (ok? (fileWrite (str root "/.asl.config.asn") "(:asl-config :workspace \"stagesourcesfixture\")\n"))
                 (and (ok? (fileWrite (str root "/a.asl") "(module stagesourcesfixture/a\n  :x [valueA]\n  :i [])\n\nfn valueA -> Int64\n  7\n"))
                   (and (ok? (fileWrite (str root "/theTest.asl") (testSource)))
                        (and (ok? (fileWrite (str root "/data/small.txt") "42\n"))
                             (ok? (fileWrite (str root "/data/rw.txt") "orig\n")))))))
        (big (sh! root (list "truncate" "-s" "100M" (str root "/data/big.bin"))))
        (git (sh! root (list "git" "init" "-q")))]
    (and dirs (and files (and (= big.exit 0) (= git.exit 0)))))

fn ! stageDirOf! root: String -> String
  (let [(a (str (repoRoot!) "/.asl/cache/nativeTest/outsidePkg/" (bytesSha256 (stringToBytes root))))
        (b (str (repoRoot!) "/.asl/cache/nativeTest/outsidePkg/" (bytesSha256 (stringToBytes (resultOr (realPath root) root)))))]
    (if (ok? (fileStat a)) a b))

fn ! testStageCopiesSourcesOnly! -> Bool
  (let [(root (tmpRoot! "pkg"))
        (built (buildFixture! root))
        (run (sh! (repoRoot!) (list (str (repoRoot!) "/bin/asl") "test" (str root "/theTest.asl"))))
        (stage (stageDirOf! root))
        (kb (duKb! stage))
        (_rm (pathRemove stage))
        (origKept (match (fileStat (str root "/data/big.bin")) ((ok st) (= st.size 104857600)) ((err _) false)))
        (rwKept (resultOr (fileReadString (str root "/data/rw.txt")) "gone"))
        (_rm2 (pathRemove root))]
    (do
      (assert built "fixture built")
      (assert (= run.exit 0) (str "asl test of the foreign package passes reading data by relative path: " run.out))
      (assert (stringContains? run.out "assertion(s) executed") "the suite reports executed assertions")
      (assert (>= kb 0) (str "stage dir found and measured: " stage))
      (assert (< kb 1024) (str "staged size under 1MB, was " (stringFromInt64 kb) "KB"))
      (assert (= rwKept "orig\n") (str "a staged suite writing into its data leaves the original byte-identical: " rwKept))
      (assert origKept "removing the stage left the original data file intact")
      true))

fn ! touchOld! path: String stamp: String -> Bool
  (let [(d (sh! "/" (list "touch" "-t" stamp path)))] (= d.exit 0))

fn ! entry! dir: String name: String -> Bool
  (and (mk! (str dir "/" name)) (ok? (fileWrite (str dir "/" name "/x") "x\n")))

fn ! names! dir: String -> (List String)
  (listSort (resultOr (dirList dir) (list)))

fn ! testPruneKeepsNewestAndInUse! -> Bool
  (let [(dir (tmpRoot! "prune"))
        (made (mk! dir))
        (outside (str dir "-target.txt"))
        (_t (fileWrite outside "keep me\n"))
        (names (list "e0" "e1" "e2" "e3" "e4" "e5" "e6"))
        (_mk (map (fn [(n String)] -> Bool (entry! dir n)) names))
        (_link (sh! dir (list "ln" "-s" outside (str dir "/e1/link"))))
        (_o (map (fn [(p (Pair String String))] -> Bool (touchOld! (str dir "/" (pairFirst p)) (pairSecond p)))
                 (list (pair "e0" "202001010000") (pair "e1" "202101010000") (pair "e3" "202301010000") (pair "e4" "202401010000") (pair "e5" "202501010000") (pair "e6" "202601010000"))))
        (removed (nc/pruneEntries! dir "e" 4 1800000000000 (list "e0")))
        (left (names! dir))
        (targetKept (ok? (fileStat outside)))
        (second (nc/pruneEntries! dir "e" 4 1800000000000 (list "e0")))
        (_c (pathRemove dir))
        (_c2 (pathRemove outside))]
    (do
      (assert made "prune dir made")
      (assert (= removed 2) (str "N+3 entries with one in use and one protected: two removed, was " (stringFromInt64 removed)))
      (assert (= left (list "e0" "e2" "e4" "e5" "e6")) (str "newest 4 (e2 in use, e4 e5 e6) plus protected e0 remain: " (stringJoin left " ")))
      (assert targetKept "pruning a directory holding a symlink leaves the link target")
      (assert (= second 0) "a second prune removes nothing")
      true))

fn ! testPruneNeverTouchesRecent! -> Bool
  (let [(dir (tmpRoot! "recent"))
        (made (mk! dir))
        (_mk (map (fn [(n String)] -> Bool (entry! dir n)) (list "r0" "r1" "r2" "r3" "r4" "r5")))
        (removed (nc/pruneEntries! dir "r" 4 1800000000000 (list)))
        (left (listLength (names! dir)))
        (_c (pathRemove dir))]
    (do
      (assert made "dir made")
      (assert (= removed 0) "entries used within the last 30 minutes are never pruned, even beyond the newest 4")
      (assert (= left 6) "all six recent entries remain")
      true))

fn ! testNativeCachePrune! -> Bool
  (let [(cache (tmpRoot! "native"))
        (made (mk! cache))
        (ids (list "0" "1" "2" "3" "4" "5" "6" "7"))
        (_c (map (fn [(i String)] -> Bool (entry! cache (str "cli-" i))) ids))
        (_a (map (fn [(i String)] -> Bool (entry! cache (str "asl1-" i))) ids))
        (_h (fileWrite (str cache "/head_some_root") (str cache "/cli-0\n")))
        (_hp (fileWrite (str cache "/head_some_root.part.1") (str cache "/cli-1\n")))
        (_o (map (fn [(i String)] -> Bool (and (touchOld! (str cache "/cli-" i) (str "201" i "01010000")) (touchOld! (str cache "/asl1-" i) (str "201" i "01010000")))) ids))
        (removed (nc/pruneNativeCache! cache 4 21600000000000))
        (left (names! cache))
        (_x (pathRemove cache))]
    (do
      (assert made "cache dir made")
      (assert (= removed 7) (str "cli: 8 minus 4 newest minus the head-referenced one = 3, asl1: 8 minus 4 = 4; removed " (stringFromInt64 removed)))
      (assert (= left (list "asl1-4" "asl1-5" "asl1-6" "asl1-7" "cli-0" "cli-4" "cli-5" "cli-6" "cli-7" "head_some_root" "head_some_root.part.1")) (str "left: " (stringJoin left " ")))
      true))

fn ! runTests -> Bool
  (and (and (testStageCopiesSourcesOnly!) (testPruneKeepsNewestAndInUse!))
       (and (testPruneNeverTouchesRecent!) (testNativeCachePrune!)))
