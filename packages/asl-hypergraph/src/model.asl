(module asl-hypergraph/model
  :d "Pure ASL Codebase Hypergraph data models and constructor functions under ADR D94."
  :x [HyperNode makeHyperNode
      HyperEdge makeHyperEdge
      HyperIndex makeHyperIndex
      ImpactReceipt makeImpactReceipt
      findEdgesByTarget
      findEdgesBySource
      findNodeById])

(dfs HyperNode
  (:f id Str "Fully-qualified identifier Module:symbol")
  (:f kind Str "Kind of declaration: function, struct, test, type")
  (:f module Str "Enclosing module path")
  (:f symbol Str "Unqualified symbol name")
  (:f doc Str "Documentation string from :d attribute"))

(df makeHyperNode [(id Str) (kind Str) (module Str) (symbol Str) (doc Str)] -> HyperNode
  :d "Constructs a HyperNode record."
  (HyperNode :id id :kind kind :module module :symbol symbol :doc doc))

(dfs HyperEdge
  (:f source Str "Source symbol identifier Module:symbol")
  (:f relation Str "Relationship type: calls, types, mutates, tests")
  (:f target Str "Target symbol identifier Module:symbol or type name")
  (:f anchor Str "Subtree anchor key within declaration"))

(df makeHyperEdge [(source Str) (relation Str) (target Str) (anchor Str)] -> HyperEdge
  :d "Constructs a HyperEdge record."
  (HyperEdge :source source :relation relation :target target :anchor anchor))

(dfs HyperIndex
  (:f version Int64 "Index schema version")
  (:f nodes (List HyperNode) "Indexed declaration nodes")
  (:f edges (List HyperEdge) "Indexed relational edges")
  (:f timestamp Int64 "Epoch timestamp of index generation"))

(df makeHyperIndex [(version Int64) (nodes (List HyperNode)) (edges (List HyperEdge)) (timestamp Int64)] -> HyperIndex
  :d "Constructs a HyperIndex record."
  (HyperIndex :version version :nodes nodes :edges edges :timestamp timestamp))

(dfs ImpactReceipt
  (:f symbol Str "Target query symbol")
  (:f callers (List Str) "Truncated direct callers list, max 5 plus overflow label")
  (:f callersCount Int64 "Total count of direct inbound callers")
  (:f tests (List Str) "Direct and transitive test dependencies")
  (:f testsCount Int64 "Total count of affected test suites")
  (:f types (List Str) "Type signatures and referenced struct definitions")
  (:f status Str "Query status: ok, not-found, circular"))

(df makeImpactReceipt [(symbol Str) (callers (List Str)) (callersCount Int64) (tests (List Str)) (testsCount Int64) (types (List Str)) (status Str)] -> ImpactReceipt
  :d "Constructs an ImpactReceipt record."
  (ImpactReceipt :symbol symbol :callers callers :callersCount callersCount :tests tests :testsCount testsCount :types types :status status))

(df findEdgesByTarget [(edges (List HyperEdge)) (targetStr Str) (relationFilter (Option Str))] -> (List HyperEdge
)
  :d "Filters hyperedges matching target and optional relation."
  (fold (fn [(acc (List HyperEdge)) (edge HyperEdge)] -> (List HyperEdge)
          (if (and (= (.-target edge) targetStr)
                   (mt relationFilter
                     ((some rel) (= (.-relation edge) rel))
                     ((none) true)))
              (list-append acc (list edge))
              (let [(cleanTarget (fold (fn [(acc Str) (s Str)] -> Str s) targetStr (string-split targetStr ":")))]
                (if (and (or (= (.-target edge) cleanTarget)
                             (string-ends-with? (.-target edge) (str ":" cleanTarget)))
                         (mt relationFilter
                           ((some rel) (= (.-relation edge) rel))
                           ((none) true)))
                    (list-append acc (list edge))
                    acc))))
        (list)
        edges))

(df findEdgesBySource [(edges (List HyperEdge)) (sourceStr Str) (relationFilter (Option Str))] -> (List HyperEdge)
  :d "Filters hyperedges matching source and optional relation."
  (fold (fn [(acc (List HyperEdge)) (edge HyperEdge)] -> (List HyperEdge)
          (if (and (= (.-source edge) sourceStr)
                   (mt relationFilter
                     ((some rel) (= (.-relation edge) rel))
                     ((none) true)))
              (list-append acc (list edge))
              acc))
        (list)
        edges))

(df findNodeById [(nodes (List HyperNode)) (targetId Str)] -> (Option HyperNode)
  :d "Finds a HyperNode by exact id or unqualified symbol."
  (fold (fn [(acc (Option HyperNode)) (node HyperNode)] -> (Option HyperNode)
          (mt acc
            ((some n) (some n))
            ((none)
             (if (or (= (.-id node) targetId)
                     (= (.-symbol node) targetId)
                     (string-ends-with? (.-id node) (str ":" targetId)))
                 (some node)
                 (none)))))
        (none)
        nodes))
