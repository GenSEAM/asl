(module asl-ui/blastRadiusHeatmap :x [DependencyClassification classifyDependencyEdge BlastRadiusNode makeBlastRadiusNode renderBlastRadiusTile calculateMaxBlastRadius] :i [(asl-ui/vnode :a ui) (asl-ui/theme :a theme)])

(enum DependencyClassification (:c edgeRuntimeCycle [] "Critical runtime cyclic dependency") (:c edgeTypeAlias [] "Benign type alias or contract dependency") (:c edgeCausalBlast [] "Direct downstream causal blast dependency"))

(schema BlastRadiusNode (:f moduleName String) (:f blastCount Int64) (:f hasCycles Bool) (:f isRuntimeCycle Bool))

fn makeBlastRadiusNode name: String blastCount: Int64 hasCycles: Bool isRuntimeCycle: Bool -> BlastRadiusNode
  (BlastRadiusNode :moduleName name :blastCount blastCount :hasCycles hasCycles :isRuntimeCycle isRuntimeCycle)

fn classifyDependencyEdge isCycle: Bool isRuntime: Bool -> DependencyClassification
  (if isCycle (if isRuntime (edgeRuntimeCycle) (edgeTypeAlias)) (edgeCausalBlast))

fn calculateMaxBlastRadius nodes: (List BlastRadiusNode) -> Int64
  (fold (fn [(acc Int64) (n BlastRadiusNode)] -> Int64 (if (> n.blastCount acc) n.blastCount acc)) 0 nodes)

fn renderModuleBadge node: BlastRadiusNode -> ui/VNode
  (let [(statusText (if node.isRuntimeCycle "[CYCLE] Runtime Cycle" (if node.hasCycles "[TYPE] Type Cycle" (str "[BLAST] " (stringFromInt64 node.blastCount))))) (label (str node.moduleName " : " statusText)) (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-blast-node") "data-runtime-cycle" (if node.isRuntimeCycle "true" "false")))] (ui/makeContainer (str "blast-" node.moduleName) attrs (list (ui/makeText label "lbl-blast"))))

fn renderBlastRadiusTile nodes: (List BlastRadiusNode) -> ui/VNode
  (let [(maxB (calculateMaxBlastRadius nodes)) (summaryText (str "Causal Blast Radius & Coupling Heatmap (Max Blast: " (stringFromInt64 maxB) ")")) (titleNode (ui/makeText summaryText "blast-title")) (nodeVNodes (fold (fn [(acc (List ui/VNode)) (n BlastRadiusNode)] -> (List ui/VNode) (listAppend acc (list (renderModuleBadge n)))) (list) nodes)) (tileAttrs (mapSet (mapSet (mapEmpty) "class" "sds1-blast-heatmap-card") "data-max-blast" (stringFromInt64 maxB)))] (ui/makeContainer "blast-heatmap-root" tileAttrs (cons titleNode nodeVNodes)))
