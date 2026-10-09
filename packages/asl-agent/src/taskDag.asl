(module aslAgent/taskDag :x [TaskNodeStatus TaskNode TaskDAG nodePending nodeReady nodeInProgress nodeCompleted nodeFailed nodeBlocked makeTaskNode makeTaskDag findNode isNodeCompleted? areDepsSatisfied? getCompletedNodeIds getReadyNodes markNodeStatus markNodeCompleted isDagComplete? hasDagDeadlock? formatDagSummary nodeStatusToString renderTaskDagBoxart renderTaskDagVdomAsn] :i [(asnBoxart :a box)])

(enum TaskNodeStatus (:c nodePending [] "Awaiting dependency completion") (:c nodeReady [] "All dependencies satisfied, unblocked for worker execution") (:c nodeInProgress [] "Currently claimed and actively running") (:c nodeCompleted [] "Successfully executed and verified against gates") (:c nodeFailed [] "Execution or gate verification failed") (:c nodeBlocked [] "Blocked due to upstream failure or unresolvable constraint"))

(schema TaskNode (:f id Str) (:f title Str) (:f role Str) (:f deps (List Str)) (:f status TaskNodeStatus) (:f assignedModel Str) (:f receipt Str))

(schema TaskDAG (:f id Str) (:f nodes (List TaskNode)) (:f iteration I64))

fn makeTaskNode id: Str title: Str role: Str deps: (List Str) -> TaskNode
  (TaskNode :id id :title title :role role :deps deps :status (nodePending) :assignedModel "" :receipt "")

fn makeTaskDag id: Str nodes: (List TaskNode) -> TaskDAG
  (TaskDAG :id id :nodes nodes :iteration 0)

fn isNodeCompleted? node: TaskNode -> Bool
  (mt node.status ((nodeCompleted) true) ((nodePending) false) ((nodeReady) false) ((nodeInProgress) false) ((nodeFailed) false) ((nodeBlocked) false))

fn isNodeInFlight? node: TaskNode -> Bool
  (mt node.status ((nodeInProgress) true) ((nodeReady) true) ((nodePending) false) ((nodeCompleted) false) ((nodeFailed) false) ((nodeBlocked) false))

fn findNode dag: TaskDAG nodeId: Str -> (Option TaskNode)
  (let [(nodes dag.nodes) (matched (fold (fn [(acc (Option TaskNode)) (n TaskNode)] -> (Option TaskNode) (mt acc ((some _) acc) ((none) (if (= n.id nodeId) (some n) (none))))) (none) nodes))] matched)

fn getCompletedNodeIds dag: TaskDAG -> (List Str)
  (fold (fn [(acc (List Str)) (n TaskNode)] -> (List Str) (if (isNodeCompleted? n) (cons n.id acc) acc)) (list) dag.nodes)

fn areDepsSatisfied? node: TaskNode completedIds: (List Str) -> Bool
  (let [(dependencies node.deps)] (if (listEmpty? dependencies) true (fold (fn [(allOk Bool) (depId Str)] -> Bool (if (not allOk) false (let [(hasDep (fold (fn [(found Bool) (doneId Str)] -> Bool (if found true (= depId doneId))) false completedIds))] hasDep))) true dependencies)))

fn getReadyNodes dag: TaskDAG -> (List TaskNode)
  (let [(completed (getCompletedNodeIds dag))] (fold (fn [(acc (List TaskNode)) (n TaskNode)] -> (List TaskNode) (mt n.status ((nodePending) (if (areDepsSatisfied? n completed) (cons (TaskNode :id n.id :title n.title :role n.role :deps n.deps :status (nodeReady) :assignedModel n.assignedModel :receipt n.receipt) acc) acc)) ((nodeReady) (cons n acc)) ((nodeInProgress) acc) ((nodeCompleted) acc) ((nodeFailed) acc) ((nodeBlocked) acc))) (list) dag.nodes))

