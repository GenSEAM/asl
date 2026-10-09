(module asl-mesh/tests/meshTest
  :x [testScheduler testScanner testSynthesis testEmitter testDualPolarityRefutations runTests]
  :i [(asl-mesh/scheduler :a sched)
      (asl-mesh/scanner :a scan)
      (asl-mesh/synthesis :a synth)
      (asl-mesh/emitter :a emit)])

fn testScheduler -> Bool
  (let [(pkgs (list "asl-ir" "asl-mesh" "asl-web"))
        (workers (list {:workerId "w1" :tier "pro"} {:workerId "w2" :tier "flash"}))
        (assigned (sched/schedulePartitions pkgs workers))
        (pool (sched/worktreePool "/tmp/mesh" 3))
        (emptyPool (sched/worktreePool "/tmp/mesh" 0))
        (wtPath (sched/allocateWorkerWorktree "w1" "/workspace"))]
    (do
      (assert (= (listLength assigned) 1) "schedulePartitions returns 1 assignment")
      (refute (!= (listLength assigned) 1) "schedulePartitions refutes non-1 length")
      (assert (= (optionOr (listHead assigned) mapEmpty).worker "w1") "assigned worker is w1")
      (assert (= (listLength pool) 3) "worktree pool returns 3 paths")
      (assert (= pool (list "/tmp/mesh/worker-0" "/tmp/mesh/worker-1" "/tmp/mesh/worker-2")) "worktree pool numbers its paths 0 to 2")
      (assert (= (listLength emptyPool) 0) "zero workers returns an empty worktree pool")
      (assert (= wtPath "/workspace/.asl/worktrees/w1") "worktree path matches expected")
      (refute (!= wtPath "/workspace/.asl/worktrees/w1") "worktree path refutes mismatch")
      true))

fn testScanner -> Bool
  (let [(vacuousSrc "(module test :x [foo]) (assert (= 1 1))")
        (cleanSrc "(module test :x [foo]) (assert (= x 42))")
        (noAssertSrc "(module test :x [foo]) (println \"hi\")")
        (vacuousDefects (scan/checkVacuousTests vacuousSrc "test.asl"))
        (cleanDefects (scan/checkVacuousTests cleanSrc "test.asl"))
        (noAssertDefects (scan/checkVacuousTests noAssertSrc "test.asl"))]
    (do
      (assert (= (listLength vacuousDefects) 1) "vacuous assertion detected")
      (refute (listEmpty? vacuousDefects) "vacuous defects refutes empty")
      (assert (listEmpty? cleanDefects) "clean source reports zero defects")
      (refute (not (listEmpty? cleanDefects)) "clean defects refutes non-empty")
      (assert (= (listLength noAssertDefects) 1) "missing assertion detected")
      true))

fn testSynthesis -> Bool
  (let [(fOpus (list {:id "d1" :sev :critical}))
        (fPro (list {:id "d2" :sev :high}))
        (fFlash (list {:id "d3" :sev :low}))
        (triangulated (synth/triangulateFindings fOpus fPro fFlash))
        (synthesized (synth/synthesizeDefects "partition-A" triangulated))
        (refuted (synth/refutationEngine {:id "d1" :reproduced true}))
        (notRefuted (synth/refutationEngine {:id "d2" :reproduced false}))]
    (do
      (assert (= (listLength triangulated) 3) "triangulated findings count is 3")
      (refute (!= (listLength triangulated) 3) "triangulated findings refutes non-3")
      (assert (= synthesized.status :consensus) "synthesized status is consensus")
      (assert refuted.reproduced "refuted engine reproduced is true")
      (refute (not refuted.reproduced) "refuted engine refutes false")
      (assert (not notRefuted.reproduced) "unreproduced finding stays unverified")
      (refute notRefuted.reproduced "unreproduced finding refutes reproduction")
      (assert (= notRefuted.status :unverified) "unreproduced finding has status unverified")
      (assert (= refuted.status :verified) "reproduced finding has status verified")
      true))

fn testEmitter -> Bool
  (let [(rec {:defectId "def-01" :path "src/main.asl" :lineNumber 42})
        (rLink (emit/roadmapLink "Phase554" "Task55402" "D110"))
        (ledger (emit/gapLedger (list rec)))
        (recordStr (emit/writeGapRecord "out.asn" rec))
        (emitted (emit/emitGapLedger "/tmp" (list rec) rLink))]
    (do
      (assert (stringContains? recordStr "def-01") "writeGapRecord contains defectId")
      (refute (not (stringContains? recordStr "def-01")) "recordStr refutes missing def-01")
      (assert (stringContains? recordStr "src/main.asl") "writeGapRecord contains path")
      (assert (= ledger.total 1) "ledger total count is 1")
      (assert (= emitted.status :emitted) "emitted status is emitted")
      true))

fn testDualPolarityRefutations -> Bool
  (let [(emptyWorkers (list))
        (pkgs (list "pkg1"))
        (assigned (sched/schedulePartitions pkgs emptyWorkers))]
    (do
      (assert (listEmpty? assigned) "empty workers results in empty assignment")
      (refute (not (listEmpty? assigned)) "empty workers refutes non-empty")
      true))

fn ! runTests -> Bool
  (do
    (assert (testScheduler) "testScheduler")
    (assert (testScanner) "testScanner")
    (assert (testSynthesis) "testSynthesis")
    (assert (testEmitter) "testEmitter")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations")
    true)
