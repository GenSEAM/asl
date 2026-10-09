(module asl-hypergraph :x [HyperNode makeHyperNode HyperEdge makeHyperEdge HyperIndex makeHyperIndex ImpactReceipt makeImpactReceipt findEdgesByTarget findEdgesBySource findNodeById extractSymbolsFromSexpr extractNodesAndEdgesFromModule buildHypergraphFromModules serializeHyperIndex deserializeHyperIndex loadOrBuildHyperIndex! querySymbolImpact formatImpactReceipt estimateReceiptTokens] :i [(asl-hypergraph/model :a model) (asl-hypergraph/index :a index) (asl-hypergraph/query :a query)])

fn makeHyperNode id: Str kind: Str module: Str symbol: Str doc: Str -> model/HyperNode
  (model/makeHyperNode id kind module symbol doc)

fn makeHyperEdge source: Str relation: Str target: Str anchor: Str -> model/HyperEdge
  (model/makeHyperEdge source relation target anchor)

fn makeHyperIndex version: Int64 nodes: (List model/HyperNode) edges: (List model/HyperEdge) timestamp: Int64 -> model/HyperIndex
  (model/makeHyperIndex version nodes edges timestamp)

fn makeImpactReceipt symbol: Str callers: (List Str) callersCount: Int64 tests: (List Str) testsCount: Int64 types: (List Str) status: Str -> model/ImpactReceipt
  (model/makeImpactReceipt symbol callers callersCount tests testsCount types status)

fn findEdgesByTarget edges: (List model/HyperEdge) targetStr: Str relationFilter: (Option Str) -> (List model/HyperEdge)
  (model/findEdgesByTarget edges targetStr relationFilter)

fn findEdgesBySource edges: (List model/HyperEdge) sourceStr: Str relationFilter: (Option Str) -> (List model/HyperEdge)
  (model/findEdgesBySource edges sourceStr relationFilter)

fn findNodeById nodes: (List model/HyperNode) targetId: Str -> (Option model/HyperNode)
  (model/findNodeById nodes targetId)

fn extractSymbolsFromSexpr form: asl-parser/reader:SExpr -> (List Str)
  (index/extractSymbolsFromSexpr form)

fn extractNodesAndEdgesFromModule modName: Str sourceText: Str -> (Pair (List model/HyperNode) (List model/HyperEdge))
  (index/extractNodesAndEdgesFromModule modName sourceText)

fn buildHypergraphFromModules modules: (List (Pair Str Str)) -> model/HyperIndex
  (index/buildHypergraphFromModules modules)

fn serializeHyperIndex idx: model/HyperIndex -> Str
  (index/serializeHyperIndex idx)

fn deserializeHyperIndex text: Str -> (Result model/HyperIndex Str)
  (index/deserializeHyperIndex text)

fn loadOrBuildHyperIndex! indexPath: Str fallbackModules: (List (Pair Str Str)) -> model/HyperIndex
  (index/loadOrBuildHyperIndex! indexPath fallbackModules)

fn querySymbolImpact idx: model/HyperIndex targetSym: Str -> model/ImpactReceipt
  (query/querySymbolImpact idx targetSym)

fn formatImpactReceipt r: model/ImpactReceipt -> Str
  (query/formatImpactReceipt r)

fn estimateReceiptTokens receiptText: Str -> Int64
  (query/estimateReceiptTokens receiptText)
