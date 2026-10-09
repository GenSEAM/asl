(module aslIntel/intel :i [(extractor :a [SymbolKind SymbolDef SymbolRef FileSymbols]) (symbolGraph :a [EdgeKind GraphNode GraphEdge SymbolGraph]) (query :a [QueryKind ImpactItem QueryResult]) (codec :a [encodeSymbolAsn encodeEdgeAsn encodeImpactAsn encodeAsnResponse]) (health :a [intelHealth buildHealthMatrix formatHealthReport HealthMatrix]) (diagram :a [DiagramFormat diagramFormatMermaid diagramFormatAsn diagramFormatToString generateMermaidDiagram generateAsnDiagram generateDiagram renderMermaidDag renderAsnDag]) (placement :a [auditFilePlacement])] :x [intelVersion intelBanner intelHealth buildHealthMatrix formatHealthReport renderMermaidDag renderAsnDag generateMermaidDiagram generateAsnDiagram generateDiagram auditFilePlacement])

fn intelVersion -> Str
  "0.1.0"

fn intelBanner -> Str
  "GenSEAM ASL-Intel — Native Multi-Language Code Intelligence Engine (v0.1.0)"
