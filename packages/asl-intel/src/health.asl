(module aslIntel/health :x [HealthAnomalyKind anomalyCycle anomalyBlastRadius anomalyOrphanExport anomalySignatureMismatch anomalyComplexityHotspot anomalyLayerLeakage anomalyBrokenReference anomalyDanglingPointer anomalyTokenPenalty anomalyUncompensatedSaga HealthAnomaly HealthMatrix RefEdge MultidimensionalHealthReport healthAnomalyKindToString detectImportCycles detectBlastRadiusHotspots detectOrphanExports detectSignatureMismatches detectCyclomaticHotspots moduleToLayer isAgentId? detectLayerLeakage detectBrokenReferences detectDanglingPointers detectCyclicReferences auditReferenceIntegrity buildHealthMatrix detectTokenPenalties detectUncompensatedSagas detectSubwordInefficiencies buildMultidimensionalReport intelHealth formatHealthReport] :i [(symbolGraph :a g) (xref :a xr)])

(enum HealthAnomalyKind (:c anomalyCycle [] "Cycle detected in import dependencies") (:c anomalyBlastRadius [] "Blast radius hotspot: high fan-in symbol") (:c anomalyOrphanExport [] "Orphan export: exported symbol with zero references") (:c anomalySignatureMismatch [] "Signature mismatch across call edge") (:c anomalyComplexityHotspot [] "Complexity hotspot: function exceeding complexity threshold") (:c anomalyLayerLeakage [] "Boundary violation: illegal cross-layer dependency from lower to higher layer") (:c anomalyBrokenReference [] "Broken reference: reference targets nonexistent symbol, task, ADR or anchor") (:c anomalyDanglingPointer [] "Dangling pointer: perceptual pointer or memory chunk targets missing buffer") (:c anomalyTokenPenalty [] "Token penalty: dashed identifier exceeding token baseline") (:c anomalyUncompensatedSaga [] "Uncompensated saga: side-effect mutation without cleanup handler"))

(schema HealthAnomaly (:f kind HealthAnomalyKind) (:f symbol Str) (:f location Str) (:f message Str) (:f severity Str) (:f metric I64))

(schema HealthMatrix (:f scope Str) (:f totalNodes I64) (:f totalEdges I64) (:f anomalies (List HealthAnomaly)) (:f hasCycles Bool) (:f healthy Bool))

(schema CycleDfsState (:f visited (List Str)) (:f anomalies (List HealthAnomaly)))

(schema RefEdge (:f source Str) (:f target Str))

(schema XRefCycleState (:f visited (List Str)) (:f inPath (List Str)) (:f anomalies (List HealthAnomaly)))

fn healthAnomalyKindToString k: HealthAnomalyKind -> Str
  (mt k ((anomalyCycle) "cycle") ((anomalyBlastRadius) "blast-radius") ((anomalyOrphanExport) "orphan-export") ((anomalySignatureMismatch) "signature-mismatch") ((anomalyComplexityHotspot) "complexity-hotspot") ((anomalyLayerLeakage) "layer-leakage") ((anomalyBrokenReference) "broken-reference") ((anomalyDanglingPointer) "dangling-pointer") ((anomalyTokenPenalty) "token-penalty") ((anomalyUncompensatedSaga) "uncompensated-saga"))

fn findNodeByKey nodes: (List g/GraphNode) key: Str -> (Option g/GraphNode)
  (listHead (filter (fn [(n g/GraphNode)] -> Bool (or (= n.id key) (= n.name key))) nodes))

fn nodeLocation nodeOpt: (Option g/GraphNode) fallback: Str -> Str
  (mt nodeOpt ((some n) (str n.file ":" (stringFromInt64 n.startLine))) ((none) fallback))

fn nodeInDegree node: g/GraphNode edges: (List g/GraphEdge) -> I64
  (let [(nid node.id) (nname node.name)] (listLength (filter (fn [(e g/GraphEdge)] -> Bool (or (= e.dst nid) (= e.dst nname))) edges)))

