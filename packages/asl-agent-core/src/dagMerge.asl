(module aslAgentCore/dagMerge :x [MergedTaskNode DagMergeResult stateToRank resolveStateLattice dagMergeBranches validateDagAcyclic])

(schema MergedTaskNode (:f id Str) (:f title Str) (:f stateStr Str) (:f dependencies (List Str)) (:f premises (List Str)))

(schema DagMergeResult (:f mergedNodes (List MergedTaskNode)) (:f addedByA (List Str)) (:f addedByB (List Str)) (:f reconciledNodes (List Str)) (:f validDag Bool) (:f errorMessage (Option Str)))

fn stateToRank st: Str -> I64
  (if (= st "pending") 0 (if (= st "active") 1 (if (= st "completed") 2 (if (= st "failed") 3 (if (= st "invalidated") 4 0)))))

fn resolveStateLattice stA: Str stB: Str -> Str
  (let [(rankA (stateToRank stA)) (rankB (stateToRank stB))] (if (>= rankA rankB) stA stB))

fn mergeStrLists listA: (List Str) listB: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (item Str)] -> (List Str) (if (listContains? acc item) acc (listAppend acc (list item)))) listA listB)

fn findNodeById nodes: (List MergedTaskNode) targetId: Str -> (Option MergedTaskNode)
  (fold (fn [(acc (Option MergedTaskNode)) (n MergedTaskNode)] -> (Option MergedTaskNode) (mt acc ((some found) (some found)) ((none) (if (= n.id targetId) (some n) (none))))) (none) nodes)

fn checkCycle nodes: (List MergedTaskNode) currentId: Str visited: (List Str) path: (List Str) -> Bool
  (if (listContains? path currentId) true (if (listContains? visited currentId) false (let [(nodeOpt (findNodeById nodes currentId))] (mt nodeOpt ((none) false) ((some n) (let [(newPath (listAppend path (list currentId)))] (fold (fn [(acc Bool) (depId Str)] -> Bool (if acc true (checkCycle nodes depId visited newPath))) false n.dependencies)))))))

fn validateDagAcyclic nodes: (List MergedTaskNode) -> Bool
  (let [(hasCycle (fold (fn [(acc Bool) (n MergedTaskNode)] -> Bool (if acc true (checkCycle nodes n.id (list) (list)))) false nodes))] (not hasCycle))

(schema DagMergeAccumulator (:f nodes (List MergedTaskNode)) (:f added-a (List Str)) (:f added-b (List Str)) (:f reconciled (List Str)) (:f seen (List Str)))

fn dagMergeBranches baseNodes: (List MergedTaskNode) branchANodes: (List MergedTaskNode) branchBNodes: (List MergedTaskNode) -> DagMergeResult
  (let [(baseIds (fold (fn [(acc (List Str)) (n MergedTaskNode)] -> (List Str) (listAppend acc (list n.id))) (list) baseNodes)) (init (DagMergeAccumulator :nodes (list) :added-a (list) :added-b (list) :reconciled (list) :seen (list))) (afterA (fold (fn [(acc DagMergeAccumulator) (na MergedTaskNode)] -> DagMergeAccumulator (let [(id na.id) (bOpt (findNodeById branchBNodes id)) (curNodes acc.nodes) (curSeen (listAppend acc.seen (list id)))] (mt bOpt ((none) (let [(isNew (not (listContains? baseIds id))) (nextA (if isNew (listAppend acc.added-a (list id)) acc.added-a))] (DagMergeAccumulator :nodes (listAppend curNodes (list na)) :added-a nextA :added-b acc.added-b :reconciled acc.reconciled :seen curSeen))) ((some nb) (let [(resolvedSt (resolveStateLattice na.stateStr nb.stateStr)) (mergedDeps (mergeStrLists na.dependencies nb.dependencies)) (mergedPremises (mergeStrLists na.premises nb.premises)) (unified (MergedTaskNode :id id :title na.title :stateStr resolvedSt :dependencies mergedDeps :premises mergedPremises)) (nextRec (listAppend acc.reconciled (list id)))] (DagMergeAccumulator :nodes (listAppend curNodes (list unified)) :added-a acc.added-a :added-b acc.added-b :reconciled nextRec :seen curSeen)))))) init branchANodes)) (finalAcc (fold (fn [(acc DagMergeAccumulator) (nb MergedTaskNode)] -> DagMergeAccumulator (let [(id nb.id)] (if (listContains? acc.seen id) acc (let [(curNodes acc.nodes) (curSeen (listAppend acc.seen (list id))) (isNew (not (listContains? baseIds id))) (nextB (if isNew (listAppend acc.added-b (list id)) acc.added-b))] (DagMergeAccumulator :nodes (listAppend curNodes (list nb)) :added-a acc.added-a :added-b nextB :reconciled acc.reconciled :seen curSeen))))) afterA branchBNodes)) (mergedList finalAcc.nodes) (isAcyclic (validateDagAcyclic mergedList))] (if isAcyclic (DagMergeResult :mergedNodes mergedList :addedByA finalAcc.added-a :addedByB finalAcc.added-b :reconciledNodes finalAcc.reconciled :validDag true :errorMessage (none)) (DagMergeResult :mergedNodes mergedList :addedByA finalAcc.added-a :addedByB finalAcc.added-b :reconciledNodes finalAcc.reconciled :validDag false :errorMessage (some "Topological cycle detected in merged task dependencies"))))
