(module asl-conform/hypergraph :x [AuditNode makeAuditNode AuditEdge makeAuditEdge AuditHypergraph makeAuditHypergraph PatchReceipt makePatchReceipt buildAuditHypergraph queryAuditGraph findEdgesFrom findEdgesTo calculateBlastRadius pathExists? detectCycles calculateLensScore emitPatchReceipt formatAuditAsn formatReceiptAsn canonicalLenses])

(schema AuditNode (:f id Str) (:f lens Str) (:f severity Str) (:f anchor Str) (:f evidence Str) (:f remedy Str) (:f provenance Str))

fn makeAuditNode id: Str lens: Str severity: Str anchor: Str evidence: Str remedy: Str provenance: Str -> AuditNode
  (AuditNode :id id :lens lens :severity severity :anchor anchor :evidence evidence :remedy remedy :provenance provenance)

(schema AuditEdge (:f from Str) (:f to Str) (:f kind Str))

fn makeAuditEdge from: Str to: Str kind: Str -> AuditEdge
  (AuditEdge :from from :to to :kind kind)

(schema AuditHypergraph (:f version Str) (:f timestamp Int64) (:f nodes (List AuditNode)) (:f edges (List AuditEdge)) (:f score Int64))

fn makeAuditHypergraph version: Str timestamp: Int64 nodes: (List AuditNode) edges: (List AuditEdge) score: Int64 -> AuditHypergraph
  (AuditHypergraph :version version :timestamp timestamp :nodes nodes :edges edges :score score)

(schema PatchReceipt (:f id Str) (:f target Str) (:f status Str) (:f diffStr Str) (:f tokenCount Int64))

fn makePatchReceipt id: Str target: Str status: Str diffStr: Str tokenCount: Int64 -> PatchReceipt
  (PatchReceipt :id id :target target :status status :diffStr diffStr :tokenCount tokenCount)

fn canonicalLenses -> (List Str)
  (list "architecture" "platform" "logic" "memory" "security" "tokenEconomics")

fn calculateLensScore nodes: (List AuditNode) targetLens: Str -> Int64
  (let [(penalty (fold (fn [(acc Int64) (n AuditNode)] -> Int64 (if (= n.lens targetLens) (cond ((= n.severity "critical") (+ acc 25)) ((= n.severity "error") (+ acc 15)) ((= n.severity "warning") (+ acc 5)) (else (+ acc 1))) acc)) 0 nodes)) (rawScore (- 100 penalty))] (if (< rawScore 0) 0 rawScore))

fn computeOverallScore nodes: (List AuditNode) -> Int64
  (let [(lenses (canonicalLenses)) (total (fold (fn [(acc Int64) (lens Str)] -> Int64 (+ acc (calculateLensScore nodes lens))) 0 lenses))] (/ total (listLength lenses)))

fn buildAuditHypergraph nodes: (List AuditNode) edges: (List AuditEdge) -> AuditHypergraph
  (let [(score (computeOverallScore nodes))] (makeAuditHypergraph "0.1.0" 1789725000000 nodes edges score))

fn queryAuditGraph graph: AuditHypergraph lensFilter: (Option Str) severityFilter: (Option Str) anchorPrefix: (Option Str) -> (List AuditNode)
  (fold (fn [(acc (List AuditNode)) (n AuditNode)] -> (List AuditNode) (let [(lensMatch (mt lensFilter ((some l) (= n.lens l)) ((none) true))) (sevMatch (mt severityFilter ((some s) (= n.severity s)) ((none) true))) (anchorMatch (mt anchorPrefix ((some a) (stringStartsWith? n.anchor a)) ((none) true)))] (if (and (and lensMatch sevMatch) anchorMatch) (listAppend acc (list n)) acc))) (list) graph.nodes)

fn findEdgesFrom edges: (List AuditEdge) fromNode: Str -> (List AuditEdge)
  (fold (fn [(acc (List AuditEdge)) (e AuditEdge)] -> (List AuditEdge) (if (= e.from fromNode) (listAppend acc (list e)) acc)) (list) edges)

