(module aslIntel/stmBridge :x [OverlaySymbolGraph buildStmOverlay overlayFind overlayIncoming] :i [(symbolGraph :a g)])

(schema OverlaySymbolGraph (:f baseGraph g/SymbolGraph) (:f shadowedFiles (Map Str Bool)) (:f localNodes (Map Str g/GraphNode)) (:f localEdgesDst (Map Str (List g/GraphEdge))))

fn buildStmOverlay dirtyFiles: (Map Str Bool) base: g/SymbolGraph -> OverlaySymbolGraph
  (OverlaySymbolGraph :baseGraph base :shadowedFiles dirtyFiles :localNodes (mapEmpty) :localEdgesDst (mapEmpty))

fn overlayFind graph: OverlaySymbolGraph id: Str -> (Option g/GraphNode)
  (let [(localMatch (mapGet graph.localNodes id))] (mt localMatch ((some n) (some n)) ((none) (let [(baseMatch (g/graphFind graph.baseGraph id))] (mt baseMatch ((none) (none)) ((some bn) (if (some? (mapGet graph.shadowedFiles bn.file)) (none) (some bn))))))))

fn overlayIncoming graph: OverlaySymbolGraph id: Str -> (List g/GraphEdge)
  (let [(baseEdges (g/graphIncoming graph.baseGraph id)) (validBaseEdges (filter (fn [(e g/GraphEdge)] -> Bool (not (some? (mapGet graph.shadowedFiles e.file)))) baseEdges)) (extraEdges (optionOr (mapGet graph.localEdgesDst id) (list)))] (listAppend validBaseEdges extraEdges))