fn hasSymbolInAnomalies? anoms: (List HealthAnomaly) sym: Str -> Bool
  (not (listEmpty? (filter (fn [(a HealthAnomaly)] -> Bool (= a.symbol sym)) anoms)))

fn getImportTargets key: Str edges: (List g/GraphEdge) -> (List Str)
  (fold (fn [(acc (List Str)) (e g/GraphEdge)] -> (List Str) (if (and (= (g/edgeKindToString e.kind) "imports") (= e.src key)) (if (listContains? acc e.dst) acc (listAppend acc (list e.dst))) acc)) (list) edges)

fn dfsImportCycles curr: Str inPath: (List Str) state: CycleDfsState edges: (List g/GraphEdge) nodes: (List g/GraphNode) -> CycleDfsState
  (if (listContains? inPath curr) (let [(nodeOpt (findNodeByKey nodes curr)) (loc (nodeLocation nodeOpt curr)) (msg (str "CYCLE_DETECTED: Circular import barrier violation involving '" curr "'")) (anom (HealthAnomaly :kind (anomalyCycle) :symbol curr :location loc :message msg :severity "blocker" :metric (listLength inPath))) (curAnoms state.anomalies)] (if (hasSymbolInAnomalies? curAnoms curr) state (with state :anomalies (listAppend curAnoms (list anom))))) (if (listContains? state.visited curr) state (let [(nextPath (cons curr inPath)) (targets (getImportTargets curr edges)) (afterTargets (fold (fn [(st CycleDfsState) (tgt Str)] -> CycleDfsState (dfsImportCycles tgt nextPath st edges nodes)) state targets))] (CycleDfsState :visited (cons curr afterTargets.visited) :anomalies afterTargets.anomalies))))

fn detectImportCycles g: g/SymbolGraph -> (List HealthAnomaly)
  (let [(importEdges (filter (fn [(e g/GraphEdge)] -> Bool (= (g/edgeKindToString e.kind) "imports")) g.edges)) (allNodes g.nodes) (nodeKeys (fold (fn [(acc (List Str)) (n g/GraphNode)] -> (List Str) (let [(k (if (not (stringEmpty? n.id)) n.id n.name))] (if (listContains? acc k) acc (listAppend acc (list k))))) (list) allNodes)) (allKeys (fold (fn [(acc (List Str)) (e g/GraphEdge)] -> (List Str) (let [(s e.src)] (if (listContains? acc s) acc (listAppend acc (list s))))) nodeKeys importEdges)) (initState (CycleDfsState :visited (list) :anomalies (list))) (finalState (fold (fn [(st CycleDfsState) (key Str)] -> CycleDfsState (if (listContains? st.visited key) st (dfsImportCycles key (list) st importEdges allNodes))) initState allKeys))] finalState.anomalies)

fn detectBlastRadiusHotspots g: g/SymbolGraph threshold: I64 -> (List HealthAnomaly)
  (let [(thresh (if (<= threshold 0) 10 threshold)) (edges g.edges)] (fold (fn [(acc (List HealthAnomaly)) (node g/GraphNode)] -> (List HealthAnomaly) (let [(deg (nodeInDegree node edges))] (if (>= deg thresh) (let [(anom (HealthAnomaly :kind (anomalyBlastRadius) :symbol node.name :location (str node.file ":" (stringFromInt64 node.startLine)) :message (str "BLAST_RADIUS_WARNING: Symbol '" node.name "' has high fan-in (in-degree=" (stringFromInt64 deg) ", threshold=" (stringFromInt64 thresh) ")") :severity "warning" :metric deg))] (listAppend acc (list anom))) acc))) (list) g.nodes))

