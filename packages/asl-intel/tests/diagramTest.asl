(module aslIntel/tests/diagramTest :x [testDiagramMermaidFormat testDiagramAsnFormat testDiagramDiamondDag testDiagramEmptyGraph testDiagramFormatEnum runTests] :i [(diagram :a d) (symbolGraph :a g)])

fn makeNode id: Str name: Str -> g/GraphNode
  (g/GraphNode :id id :name name :kind "fn" :file (str "src/" id ".asl") :startLine 1 :endLine 10 :signature "[]" :exported true)

fn makeEdge src: Str dst: Str -> g/GraphEdge
  (g/GraphEdge :src src :dst dst :kind (g/edgeImports) :file (str "src/" src ".asl") :line 1)

fn testDiagramMermaidFormat -> Bool
  (let [(na (makeNode "pkgA" "ModuleA")) (nb (makeNode "pkgB" "ModuleB")) (e1 (makeEdge "pkgA" "pkgB")) (graph (g/SymbolGraph :nodes (list na nb) :edges (list e1))) (out (d/generateMermaidDiagram graph))] (assert (stringStartsWith? out "graph TD") "Output must start with 'graph TD'") (assert (stringContains? out "-->") "Output must contain dependency arrow '-->'") (assert (stringContains? out "pkgA --> pkgB") "Output must contain 'pkgA --> pkgB'") true)

fn testDiagramAsnFormat -> Bool
  (let [(na (makeNode "pkgA" "ModuleA")) (nb (makeNode "pkgB" "ModuleB")) (e1 (makeEdge "pkgA" "pkgB")) (graph (g/SymbolGraph :nodes (list na nb) :edges (list e1))) (out (d/generateAsnDiagram graph))] (assert (stringContains? out "(:dependency-dag") "Output must contain '(:dependency-dag'") (assert (stringContains? out ":nodes") "Output must contain ':nodes'") (assert (stringContains? out ":edges") "Output must contain ':edges'") (assert (stringContains? out "(:node :id \"pkgA\"") "Output must serialize node pkgA") (assert (stringContains? out "(:edge :src \"pkgA\" :dst \"pkgB\"") "Output must serialize edge A->B") true)

fn testDiagramDiamondDag -> Bool
  (let [(na (makeNode "A" "NodeA")) (nb (makeNode "B" "NodeB")) (nc (makeNode "C" "NodeC")) (nd (makeNode "D" "NodeD")) (e1 (makeEdge "A" "B")) (e2 (makeEdge "A" "C")) (e3 (makeEdge "B" "D")) (e4 (makeEdge "C" "D")) (graph (g/SymbolGraph :nodes (list na nb nc nd) :edges (list e1 e2 e3 e4))) (mermaidOut (d/generateMermaidDiagram graph)) (asnOut (d/generateAsnDiagram graph))] (assert (stringContains? mermaidOut "A --> B") "Mermaid must contain A --> B") (assert (stringContains? mermaidOut "A --> C") "Mermaid must contain A --> C") (assert (stringContains? mermaidOut "B --> D") "Mermaid must contain B --> D") (assert (stringContains? mermaidOut "C --> D") "Mermaid must contain C --> D") (assert (stringContains? asnOut "(:edge :src \"A\" :dst \"B\"") "ASN must contain edge A->B") (assert (stringContains? asnOut "(:edge :src \"C\" :dst \"D\"") "ASN must contain edge C->D") true)

fn testDiagramEmptyGraph -> Bool
  (let [(graph (g/SymbolGraph :nodes (list) :edges (list))) (mermaidOut (d/generateMermaidDiagram graph)) (asnOut (d/generateAsnDiagram graph))] (assert (stringStartsWith? mermaidOut "graph TD") "Empty mermaid diagram must start with 'graph TD'") (assert (stringContains? asnOut "(:dependency-dag") "Empty ASN diagram must contain '(:dependency-dag'") (assert (stringContains? asnOut ":nodes []") "Empty ASN diagram must contain ':nodes []'") (assert (stringContains? asnOut ":edges []") "Empty ASN diagram must contain ':edges []'") true)

fn testDiagramFormatEnum -> Bool
  (let [(fmtM (d/diagramFormatMermaid)) (fmtA (d/diagramFormatAsn)) (strM (d/diagramFormatToString fmtM)) (strA (d/diagramFormatToString fmtA)) (graph (g/SymbolGraph :nodes (list) :edges (list))) (dispM (d/generateDiagram fmtM graph)) (dispA (d/generateDiagram fmtA graph)) (rendM (d/renderMermaidDag graph)) (rendA (d/renderAsnDag graph))] (assert (= strM "mermaid") "Enum string for mermaid must be 'mermaid'") (assert (= strA "asn") "Enum string for asn must be 'asn'") (assert (stringStartsWith? dispM "graph TD") "Dispatcher mermaid must start with 'graph TD'") (assert (stringContains? dispA "(:dependency-dag") "Dispatcher asn must contain '(:dependency-dag'") (assert (stringStartsWith? rendM "graph TD") "render-mermaid-dag must match generate-mermaid-diagram") (assert (stringContains? rendA "(:dependency-dag") "render-asn-dag must match generate-asn-diagram") true)

fn runTests -> Bool
  (let [(r1 (testDiagramMermaidFormat)) (r2 (testDiagramAsnFormat)) (r3 (testDiagramDiamondDag)) (r4 (testDiagramEmptyGraph)) (r5 (testDiagramFormatEnum))] (and r1 (and r2 (and r3 (and r4 r5)))))
