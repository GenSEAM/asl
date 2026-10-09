(module aslBus/clusterTest :x [testWorkerIdleState testPoolRegistrationAndSelection testNormalizeKeys testPackDagKeys testDispatchAndReceiptLifecycle runClusterTests runTests] :i [(cluster :a c)])

fn testWorkerIdleState -> Bool
  (let [(w1 (c/WorkerNode :id "worker-qwen-1" :host "10.0.0.1" :port 8765 :role "coder" :arm "qwen-3b" :state (c/stateIdle) :caps (list "ast-patch" "test-runner") :ping 12)) (w2 (c/WorkerNode :id "worker-gemma-1" :host "10.0.0.2" :port 8765 :role "architect" :arm "gemma-31b" :state (c/stateBusy) :caps (list "dag-plan" "adr-review") :ping 24))] (do (assert (c/workerIdle? w1) "worker 1 is idle") (assert (not (c/workerIdle? w2)) "worker 2 is not idle") true))

fn testPoolRegistrationAndSelection -> Bool
  (let [(p0 (c/poolCreate)) (w1 (c/WorkerNode :id "worker-qwen-1" :host "10.0.0.1" :port 8765 :role "coder" :arm "qwen-3b" :state (c/stateIdle) :caps (list "ast-patch") :ping 10)) (w2 (c/WorkerNode :id "worker-vision-1" :host "10.0.0.3" :port 8765 :role "vision" :arm "gemini-flash" :state (c/stateIdle) :caps (list "vdom-render" "svg-diff") :ping 45)) (p1 (c/poolAdd (c/poolAdd p0 w1) w2)) (coderOpt (c/poolSelect p1 "coder" "ast-patch")) (visionOpt (c/poolSelect p1 "vision" "svg-diff")) (missOpt (c/poolSelect p1 "crawler" "deep-search"))] (do (assert (some? coderOpt) "coder worker found") (assert (some? visionOpt) "vision worker found") (assert (not (some? missOpt)) "missing worker not found") (assert (= (mt coderOpt ((some w) w.id) (none "")) "worker-qwen-1") "coder worker id match") (assert (= (mt visionOpt ((some w) w.id) (none "")) "worker-vision-1") "vision worker id match") true))

fn testNormalizeKeys -> Bool
  (let [(raw "(:node :sender \"orchestrator\" :target \"worker-1\" :payload \"test\" :status :pass :state :active :dependencies [\"t0\"])") (normalized (c/packKeys raw)) (restored (c/unpackKeys normalized))] (do (assert (stringContains? normalized ":from \"orchestrator\"") "has from") (assert (stringContains? normalized ":to \"worker-1\"") "has to") (assert (stringContains? normalized ":deps [\"t0\"]") "has deps") (assert (stringContains? normalized ":status :pass") "has status pass") (assert (stringContains? normalized ":state :active") "has state active") (assert (= restored raw) "restored matches raw") true))

fn testPackDagKeys -> Bool
  (let [(deps (list "task-setup" "task-schema")) (premises (list "premise-airgap-active")) (dagStr (c/packDag "task-cluster-01" "Deploy remote worker" deps premises))] (do (assert (stringContains? dagStr ":node :id \"task-cluster-01\"") "has node id") (assert (stringContains? dagStr ":deps 2") "has deps 2") (assert (stringContains? dagStr ":premises 1") "has premises 1") (assert (stringContains? dagStr ":state :pending") "has state pending") true))

fn testDispatchAndReceiptLifecycle -> Bool
  (let [(w (c/WorkerNode :id "worker-qwen-1" :host "10.0.0.1" :port 8765 :role "coder" :arm "qwen-3b" :state (c/stateIdle) :caps (list "ast-patch") :ping 10)) (dagPayload "(:task :title \"Patch AST\" :deps 0 :status :active)") (dispatchFrame (c/dispatchTask "frame-9001" "leader-node" w "task-42" dagPayload)) (rcFrame (c/makeReceipt "frame-9002" "worker-qwen-1" "leader-node" "task-42" 18 55))] (do (assert (= dispatchFrame.from "leader-node") "dispatch frame leader") (assert (= dispatchFrame.to "worker-qwen-1") "dispatch frame to worker") (assert (stringContains? dispatchFrame.wirePayload ":task :title \"Patch AST\"") "dispatch payload content") (assert (= rcFrame.from "worker-qwen-1") "rc frame from worker") (assert (= rcFrame.to "leader-node") "rc frame to leader") (assert (stringContains? rcFrame.wirePayload ":receipt :node \"worker-qwen-1\"") "rc payload worker") (assert (stringContains? rcFrame.wirePayload ":status :pass") "rc payload pass") true))

fn runClusterTests -> Bool
  (do (testWorkerIdleState) (testPoolRegistrationAndSelection) (testNormalizeKeys) (testPackDagKeys) (testDispatchAndReceiptLifecycle) true)

fn runTests -> Bool
  (runClusterTests)