fn detectOrphanExports g: g/SymbolGraph -> (List HealthAnomaly)
  (let [(edges g.edges)] (fold (fn [(acc (List HealthAnomaly)) (node g/GraphNode)] -> (List HealthAnomaly) (if node.exported (let [(deg (nodeInDegree node edges))] (if (= deg 0) (let [(anom (HealthAnomaly :kind (anomalyOrphanExport) :symbol node.name :location (str node.file ":" (stringFromInt64 node.startLine)) :message (str "ORPHAN_EXPORT_WARNING: Exported symbol '" node.name "' has zero incoming references") :severity "warning" :metric 0))] (listAppend acc (list anom))) acc)) acc)) (list) g.nodes))

fn detectSignatureMismatches g: g/SymbolGraph -> (List HealthAnomaly)
  (let [(nodes g.nodes) (callEdges (filter (fn [(e g/GraphEdge)] -> Bool (= (g/edgeKindToString e.kind) "calls")) g.edges))] (fold (fn [(acc (List HealthAnomaly)) (edge g/GraphEdge)] -> (List HealthAnomaly) (let [(calleeOpt (findNodeByKey nodes edge.dst))] (mt calleeOpt ((none) (let [(anom (HealthAnomaly :kind (anomalySignatureMismatch) :symbol edge.dst :location (str edge.file ":" (stringFromInt64 edge.line)) :message (str "SIGNATURE_ERROR: Unresolved callee '" edge.dst "' at call site") :severity "error" :metric 0))] (listAppend acc (list anom)))) ((some callee) (let [(sig (stringTrim callee.signature))] (if (or (stringEmpty? sig) (stringContains? sig "mismatch")) (let [(anom (HealthAnomaly :kind (anomalySignatureMismatch) :symbol callee.name :location (str edge.file ":" (stringFromInt64 edge.line)) :message (str "SIGNATURE_ERROR: Callee '" callee.name "' has incompatible or missing signature") :severity "error" :metric 0))] (listAppend acc (list anom))) acc)))))) (list) callEdges))

fn detectCyclomaticHotspots g: g/SymbolGraph threshold: I64 -> (List HealthAnomaly)
  (let [(thresh (if (<= threshold 0) 15 threshold))] (fold (fn [(acc (List HealthAnomaly)) (node g/GraphNode)] -> (List HealthAnomaly) (let [(span (- node.endLine node.startLine))] (if (> span thresh) (let [(anom (HealthAnomaly :kind (anomalyComplexityHotspot) :symbol node.name :location (str node.file ":" (stringFromInt64 node.startLine) "-" (stringFromInt64 node.endLine)) :message (str "COMPLEXITY_HOTSPOT: Symbol '" node.name "' span (" (stringFromInt64 span) " lines) exceeds threshold " (stringFromInt64 thresh)) :severity "warning" :metric span))] (listAppend acc (list anom))) acc))) (list) g.nodes))

fn moduleToLayer name: Str -> I64
  (let [(n (stringTrim name))] (if (or (stringContains? n "asl-bridge") (or (stringContains? n "asl-plugin") (or (stringContains? n "asl-sh") (or (stringContains? n "asl-cli") (or (stringContains? n "asl-gates") (or (stringContains? n "browser-plugin") (or (stringContains? n "bridges/") (stringContains? n "bin/")))))))) 3 (if (or (stringContains? n "crawler") (or (stringContains? n "web-api-search") (or (stringContains? n "asl-registry") (or (stringContains? n "voice") (or (stringContains? n "asl-mem") (or (= n "mem") (or (stringContains? n "mem/") (stringContains? n "/mem/")))))))) 2 (if (or (stringContains? n "agent-bus") (or (stringContains? n "agent-core") (or (stringContains? n "harness") (stringContains? n "asl-contracts")))) 1 0))))

fn isAgentId? s: Str -> Bool
  (let [(trimmed (stringTrim s))] (and (or (stringStartsWith? trimmed "@") (stringStartsWith? trimmed ":agent:")) (and (> (stringLength trimmed) 1) (and (not (stringContains? trimmed "/")) (not (stringStartsWith? trimmed "wal")) (not (stringStartsWith? trimmed "@wal"))))))

