(module aslIntel/symbolGraph :x [EdgeKind edgeCalls edgeDefines edgeImports edgeImplements edgeSubtypes GraphNode GraphEdge SymbolGraph edgeKindToString graphCreate graphAddNode graphAddEdge graphNodeCount graphEdgeCount graphIncoming graphOutgoing graphFind])

(enum EdgeKind (:c edgeCalls [] "Calls edge") (:c edgeDefines [] "Defines edge") (:c edgeImports [] "Imports edge") (:c edgeImplements [] "Implements edge") (:c edgeSubtypes [] "Subtypes edge"))

(schema GraphNode (:f id Str) (:f name Str) (:f kind Str) (:f file Str) (:f startLine I64) (:f endLine I64) (:f signature Str) (:f exported Bool))

(schema GraphEdge (:f src Str) (:f dst Str) (:f kind EdgeKind) (:f file Str) (:f line I64))

(schema SymbolGraph (:f nodes (List GraphNode)) (:f edges (List GraphEdge)))

fn edgeKindToString k: EdgeKind -> Str
  (mt k ((edgeCalls) "calls") ((edgeDefines) "defines") ((edgeImports) "imports") ((edgeImplements) "implements") ((edgeSubtypes) "subtypes"))

fn graphCreate -> SymbolGraph
  (SymbolGraph :nodes (list) :edges (list))

fn graphAddNode g: SymbolGraph node: GraphNode -> SymbolGraph
  (with g :nodes (cons node g.nodes))

fn graphAddEdge g: SymbolGraph edge: GraphEdge -> SymbolGraph
  (with g :edges (cons edge g.edges))

fn graphNodeCount g: SymbolGraph -> I64
  (listLength g.nodes)

fn graphEdgeCount g: SymbolGraph -> I64
  (listLength g.edges)

fn graphIncoming g: SymbolGraph dstId: Str -> (List GraphEdge)
  (filter (fn [(e GraphEdge)] -> Bool (= e.dst dstId)) g.edges)

fn graphOutgoing g: SymbolGraph srcId: Str -> (List GraphEdge)
  (filter (fn [(e GraphEdge)] -> Bool (= e.src srcId)) g.edges)

fn graphFind g: SymbolGraph id: Str -> (Option GraphNode)
  (let [(matches (filter (fn [(n GraphNode)] -> Bool (= n.id id)) g.nodes))] (listHead matches))

(schema FastSymbolGraph (:f nodes (Map Str GraphNode)) (:f edgesSrc (Map Str (List GraphEdge))) (:f edgesDst (Map Str (List GraphEdge))))

fn fastGraphCreate -> FastSymbolGraph
  (FastSymbolGraph :nodes (mapEmpty) :edgesSrc (mapEmpty) :edgesDst (mapEmpty))

fn fastGraphAddNode g: FastSymbolGraph node: GraphNode -> FastSymbolGraph
  (with g :nodes (mapSet g.nodes node.id node))

fn fastGraphRemoveNode g: FastSymbolGraph nodeId: Str -> FastSymbolGraph
  (let [(incoming (optionOr (mapGet g.edgesDst nodeId) (list))) (outgoing (optionOr (mapGet g.edgesSrc nodeId) (list))) (gSrcCleaned (fold (fn [(acc (Map Str (List GraphEdge))) (e GraphEdge)] -> (Map Str (List GraphEdge)) (let [(src e.src) (srcList (optionOr (mapGet acc src) (list))) (newSrcList (filter (fn [(se GraphEdge)] -> Bool (not (= se.dst nodeId))) srcList))] (if (= (listLength newSrcList) 0) (mapRemove acc src) (mapSet acc src newSrcList)))) g.edgesSrc incoming)) (gDstCleaned (fold (fn [(acc (Map Str (List GraphEdge))) (e GraphEdge)] -> (Map Str (List GraphEdge)) (let [(dst e.dst) (dstList (optionOr (mapGet acc dst) (list))) (newDstList (filter (fn [(de GraphEdge)] -> Bool (not (= de.src nodeId))) dstList))] (if (= (listLength newDstList) 0) (mapRemove acc dst) (mapSet acc dst newDstList)))) g.edgesDst outgoing))] (FastSymbolGraph :nodes (mapRemove g.nodes nodeId) :edgesSrc (mapRemove gSrcCleaned nodeId) :edgesDst (mapRemove gDstCleaned nodeId)))

fn fastGraphAddEdge g: FastSymbolGraph edge: GraphEdge -> FastSymbolGraph
  (let [(src edge.src) (dst edge.dst) (srcList (optionOr (mapGet g.edgesSrc src) (list))) (dstList (optionOr (mapGet g.edgesDst dst) (list)))] (with g :edgesSrc (mapSet g.edgesSrc src (listAppend srcList (list edge))) :edgesDst (mapSet g.edgesDst dst (listAppend dstList (list edge)))))