fn markNodeStatus dag: TaskDAG nodeId: Str status: TaskNodeStatus receipt: Str -> TaskDAG
  (let [(updatedNodes (fold (fn [(acc (List TaskNode)) (n TaskNode)] -> (List TaskNode) (if (= n.id nodeId) (cons (TaskNode :id n.id :title n.title :role n.role :deps n.deps :status status :assignedModel n.assignedModel :receipt receipt) acc) (cons n acc))) (list) dag.nodes))] (with dag :nodes (listReverse updatedNodes) :iteration (+ dag.iteration 1)))

fn markNodeCompleted dag: TaskDAG nodeId: Str receipt: Str -> TaskDAG
  (markNodeStatus dag nodeId (nodeCompleted) receipt)

fn isDagComplete? dag: TaskDAG -> Bool
  (fold (fn [(allDone Bool) (n TaskNode)] -> Bool (and allDone (isNodeCompleted? n))) true dag.nodes)

fn hasDagDeadlock? dag: TaskDAG -> Bool
  (if (isDagComplete? dag) false (let [(ready (getReadyNodes dag)) (hasInFlight (fold (fn [(acc Bool) (n TaskNode)] -> Bool (or acc (isNodeInFlight? n))) false dag.nodes))] (and (listEmpty? ready) (not hasInFlight))))

fn formatDagSummary dag: TaskDAG -> Str
  (let [(total (listLength dag.nodes)) (done (listLength (getCompletedNodeIds dag))) (ready (listLength (getReadyNodes dag)))] (str "DAG [" dag.id "]: " (stringFromInt64 done) "/" (stringFromInt64 total) " completed, " (stringFromInt64 ready) " ready"))

fn nodeStatusToString status: TaskNodeStatus -> Str
  (mt status ((nodePending) "pending") ((nodeReady) "ready") ((nodeInProgress) "in-progress") ((nodeCompleted) "completed") ((nodeFailed) "failed") ((nodeBlocked) "blocked"))

fn renderTaskDagBoxart dag: TaskDAG -> Str
  (let [(boxNodes (listReverse (fold (fn [(acc (List box/BoxNode)) (n TaskNode)] -> (List box/BoxNode) (let [(st (mt n.status ((nodeCompleted) "done") ((nodeInProgress) "running") ((nodeFailed) "failed") ((nodeBlocked) "blocked") ((nodeReady) "ready") ((nodePending) "queued")))] (cons (box/BoxNode :id n.id :title n.title :state st) acc))) (list) dag.nodes))) (boxEdges (listReverse (fold (fn [(acc (List box/BoxEdge)) (n TaskNode)] -> (List box/BoxEdge) (fold (fn [(e-acc (List box/BoxEdge)) (depId Str)] -> (List box/BoxEdge) (cons (box/BoxEdge :from depId :to n.id :label (none)) e-acc)) acc n.deps)) (list) dag.nodes)))] (box/renderDagBoxart boxNodes boxEdges))

fn renderTaskDagVdomAsn dag: TaskDAG -> Str
  (let [(nodeVdoms (fold (fn [(acc Str) (n TaskNode)] -> Str (let [(stStr (nodeStatusToString n.status)) (depsStr (stringTrim (fold (fn [(s Str) (d Str)] -> Str (str s "\"" d "\" ")) "" n.deps))) (receiptPart (if (stringEmpty? n.receipt) "" (str " (:span :class \"node-receipt\" \"" n.receipt "\")")))] (str acc "    (:div :class \"dag-node\" :data-id \"" n.id "\" :data-status \"" stStr "\" :data-role \"" n.role "\"\n" "      (:span :class \"node-title\" \"" n.title "\")\n" "      (:span :class \"node-deps\" [" depsStr "])" receiptPart ")\n"))) "" dag.nodes))] (str "(:div :class \"task-dag\" :data-dag-id \"" dag.id "\" :data-iteration " (stringFromInt64 dag.iteration) " :data-complete " (if (isDagComplete? dag) "true" "false") " :data-deadlocked " (if (hasDagDeadlock? dag) "true" "false") "\n" "  (:div :class \"dag-nodes\"\n" nodeVdoms "  ))"))
