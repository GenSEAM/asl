(module asl-ui/auditDashboard
  :d "Pure AgentScript Declarative VDOM and SVG Audit Hypergraph Dashboard under ADR D98"
  :x [renderAuditDashboard
      renderAuditRadar
      renderRadarSvg
      renderBlastRadiusHeatmap
      renderFindingsList
      renderFindingCard
      radarAxisPoints
      extractLensScores]
  :i [(asl-ui/vnode :a v)
      (asl-conform/hypergraph :a hyper)])

(df extractLensScores [(nodes (List hyper/AuditNode))] -> (Map Str Int64)
  :d "Extracts health scores for all 6 canonical lenses from findings"
  (let [(lenses (hyper/canonicalLenses))]
    (fold (fn [(acc (Map Str Int64)) (lens Str)] -> (Map Str Int64)
            (map-set acc lens (hyper/calculateLensScore nodes lens)))
          (map-empty)
          lenses)))

(df computeAxisCoord [(center Int64) (delta Int64) (isPositive Bool)] -> Int64
  :d "Computes single axis coordinate"
  (if isPositive (+ center delta) (- center delta)))

(df radarAxisPoints [(scores (Map Str Int64))] -> Str
  :d "Calculates SVG polygon points for the 6-axis radar polygon using integer trigonometry"
  (let [(s0 (option-or (map-get scores "architecture") 100))
        (s1 (option-or (map-get scores "platform") 100))
        (s2 (option-or (map-get scores "logic") 100))
        (s3 (option-or (map-get scores "memory") 100))
        (s4 (option-or (map-get scores "security") 100))
        (s5 (option-or (map-get scores "tokenEconomics") 100))
        (x0 150)
        (y0 (- 150 s0))
        (x1 (+ 150 (/ (* s1 866) 1000)))
        (y1 (- 150 (/ (* s1 500) 1000)))
        (x2 (+ 150 (/ (* s2 866) 1000)))
        (y2 (+ 150 (/ (* s2 500) 1000)))
        (x3 150)
        (y3 (+ 150 s3))
        (x4 (- 150 (/ (* s4 866) 1000)))
        (y4 (+ 150 (/ (* s4 500) 1000)))
        (x5 (- 150 (/ (* s5 866) 1000)))
        (y5 (- 150 (/ (* s5 500) 1000)))]
    (str (string-from-int64 x0) "," (string-from-int64 y0) " "
         (string-from-int64 x1) "," (string-from-int64 y1) " "
         (string-from-int64 x2) "," (string-from-int64 y2) " "
         (string-from-int64 x3) "," (string-from-int64 y3) " "
         (string-from-int64 x4) "," (string-from-int64 y4) " "
         (string-from-int64 x5) "," (string-from-int64 y5))))

(df renderRadarSvg [(scores (Map Str Int64))] -> Str
  :d "Renders declarative 6-axis SVG radar chart markup without external JS dependencies"
  (let [(dataPoints (radarAxisPoints scores))]
    (str "<svg viewBox=\"0 0 300 300\" class=\"asl-audit-radar\">\n"
         "  <polygon points=\"150,50 237,100 237,200 150,250 63,200 63,100\" fill=\"none\" stroke=\"#334155\" stroke-width=\"1\"/>\n"
         "  <polygon points=\"150,100 193,125 193,175 150,200 107,175 107,125\" fill=\"none\" stroke=\"#1e293b\" stroke-width=\"1\" stroke-dasharray=\"2,2\"/>\n"
         "  <line x1=\"150\" y1=\"150\" x2=\"150\" y2=\"50\" stroke=\"#475569\" stroke-width=\"1\"/>\n"
         "  <line x1=\"150\" y1=\"150\" x2=\"237\" y2=\"100\" stroke=\"#475569\" stroke-width=\"1\"/>\n"
         "  <line x1=\"150\" y1=\"150\" x2=\"237\" y2=\"200\" stroke=\"#475569\" stroke-width=\"1\"/>\n"
         "  <line x1=\"150\" y1=\"150\" x2=\"150\" y2=\"250\" stroke=\"#475569\" stroke-width=\"1\"/>\n"
         "  <line x1=\"150\" y1=\"150\" x2=\"63\" y2=\"200\" stroke=\"#475569\" stroke-width=\"1\"/>\n"
         "  <line x1=\"150\" y1=\"150\" x2=\"63\" y2=\"100\" stroke=\"#475569\" stroke-width=\"1\"/>\n"
         "  <polygon points=\"" dataPoints "\" fill=\"rgba(14,165,233,0.3)\" stroke=\"#0ea5e9\" stroke-width=\"2\"/>\n"
         "  <text x=\"150\" y=\"40\" text-anchor=\"middle\" fill=\"#94a3b8\" font-size=\"10\">Architecture</text>\n"
         "  <text x=\"245\" y=\"98\" text-anchor=\"start\" fill=\"#94a3b8\" font-size=\"10\">Platform</text>\n"
         "  <text x=\"245\" y=\"206\" text-anchor=\"start\" fill=\"#94a3b8\" font-size=\"10\">Logic</text>\n"
         "  <text x=\"150\" y=\"268\" text-anchor=\"middle\" fill=\"#94a3b8\" font-size=\"10\">Memory</text>\n"
         "  <text x=\"55\" y=\"206\" text-anchor=\"end\" fill=\"#94a3b8\" font-size=\"10\">Security</text>\n"
         "  <text x=\"55\" y=\"98\" text-anchor=\"end\" fill=\"#94a3b8\" font-size=\"10\">TokenEconomics</text>\n"
         "</svg>")))