fn findEdgesTo edges: (List AuditEdge) toNode: Str -> (List AuditEdge)
  (fold (fn [(acc (List AuditEdge)) (e AuditEdge)] -> (List AuditEdge) (if (= e.to toNode) (listAppend acc (list e)) acc)) (list) edges)

fn pathExists? edges: (List AuditEdge) src: Str dst: Str visited: (List Str) -> Bool
  (if (= src dst) true (if (listContains? visited src) false (let [(outgoing (findEdgesFrom edges src)) (nextVisited (cons src visited))] (listAny? (fn [(e AuditEdge)] -> Bool (pathExists? edges e.to dst nextVisited)) outgoing))))

fn detectCycles edges: (List AuditEdge) -> (List (List Str))
  (fold (fn [(acc (List (List Str))) (e AuditEdge)] -> (List (List Str)) (if (pathExists? edges e.to e.from (list e.from)) (let [(cycle (list e.from e.to))] (listAppend acc (list cycle))) acc)) (list) edges)

fn calculateBlastRadius graph: AuditHypergraph targetAnchor: Str -> (List Str)
  (let [(edges graph.edges) (inbound (findEdgesTo edges targetAnchor)) (outbound (findEdgesFrom edges targetAnchor)) (inboundIds (fold (fn [(acc (List Str)) (e AuditEdge)] -> (List Str) (if (listContains? acc e.from) acc (listAppend acc (list e.from)))) (list) inbound)) (allIds (fold (fn [(acc (List Str)) (e AuditEdge)] -> (List Str) (if (listContains? acc e.to) acc (listAppend acc (list e.to)))) inboundIds outbound))] (if (listContains? allIds targetAnchor) allIds (cons targetAnchor allIds)))

fn emitPatchReceipt node: AuditNode -> PatchReceipt
  (let [(rcId (str "rc-" node.id)) (target node.anchor) (remedy node.remedy) (diffStr (str "(:remedy :anchor \"" target "\" :patch \"" remedy "\")")) (estTokens (+ (/ (stringLength diffStr) 4) 8))] (makePatchReceipt rcId target "ready" diffStr estTokens))

fn formatAuditNodeAsn n: AuditNode -> Str
  (str "    (:node :id \"" n.id "\"\n" "           :lens \"" n.lens "\"\n" "           :severity \"" n.severity "\"\n" "           :anchor \"" n.anchor "\"\n" "           :evidence \"" n.evidence "\"\n" "           :remedy \"" n.remedy "\"\n" "           :provenance \"" n.provenance "\")")

fn formatAuditEdgeAsn e: AuditEdge -> Str
  (str "    (:edge :from \"" e.from "\" :to \"" e.to "\" :kind \"" e.kind "\")")

fn formatAuditAsn graph: AuditHypergraph -> Str
  (let [(nodesStr (stringJoin (fold (fn [(acc (List Str)) (n AuditNode)] -> (List Str) (listAppend acc (list (formatAuditNodeAsn n)))) (list) graph.nodes) "\n")) (edgesStr (stringJoin (fold (fn [(acc (List Str)) (e AuditEdge)] -> (List Str) (listAppend acc (list (formatAuditEdgeAsn e)))) (list) graph.edges) "\n"))] (str "(:auditHypergraph\n" "  :version \"" graph.version "\"\n" "  :timestamp " (stringFromInt64 graph.timestamp) "\n" "  :score " (stringFromInt64 graph.score) "\n" "  :nodeCount " (stringFromInt64 (listLength graph.nodes)) "\n" "  :edgeCount " (stringFromInt64 (listLength graph.edges)) "\n" "  :nodes [\n" nodesStr "\n  ]\n" "  :edges [\n" edgesStr "\n  ])"))

fn formatReceiptAsn rc: PatchReceipt -> Str
  (str "(:patchReceipt\n" "  :id \"" rc.id "\"\n" "  :target \"" rc.target "\"\n" "  :status \"" rc.status "\"\n" "  :tokens " (stringFromInt64 rc.tokenCount) "\n" "  :diff " rc.diffStr ")")
