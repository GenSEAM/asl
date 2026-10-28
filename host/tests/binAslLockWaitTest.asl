(module asl/host/tests/binAslLockWaitTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

fn fixtureScript -> String
  "set -e; s=$1; rm -rf \"$s\"; mkdir -p \"$s/bin\" \"$s/cache/cliD\"; cp \"$2\" \"$s/bin/asl\"; chmod +x \"$s/bin/asl\"; printf '#!/bin/sh\\necho served\\n' > \"$s/cache/cliD/bin\"; chmod +x \"$s/cache/cliD/bin\"; echo dep.txt > \"$s/cache/cliD/deps\"; : > \"$s/dep.txt\"; r=$(cd \"$s\" && pwd -P); printf '%s\\n' \"$s/cache/cliD\" > \"$s/cache/head$(printf '%s' \"$r\" | tr / _)\"; touch -t 203001010000 \"$s/dep.txt\"; mkdir -p \"$s/cache/lock\"; echo \"$3\" > \"$s/cache/lock/pid\""

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 60 8))

fn envFor cache: String -> (List String)
  (listAppend (list (str "ASL_NATIVE_CLI_CACHE=" cache) "ASL_NATIVE_BUILD_WAIT=3" "ASL_NATIVE_WAIT_REPORT_S=1")
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_NATIVE_") (stringStartsWith? row "ASL_CLI_")))) (run/childEnv (list))))

; (:m :ref NATIVECLI-LOCK-WAIT :do "a stale-looking native CLI whose rebuild lock is held by a live pid waits only as long as ASL_NATIVE_BUILD_WAIT, reports (:wait :nativeCli ...) progress while it waits, and then fails naming the budget; nothing builds because the fixture has no builder")
fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (s (str root "/.asl/cache/binAslLockWait/" (stringFromInt64 (procSelf))))
        (pid (stringFromInt64 (procSelf)))
        (made (sh! root (list "/bin/sh" "-c" (fixtureScript) "sh" s (str root "/bin/asl") pid)))
        (ran (run/runOneLimited (run/job (list (str s "/bin/asl") "x") s (envFor (str s "/cache"))) (run/limits 60 8)))
        (cleaned (sh! root (list "/bin/rm" "-rf" s)))]
    (do (assert (= made.exit 0) (str "fixture built: " made.out))
        (assert (stringContains? ran.out "ERR_NATIVE_STALE") (str "the wait ended in the stale failure row: " ran.out))
        (assert (= ran.exit 2) (str "exit 2 at the budget: " (stringFromInt64 ran.exit)))
        (assert (stringContains? ran.out (str "(:wait :nativeCli :lockPid " pid " :elapsedS")) (str "progress rows name the holder: " ran.out))
        (assert (stringContains? ran.out "past the budget ASL_NATIVE_BUILD_WAIT=3s") (str "the failure names the budget: " ran.out))
        (assert (= cleaned.exit 0) "fixture removed")
        true))
