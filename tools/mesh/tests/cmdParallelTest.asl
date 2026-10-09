(module ws/asl/tools/mesh/tests/cmdParallelTest
  :x [runTests]
  :i [(ws/asl/tools/mesh/cmd :a cmd)])

fn makeJob id: Int64 delayMs: Int64 -> cmd/ProcJob
  (cmd/ProcJob
    :argv (list "/usr/bin/perl" "-e" "select(undef, undef, undef, $ARGV[0] / 1000.0); print qq{item-$ARGV[1]\\n};" (stringFromInt64 delayMs) (stringFromInt64 id))
    :cwd ""
    :env (list "PATH=/usr/bin:/bin")
    :input ""
    :timeoutMs 10000)

fn spawnFailureCleansWorkers! -> Bool
  (let [marker (str "/tmp/asl-mesh-spawn-failure-" (stringFromInt64 (monotonicNs)))
        worker (cmd/ProcJob :argv (list "/usr/bin/perl" "-e" "select(undef, undef, undef, 0.15); open(F, \">\", $ARGV[0]); print F \"leaked\"; close(F); select(undef, undef, undef, 2.0);" marker)
                           :cwd "" :env (list "PATH=/usr/bin:/bin") :input "" :timeoutMs 10000)
        missing (cmd/ProcJob :argv (list (str marker "-missing"))
                           :cwd "" :env (list "PATH=/usr/bin:/bin") :input "" :timeoutMs 10000)
        failed (cmd/runProcPool! (list worker missing) 2)
        _ (assert (err? failed) "later spawn failure is returned")
        pause (cmd/runProcPool! (list (makeJob 9 350)) 1)
        leaked (fileExists? marker)
        removed (if leaked (pathRemove marker) (ok ()))]
    (do (assert (ok? pause) "leak observation wait succeeds")
        (assert (not leaked) "earlier worker is terminated after later spawn failure")
        true))

fn ! runTests -> Bool
  (let [n 4
        t 350
        k 2
        threshold (/ (* (* n t) 15) (* k 10))
        jobs (list (makeJob 0 t) (makeJob 1 t) (makeJob 2 t) (makeJob 3 t))
        t0Serial (monotonicNs)
        serialRes (cmd/runProcPool! jobs 1)
        tSerial (/ (- (monotonicNs) t0Serial) 1000000)
        _ (assert (ok? serialRes) "serial runProcPool succeeds")
        serialOuts (resultOr serialRes (list))
        t0Parallel (monotonicNs)
        parallelRes (cmd/runProcPool! jobs k)
        tParallel (/ (- (monotonicNs) t0Parallel) 1000000)
        _ (assert (ok? parallelRes) "parallel runProcPool succeeds")
        parallelOuts (resultOr parallelRes (list))
        serialTexts (map (fn [p] p.out) serialOuts)
        parallelTexts (map (fn [p] p.out) parallelOuts)]
    (do
      (println (str "cmdParallelTest: serial=" (stringFromInt64 tSerial) "ms, parallel=" (stringFromInt64 tParallel) "ms, threshold=" (stringFromInt64 threshold) "ms"))
      (assert (= (listLength serialTexts) n) "serial produced N outputs")
      (assert (= (listLength parallelTexts) n) "parallel produced N outputs")
      (assert (= parallelTexts serialTexts) "identical output to serial")
      (assert (< tParallel threshold) "wall time < N*t/K*1.5")
      (assert (spawnFailureCleansWorkers!) "spawn failure cleans already-started workers")
      (let [oooJobs (list (makeJob 0 250) (makeJob 1 50))
            oooRes (cmd/runProcPool! oooJobs 2)
            _ (assert (ok? oooRes) "ooo runProcPool succeeds")
            oooOuts (resultOr oooRes (list))
            oooTexts (map (fn [p] p.out) oooOuts)]
        (do
          (assert (= oooTexts (list "item-0\n" "item-1\n")) "out-of-order completions preserve input order")
          (let [emptyRes (cmd/runProcPool! (list) 2)]
            (do
              (assert (ok? emptyRes) "empty jobs list succeeds")
              (assert (listEmpty? (resultOr emptyRes (list))) "empty jobs list returns empty")
              (let [toJob (cmd/ProcJob :argv (list "/usr/bin/perl" "-e" "select(undef, undef, undef, 2.0);")
                                       :cwd "" :env (list "PATH=/usr/bin:/bin") :input "" :timeoutMs 50)
                    toRes (cmd/runProcPool! (list toJob) 1)
                    _ (assert (ok? toRes) "timeout job succeeds with ProcOut")
                    toOuts (resultOr toRes (list))
                    firstTo (optionOr (listHead toOuts) (cmd/ProcOut :code 0 :out "" :errText "" :timedOut false))]
                (do
                  (assert firstTo.timedOut "job is marked timedOut")
                  (assert (= firstTo.code 124) "timed out job has exit code 124")
                  true))))))))
