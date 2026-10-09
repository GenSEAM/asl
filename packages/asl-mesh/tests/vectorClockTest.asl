(module asl-mesh/tests/vectorClockTest
  :x [runTests RunTests testVectorClockTick testVectorClockMerge testCausalPrecedence testConcurrentDivergence testDualPolarityRefutations]
  :i [(asl-mesh/vectorClock :a vc)])

fn testVectorClockTick -> Bool
  (let [(clock0 (vc/makeVectorClock "agent-1"))
        (clock1 (vc/vectorClockTick clock0))
        (clock2 (vc/vectorClockTick clock1))]
    (assert (= (vc/getClockValue clock0 "agent-1") 0) "initial clock value is 0")
    (refute (!= (vc/getClockValue clock0 "agent-1") 0) "initial clock value refutes non-zero")
    (assert (= (vc/getClockValue clock1 "agent-1") 1) "clock value after 1 tick is 1")
    (assert (= (vc/getClockValue clock2 "agent-1") 2) "clock value after 2 ticks is 2")
    (refute (!= (vc/getClockValue clock2 "agent-1") 2) "clock value refutes divergence"))
  true

fn testVectorClockMerge -> Bool
  (let [(clockA (vc/vectorClockTick (vc/makeVectorClock "agent-A")))
        (clockB (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "agent-B"))))
        (merged (vc/vectorClockMerge clockA clockB))]
    (assert (= (vc/getClockValue merged "agent-A") 1) "merged clock retains agent-A timestamp 1")
    (assert (= (vc/getClockValue merged "agent-B") 2) "merged clock retains agent-B timestamp 2")
    (refute (!= (vc/getClockValue merged "agent-B") 2) "merged clock refutes lower timestamp for agent-B"))
  true

fn testCausalPrecedence -> Bool
  (let [(c0 (vc/makeVectorClock "node-1"))
        (c1 (vc/vectorClockTick c0))
        (c2 (vc/vectorClockTick c1))]
    (assert (vc/isCausalPredecessor? c0 c1) "c0 is causal predecessor of c1")
    (refute (not (vc/isCausalPredecessor? c0 c1)) "c0 refutes not being predecessor of c1")
    (assert (vc/isCausalPredecessor? c1 c2) "c1 is causal predecessor of c2")
    (assert (vc/isCausalPredecessor? c0 c2) "c0 is transitive causal predecessor of c2")
    (assert (not (vc/isCausalPredecessor? c2 c0)) "c2 is not predecessor of c0")
    (refute (vc/isCausalPredecessor? c2 c0) "c2 refutes being predecessor of c0"))
  true

fn testConcurrentDivergence -> Bool
  (let [(cA (vc/vectorClockTick (vc/makeVectorClock "worker-A")))
        (cB (vc/vectorClockTick (vc/makeVectorClock "worker-B")))]
    (assert (vc/isConcurrent? cA cB) "independent concurrent edits on disjoint workers are concurrent")
    (refute (not (vc/isConcurrent? cA cB)) "concurrent edits refute non-concurrent")
    (assert (not (vc/isCausalPredecessor? cA cB)) "neither cA precedes cB")
    (assert (not (vc/isCausalPredecessor? cB cA)) "nor cB precedes cA"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(cIdentical1 (vc/vectorClockTick (vc/makeVectorClock "worker-1")))
        (cIdentical2 (vc/vectorClockTick (vc/makeVectorClock "worker-1")))]
    (assert (vc/areClocksEqual? cIdentical1 cIdentical2) "identical clocks are equal")
    (refute (not (vc/areClocksEqual? cIdentical1 cIdentical2)) "identical clocks refute inequality")
    (assert (not (vc/isConcurrent? cIdentical1 cIdentical2)) "identical clocks are not concurrent")
    (refute (vc/isConcurrent? cIdentical1 cIdentical2) "identical clocks refute concurrency"))
  true

