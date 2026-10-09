(module asl-runtime/tests/pipelineTest
  :x [testInitPipeline testStageExecution testErrorPolicyHalt testThroughputMetrics runTests]
  :i [(asl-runtime/pipeline :a pipe)])

fn testInitPipeline -> Bool
  (let [(p (pipe/initPipeline "stream-engine"))]
    (assert (= p.name "stream-engine") "Pipeline name must match")
    (assert (= (pipe/stageCount p) 0) "Initial stage count must be 0")
    (assert (pipe/isHealthy p) "Initial pipeline must be healthy")
    true)

fn testStageExecution -> Bool
  (let [(p0 (pipe/initPipeline "etl"))
        (p1 (pipe/addStage p0 "ingest" true))
        (p2 (pipe/addStage p1 "transform" true))
        (ctx (pipe/initContext "payload-data" 100))
        (res (pipe/executePipeline p2 ctx))]
    (assert (= (pipe/stageCount p2) 2) "Stage count must be 2")
    (assert (= res.context.stepIndex 102) "Step index must increment across 2 stages")
    (assert res.success "Pipeline execution must succeed")
    (refute res.hasError "Pipeline execution must have no error")
    true)

fn testErrorPolicyHalt -> Bool
  (let [(p0 (pipe/initPipeline "fault-tolerant"))
        (p1 (pipe/addStage p0 "validation" true))
        (ctx (pipe/initContextWithFlag "bad-input" 0 false))
        (res (pipe/executePipeline p1 ctx))]
    (assert res.hasError "Pipeline must report error on invalid input")
    (refute res.success "Pipeline must not report success on halted execution")
    true)

fn testThroughputMetrics -> Bool
  (let [(p (pipe/initPipeline "metrics-test"))
        (updated (pipe/recordLatency p 5000 10))]
    (assert (> (pipe/getAverageLatencyNs updated) 0) "Average latency must be strictly positive")
    (assert (> (pipe/computeThroughput updated 1000000) 0.0) "Throughput must be strictly positive")
    true)

fn runTests -> Bool
  (do
    (assert (testInitPipeline) "Init pipeline test must pass")
    (assert (testStageExecution) "Stage execution test must pass")
    (assert (testErrorPolicyHalt) "Error policy halt test must pass")
    (assert (testThroughputMetrics) "Throughput metrics test must pass")
    true)
