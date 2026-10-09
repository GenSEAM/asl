(module asl-hypergraph/model :x [HyperNode makeHyperNode HyperEdge makeHyperEdge HyperIndex makeHyperIndex ImpactReceipt makeImpactReceipt findEdgesByTarget findEdgesBySource findNodeById])

(schema HyperNode (:f id Str) (:f kind Str) (:f module Str) (:f symbol Str) (:f doc Str))

fn makeHyperNode id: Str kind: Str module: Str symbol: Str doc: Str -> HyperNode
  (HyperNode :id id :kind kind :module module :symbol symbol :doc doc)

(schema HyperEdge (:f source Str) (:f relation Str) (:f target Str) (:f anchor Str))

fn makeHyperEdge source: Str relation: Str target: Str anchor: Str -> HyperEdge
  (HyperEdge :source source :relation relation :target target :anchor anchor)

(schema HyperIndex (:f version Int64) (:f nodes (List HyperNode)) (:f edges (List HyperEdge)) (:f timestamp Int64))

fn makeHyperIndex version: Int64 nodes: (List HyperNode) edges: (List HyperEdge) timestamp: Int64 -> HyperIndex
  (HyperIndex :version version :nodes nodes :edges edges :timestamp timestamp)

(schema ImpactReceipt (:f symbol Str) (:f callers (List Str)) (:f callersCount Int64) (:f tests (List Str)) (:f testsCount Int64) (:f types (List Str)) (:f status Str))

fn makeImpactReceipt symbol: Str callers: (List Str) callersCount: Int64 tests: (List Str) testsCount: Int64 types: (List Str) status: Str -> ImpactReceipt
  (ImpactReceipt :symbol symbol :callers callers :callersCount callersCount :tests tests :testsCount testsCount :types types :status status)

fn findEdgesByTarget edges: (List HyperEdge) targetStr: Str relationFilter: (Option Str) -> (List HyperEdge)
  (fold (fn [(acc (List HyperEdge)) (edge HyperEdge)] -> (List HyperEdge) (if (and (= edge.target targetStr) (mt relationFilter ((some rel) (= edge.relation rel)) ((none) true))) (listAppend acc (list edge)) (let [(cleanTarget (fold (fn [(acc Str) (s Str)] -> Str s) targetStr (stringSplit targetStr ":")))] (if (and (or (= edge.target cleanTarget) (stringEndsWith? edge.target (str ":" cleanTarget))) (mt relationFilter ((some rel) (= edge.relation rel)) ((none) true))) (listAppend acc (list edge)) acc)))) (list) edges)

fn findEdgesBySource edges: (List HyperEdge) sourceStr: Str relationFilter: (Option Str) -> (List HyperEdge)
  (fold (fn [(acc (List HyperEdge)) (edge HyperEdge)] -> (List HyperEdge) (if (and (= edge.source sourceStr) (mt relationFilter ((some rel) (= edge.relation rel)) ((none) true))) (listAppend acc (list edge)) acc)) (list) edges)

fn findNodeById nodes: (List HyperNode) targetId: Str -> (Option HyperNode)
  (fold (fn [(acc (Option HyperNode)) (node HyperNode)] -> (Option HyperNode) (mt acc ((some n) (some n)) ((none) (if (or (= node.id targetId) (= node.symbol targetId) (stringEndsWith? node.id (str ":" targetId))) (some node) (none))))) (none) nodes)
