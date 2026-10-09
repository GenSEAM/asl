(module aslMem/snapshot :x [SnapshotManifest createSnapshotFrame serializeVectorItem serializeGraphNodeFrame serializeGraphEdge formatSnapshotLedger] :i [(store :a s) (graph :a g) (asl-transpile/asn :a asn)])

(schema SnapshotManifest (:f version Str) (:f timestampEpoch I64) (:f vectorCount I64) (:f nodeCount I64) (:f edgeCount I64) (:f checksum Str))

fn serializeVectorItem item: s/VectorItem -> Str
  (let [(dense (stringJoin (map (fn [(f F64)] -> Str (stringFromFloat64 f)) item.vector) ","))] (str "v:{" item.id "|" item.text "|[" dense "]}"))

fn serializeGraphNodeFrame node: g/GraphNode -> Str
  (str "n:{" node.id "|" node.label "|" (stringFromInt64 node.timestampEpoch) "|" (stringFromFloat64 node.confidence) "|" node.content "}")

fn serializeGraphEdge edge: g/GraphEdge -> Str
  (str "e:{" edge.sourceId "|" edge.targetId "|" edge.relation "|" (stringFromFloat64 edge.weight) "|" (stringFromInt64 edge.timestampEpoch) "}")

fn createSnapshotFrame vCount: I64 nCount: I64 eCount: I64 epoch: I64 -> Str
  (asn/asnWrite (asn/asnCtor ":snapshot-manifest" (list (asn/AsnField :key ":v-count" :val (asn/asnInt (stringFromInt64 vCount))) (asn/AsnField :key ":n-count" :val (asn/asnInt (stringFromInt64 nCount))) (asn/AsnField :key ":e-count" :val (asn/asnInt (stringFromInt64 eCount))) (asn/AsnField :key ":epoch" :val (asn/asnInt (stringFromInt64 epoch))))))

fn formatSnapshotLedger vStore: s/VectorStore kGraph: g/KnowledgeGraph epoch: I64 -> Str
  (let [(vItems vStore.items) (gNodes kGraph.nodes) (gEdges kGraph.edges) (header (createSnapshotFrame (listLength vItems) (listLength gNodes) (listLength gEdges) epoch)) (vFrames (map serializeVectorItem vItems)) (nFrames (map serializeGraphNodeFrame gNodes)) (eFrames (map serializeGraphEdge gEdges)) (allLines (listAppend (listAppend (list header) vFrames) (listAppend nFrames eFrames)))] (stringJoin allLines "\n"))
