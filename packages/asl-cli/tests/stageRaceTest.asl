(module asl-cli/tests/stageRaceTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-cli/native :a nv)])

fn ! repoRoot! -> String
  (resultOr (realPath ".") ".")

fn ! fixtureRoot! -> String
  (str "/tmp/aslStageRaceTest_" (stringFromInt64 (monotonicNs)))

fn looseSource pad: String -> String
  (str "(module stageracefixture/loose\n"
       "  :x [runTests]\n"
       "  :i [])\n"
       "\n"
       "fn ! runTests -> Bool\n"
       "  (do (assert (= (stringLength \"x\") 1) \"loose runs\")\n"
       "      true)\n"
       "\n"
       pad)

fn ! aslTest! testPath: String -> fr/Job
  (fr/job (list (str (repoRoot!) "/bin/asl") "test" testPath) (repoRoot!) (fr/childEnv (list)))

fn ! runStaged! testPath: String -> fr/Done
  (fr/runOneLimited (aslTest! testPath) (fr/limits 900 64))

fn ! pollerScript -> String
  (str "dest=\"$1\"\n"
       "size=\"$2\"\n"
       "log=\"$3\"\n"
       "stop=\"$4\"\n"
       "while [ ! -f \"$stop\" ]; do\n"
       "  if [ -f \"$dest\" ]; then\n"
       "    s=$(wc -c < \"$dest\" 2>/dev/null | tr -d ' ')\n"
       "    if [ -n \"$s\" ] && [ \"$s\" != \"$size\" ]; then echo \"PARTIAL $s\" >> \"$log\"; fi\n"
       "  fi\n"
       "  sleep 0.005\n"
       "done\n")

fn ! startPoller! script: String dest: String size: String log: String stop: String -> fr/Done
  (fr/runOneLimited
    (fr/job (list "sh" "-c" "nohup sh \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" >/dev/null 2>&1 &" script dest size log stop)
            "/" (fr/childEnv (list)))
    (fr/limits 30 4))

fn ! partsLeft! dir: String digest: String -> Int64
  (let [(d (fr/runOneLimited (fr/job (list "find" dir "-name" (str ".part.*" digest "*")) "/" (fr/childEnv (list))) (fr/limits 60 4)))]
    (listLength (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines d.out))))

fn ! testAtomicStage! -> Bool
  (let [(root (fixtureRoot!))
        (made (dirCreate root))
        (pad (stringRepeat (str "; " "(:m \"pad-" (stringFromInt64 (monotonicNs)) "\")\n") 20000))
        (src (looseSource pad))
        (wSrc (fileWrite (str root "/loose.asl") src))
        (digest (bytesSha256 (stringToBytes src)))
        (outside (str (repoRoot!) "/.asl/cache/nativeTest/outside"))
        (dest (str outside "/" digest ".asl"))
        (script (str root "/poll.sh"))
        (log (str root "/poll.log"))
        (stop (str root "/poll.stop"))
        (wScript (fileWrite script (pollerScript)))
        (size (stringFromInt64 (stringLength src)))
        (started (startPoller! script dest size log stop))
        (_ (sleepMs 200))
        (run1 (runStaged! (str root "/loose.asl")))
        (_ (fileWrite stop "stop"))
        (_ (sleepMs 300))
        (logText (resultOr (fileReadString log) ""))
        (destText (resultOr (fileReadString dest) ""))
        (left (partsLeft! outside digest))
        (pool (fr/runPoolLimited (list (aslTest! (str root "/loose.asl")) (aslTest! (str root "/loose.asl"))) 2 (fr/limits 900 64)))
        (left2 (partsLeft! outside digest))
        (removed (fr/runOneLimited (fr/job (list "rm" "-rf" "--" root) "/" (fr/childEnv (list))) (fr/limits 60 4)))]
    (do
      (assert (and (ok? made) (and (ok? wSrc) (ok? wScript))) "fixture written")
      (assert (= started.exit 0) (str "poller started: " started.out))
      (assert (= run1.exit 0) (str "the loose outside file runs: " run1.out))
      (assert (stringEmpty? (stringTrim logText)) (str "the staged destination was never observed partial: " logText))
      (assert (= destText src) "the staged destination holds the whole source")
      (assert (= left 0) (str "no temp file is left behind: " left))
      (assert (listAll? (fn [(d fr/Done)] -> Bool (= d.exit 0)) pool) (str "two concurrent runs both pass: " (stringJoin (map (fn [(d fr/Done)] -> String (str d.exit)) pool) " ")))
      (assert (= left2 0) (str "no temp file is left behind after concurrent runs: " left2))
      (assert (= removed.exit 0) "fixture directory is removed")
      true))

