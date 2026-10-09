(module aslIntel/diagram :x [DiagramFormat diagramFormatMermaid diagramFormatAsn diagramFormatToString generateMermaidDiagram generateAsnDiagram generateDiagram renderMermaidDag renderAsnDag] :i [(symbolGraph :a g)])

(enum DiagramFormat (:c diagramFormatMermaid [] "Mermaid graph TD notation") (:c diagramFormatAsn [] "Canonical ASN S-expression DAG representation"))

fn diagramFormatToString fmt: DiagramFormat -> Str
  (mt fmt ((diagramFormatMermaid) "mermaid") ((diagramFormatAsn) "asn"))

fn formatMermaidNode n: g/GraphNode -> Str
  (let [(label (if (stringEmpty? n.name) n.id n.name))] (str "  " n.id "[\"" label "\"]"))

fn formatMermaidEdge e: g/GraphEdge -> Str
  (str "  " e.src " --> " e.dst)

fn generateMermaidDiagram graph: g/SymbolGraph -> Str
  (let [(nodes graph.nodes) (edges graph.edges)] (if (and (listEmpty? nodes) (listEmpty? edges)) "graph TD" (if (listEmpty? edges) (str "graph TD\n" (stringJoin (map formatMermaidNode nodes) "\n")) (let [(nodesStr (stringJoin (map formatMermaidNode nodes) "\n")) (edgesStr (stringJoin (map formatMermaidEdge edges) "\n"))] (str "graph TD\n" (if (stringEmpty? nodesStr) "" (str nodesStr "\n")) edgesStr)))))

fn formatAsnNode n: g/GraphNode -> Str
  (str "(:node :id \"" n.id "\" :name \"" n.name "\" :kind \"" n.kind "\")")

fn formatAsnEdge e: g/GraphEdge -> Str
  (str "(:edge :src \"" e.src "\" :dst \"" e.dst "\" :kind \"" (g/edgeKindToString e.kind) "\")")

fn generateAsnDiagram graph: g/SymbolGraph -> Str
  (let [(nodes graph.nodes) (edges graph.edges) (nodeEntries (map formatAsnNode nodes)) (edgeEntries (map formatAsnEdge edges)) (nodesBlock (if (listEmpty? nodes) "[]" (str "[\n    " (stringJoin nodeEntries "\n    ") "\n  ]"))) (edgesBlock (if (listEmpty? edges) "[]" (str "[\n    " (stringJoin edgeEntries "\n    ") "\n  ]")))] (str "(:dependency-dag\n  :nodes " nodesBlock "\n  :edges " edgesBlock "\n)"))

fn generateDiagram fmt: DiagramFormat graph: g/SymbolGraph -> Str
  (mt fmt ((diagramFormatMermaid) (generateMermaidDiagram graph)) ((diagramFormatAsn) (generateAsnDiagram graph)))

fn renderMermaidDag graph: g/SymbolGraph -> Str
  (generateMermaidDiagram graph)

fn renderAsnDag graph: g/SymbolGraph -> Str
  (generateAsnDiagram graph)