fn testVectorClockPrune -> Bool
  (let [(clockA (vc/vectorClockTick (vc/makeVectorClock "node-A")))
        (clockB (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-B"))))
        (merged (vc/vectorClockMerge clockA clockB))
        (pruned (vc/vectorClockPrune merged (list "node-A")))]
    (do
      (assert (= (vc/getClockValue pruned "node-A") 1) "retained active node has clock value 1")
      (assert (= (vc/getClockValue pruned "node-B") 0) "pruned inactive node clock value is reset to 0")
      (refute (!= (vc/getClockValue pruned "node-A") 1) "active node refutes divergence")
      (refute (= (vc/getClockValue pruned "node-B") 2) "Refutation: pruned inactive node must not retain clock value 2")
      true))

fn testVectorClockPruneWithHorizon -> Bool
  (let [(clockA (vc/vectorClockTick (vc/makeVectorClock "node-A")))
        (clockB (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-B"))))
        (clockC (vc/vectorClockTick (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-C")))))
        (mergedAB (vc/vectorClockMerge clockA clockB))
        (mergedAll (vc/vectorClockMerge mergedAB clockC))
        (prunedWithHorizon (vc/vectorClockPruneWithHorizon mergedAll (list "node-A")))]
    (do
      (assert (= (vc/getBaseHorizon mergedAll) 0) "initial base horizon is 0")
      (refute (!= (vc/getBaseHorizon mergedAll) 0) "initial base horizon refutes non-zero")
      (assert (= (vc/getBaseHorizon prunedWithHorizon) 3) "base horizon after pruning node-B(2) and node-C(3) is 3")
      (refute (!= (vc/getBaseHorizon prunedWithHorizon) 3) "pruned base horizon refutes divergence")
      (assert (= (vc/getClockValueWithHorizon prunedWithHorizon "node-A") 1) "retained active node retains clock value 1")
      (refute (!= (vc/getClockValueWithHorizon prunedWithHorizon "node-A") 1) "retained active node refutes divergence")
      (assert (= (vc/getClockValueWithHorizon prunedWithHorizon "node-B") 3) "pruned node-B returns base horizon 3")
      (assert (= (vc/getClockValueWithHorizon prunedWithHorizon "node-C") 3) "pruned node-C returns base horizon 3")
      (assert (= (vc/getClockValueWithHorizon prunedWithHorizon "node-Unknown") 3) "unknown node returns base horizon 3")
      (refute (< (vc/getClockValueWithHorizon prunedWithHorizon "node-B") 3) "pruned node refutes lower than horizon")
      true))

fn testCausalPrecedenceWithCompactedClocks -> Bool
  (let [(clockBase (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-B"))))
        (clockA1 (vc/vectorClockTick (vc/makeVectorClock "node-A")))
        (clockA2 (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-A"))))
        (merged1 (vc/vectorClockMerge clockA1 clockBase))
        (merged2 (vc/vectorClockMerge clockA2 clockBase))
        (compacted1 (vc/vectorClockPruneWithHorizon merged1 (list "node-A")))
        (compacted2 (vc/vectorClockPruneWithHorizon merged2 (list "node-A")))]
    (do
      (assert (= (vc/getBaseHorizon compacted1) 2) "compacted1 horizon is 2")
      (assert (= (vc/getBaseHorizon compacted2) 2) "compacted2 horizon is 2")
      (assert (vc/isCausalPredecessor? compacted1 compacted2) "compacted1 is causal predecessor of compacted2")
      (refute (not (vc/isCausalPredecessor? compacted1 compacted2)) "refute non-precedence between compacted clocks")
      (assert (not (vc/isCausalPredecessor? compacted2 compacted1)) "compacted2 does not precede compacted1")
      (assert (vc/areClocksEqual? compacted1 compacted1) "compacted clock equals itself")
      (refute (not (vc/areClocksEqual? compacted1 compacted1)) "refute self inequality on compacted clock")
      (assert (not (vc/isConcurrent? compacted1 compacted2)) "compacted monotonic clocks are not concurrent")
      true))

fn testPruneStaleNodes -> Bool
  (let [(cA (vc/vectorClockTick (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-A")))))
        (cB (vc/vectorClockTick (vc/makeVectorClock "node-B")))
        (cC (vc/vectorClockTick (vc/vectorClockTick (vc/makeVectorClock "node-C"))))
        (mAB (vc/vectorClockMerge cA cB))
        (allClocks (vc/vectorClockMerge mAB cC))
        (pruned (vc/pruneStaleNodes allClocks 2))]
    (do
      (assert (= (vc/getClockValue pruned "node-A") 3) "node-A (val 3 >= 2) retained")
      (assert (= (vc/getClockValue pruned "node-C") 2) "node-C (val 2 >= 2) retained")
      (assert (= (vc/getClockValue pruned "node-B") 0) "node-B (val 1 < 2) pruned")
      (assert (= (vc/getBaseHorizon pruned) 1) "base horizon updated to pruned value 1")
      (assert (= (vc/getClockValueWithHorizon pruned "node-B") 1) "pruned node-B returns horizon 1")
      (refute (!= (vc/getBaseHorizon pruned) 1) "pruned horizon refutes non-1")
      true))

fn runTests -> Bool
  (do
    (assert (testVectorClockTick) "testVectorClockTick passed")
    (assert (testVectorClockMerge) "testVectorClockMerge passed")
    (assert (testCausalPrecedence) "testCausalPrecedence passed")
    (assert (testConcurrentDivergence) "testConcurrentDivergence passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    (assert (testVectorClockPrune) "testVectorClockPrune passed")
    (assert (testVectorClockPruneWithHorizon) "testVectorClockPruneWithHorizon passed")
    (assert (testCausalPrecedenceWithCompactedClocks) "testCausalPrecedenceWithCompactedClocks passed")
    (assert (testPruneStaleNodes) "testPruneStaleNodes passed")
    true)

fn RunTests -> Bool
  (runTests)
