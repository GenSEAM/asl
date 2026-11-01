(module asl-cli/binAslColdTest :x [runTests] :i [(asl-tools/fleet/run :a run)])

; (:m :ref BASE-RED-BINASL-MAC :do "the cold-start contract of bin/asl: an empty cache blocks the first call on one build (asl/host/build.sh --cold takes the CACHE/build.lockd lock) and then answers it natively, with no asl-host fallback line; the lock is released and a head names the new binary, so the next call is served natively. The old host-fallback-with-background-build contract went with HL-DELETE")
fn ! envFor cache: String extra: (List String) -> (List String)
  (listAppend (cons (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))) (cons (str "ASL_NATIVE_CLI_CACHE=" cache) (cons "ASL_NATIVE_CLI_TIMEOUT=3000" extra)))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST=") (or (stringStartsWith? row "ASL_NATIVE_CLI_") (stringStartsWith? row "SERVED_STOP_PID="))))) (run/childEnv (list))))

fn ! binAsl! root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str root "/bin/asl") args) root env) (run/limits 3600 64))

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 30 4))

fn ! cleanup! root: String cache: String -> Bool
  (let [(pid (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str cache "/build.lockd/holder")) ""))) 0))
        (killed (if (> pid 1) (sh! root (list "/bin/kill" "-9" (str "-" (stringFromInt64 pid)))) (sh! root (list "/usr/bin/true"))))
        (removed (sh! root (list "/bin/rm" "-rf" cache)))]
    (= removed.exit 0))

fn headNamed? name: String -> Bool
  (stringStartsWith? name "head")

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (cache (str root "/.asl/cache/binAslCold/" (stringFromInt64 (procSelf))))
        (fresh (sh! root (list "/bin/rm" "-rf" cache)))
        (cold (binAsl! root (list "test" "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl") (envFor cache (list))))
        (lockHeld (fileExists? (str cache "/build.lockd")))
        (heads (filter headNamed? (resultOr (dirList cache) (list))))
        (served (binAsl! root (list "test" "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl") (envFor cache (list))))
        (cleaned (cleanup! root cache))]
    (do (assert (= fresh.exit 0) "the test cache starts empty")
        (assert (= cold.exit 0) (str "the cold call blocks on one build and answers: " cold.out))
        (assert (stringContains? cold.out "passTest.asl: 1 assertion(s) executed, 1 refutation(s) executed (2 passed)") (str "the cold call carries the native verdict: " cold.out))
        (assert (not (stringContains? cold.out "runs on asl-host")) "the cold call has no asl-host fallback line")
        (assert (not lockHeld) "the build lock is released when the call returns")
        (assert (= (listLength heads) 1) (str "one head names the new binary: " (stringJoin heads ",")))
        (assert (= served.exit 0) (str "the next call is served natively: " served.out))
        (assert (stringContains? served.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the native run reports the probe's assertions")
        (assert cleaned "the test cache was removed")
        true))