fn detectLayerLeakage g: g/SymbolGraph -> (List HealthAnomaly)
  (let [(nodes g.nodes) (edges g.edges) (edgeLeaks (fold (fn [(acc (List HealthAnomaly)) (edge g/GraphEdge)] -> (List HealthAnomaly) (let [(srcNode (findNodeByKey nodes edge.src)) (srcPath (mt srcNode ((some sn) (if (not (stringEmpty? sn.file)) sn.file edge.src)) ((none) (if (not (stringEmpty? edge.file)) edge.file edge.src)))) (lSrc (moduleToLayer srcPath)) (dstNode (findNodeByKey nodes edge.dst)) (dstPath (mt dstNode ((some dn) (if (not (stringEmpty? dn.file)) dn.file edge.dst)) ((none) edge.dst))) (lDst (moduleToLayer dstPath)) (loc (str edge.file ":" (stringFromInt64 edge.line)))] (if (and (= lSrc 0) (isAgentId? edge.dst)) (let [(anom (HealthAnomaly :kind (anomalyLayerLeakage) :symbol edge.src :location loc :message (str "LAYER_LEAKAGE: Layer 0 component references forbidden agent ID '" edge.dst "'") :severity "blocker" :metric 1))] (listAppend acc (list anom))) (if (and (>= lSrc 0) (and (>= lDst 0) (< lSrc lDst))) (let [(anom (HealthAnomaly :kind (anomalyLayerLeakage) :symbol edge.src :location loc :message (str "LAYER_LEAKAGE: Illegal upward dependency from Layer " (stringFromInt64 lSrc) " ('" edge.src "') to Layer " (stringFromInt64 lDst) " ('" edge.dst "')") :severity "blocker" :metric (- lDst lSrc)))] (listAppend acc (list anom))) acc)))) (list) edges)) (nodeLeaks (fold (fn [(acc (List HealthAnomaly)) (node g/GraphNode)] -> (List HealthAnomaly) (let [(nPath (if (not (stringEmpty? node.file)) node.file node.name)) (lNode (moduleToLayer nPath))] (if (and (= lNode 0) (or (isAgentId? node.name) (or (isAgentId? node.id) (isAgentId? node.signature)))) (let [(loc (str node.file ":" (stringFromInt64 node.startLine))) (anom (HealthAnomaly :kind (anomalyLayerLeakage) :symbol node.name :location loc :message (str "LAYER_LEAKAGE: Layer 0 component references forbidden agent ID '" node.name "'") :severity "blocker" :metric 1))] (listAppend acc (list anom))) acc))) (list) nodes))] (listAppend edgeLeaks nodeLeaks))

fn getXrefTargets curr: Str edges: (List RefEdge) -> (List Str)
  (fold (fn [(acc (List Str)) (e RefEdge)] -> (List Str) (if (= e.source curr) (let [(tgt e.target)] (if (listContains? acc tgt) acc (listAppend acc (list tgt)))) acc)) (list) edges)

fn dfsXrefCycle curr: Str state: XRefCycleState edges: (List RefEdge) -> XRefCycleState
  (if (listContains? state.inPath curr) (let [(msg (str "CYCLIC_REFERENCE: Circular dependency chain detected involving '" curr "'")) (anom (HealthAnomaly :kind (anomalyCycle) :symbol curr :location "cross-reference" :message msg :severity "blocker" :metric (listLength state.inPath))) (curAnoms state.anomalies)] (if (hasSymbolInAnomalies? curAnoms curr) state (with state :anomalies (listAppend curAnoms (list anom))))) (if (listContains? state.visited curr) state (let [(nextPath (cons curr state.inPath)) (targets (getXrefTargets curr edges)) (st1 (with state :inPath nextPath)) (afterTargets (fold (fn [(st XRefCycleState) (tgt Str)] -> XRefCycleState (dfsXrefCycle tgt st edges)) st1 targets))] (XRefCycleState :visited (cons curr afterTargets.visited) :inPath state.inPath :anomalies afterTargets.anomalies))))

