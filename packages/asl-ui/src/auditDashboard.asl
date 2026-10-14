(module asl-ui/auditDashboard :x [renderAuditDashboard renderAuditRadar renderRadarSvg renderBlastRadiusHeatmap renderFindingsList renderFindingCard radarAxisPoints extractLensScores] :i [(asl-ui/vnode :a v) (asl-conform/hypergraph :a hyper)])

fn extractLensScores nodes: (List hyper/AuditNode) -> (Map Str Int64)
  (let [(lenses (hyper/canonicalLenses))] (fold (fn [(acc (Map Str Int64)) (lens Str)] -> (Map Str Int64) (mapSet acc lens (hyper/calculateLensScore nodes lens))) (mapEmpty) lenses))

fn computeAxisCoord center: Int64 delta: Int64 isPositive: Bool -> Int64
  (if isPositive (+ center delta) (- center delta))

fn radarAxisPoints scores: (Map Str Int64) -> Str
  (let [(s0 (optionOr (mapGet scores "architecture") 100)) (s1 (optionOr (mapGet scores "platform") 100)) (s2 (optionOr (mapGet scores "logic") 100)) (s3 (optionOr (mapGet scores "memory") 100)) (s4 (optionOr (mapGet scores "security") 100)) (s5 (optionOr (mapGet scores "tokenEconomics") 100)) (x0 150) (y0 (- 150 s0)) (x1 (+ 150 (/ (* s1 866) 1000))) (y1 (- 150 (/ (* s1 500) 1000))) (x2 (+ 150 (/ (* s2 866) 1000))) (y2 (+ 150 (/ (* s2 500) 1000))) (x3 150) (y3 (+ 150 s3)) (x4 (- 150 (/ (* s4 866) 1000))) (y4 (+ 150 (/ (* s4 500) 1000))) (x5 (- 150 (/ (* s5 866) 1000))) (y5 (- 150 (/ (* s5 500) 1000)))] (str (stringFromInt64 x0) "," (stringFromInt64 y0) " " (stringFromInt64 x1) "," (stringFromInt64 y1) " " (stringFromInt64 x2) "," (stringFromInt64 y2) " " (stringFromInt64 x3) "," (stringFromInt64 y3) " " (stringFromInt64 x4) "," (stringFromInt64 y4) " " (stringFromInt64 x5) "," (stringFromInt64 y5)))

fn renderRadarSvg scores: (Map Str Int64) -> Str
  (let [(dataPoints (radarAxisPoints scores))] (str "<svg viewBox=\"0 0 300 300\" class=\"asl-audit-radar\">\n" "  <polygon points=\"150,50 237,100 237,200 150,250 63,200 63,100\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>\n" "  <polygon points=\"150,100 193,125 193,175 150,200 107,175 107,125\" fill=\"none\" stroke=\"#1e293b\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>\n" "  <line x1=\"150\" y1=\"150\" x2=\"150\" y2=\"50\" stroke=\"#475569\" stroke-width=\"1\"/>\n" "  <line x1=\"150\" y1=\"150\" x2=\"237\" y2=\"100\" stroke=\"#475569\" stroke-width=\"1\"/>\n" "  <line x1=\"150\" y1=\"150\" x2=\"237\" y2=\"200\" stroke=\"#475569\" stroke-width=\"1\"/>\n" "  <line x1=\"150\" y1=\"150\" x2=\"150\" y2=\"250\" stroke=\"#475569\" stroke-width=\"1\"/>\n" "  <line x1=\"150\" y1=\"150\" x2=\"63\" y2=\"200\" stroke=\"#475569\" stroke-width=\"1\"/>\n" "  <line x1=\"150\" y1=\"150\" x2=\"63\" y2=\"100\" stroke=\"#475569\" stroke-width=\"1\"/>\n" "  <polygon points=\"" dataPoints "\" fill=\"rgba(14,165,233,0.3)\" stroke=\"#0ea5e9\" stroke-width=\"2\"/>\n" "  <text x=\"150\" y=\"40\" text-anchor=\"middle\" fill=\"#94a3b8\" font-size=\"10\">Architecture</text>\n" "  <text x=\"245\" y=\"98\" text-anchor=\"start\" fill=\"#94a3b8\" font-size=\"10\">Platform</text>\n" "  <text x=\"245\" y=\"206\" text-anchor=\"start\" fill=\"#94a3b8\" font-size=\"10\">Logic</text>\n" "  <text x=\"150\" y=\"268\" text-anchor=\"middle\" fill=\"#94a3b8\" font-size=\"10\">Memory</text>\n" "  <text x=\"55\" y=\"206\" text-anchor=\"end\" fill=\"#94a3b8\" font-size=\"10\">Security</text>\n" "  <text x=\"55\" y=\"98\" text-anchor=\"end\" fill=\"#94a3b8\" font-size=\"10\">TokenEconomics</text>\n" "</svg>"))

fn renderAuditRadar scores: (Map Str Int64) -> v/VNode
  (let [(svgContent (renderRadarSvg scores)) (attrs (mapSet (mapEmpty) "data-component" "audit-radar"))] (v/makeVNode "svg-wrapper" "radar-widget" svgContent attrs (list) 300 300 true))

fn renderFindingCard node: hyper/AuditNode -> v/VNode
  (let [(cardAttrs (mapSet (mapSet (mapEmpty) "class" "audit-finding-card") "data-severity" node.severity)) (titleNode (v/makeText (str "[" node.severity "] " node.lens ": " node.id) "title")) (anchorNode (v/makeText (str "Anchor: " node.anchor) "anchor")) (evidenceNode (v/makeText (str "Evidence: " node.evidence) "evidence")) (remedyNode (v/makeText (str "Remedy: " node.remedy) "remedy"))] (v/makeContainer (str "finding-" node.id) cardAttrs (list titleNode anchorNode evidenceNode remedyNode)))

fn renderFindingsList nodes: (List hyper/AuditNode) -> v/VNode
  (let [(cards (fold (fn [(acc (List v/VNode)) (n hyper/AuditNode)] -> (List v/VNode) (listAppend acc (list (renderFindingCard n)))) (list) nodes))] (v/makeContainer "findings-list" (mapEmpty) cards))

fn renderBlastRadiusHeatmap nodes: (List hyper/AuditNode) edges: (List hyper/AuditEdge) -> v/VNode
  (let [(heatmapAttrs (mapSet (mapEmpty) "class" "audit-heatmap-grid")) (edgeSummaryText (str "Hypergraph Causal Edges: " (stringFromInt64 (listLength edges)) ", Findings: " (stringFromInt64 (listLength nodes)))) (summaryNode (v/makeText edgeSummaryText "heatmap-summary"))] (v/makeContainer "blast-heatmap" heatmapAttrs (list summaryNode)))

fn renderAuditDashboard graph: hyper/AuditHypergraph -> v/VNode
  (let [(nodes graph.nodes) (edges graph.edges) (scores (extractLensScores nodes)) (headerAttrs (mapSet (mapEmpty) "class" "audit-dashboard-header")) (headerText (str "AgentSlang Audit Hypergraph Dashboard (Score: " (stringFromInt64 graph.score) "/100)")) (headerNode (v/makeText headerText "dashboard-title")) (radarNode (renderAuditRadar scores)) (heatmapNode (renderBlastRadiusHeatmap nodes edges)) (findingsNode (renderFindingsList nodes)) (rootAttrs (mapSet (mapEmpty) "class" "asl-audit-dashboard"))] (v/makeContainer "audit-dashboard-root" rootAttrs (list (v/makeContainer "dash-header" headerAttrs (list headerNode)) radarNode heatmapNode findingsNode)))
