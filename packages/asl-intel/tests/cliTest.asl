(module aslIntel/tests/cliTest :x [testCliHealthMatrixStructure testCliOrphansFilter testCliCycles3stateDfs testCliHotspotsThreshold runTests] :i [(health :a h) (symbolGraph :a g)])

fn makeNode id: Str name: Str start: I64 end: I64 sig: Str exp: Bool -> g/GraphNode
  (g/GraphNode :id id :name name :kind "fn" :file (str "src/" id ".asl") :startLine start :endLine end :signature sig :exported exp)

fn makeEdge src: Str dst: Str k: g/EdgeKind -> g/GraphEdge
  (g/GraphEdge :src src :dst dst :kind k :file (str "src/" src ".asl") :line 10)

fn testCliHealthMatrixStructure -> Bool
  (let [(cleanM (h/intelHealth "clean-scope")) (report (h/formatHealthReport cleanM))] (assert (= cleanM.scope "clean-scope") "Scope must match 'clean-scope'") (assert cleanM.healthy "Clean matrix must be healthy") (assert (not cleanM.hasCycles) "Clean matrix must have no cycles") (assert (listEmpty? cleanM.anomalies) "Clean matrix must have empty anomalies") (assert (stringContains? report "Structural Health Matrix") "Report must contain canonical header") true)

fn testCliOrphansFilter -> Bool
  (let [(orphanNode (makeNode "orphan-fn" "orphan-fn" 1 10 "[]" true)) (internalNode (makeNode "internal-fn" "internal-fn" 1 10 "[]" false)) (calledNode (makeNode "called-fn" "called-fn" 1 10 "[]" true)) (callerNode (makeNode "caller-fn" "caller-fn" 1 10 "[]" false)) (callEdge (makeEdge "caller-fn" "called-fn" (g/edgeCalls))) (graph (g/SymbolGraph :nodes (list orphanNode internalNode calledNode callerNode) :edges (list callEdge))) (orphans (h/detectOrphanExports graph))] (assert (= (listLength orphans) 1) "Expected exactly 1 orphan export") (let [(anom (optionOr (listHead orphans) (h/HealthAnomaly :kind (h/anomalyOrphanExport) :symbol "" :location "" :message "" :severity "" :metric 0)))] (assert (= anom.symbol "orphan-fn") "Detected orphan symbol must be 'orphan-fn'")) true)

fn testCliCycles3stateDfs -> Bool
  (let [(na (makeNode "A" "A" 1 10 "[]" false)) (nb (makeNode "B" "B" 1 10 "[]" false)) (e-ab (makeEdge "A" "B" (g/edgeImports))) (e-ba (makeEdge "B" "A" (g/edgeImports))) (cyclicGraph (g/SymbolGraph :nodes (list na nb) :edges (list e-ab e-ba))) (acyclicGraph (g/SymbolGraph :nodes (list na nb) :edges (list e-ab))) (cycAnoms (h/detectImportCycles cyclicGraph)) (cleanAnoms (h/detectImportCycles acyclicGraph))] (assert (not (listEmpty? cycAnoms)) "Cyclic graph must yield cycle anomalies") (assert (listEmpty? cleanAnoms) "Acyclic graph must yield zero cycle anomalies") true)

fn testCliHotspotsThreshold -> Bool
  (let [(nSmall (makeNode "small-fn" "small-fn" 1 10 "[]" false)) (nLarge (makeNode "large-fn" "large-fn" 1 35 "[]" false)) (graph (g/SymbolGraph :nodes (list nSmall nLarge) :edges (list))) (spanHotspots (h/detectCyclomaticHotspots graph 15))] (assert (= (listLength spanHotspots) 1) "Span of 34 lines must trigger cyclomatic hotspot (threshold 15)") (let [(anom (optionOr (listHead spanHotspots) (h/HealthAnomaly :kind (h/anomalyComplexityHotspot) :symbol "" :location "" :message "" :severity "" :metric 0)))] (assert (= anom.symbol "large-fn") "Hotspot symbol must be 'large-fn'") (assert (= anom.metric 34) "Hotspot metric must be span length 34")) true)

fn runTests -> Bool
  (let [(r1 (testCliHealthMatrixStructure)) (r2 (testCliOrphansFilter)) (r3 (testCliCycles3stateDfs)) (r4 (testCliHotspotsThreshold))] (and r1 (and r2 (and r3 r4))))