(df renderAuditRadar [(scores (Map Str Int64))] -> v/VNode
  :d "Renders VDOM container holding the radar SVG"
  (let [(svgContent (renderRadarSvg scores))
        (attrs (map-set (map-empty) "data-component" "audit-radar"))]
    (v/makeVNode "svg-wrapper" "radar-widget" svgContent attrs (list) 300 300 true)))

(df renderFindingCard [(node hyper/AuditNode)] -> v/VNode
  :d "Renders single diagnostic audit finding card in progressive disclosure UI"
  (let [(cardAttrs (map-set (map-set (map-empty) "class" "audit-finding-card")
                            "data-severity" (.-severity node)))
        (titleNode (v/makeText (str "[" (.-severity node) "] " (.-lens node) ": " (.-id node)) "title"))
        (anchorNode (v/makeText (str "Anchor: " (.-anchor node)) "anchor"))
        (evidenceNode (v/makeText (str "Evidence: " (.-evidence node)) "evidence"))
        (remedyNode (v/makeText (str "Remedy: " (.-remedy node)) "remedy"))]
    (v/makeContainer (str "finding-" (.-id node))
                     cardAttrs
                     (list titleNode anchorNode evidenceNode remedyNode))))

(df renderFindingsList [(nodes (List hyper/AuditNode))] -> v/VNode
  :d "Renders list of audit finding cards"
  (let [(cards (fold (fn [(acc (List v/VNode)) (n hyper/AuditNode)] -> (List v/VNode)
                       (list-append acc (list (renderFindingCard n))))
                     (list)
                     nodes))]
    (v/makeContainer "findings-list" (map-empty) cards)))

(df renderBlastRadiusHeatmap [(nodes (List hyper/AuditNode)) (edges (List hyper/AuditEdge))] -> v/VNode
  :d "Renders blast-radius causal topology heatmap container"
  (let [(heatmapAttrs (map-set (map-empty) "class" "audit-heatmap-grid"))
        (edgeSummaryText (str "Hypergraph Causal Edges: " (string-from-int64 (list-length edges))
                              ", Findings: " (string-from-int64 (list-length nodes))))
        (summaryNode (v/makeText edgeSummaryText "heatmap-summary"))]
    (v/makeContainer "blast-heatmap" heatmapAttrs (list summaryNode))))

(df renderAuditDashboard [(graph hyper/AuditHypergraph)] -> v/VNode
  :d "Renders complete progressive disclosure audit dashboard VNode tree"
  (let [(nodes (.-nodes graph))
        (edges (.-edges graph))
        (scores (extractLensScores nodes))
        (headerAttrs (map-set (map-empty) "class" "audit-dashboard-header"))
        (headerText (str "AgentScript Audit Hypergraph Dashboard (Score: "
                         (string-from-int64 (.-score graph)) "/100)"))
        (headerNode (v/makeText headerText "dashboard-title"))
        (radarNode (renderAuditRadar scores))
        (heatmapNode (renderBlastRadiusHeatmap nodes edges))
        (findingsNode (renderFindingsList nodes))
        (rootAttrs (map-set (map-empty) "class" "asl-audit-dashboard"))]
    (v/makeContainer "audit-dashboard-root"
                     rootAttrs
                     (list (v/makeContainer "dash-header" headerAttrs (list headerNode))
                           radarNode
                           heatmapNode
                           findingsNode))))
