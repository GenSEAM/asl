(module aslAgentTests/taskDagTest :x [testDagCreationAndReadyQueue testDagTopologicalAdvancement testDagDeadlockDetection testDagCompletion testDagStatusStrings testDagBoxartRendering testDagVdomRendering runTests] :i [(aslAgent/taskDag :a dag)])

fn testDagCreationAndReadyQueue -> Bool
  (let [(t1 (dag/makeTaskNode "t1" "Root task" "triage" (list))) (t2 (dag/makeTaskNode "t2" "Child task" "coding" (list "t1"))) (d (dag/makeTaskDag "dag-1" (list t1 t2))) (ready (dag/getReadyNodes d))] (assert (= (listLength ready) 1) "c-dag-pos-001: ready has 1 root node") (assert (not (listEmpty? ready)) "c-dag-pos-001: ready queue not empty") true)

fn testDagTopologicalAdvancement -> Bool
  (let [(t1 (dag/makeTaskNode "t1" "Root task" "triage" (list))) (t2 (dag/makeTaskNode "t2" "Child task" "coding" (list "t1"))) (d (dag/makeTaskDag "dag-1" (list t1 t2))) (d2 (dag/markNodeCompleted d "t1" "receipt: ok")) (ready (dag/getReadyNodes d2))] (assert (= (listLength ready) 1) "c-dag-pos-002: child task unblocked") (assert (not (= (listLength (dag/getCompletedNodeIds d2)) 0)) "c-dag-pos-002: completed nodes present") true)

fn testDagDeadlockDetection -> Bool
  (let [(t1 (dag/makeTaskNode "t1" "Cycle 1" "coding" (list "t2"))) (t2 (dag/makeTaskNode "t2" "Cycle 2" "coding" (list "t1"))) (cyclicDag (dag/makeTaskDag "dag-cyclic" (list t1 t2))) (cleanRoot (dag/makeTaskNode "root" "Clean root" "triage" (list))) (cleanDag (dag/makeTaskDag "dag-clean" (list cleanRoot)))] (assert (dag/hasDagDeadlock? cyclicDag) "c-dag-neg-001: cyclic dag deadlocked") (assert (not (dag/hasDagDeadlock? cleanDag)) "c-dag-neg-001: clean dag not deadlocked") true)

fn testDagCompletion -> Bool
  (let [(t1 (dag/makeTaskNode "t1" "Single task" "triage" (list))) (d (dag/makeTaskDag "dag-done" (list t1))) (dDone (dag/markNodeCompleted d "t1" "receipt: ok"))] (assert (dag/isDagComplete? dDone) "dag is complete") (assert (not (dag/isDagComplete? d)) "partial dag is not complete") true)

fn testDagStatusStrings -> Bool
  (let [(s1 (dag/nodeStatusToString (dag/nodePending))) (s2 (dag/nodeStatusToString (dag/nodeCompleted)))] (assert (= s1 "pending") "c-dag-status-001: pending matches") (assert (= s2 "completed") "c-dag-status-002: completed matches") (assert (not (= s1 s2)) "c-dag-status-neg-001: states distinct") true)

fn testDagBoxartRendering -> Bool
  (let [(t1 (dag/makeTaskNode "t1" "Root task" "triage" (list))) (t2 (dag/makeTaskNode "t2" "Child task" "coding" (list "t1"))) (d (dag/makeTaskDag "dag-render" (list t1 t2))) (art (dag/renderTaskDagBoxart d))] (assert (stringContains? art "t1 : Root task") "c-dag-box-001: contains t1") (assert (stringContains? art "t2 : Child task") "c-dag-box-002: contains t2") (assert (stringContains? art "[v]") "c-dag-box-003: contains directed arrow") (assert (not (stringEmpty? art)) "c-dag-box-neg-001: art not empty") true)

fn testDagVdomRendering -> Bool
  (let [(t1 (dag/makeTaskNode "t1" "Root task" "triage" (list))) (d (dag/makeTaskDag "dag-vdom" (list t1))) (vdom (dag/renderTaskDagVdomAsn d))] (assert (stringContains? vdom "(:div :class \"task-dag\"") "c-dag-vdom-001: root div class") (assert (stringContains? vdom ":data-dag-id \"dag-vdom\"") "c-dag-vdom-002: data-dag-id present") (assert (stringContains? vdom "(:span :class \"node-title\" \"Root task\")") "c-dag-vdom-003: node title present") (assert (not (stringContains? vdom ":data-complete true")) "c-dag-vdom-neg-001: incomplete dag") true)

fn runTests -> Bool
  (and (testDagCreationAndReadyQueue) (and (testDagTopologicalAdvancement) (and (testDagDeadlockDetection) (and (testDagCompletion) (and (testDagStatusStrings) (and (testDagBoxartRendering) (testDagVdomRendering)))))))
