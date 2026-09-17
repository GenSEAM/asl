(module asl-hypergraph
  :d "Root module for pure ASL Codebase Hypergraph Indexer and Impact Analysis under ADR D94."
  :x [HyperNode makeHyperNode
      HyperEdge makeHyperEdge
      HyperIndex makeHyperIndex
      ImpactReceipt makeImpactReceipt
      findEdgesByTarget
      findEdgesBySource
      findNodeById
      extractSymbolsFromSexpr
      extractNodesAndEdgesFromModule
      buildHypergraphFromModules
      serializeHyperIndex
      deserializeHyperIndex
      loadOrBuildHyperIndex
      querySymbolImpact
      formatImpactReceipt
      estimateReceiptTokens]
  :i [(asl-hypergraph/model :a model)
      (asl-hypergraph/index :a index)
      (asl-hypergraph/query :a query)])

(df makeHyperNode [(id Str) (kind Str) (module Str) (symbol Str) (doc Str)] -> model/HyperNode
  :d "Re-exports makeHyperNode."
  (model/makeHyperNode id kind module symbol doc))

(df makeHyperEdge [(source Str) (relation Str) (target Str) (anchor Str)] -> model/HyperEdge
  :d "Re-exports makeHyperEdge."
  (model/makeHyperEdge source relation target anchor))

(df makeHyperIndex [(version Int64) (nodes (List model/HyperNode)) (edges (List model/HyperEdge)) (timestamp Int64)] -> model/HyperIndex
  :d "Re-exports makeHyperIndex."
  (model/makeHyperIndex version nodes edges timestamp))

(df makeImpactReceipt [(symbol Str) (callers (List Str)) (callersCount Int64) (tests (List Str)) (testsCount Int64) (types (List Str)) (status Str)] -> model/ImpactReceipt
  :d "Re-exports makeImpactReceipt."
  (model/makeImpactReceipt symbol callers callersCount tests testsCount types status))

(df findEdgesByTarget [(edges (List model/HyperEdge)) (targetStr Str) (relationFilter (Option Str))] -> (List model/HyperEdge)
  :d "Re-exports findEdgesByTarget."
  (model/findEdgesByTarget edges targetStr relationFilter))

(df findEdgesBySource [(edges (List model/HyperEdge)) (sourceStr Str) (relationFilter (Option Str))] -> (List model/HyperEdge)
  :d "Re-exports findEdgesBySource."
  (model/findEdgesBySource edges sourceStr relationFilter))

(df findNodeById [(nodes (List model/HyperNode)) (targetId Str)] -> (Option model/HyperNode)
  :d "Re-exports findNodeById."
  (model/findNodeById nodes targetId))

(df extractSymbolsFromSexpr [(form asl-parser/reader:SExpr)] -> (List Str)
  :d "Re-exports extractSymbolsFromSexpr."
  (index/extractSymbolsFromSexpr form))

(df extractNodesAndEdgesFromModule [(modName Str) (sourceText Str)] -> (Pair (List model/HyperNode) (List model/HyperEdge))
  :d "Re-exports extractNodesAndEdgesFromModule."
  (index/extractNodesAndEdgesFromModule modName sourceText))

(df buildHypergraphFromModules [(modules (List (Pair Str Str)))] -> model/HyperIndex
  :d "Re-exports buildHypergraphFromModules."
  (index/buildHypergraphFromModules modules))

(df serializeHyperIndex [(idx model/HyperIndex)] -> Str
  :d "Re-exports serializeHyperIndex."
  (index/serializeHyperIndex idx))

(df deserializeHyperIndex [(text Str)] -> (Result model/HyperIndex Str)
  :d "Re-exports deserializeHyperIndex."
  (index/deserializeHyperIndex text))

(df loadOrBuildHyperIndex [(indexPath Str) (fallbackModules (List (Pair Str Str)))] -> model/HyperIndex
  :d "Re-exports loadOrBuildHyperIndex."
  (index/loadOrBuildHyperIndex indexPath fallbackModules))

(df querySymbolImpact [(idx model/HyperIndex) (targetSym Str)] -> model/ImpactReceipt
  :d "Re-exports querySymbolImpact."
  (query/querySymbolImpact idx targetSym))

(df formatImpactReceipt [(r model/ImpactReceipt)] -> Str
  :d "Re-exports formatImpactReceipt."
  (query/formatImpactReceipt r))

(df estimateReceiptTokens [(receiptText Str)] -> Int64
  :d "Re-exports estimateReceiptTokens."
  (query/estimateReceiptTokens receiptText))
