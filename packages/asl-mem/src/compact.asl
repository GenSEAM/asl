(module asl-mem/compact
  :d "High-density compact binary serialization and ASN frame encoding for memory in ASL Nano."
  :x [CompactRecord encode-vector-frame serialize-graph-node format-compact-ledger]
  :i [(graph :a g)])

(dfs CompactRecord
  (:f id Str "Unique record identifier")
  (:f frame-type Str "Schema frame category (vector, node, edge)")
  (:f payload Str "Dense serialized string or ASN frame representation")
  (:f byte-size I64 "Estimated byte size of the payload"))

(df float-list-to-dense-string [(fs (List F64))] -> Str
  :d "Encodes float vector into compact space-separated string."
  (string-join (map (fn [(f F64)] -> Str (string-from-float64 f)) fs) ","))

(df encode-vector-frame [(id Str) (text Str) (v (List F64))] -> CompactRecord
  :d "Serializes vector memory entry into compact ASN frame format."
  (let [(dense-v (float-list-to-dense-string v))
        (frame (str "@v:{" id "|" text "|[" dense-v "]}"))]
    (CompactRecord
      :id id
      :frame-type "vector"
      :payload frame
      :byte-size (string-length frame))))

(df serialize-graph-node [(node g/GraphNode)] -> CompactRecord
  :d "Serializes knowledge graph entity into compact ASN record."
  (let [(frame (str "@n:{" (.-id node) "|" (.-label node) "|" (string-from-int64 (.-timestamp-epoch node)) "|" (string-from-float64 (.-confidence node)) "|" (.-content node) "}"))]
    (CompactRecord
      :id (.-id node)
      :frame-type "node"
      :payload frame
      :byte-size (string-length frame))))

(df format-compact-ledger [(records (List CompactRecord))] -> Str
  :d "Compiles sequence of compact records into unified dense storage stream."
  (string-join (map (fn [(r CompactRecord)] -> Str (.-payload r)) records) "\n"))
