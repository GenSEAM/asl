(module asl-cli/binAslColdTest :x [runTests] :i [(tools/fleet/run :a run)])

fn ! envFor cache: String extra: (List String) -> (List String)
  (listAppend (cons (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))) (cons (str "ASL_NATIVE_CLI_CACHE=" cache) (cons "ASL_NATIVE_CLI_TIMEOUT=1200" extra)))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST=") (or (stringStartsWith? row "ASL_NATIVE_CLI_") (stringStartsWith? row "SERVED_STOP_PID="))))) (run/childEnv (list))))

fn ! binAsl! root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str root "/bin/asl") args) root env) (run/limits 1500 64))

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 30 4))

fn ! cleanup! root: String cache: String -> Bool
  (let [(pid (optionOr (stringToInt64 (stringTrim (resultOr (fileRead (str cache "/lock/pid")) ""))) 0))
        (killed (if (> pid 1) (sh! root (list "/bin/kill" "-9" (str "-" (stringFromInt64 pid)))) (sh! root (list "/usr/bin/true"))))
        (removed (sh! root (list "/bin/rm" "-rf" cache)))]
    (= removed.exit 0))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (cache (str root "/.asl/cache/binAslCold/" (stringFromInt64 (procSelf))))
        (fresh (sh! root (list "/bin/rm" "-rf" cache)))
        (cold (binAsl! root (list "test" "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") (envFor cache (list))))
        (locked (ok? (dirList (str cache "/lock"))))
        (served (binAsl! root (list "test" "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl") (envFor cache (list "ASL_NATIVE_CLI_WAIT=1"))))
        (log (resultOr (fileRead (str cache "/build.log")) ""))
        (cleaned (cleanup! root cache))]
    (do (assert (= fresh.exit 0) "the test cache starts empty")
        (assert (= cold.exit 0) (str "the cold call answers on asl-host: " cold.out))
        (assert (stringContains? cold.out "asl: test runs on asl-host: no native toolchain, its build started in the background") "the cold call names the verb and the background build")
        (assert (stringContains? cold.out "passTest.asl: 1 assertion(s) executed, 1 refutation(s) executed (2 passed)") "the cold call carries the host verdict")
        (assert locked "the cold call returned while the detached build holds the lock")
        (assert (< cold.ms 120000) (str "the cold call returned in host time, not build time: " (stringFromInt64 cold.ms) " ms"))
        (assert (= served.exit 0) (str "after the build the probe is served natively: " served.out " log: " log))
        (assert (stringContains? served.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the native run reports the probe's assertions")
        (assert (stringContains? log " exit 0") "the detached build finished with exit 0")
        (assert cleaned "the test cache was removed")
        true))