fn detectCyclicReferences edges: (List RefEdge) -> (List HealthAnomaly)
  (let [(allNodes (fold (fn [(acc (List Str)) (e RefEdge)] -> (List Str) (let [(s e.source) (t e.target) (acc1 (if (listContains? acc s) acc (listAppend acc (list s))))] (if (listContains? acc1 t) acc1 (listAppend acc1 (list t))))) (list) edges)) (initState (XRefCycleState :visited (list) :inPath (list) :anomalies (list))) (finalState (fold (fn [(st XRefCycleState) (node Str)] -> XRefCycleState (if (listContains? st.visited node) st (dfsXrefCycle node st edges))) initState allNodes))] finalState.anomalies)

fn detectBrokenReferences refs: (List xr/CrossReference) validTargets: (List Str) -> (List HealthAnomaly)
  (fold (fn [(acc (List HealthAnomaly)) (ref xr/CrossReference)] -> (List HealthAnomaly) (let [(tgt ref.target) (k tgt.kind) (id tgt.id) (formatted (xr/formatRefUri tgt)) (isValid (or (listContains? validTargets formatted) (or (listContains? validTargets id) (listContains? validTargets (str k ":" id)))))] (if isValid acc (let [(anom (HealthAnomaly :kind (anomalyBrokenReference) :symbol formatted :location ref.source :message (str "BROKEN_REFERENCE: Target '" formatted "' in '" ref.source "' not found in valid registry") :severity "error" :metric 1))] (listAppend acc (list anom)))))) (list) refs)

fn detectDanglingPointers pointers: (List Str) validBuffers: (List Str) -> (List HealthAnomaly)
  (fold (fn [(acc (List HealthAnomaly)) (ptr Str)] -> (List HealthAnomaly) (if (listContains? validBuffers ptr) acc (let [(anom (HealthAnomaly :kind (anomalyDanglingPointer) :symbol ptr :location "mem/pointers" :message (str "DANGLING_POINTER: Target memory buffer for pointer '" ptr "' has vanished") :severity "error" :metric 1))] (listAppend acc (list anom))))) (list) pointers)

fn auditReferenceIntegrity refs: (List xr/CrossReference) validTargets: (List Str) -> (List HealthAnomaly)
  (let [(broken (detectBrokenReferences refs validTargets)) (edges (map (fn [(r xr/CrossReference)] -> RefEdge (RefEdge :source r.source :target (xr/formatRefUri r.target))) refs)) (cycles (detectCyclicReferences edges))] (listAppend broken cycles))

fn buildHealthMatrix g: g/SymbolGraph scope: Str -> HealthMatrix
  (let [(cycles (detectImportCycles g)) (layerLeaks (detectLayerLeakage g)) (blastHotspots (detectBlastRadiusHotspots g 10)) (orphans (detectOrphanExports g)) (sigMismatches (detectSignatureMismatches g)) (complexityHotspots (detectCyclomaticHotspots g 15)) (anomalies (listAppend (listAppend (listAppend cycles layerLeaks) sigMismatches) (listAppend (listAppend blastHotspots orphans) complexityHotspots))) (hasCycles (not (listEmpty? cycles))) (hasBlockers (or (or hasCycles (not (listEmpty? layerLeaks))) (not (listEmpty? sigMismatches)))) (healthy (not hasBlockers)) (totalN (g/graphNodeCount g)) (totalE (g/graphEdgeCount g))] (HealthMatrix :scope scope :totalNodes totalN :totalEdges totalE :anomalies anomalies :hasCycles hasCycles :healthy healthy))

fn intelHealth scope: Str -> HealthMatrix
  (buildHealthMatrix (g/graphCreate) scope)

