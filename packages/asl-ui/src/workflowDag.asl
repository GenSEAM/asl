(module asl-ui/workflowDag :x [WorkflowStepStatus stepStatusPending stepStatusRunning stepStatusSuccess stepStatusFailed stepStatusBlocked WorkflowDagNode makeWorkflowDagNode layoutWorkflowDagNodes formatDagStepStatus renderWorkflowDagNode renderWorkflowDag] :i [(asl-ui/vnode :a ui) (asl-ui/theme :a theme)])

(enum WorkflowStepStatus
  (:c stepStatusPending [] "Step waiting on dependencies")
  (:c stepStatusRunning [] "Step currently executing")
  (:c stepStatusSuccess [] "Step completed and verified green")
  (:c stepStatusFailed [] "Step failed falsification gate")
  (:c stepStatusBlocked [] "Step blocked by human sovereignty 2PC gate"))

(schema WorkflowDagNode
  (:f stepId String)
  (:f title String)
  (:f role String)
  (:f status String)
  (:f dependenciesCount Int64)
  (:f durationMs Int64)
  (:f assertionsCount Int64))

fn makeWorkflowDagNode id: String title: String role: String status: String depsCount: Int64 dur: Int64 asserts: Int64 -> WorkflowDagNode
  (WorkflowDagNode :stepId id :title title :role role :status status :dependenciesCount depsCount :durationMs dur :assertionsCount asserts)

fn formatDagStepStatus status: String -> String
  (if (= status "success")
    "[VERIFIED] Done"
    (if (= status "running")
      "[RUN] In-Flight"
      (if (= status "pending")
        "[QUEUED] Pending"
        (if (= status "failed")
          "[FAILED] Refuted"
          (if (= status "blocked")
            "[2PC-GATE] Attention Rail"
            "[UNKNOWN] Status")))))

fn layoutWorkflowDagNodes nodes: List -> List
  nodes

fn renderWorkflowDagNode dagNode: WorkflowDagNode -> ui/VNode
  (let [(cue (formatDagStepStatus dagNode.status))]
    (let [(titleText (str dagNode.title " (" cue ")"))
          (metaText (str "ID: " dagNode.stepId " | Role: :" dagNode.role " | Latency: " (stringFromInt64 dagNode.durationMs) "ms | Asserts: " (stringFromInt64 dagNode.assertionsCount)))
          (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-dag-step-node") "data-step-id" dagNode.stepId))]
      (ui/makeContainer (str "dag-node-" dagNode.stepId) attrs (list (ui/makeText titleText "dag-node-title") (ui/makeText metaText "dag-node-meta")))))

fn renderWorkflowDagNodesLoop nodes: List idx: Int64 len: Int64 acc: (List ui/VNode) -> (List ui/VNode)
  (if (>= idx len)
    acc
    (let [(n (optionOr (listGet nodes idx) (makeWorkflowDagNode "" "" "" "" 0 0 0)))
          (v (renderWorkflowDagNode n))]
      (renderWorkflowDagNodesLoop nodes (+ idx 1) len (listAppend acc (list v)))))

fn renderWorkflowDag dagId: String nodes: List -> ui/VNode
  (let [(count (listLength nodes))]
    (let [(headerText (str "Workflow Task DAG: " dagId " (" (stringFromInt64 count) " steps)"))
          (stepNodes (renderWorkflowDagNodesLoop nodes 0 count (list)))
          (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-workflow-dag-container") "data-dag-id" dagId))]
      (let [(headerNode (ui/makeText headerText "dag-header-title"))]
        (ui/makeContainer (str "dag-root-" dagId) attrs (cons headerNode stepNodes)))))
