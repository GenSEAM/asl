(module aslMem/compact
  :x [CompactRecord encodeVectorFrame serializeGraphNode formatCompactRecord formatCompactLedger ensureQuoted]
  :i [(graph :a g)
      (asl-transpile/asn :a asn)])

(schema CompactRecord
  (:f id Str)
  (:f frameType Str)
  (:f payload Str)
  (:f byteSize I64))

fn ensureQuoted s: Str -> Str
  (let [(len (stringLength s))] (if (and (>= len 2) (= (optionOr (stringSlice s 0 1) "") "\"") (= (optionOr (stringSlice s (- len 1) len) "") "\"")) s (str "\"" s "\"")))

fn encodeVectorFrame id: Str text: Str v: (List F64) -> CompactRecord
  (let [(frame (asn/asnWrite (asn/asnCtor ":vector" (list (asn/AsnField :key ":id" :val (asn/asnStr (ensureQuoted id))) (asn/AsnField :key ":text" :val (asn/asnStr (ensureQuoted text))) (asn/AsnField :key ":v" :val (asn/asnVec (map (fn [(f F64)] -> asn/AsnValue (asn/asnFloat (stringFromFloat64 f))) v)))))))] (CompactRecord :id id :frameType "vector" :payload frame :byteSize (stringLength frame)))

fn serializeGraphNode node: g/GraphNode -> CompactRecord
  (let [(fId (asn/AsnField :key ":id" :val (asn/asnStr (ensureQuoted node.id)))) (fLabel (asn/AsnField :key ":label" :val (asn/asnStr (ensureQuoted node.label)))) (fTs (asn/AsnField :key ":timestamp" :val (asn/asnInt (stringFromInt64 node.timestampEpoch)))) (fConf (asn/AsnField :key ":confidence" :val (asn/asnFloat (stringFromFloat64 node.confidence)))) (fContent (asn/AsnField :key ":content" :val (asn/asnStr (ensureQuoted node.content))))] (let [(fields (list fId fLabel fTs fConf fContent))] (let [(frame (asn/asnWrite (asn/asnCtor "node" fields)))] (CompactRecord :id node.id :frameType "node" :payload frame :byteSize (stringLength frame)))))

fn formatCompactRecord record: CompactRecord -> Str
  record.payload

fn formatCompactLedger records: (List CompactRecord) -> Str
  (stringJoin (map (fn [(r CompactRecord)] -> Str r.payload) records) "\n")