fn formatHealthReport matrix: HealthMatrix -> Str
  (let [(statusStr (if matrix.healthy "HEALTHY (CLEAN)" "UNHEALTHY (ANOMALIES DETECTED)")) (cycleStr (if matrix.hasCycles "BLOCKED (CYCLES DETECTED)" "NONE (CLEAN)")) (header (str "=== Structural Health Matrix ===\n" "=== CODEBASE STRUCTURAL HEALTH REPORT ===\n" "Scope:        " matrix.scope "\n" "Status:       " statusStr "\n" "Total Nodes:  " (stringFromInt64 matrix.totalNodes) "\n" "Total Edges:  " (stringFromInt64 matrix.totalEdges) "\n" "Import Cycle: " cycleStr "\n" "Anomalies:    " (stringFromInt64 (listLength matrix.anomalies)) "\n"))] (if (listEmpty? matrix.anomalies) (str header "\nNo anomalies detected. Codebase structure is clean.") (let [(anomLines (map (fn [(a HealthAnomaly)] -> Str (str "  [" a.severity "] " a.symbol " at " a.location " (metric: " (stringFromInt64 a.metric) "): " a.message)) matrix.anomalies))] (str header "\nDetected Anomalies:\n" (stringJoin anomLines "\n")))))

(schema MultidimensionalHealthReport (:f scope Str) (:f tokenScore F64) (:f dashedCount I64) (:f anomalies (List HealthAnomaly)) (:f healthy Bool))

fn detectTokenPenalties symbols: (List Str) -> (List HealthAnomaly)
  (fold (fn [(acc (List HealthAnomaly)) (sym Str)] -> (List HealthAnomaly) (if (and (stringContains? sym "-") (> (stringLength sym) 15)) (listAppend acc (list (HealthAnomaly :kind (anomalyTokenPenalty) :symbol sym :location "grammar" :message "TOKEN_PENALTY: Symbol should be migrated to camelCase" :severity "warning" :metric 1))) acc)) (list) symbols)

fn detectUncompensatedSagas actions: (List Str) -> (List HealthAnomaly)
  (fold (fn [(acc (List HealthAnomaly)) (act Str)] -> (List HealthAnomaly) (if (and (stringContains? act "procSpawn") (or (stringContains? act "no-cleanup") (not (stringContains? act ":cleanup")))) (listAppend acc (list (HealthAnomaly :kind (anomalyUncompensatedSaga) :symbol act :location "runtime" :message "UNCOMPENSATED_SAGA: Mutation missing registered cleanup handler" :severity "error" :metric 1))) acc)) (list) actions)

fn buildMultidimensionalReport matrix: HealthMatrix symbols: (List Str) actions: (List Str) -> MultidimensionalHealthReport
  (let [(tokenAnoms (detectTokenPenalties symbols)) (sagaAnoms (detectUncompensatedSagas actions)) (allAnoms (listAppend matrix.anomalies (listAppend tokenAnoms sagaAnoms))) (dashedN (listLength tokenAnoms)) (score (if (= (listLength symbols) 0) 1.0 (- 1.0 (/ (int64ToFloat64 dashedN) (int64ToFloat64 (listLength symbols)))))) (healthy (and matrix.healthy (listEmpty? sagaAnoms)))] (MultidimensionalHealthReport :scope matrix.scope :tokenScore score :dashedCount dashedN :anomalies allAnoms :healthy healthy))

fn detectSubwordInefficiencies identifiers: (List Str) -> (List HealthAnomaly)
  (fold (fn [(acc (List HealthAnomaly)) (id Str)] -> (List HealthAnomaly) (if (and (stringContains? id "-") (or (stringEndsWith? id "-1") (or (stringEndsWith? id "-2") (or (stringEndsWith? id "-3") (or (stringEndsWith? id "-4") (stringEndsWith? id "-5")))))) (listAppend acc (list (HealthAnomaly :kind (anomalyTokenPenalty) :symbol id :location "tasks" :message "SUBWORD_PUNCTUATION_INEFFICIENCY: Use semantic subword instead of numeric dash" :severity "warning" :metric 1))) acc)) (list) identifiers)
