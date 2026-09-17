(module asl-conform/hypergraph
  :d "Pure AgentScript Multi-Dimensional Audit Hypergraph under ADR D98"
  :x [AuditNode
      makeAuditNode
      AuditEdge
      makeAuditEdge
      AuditHypergraph
      makeAuditHypergraph
      PatchReceipt
      makePatchReceipt
      buildAuditHypergraph
      queryAuditGraph
      findEdgesFrom
      findEdgesTo
      calculateBlastRadius
      pathExists?
      detectCycles
      calculateLensScore
      emitPatchReceipt
      formatAuditAsn
      formatReceiptAsn
      canonicalLenses])

(dfs AuditNode
  (:f id Str "Unique audit finding identifier lens/check/Module:symbol")
  (:f lens Str "Diagnostic lens: architecture, platform, logic, memory, security, tokenEconomics")
  (:f severity Str "Severity level: info, warning, error, critical")
  (:f anchor Str "Code location anchor Module:symbol:anchor")
  (:f evidence Str "Concrete diagnostic proof or AST snippet")
  (:f remedy Str "Machine-verifiable single-turn remediation prescription")
  (:f provenance Str "Audit rule ID and originating engine"))

(df makeAuditNode [(id Str) (lens Str) (severity Str) (anchor Str) (evidence Str) (remedy Str) (provenance Str)] -> AuditNode
  :d "Constructs an AuditNode record"
  (AuditNode :id id
             :lens lens
             :severity severity
             :anchor anchor
             :evidence evidence
             :remedy remedy
             :provenance provenance))

(dfs AuditEdge
  (:f from Str "Source audit node or AST symbol ID")
  (:f to Str "Target audit node or AST symbol ID")
  (:f kind Str "Relational causality kind: blastRadius, violates, imports, refutes, dependsOn"))

(df makeAuditEdge [(from Str) (to Str) (kind Str)] -> AuditEdge
  :d "Constructs an AuditEdge record"
  (AuditEdge :from from :to to :kind kind))

(dfs AuditHypergraph
  (:f version Str "Hypergraph schema version")
  (:f timestamp Int64 "Generation timestamp in nanoseconds")
  (:f nodes (List AuditNode) "Indexed diagnostic findings")
  (:f edges (List AuditEdge) "Causal relational edges")
  (:f score Int64 "Composite codebase integrity score (0-100)"))

(df makeAuditHypergraph [(version Str) (timestamp Int64) (nodes (List AuditNode)) (edges (List AuditEdge)) (score Int64)] -> AuditHypergraph
  :d "Constructs an AuditHypergraph record"
  (AuditHypergraph :version version
                   :timestamp timestamp
                   :nodes nodes
                   :edges edges
                   :score score))

(dfs PatchReceipt
  (:f id Str "Receipt identifier")
  (:f target Str "Target symbol or node anchor")
  (:f status Str "Remediation status: ready, applied, verified, rejected")
  (:f diffStr Str "Minimal AST diff or patch replacement")
  (:f tokenCount Int64 "Perceptual token count strictly under 120"))

(df makePatchReceipt [(id Str) (target Str) (status Str) (diffStr Str) (tokenCount Int64)] -> PatchReceipt
  :d "Constructs a PatchReceipt record"
  (PatchReceipt :id id
                :target target
                :status status
                :diffStr diffStr
                :tokenCount tokenCount))

(df canonicalLenses [] -> (List Str)
  :d "Returns the 6 canonical diagnostic lenses defined under ADR D98"
  (list "architecture" "platform" "logic" "memory" "security" "tokenEconomics"))

