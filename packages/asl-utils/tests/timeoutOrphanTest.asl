(module asl-utils/tests/timeoutOrphanTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

fn ! shimEnv! -> (List String)
  (fr/childEnv (list (str "ASL_PRELUDE=" (resultOr (realPath "asl/prelude/prelude.asl") "asl/prelude/prelude.asl")) (str "ASL_CLI_ROOT=" (resultOr (realPath ".") "."))))

fn ! shim! secs: String argv: (List String) -> fr/ProcOut
  (fr/runGuarded (listAppend (list (fr/nativeCli!) "timeout" secs "--") argv) "." (shimEnv!) (fr/limits 40 64))

fn ! alive? pid: Int64 -> Bool
  (and (> pid 1) (match (procAlive? pid) ((ok b) b) ((err _) false)))

fn pidOf out: String -> Int64
  (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit out "\n")) ""))) 0)

fn ! cleanup! pid: Int64 -> Bool
  (do (if (alive? pid) (procKill pid "SIGKILL") (ok ())) true)

; (:m :ref TIMEOUT-WRAPPER-ORPHAN :do "the direct child exits at once while its background grandchild keeps stdout/stderr open: timeout must return the child's status, not wait for the pipes to close, and the already-written pid must not be lost")
fn ! testOrphanedPipes -> Bool
  (let [(t0 (monotonicNs))
        (r (shim! "20" (list "/bin/sh" "-c" "sleep 30 & echo $!; exit 0")))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (gc (pidOf r.stdout))
        (_ (cleanup! gc))]

    (do (assert (= r.exitCode 0) (str "the child's exit 0 is returned: " r.exitCode " " r.stderr))
        (assert (> gc 1) (str "the grandchild pid was printed before the parent exited: " r.stdout))
        (assert (< ms 5000) (str "the shim returned once the direct child was reaped, not after the 30 s grandchild: " ms " ms"))
        true))

fn ! runTests -> Bool
  (do (assert (testOrphanedPipes) "a pipe held open by an orphan does not delay the shim")
      true)
