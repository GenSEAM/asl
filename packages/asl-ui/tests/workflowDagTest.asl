(module asl-ui/tests/workflowDagTest :x [runWorkflowDagTests runTests] :i [(asl-ui/workflowDag :a dag) (asl-ui/vnode :a ui)])

fn runWorkflowDagTests -> Bool
  (do
    (let [(s1 (dag/formatDagStepStatus "success"))
          (s2 (dag/formatDagStepStatus "running"))
          (s3 (dag/formatDagStepStatus "pending"))
          (s4 (dag/formatDagStepStatus "failed"))
          (s5 (dag/formatDagStepStatus "blocked"))]
      (assert (= s1 "[VERIFIED] Done") "Success status cue")
      (assert (= s2 "[RUN] In-Flight") "Running status cue")
      (assert (= s3 "[QUEUED] Pending") "Pending status cue")
      (assert (= s4 "[FAILED] Refuted") "Failed status cue")
      (assert (= s5 "[2PC-GATE] Attention Rail") "Blocked status cue"))

    (let [(n1 (dag/makeWorkflowDagNode "step-1" "Scout Workspace" "scout" "success" 0 120 4))
          (n2 (dag/makeWorkflowDagNode "step-2" "Plan Changes" "planner" "success" 1 240 8))
          (n3 (dag/makeWorkflowDagNode "step-3" "Implement Voice Engine" "coder" "running" 1 450 16))]
      (let [(nodes (list n1 n2 n3))]
        (let [(laidOut (dag/layoutWorkflowDagNodes nodes))]
          (assert (= (listLength laidOut) 3) "Must preserve 3 DAG nodes")
          (assert (= n1.stepId "step-1") "Node 1 ID matches")
          (assert (= n3.role "coder") "Node 3 role matches")
          (assert (= n3.assertionsCount 16) "Node 3 executed assertions match")

          (let [(vNode1 (dag/renderWorkflowDagNode n1))]
            (assert (= vNode1.tag "container") "Rendered node must be a container VNode")
            (assert (= vNode1.key "dag-node-step-1") (str "Key was: '" vNode1.key "'"))
            (assert (= (listLength vNode1.children) 2) "Node container must have title and meta children"))

          (let [(dagVNode (dag/renderWorkflowDag "phase-616" (list n1 n2 n3)))]
            (assert (= dagVNode.tag "container") "Root DAG node must be a container")
            (assert (= dagVNode.key "dag-root-phase-616") "DAG root key matches")
            (assert (= (listLength dagVNode.children) 4) "DAG root has 1 header + 3 step node children")))))
    true)

fn runTests -> Bool
  (runWorkflowDagTests)