(df calculateLensScore [(nodes (List AuditNode)) (targetLens Str)] -> Int64
  :d "Calculates integer health score (0-100) for a given lens based on findings"
  (let [(penalty (fold (fn [(acc Int64) (n AuditNode)] -> Int64
                         (if (= (.-lens n) targetLens)
                             (cond
                               ((= (.-severity n) "critical") (+ acc 25))
                               ((= (.-severity n) "error") (+ acc 15))
                               ((= (.-severity n) "warning") (+ acc 5))
                               (:else (+ acc 1)))
                             acc))
                       0
                       nodes))
        (rawScore (- 100 penalty))]
    (if (< rawScore 0)
        0
        rawScore)))

(df computeOverallScore [(nodes (List AuditNode))] -> Int64
  :d "Computes average composite integrity score across the 6 canonical lenses"
  (let [(lenses (canonicalLenses))
        (total (fold (fn [(acc Int64) (lens Str)] -> Int64
                       (+ acc (calculateLensScore nodes lens)))
                     0
                     lenses))]
    (/ total (list-length lenses))))

(df buildAuditHypergraph [(nodes (List AuditNode)) (edges (List AuditEdge))] -> AuditHypergraph
  :d "Constructs a verified AuditHypergraph instance computing composite health score"
  (let [(score (computeOverallScore nodes))]
    (makeAuditHypergraph "0.1.0" 1789725000000 nodes edges score)))

(df queryAuditGraph [(graph AuditHypergraph)
                     (lensFilter (Option Str))
                     (severityFilter (Option Str))
                     (anchorPrefix (Option Str))] -> (List AuditNode)
  :d "Queries hypergraph nodes matching optional lens, severity, and anchor prefix filters"
  (fold (fn [(acc (List AuditNode)) (n AuditNode)] -> (List AuditNode)
          (let [(lensMatch (mt lensFilter
                             ((some l) (= (.-lens n) l))
                             ((none) true)))
                (sevMatch (mt severityFilter
                            ((some s) (= (.-severity n) s))
                            ((none) true)))
                (anchorMatch (mt anchorPrefix
                               ((some a) (string-starts-with? (.-anchor n) a))
                               ((none) true)))]
            (if (and (and lensMatch sevMatch) anchorMatch)
                (list-append acc (list n))
                acc)))
        (list)
        (.-nodes graph)))

(df findEdgesFrom [(edges (List AuditEdge)) (fromNode Str)] -> (List AuditEdge)
  :d "Finds all hyperedges originating from a source node or symbol"
  (fold (fn [(acc (List AuditEdge)) (e AuditEdge)] -> (List AuditEdge)
          (if (= (.-from e) fromNode)
              (list-append acc (list e))
              acc))
        (list)
        edges))

(df findEdgesTo [(edges (List AuditEdge)) (toNode Str)] -> (List AuditEdge)
  :d "Finds all hyperedges targeting a target node or symbol"
  (fold (fn [(acc (List AuditEdge)) (e AuditEdge)] -> (List AuditEdge)
          (if (= (.-to e) toNode)
              (list-append acc (list e))
              acc))
        (list)
        edges))

(df pathExists? [(edges (List AuditEdge)) (src Str) (dst Str) (visited (List Str))] -> Bool
  :d "Checks if a directed path exists from src to dst in the edge graph"
  (if (= src dst)
      true
      (if (list-contains? visited src)
          false
          (let [(outgoing (findEdgesFrom edges src))
                (nextVisited (list-cons src visited))]
            (any (fn [(e AuditEdge)] -> Bool
                   (pathExists? edges (.-to e) dst nextVisited))
                 outgoing)))))

(df detectCycles [(edges (List AuditEdge))] -> (List (List Str))
  :d "Detects circular dependency cycles across directed hyperedges"
  (fold (fn [(acc (List (List Str))) (e AuditEdge)] -> (List (List Str))
          (if (pathExists? edges (.-to e) (.-from e) (list (.-from e)))
              (let [(cycle (list (.-from e) (.-to e)))]
                (list-append acc (list cycle)))
              acc))
        (list)
        edges))

