(module aslAgentCore/dag :x [DagNodeState TaskNode TaskDag dagCreate dagAddNode dagFindNode dagIsFalsified? dagFalsifyPremise dagCanActivate? dagCasVersion] :i [(premise :a p) (tasktypes :a tt)])

(enum DagNodeState (:c taskPending [] "Task is pending execution") (:c taskActive [] "Task is actively running") (:c taskCompleted [] "Task completed successfully") (:c taskFailed [] "Task execution failed") (:c taskInvalidated [] "Task invalidated due to refuted premise") (:c taskSuspended [] "Task suspended awaiting intervention"))

(schema TaskNode (:f id Str) (:f title Str) (:f state DagNodeState) (:f dependencies (List Str)) (:f premises (List Str)))

(schema TaskDag (:f nodes (List TaskNode)) (:f version I64) (:f falsifiedPremises (List Str)))

fn dagCreate -> TaskDag
  (TaskDag :nodes (list) :version 0 :falsifiedPremises (list))

fn dagAddNode dag: TaskDag node: TaskNode -> TaskDag
  (with dag :nodes (listAppend dag.nodes (list node)))

fn dagFindNode dag: TaskDag nodeId: Str -> (Option TaskNode)
  (let [(matches (filter (fn [(n TaskNode)] -> Bool (= n.id nodeId)) dag.nodes))] (listHead matches))

fn dagIsFalsified? dag: TaskDag premiseId: Str -> Bool
  (listContains? dag.falsifiedPremises premiseId)

fn dagFalsifyPremise dag: TaskDag premiseId: Str -> TaskDag
  (let [(newFalsified (if (listContains? dag.falsifiedPremises premiseId) dag.falsifiedPremises (listAppend dag.falsifiedPremises (list premiseId)))) (newNodes (map (fn [(node TaskNode)] -> TaskNode (if (listContains? node.premises premiseId) (TaskNode :id node.id :title node.title :state (taskInvalidated) :dependencies node.dependencies :premises node.premises) node)) dag.nodes))] (TaskDag :nodes newNodes :version (+ dag.version 1) :falsifiedPremises newFalsified))

fn isNodeCompleted? dag: TaskDag depId: Str -> Bool
  (let [(optN (dagFindNode dag depId))] (mt optN ((some n) (mt n.state ((taskCompleted) true) (_ false))) ((none) false)))

fn dagCanActivate? dag: TaskDag nodeId: Str -> Bool
  (let [(optN (dagFindNode dag nodeId))] (mt optN ((none) false) ((some node) (let [(isPending (mt node.state ((taskPending) true) (_ false))) (depsOk (fold (fn [(acc Bool) (depId Str)] -> Bool (and acc (isNodeCompleted? dag depId))) true node.dependencies)) (premisesOk (fold (fn [(acc Bool) (premiseId Str)] -> Bool (and acc (not (dagIsFalsified? dag premiseId)))) true node.premises))] (and isPending (and depsOk premisesOk))))))

fn dagCasVersion currentDag: TaskDag expectedVersion: I64 newDag: TaskDag -> (Option TaskDag)
  (if (= currentDag.version expectedVersion) (some newDag) (none))
