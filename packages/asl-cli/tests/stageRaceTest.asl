(module asl-cli/tests/stageRaceTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

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

fn ! runTests -> Bool
  (testAtomicStage!)
