(module asl-proc/tests/poolTest :x [runTests] :i [(asl-proc/pool :a pool)])

fn indices rs: (List pool/PoolResult) -> (List Int64)
  (map (fn [(r pool/PoolResult)] -> Int64 r.index) rs)

fn codes rs: (List pool/PoolResult) -> (List Int64)
  (map (fn [(r pool/PoolResult)] -> Int64 r.exitCode) rs)

fn byIndex rs: (List pool/PoolResult) i: Int64 -> (Option pool/PoolResult)
  (fold (fn [(acc (Option pool/PoolResult)) (r pool/PoolResult)] -> (Option pool/PoolResult) (if (= r.index i) (some r) acc)) (none) rs)

fn stdoutAt rs: (List pool/PoolResult) i: Int64 -> String
  (mt (byIndex rs i) ((some r) r.stdout) ((none) "missing"))

fn stderrAt rs: (List pool/PoolResult) i: Int64 -> String
  (mt (byIndex rs i) ((some r) r.stderr) ((none) "missing"))

fn codeAt rs: (List pool/PoolResult) i: Int64 -> Int64
  (mt (byIndex rs i) ((some r) r.exitCode) ((none) -99))

fn spawnErrorAt rs: (List pool/PoolResult) i: Int64 -> (Option String)
  (mt (byIndex rs i) ((some r) r.spawnError) ((none) (some "missing")))

fn ! runTests -> Bool
  (let [(t0 (monotonicNs))
        (timed (pool/runPool! (list (list "/bin/sleep" "5") (list "/bin/sleep" "1") (list "/bin/sleep" "1") (list "/bin/sleep" "1")) 2))
        (wallMs (/ (- (monotonicNs) t0) 1000000))
        (timedRs (resultOr timed (list)))
        (mixed (pool/runPool! (list (list "/bin/sh" "-c" "echo out; echo err >&2; exit 3") (list "/nonexistent/aslPoolJob") (list "/bin/sh" "-c" "head -c 200000 /dev/zero | tr '\\0' x") (list "/bin/sh" "-c" "kill -TERM $$")) 3))
        (mixedRs (resultOr mixed (list)))
        (single (pool/runPool! (list (list "/bin/sleep" "0.3") (list "/bin/echo" "b")) 1))
        (empty (pool/runPool! (list) 2))
        (badK (pool/runPool! (list (list "/bin/echo" "x")) 0))
        (_ (assert (ok? timed) "runPool on four sleepers is ok"))
        (_ (assert (= (indices timedRs) (list 1 2 3 0)) "jobs collected in finish order: the three 1 s sleepers before the 5 s one"))
        (_ (assert (= (codes timedRs) (list 0 0 0 0)) "all four exit codes collected"))
        (_ (assert (< wallMs 6000) "k=2 on 5 s,1 s,1 s,1 s finishes under 6 s wall (sequential is 8 s)"))
        (_ (assert (>= wallMs 4900) "wall time is bounded below by the 5 s job"))
        (_ (assert (ok? mixed) "runPool on mixed jobs is ok"))
        (_ (assert (= (listLength mixedRs) 4) "every mixed job has a result"))
        (_ (assert (= (stdoutAt mixedRs 0) "out\n") "stdout captured"))
        (_ (assert (= (stderrAt mixedRs 0) "err\n") "stderr captured"))
        (_ (assert (= (codeAt mixedRs 0) 3) "nonzero exit code collected"))
        (_ (assert (= (spawnErrorAt mixedRs 1) (some "notFound")) "missing executable reported as spawnError notFound"))
        (_ (assert (= (stringLength (stdoutAt mixedRs 2)) 200000) "200000 bytes of output drained without a full-pipe stall"))
        (_ (assert (= (codeAt mixedRs 3) -15) "job killed by SIGTERM reports -15"))
        (_ (assert (= (indices (resultOr single (list))) (list 0 1)) "k=1 runs jobs one after another in input order"))
        (_ (assert (= empty (ok (list))) "empty job list gives ok empty"))
        (_ (assert (err? badK) "k below 1 gives err"))]
    true)