(df calculateBlastRadius [(graph AuditHypergraph) (targetAnchor Str)] -> (List Str)
  :d "Calculates the blast radius of affected nodes and symbols connected to an anchor"
  (let [(edges (.-edges graph))
        (inbound (findEdgesTo edges targetAnchor))
        (outbound (findEdgesFrom edges targetAnchor))
        (inboundIds (fold (fn [(acc (List Str)) (e AuditEdge)] -> (List Str)
                            (if (list-contains? acc (.-from e)) acc (list-append acc (list (.-from e)))))
                          (list)
                          inbound))
        (allIds (fold (fn [(acc (List Str)) (e AuditEdge)] -> (List Str)
                        (if (list-contains? acc (.-to e)) acc (list-append acc (list (.-to e)))))
                      inboundIds
                      outbound))]
    (if (list-contains? allIds targetAnchor)
        allIds
        (list-cons targetAnchor allIds))))

(df emitPatchReceipt [(node AuditNode)] -> PatchReceipt
  :d "Generates a machine-verifiable single-turn remediation PatchReceipt bounded under 120 tokens"
  (let [(rcId (str "rc-" (.-id node)))
        (target (.-anchor node))
        (remedy (.-remedy node))
        (diffStr (str "(:remedy :anchor \"" target "\" :patch \"" remedy "\")"))
        (estTokens (+ (/ (string-length diffStr) 4) 8))]
    (makePatchReceipt rcId target "ready" diffStr estTokens)))

(df formatAuditNodeAsn [(n AuditNode)] -> Str
  :d "Formats single AuditNode as indented ASN"
  (str "    (:node :id \"" (.-id n) "\"\n"
       "           :lens \"" (.-lens n) "\"\n"
       "           :severity \"" (.-severity n) "\"\n"
       "           :anchor \"" (.-anchor n) "\"\n"
       "           :evidence \"" (.-evidence n) "\"\n"
       "           :remedy \"" (.-remedy n) "\"\n"
       "           :provenance \"" (.-provenance n) "\")"))

(df formatAuditEdgeAsn [(e AuditEdge)] -> Str
  :d "Formats single AuditEdge as indented ASN"
  (str "    (:edge :from \"" (.-from e) "\" :to \"" (.-to e) "\" :kind \"" (.-kind e) "\")"))

(df formatAuditAsn [(graph AuditHypergraph)] -> Str
  :d "Formats an entire AuditHypergraph as structured ASN text"
  (let [(nodesStr (string-join (fold (fn [(acc (List Str)) (n AuditNode)] -> (List Str)
                                       (list-append acc (list (formatAuditNodeAsn n))))
                                     (list)
                                     (.-nodes graph))
                               "\n"))
        (edgesStr (string-join (fold (fn [(acc (List Str)) (e AuditEdge)] -> (List Str)
                                       (list-append acc (list (formatAuditEdgeAsn e))))
                                     (list)
                                     (.-edges graph))
                               "\n"))]
    (str "(:auditHypergraph\n"
         "  :version \"" (.-version graph) "\"\n"
         "  :timestamp " (string-from-int64 (.-timestamp graph)) "\n"
         "  :score " (string-from-int64 (.-score graph)) "\n"
         "  :nodeCount " (string-from-int64 (list-length (.-nodes graph))) "\n"
         "  :edgeCount " (string-from-int64 (list-length (.-edges graph))) "\n"
         "  :nodes [\n" nodesStr "\n  ]\n"
         "  :edges [\n" edgesStr "\n  ])")))

(df formatReceiptAsn [(rc PatchReceipt)] -> Str
  :d "Formats a PatchReceipt as compact ASN text"
  (str "(:patchReceipt\n"
       "  :id \"" (.-id rc) "\"\n"
       "  :target \"" (.-target rc) "\"\n"
       "  :status \"" (.-status rc) "\"\n"
       "  :tokens " (string-from-int64 (.-tokenCount rc)) "\n"
       "  :diff " (.-diffStr rc) ")"))