; (:m :ref LEON-LAUNCH-STAGE-RACE :do "prune keeps a fresh file another stager wrote and removes an old stray one")
fn ! testPruneKeepsFresh! -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/stagePrune" (stringFromInt64 (nowNs))))
        (_a (dirCreate dir))
        (kept (str dir "/kept.asl"))
        (fresh (str dir "/fresh.asl"))
        (old (str dir "/old.asl"))
        (_b (fileWrite kept "k"))
        (_c (fileWrite fresh "f"))
        (_d (fileWrite old "o"))
        (_e (fileUtime old (- (nowNs) 7200000000000)))
        (removed (nv/pruneStaleStaged! dir (list kept)))
        (keptThere (fileExists? kept))
        (freshThere (fileExists? fresh))
        (oldThere (fileExists? old))
        (_f (pathRemove dir))]
    (do (assert keptThere "an expected file stays")
        (assert freshThere "a fresh file outside this stager's set stays: a concurrent stager wrote it")
        (refute oldThere "an old stray file is pruned")
        (assert (= removed 1) (str "one file pruned: " (stringFromInt64 removed)))
        true))

; (:m :ref ASLCLI-PREEXISTING-REDS :do "the keep and prune sides of the fresh guard through a real package stage: after one asl test of a fixture package, fresh files no copy wrote are planted in its mirror; a second run keeps those whose source lives (the toolchain root under asl/ and under tools/, the package root past the workspace segment, here an ignored file) and prunes those whose source is gone, and a flat copy is matched by its whole rel, not by its tail")
fn ! plant! path: String -> Bool
  (let [(parts (stringSplit path "/"))
        (_ (fr/runOneLimited (fr/job (list "mkdir" "-p" (stringJoin (listTake parts (- (listLength parts) 1)) "/")) "/" (fr/childEnv (list))) (fr/limits 30 4)))]
    (ok? (fileWrite path "planted\n")))

fn ! testLiveSourceSides! -> Bool
  (let [(root (str "/tmp/aslStageRaceLive_" (stringFromInt64 (monotonicNs))))
        (made (dirCreate root))
        (wCfg (fileWrite (str root "/.asl.config.asn") "(:asl-config :workspace \"stageracelive\")\n"))
        (wA (fileWrite (str root "/a.asl") "(module stageracelive/a\n  :x [valueA]\n  :i [])\n\nfn valueA -> Int64\n  7\n"))
        (wT (fileWrite (str root "/theTest.asl") "(module stageracelive/theTest\n  :x [runTests]\n  :i [(stageracelive/a :a oa)])\n\nfn ! runTests -> Bool\n  (do (assert (= (oa/valueA) 7) \"a resolves\") true)\n"))
        (wIgn (fileWrite (str root "/.gitignore") "live/\nsolo.txt\n"))
        (dLive (dirCreate (str root "/live")))
        (wLive (fileWrite (str root "/live/kept.txt") "k\n"))
        (wSolo (fileWrite (str root "/solo.txt") "s\n"))
        (gitInit (fr/runOneLimited (fr/job (list "git" "init" "-q") root (fr/childEnv (list))) (fr/limits 60 8)))
        (stage (str (repoRoot!) "/.asl/cache/nativeTest/outsidePkg/" (bytesSha256 (stringToBytes (resultOr (realPath root) root)))))
        (pkg (str stage "/stageracelive"))
        (run1 (runStaged! (str root "/theTest.asl")))
        (toolAsl (str pkg "/asl/packages/asl-json/src/json.asl"))
        (toolOther (str pkg "/tools/tests/noSelfHostTest.asl"))
        (pkgTail (str pkg "/live/kept.txt"))
        (gone (str pkg "/asl/packages/noSuchPkgRace/src/gone.asl"))
        (flat (str stage "/sub/solo.txt"))
        (planted (listAll? plant! (list toolAsl toolOther pkgTail gone flat)))
        (run2 (runStaged! (str root "/theTest.asl")))
        (results (map fileExists? (list toolAsl toolOther pkgTail gone flat)))
        (_ (map (fn [(f String)] -> Bool (ok? (pathRemove f))) (list toolAsl toolOther pkgTail gone flat)))
        (removed (fr/runOneLimited (fr/job (list "rm" "-rf" "--" root) "/" (fr/childEnv (list))) (fr/limits 60 4)))
        (at (fn [(i Int64)] -> Bool (optionOr (listGet results i) false)))]
    (do (assert (and (ok? made) (and (ok? wCfg) (and (ok? wA) (and (ok? wT) (and (ok? wIgn) (and (ok? wLive) (and (ok? wSolo) (= gitInit.exit 0)))))))) "live fixture written")
        (assert (= run1.exit 0) (str "first run passes: " run1.out))
        (assert planted "fresh files planted in the mirror")
        (assert (= run2.exit 0) (str "second run passes: " run2.out))
        (assert (at 0) "a fresh file whose toolchain source under asl/ lives stays")
        (assert (at 1) "a fresh file whose toolchain source outside asl/ (tools/) lives stays")
        (assert (at 2) "a fresh file whose package source past the workspace segment lives stays")
        (refute (at 3) "a fresh file whose source is gone is pruned")
        (refute (at 4) "a flat copy is matched by its whole rel: sub/solo.txt is pruned though solo.txt exists")
        (assert (= removed.exit 0) "live fixture removed")
        true))

fn ! runTests -> Bool
  (let [(live (testLiveSourceSides!))
        (fresh (testPruneKeepsFresh!))
        (atomic (testAtomicStage!))]
    (do (assert live "the fresh guard keeps live-sourced files and prunes gone ones")
        (assert fresh "prune keeps fresh concurrent files and removes old strays")
        (assert atomic "staging is atomic under a concurrent reader")
        true))
