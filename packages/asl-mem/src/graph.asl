(module aslMem/graph :x [GraphNode GraphEdge KnowledgeGraph ContradictionResult KnowledgeGraphIndex findNode findOutgoingEdges findNeighbors isFresh? resolveContradiction addNode addEdge addNodesBatch addEdgesBatch removeNode buildGraphIndex findNodeFast findNeighborsFast])

(schema GraphNode (:f id Str) (:f label Str) (:f content Str) (:f timestampEpoch I64) (:f confidence F64))

(schema GraphEdge (:f sourceId Str) (:f targetId Str) (:f relation Str) (:f weight F64) (:f timestampEpoch I64))

(schema KnowledgeGraph (:f nodes (List GraphNode)) (:f edges (List GraphEdge)))

(schema ContradictionResult (:f hasConflict Bool) (:f winnerId Str) (:f explanation Str))

fn findNode graph: KnowledgeGraph nodeId: Str -> (Option GraphNode)
  (let [(matches (filter (fn [(n GraphNode)] -> Bool (= n.id nodeId)) graph.nodes))] (listHead matches))

fn findOutgoingEdges graph: KnowledgeGraph sourceId: Str -> (List GraphEdge)
  (filter (fn [(e GraphEdge)] -> Bool (= e.sourceId sourceId)) graph.edges)

fn findNeighbors graph: KnowledgeGraph nodeId: Str -> (List Str)
  (map (fn [(e GraphEdge)] -> Str e.targetId) (findOutgoingEdges graph nodeId))

fn isFresh? node: GraphNode currentEpoch: I64 maxAgeSec: I64 -> Bool
  (< (- currentEpoch node.timestampEpoch) maxAgeSec)

fn resolveContradiction factA: GraphNode factB: GraphNode -> ContradictionResult
  (let [(timeDiff (- factB.timestampEpoch factA.timestampEpoch)) (confDiff (- factB.confidence factA.confidence))] (cond ((and (> timeDiff 0) (>= confDiff -0.1)) (ContradictionResult :hasConflict true :winnerId factB.id :explanation "Fact B accepted: newer timestamp with authoritative confidence")) ((and (< timeDiff 0) (<= confDiff 0.1)) (ContradictionResult :hasConflict true :winnerId factA.id :explanation "Fact A accepted: newer timestamp with authoritative confidence")) ((> factB.confidence factA.confidence) (ContradictionResult :hasConflict true :winnerId factB.id :explanation "Fact B accepted: significantly higher confidence score")) (else (ContradictionResult :hasConflict true :winnerId factA.id :explanation "Fact A retained: authoritative default"))))

fn addNode graph: KnowledgeGraph node: GraphNode -> KnowledgeGraph
  (with graph :nodes (listAppend graph.nodes (list node)))

fn addEdge graph: KnowledgeGraph edge: GraphEdge -> KnowledgeGraph
  (with graph :edges (listAppend graph.edges (list edge)))

fn addNodesBatch graph: KnowledgeGraph newNodes: (List GraphNode) -> KnowledgeGraph
  (with graph :nodes (listAppend graph.nodes newNodes))

fn addEdgesBatch graph: KnowledgeGraph newEdges: (List GraphEdge) -> KnowledgeGraph
  (with graph :edges (listAppend graph.edges newEdges))

(schema KnowledgeGraphIndex (:f nodeMap (Map Str GraphNode)) (:f adjacency (Map Str (List Str))))

fn buildGraphIndex graph: KnowledgeGraph -> KnowledgeGraphIndex
  (let [(nMap (fold (fn [(acc (Map Str GraphNode)) (n GraphNode)] -> (Map Str GraphNode) (mapSet acc n.id n)) (mapEmpty) graph.nodes)) (adj (fold (fn [(acc (Map Str (List Str))) (e GraphEdge)] -> (Map Str (List Str)) (let [(src e.sourceId) (tgt e.targetId) (existing (optionOr (mapGet acc src) (list)))] (mapSet acc src (listAppend existing (list tgt))))) (mapEmpty) graph.edges))] (KnowledgeGraphIndex :nodeMap nMap :adjacency adj))

fn findNodeFast idx: KnowledgeGraphIndex nodeId: Str -> (Option GraphNode)
  (mapGet idx.nodeMap nodeId)

fn findNeighborsFast idx: KnowledgeGraphIndex nodeId: Str -> (List Str)
  (optionOr (mapGet idx.adjacency nodeId) (list))

fn removeNode graph: KnowledgeGraph nodeId: Str -> KnowledgeGraph
  (let [(remainingNodes (filter (fn [(n GraphNode)] -> Bool (not (= n.id nodeId))) graph.nodes)) (remainingEdges (filter (fn [(e GraphEdge)] -> Bool (and (not (= e.sourceId nodeId)) (not (= e.targetId nodeId)))) graph.edges))] (KnowledgeGraph :nodes remainingNodes :edges remainingEdges))
