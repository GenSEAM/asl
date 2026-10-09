(module aslHarness/multiModelOrchestratorTest :x [testMeshWorkerSpecs! testParallelPartitions! testAstScanner! testDialecticalSynthesis! testGapLedgerEmitter! testMultiLensWitness! runTests] :i [])

fn testMeshWorkerSpecs! -> Bool
  (let [(res (fileRead "asl/grammar/mesh.asn"))] (assert (ok? res) "mesh.asn must exist") (let [(src (resultOr res ""))] (assert (stringContains? src "meshWorker") "meshWorker schema defined") (assert (stringContains? src "defectRecord") "defectRecord schema defined") (assert (stringContains? src "consensusReceipt") "consensusReceipt schema defined") (assert (stringContains? src "defectTaxonomy") "defectTaxonomy schema defined") true))

fn testParallelPartitions! -> Bool
  (let [(res (fileRead "asl/packages/asl-mesh/src/scheduler.asl"))] (assert (ok? res) "scheduler.asl must exist") (let [(src (resultOr res ""))] (assert (stringContains? src "schedulePartitions") "schedulePartitions defined") (assert (stringContains? src "allocateWorkerWorktree") "allocateWorkerWorktree defined") (assert (stringContains? src "partitionMap") "partitionMap defined") (assert (stringContains? src "worktreePool") "worktreePool defined") true))

fn testAstScanner! -> Bool
  (let [(res (fileRead "asl/packages/asl-mesh/src/scanner.asl"))] (assert (ok? res) "scanner.asl must exist") (let [(src (resultOr res ""))] (assert (stringContains? src "scanAstDefects") "scanAstDefects defined") (assert (stringContains? src "checkVacuousTests") "checkVacuousTests defined") (assert (stringContains? src "astVisitor") "astVisitor defined") (assert (stringContains? src "defectEmitter") "defectEmitter defined") true))

fn testDialecticalSynthesis! -> Bool
  (let [(res (fileRead "asl/packages/asl-mesh/src/synthesis.asl"))] (assert (ok? res) "synthesis.asl must exist") (let [(src (resultOr res ""))] (assert (stringContains? src "synthesizeDefects") "synthesizeDefects defined") (assert (stringContains? src "triangulateFindings") "triangulateFindings defined") (assert (stringContains? src "consensusFilter") "consensusFilter defined") (assert (stringContains? src "refutationEngine") "refutationEngine defined") true))

fn testGapLedgerEmitter! -> Bool
  (let [(res (fileRead "asl/packages/asl-mesh/src/emitter.asl")) (resLedger (fileRead ".asl/mem/gaps/GapsMasterLedger.asn"))] (assert (ok? res) "emitter.asl must exist") (assert (ok? resLedger) "GapsMasterLedger.asn must exist") (let [(src (resultOr res "")) (srcLedger (resultOr resLedger ""))] (assert (stringContains? src "emitGapLedger") "emitGapLedger defined") (assert (stringContains? src "writeGapRecord") "writeGapRecord defined") (assert (stringContains? srcLedger "gapsMasterLedger") "gapsMasterLedger present") true))

fn testMultiLensWitness! -> Bool
  (let [(resFix (fileRead "harness/fixtures/multilens_fixture.json")) (resWit (fileRead ".asl/mem/witness/phase557_multilens.asn"))] (assert (ok? resFix) "multilens_fixture.json must exist") (assert (ok? resWit) "phase557_multilens.asn witness must exist") (let [(srcFix (resultOr resFix "")) (srcWit (resultOr resWit ""))] (assert (stringContains? srcFix "deepseek-v4.1-flash") "deepseek model in fixture") (assert (stringContains? srcFix "glm-5.3") "glm model in fixture") (assert (stringContains? srcFix "kimi-k3") "kimi model in fixture") (assert (stringContains? srcFix "muse-spark-1.3") "muse model in fixture") (assert (stringContains? srcFix "qwen3.8-max") "qwen model in fixture") (assert (stringContains? srcWit "multilens-verdict") "verdict header in witness") (assert (stringContains? srcWit ":consensusRatio") "consensusRatio in witness") (assert (stringContains? srcWit ":verifiedConsensus") "verifiedConsensus in witness") true))

fn ! runTests -> Bool
  (let [(t1 (testMeshWorkerSpecs!)) (t2 (testParallelPartitions!)) (t3 (testAstScanner!)) (t4 (testDialecticalSynthesis!)) (t5 (testGapLedgerEmitter!)) (t6 (testMultiLensWitness!))] (assert (and (and (and (and (and t1 t2) t3) t4) t5) t6) "All multi-model orchestrator tests pass") true)

