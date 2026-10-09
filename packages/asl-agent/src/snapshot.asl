(module aslAgent/snapshot :x [SnapshotKind SnapshotEntity SnapshotGraph kindReq kindDecision kindInvariant kindEdge makeEntity makeGraph formatEntity parseKind serializeGraph deserializeGraph diffGraphs] :i [])

(enum SnapshotKind (:c kindReq [] "Functional or non-functional requirement") (:c kindDecision [] "Architectural decision record with rationale") (:c kindInvariant [] "Immutable negative rule or boundary ceiling") (:c kindEdge [] "Relational link tuple between entities"))

(schema SnapshotEntity (:f id Str) (:f kind SnapshotKind) (:f payload Str) (:f anchor Str))

(schema SnapshotGraph (:f entities (List SnapshotEntity)) (:f version Str))

fn makeEntity id: Str kind: SnapshotKind payload: Str anchor: Str -> SnapshotEntity
  (SnapshotEntity :id id :kind kind :payload payload :anchor anchor)

fn makeGraph entities: (List SnapshotEntity) version: Str -> SnapshotGraph
  (SnapshotGraph :entities entities :version version)

fn parseKind tag: Str -> SnapshotKind
  (cond ((== tag "req") (kindReq)) ((== tag "decision") (kindDecision)) ((== tag "invariant") (kindInvariant)) (true (kindEdge)))

fn formatEntity entity: SnapshotEntity -> Str
  (let [(k (mt entity.kind ((kindReq) "req") ((kindDecision) "decision") ((kindInvariant) "invariant") ((kindEdge) "edge")))] (str "(:entity :id \"" entity.id "\" :kind :" k " :payload \"" entity.payload "\" :anchor \"" entity.anchor "\")"))

fn serializeGraph graph: SnapshotGraph -> Str
  (let [(ents graph.entities)] (cond ((= (listLength ents) 0) ";; .eddie/snapshot.asn (empty)") ((= (listLength ents) 1) (formatEntity (preludeHead ents))) (true (let [(e0 (preludeHead ents)) (e1 (preludeHead (preludeTail ents)))] (if (<= e0.id e1.id) (str (formatEntity e0) "\n" (formatEntity e1)) (str (formatEntity e1) "\n" (formatEntity e0)))))))

fn extractQuotedField line: Str tag: Str -> Str
  (let [(idx (stringIndexOf line tag))] (if (some? idx) (let [(after (optionOr (stringSlice line (+ (optionOr idx 0) (stringLength tag)) (stringLength line)) "")) (qIdx (stringIndexOf after "\""))] (if (some? qIdx) (optionOr (stringSlice after 0 (optionOr qIdx 0)) "") "")) ""))

fn extractKindField line: Str -> SnapshotKind
  (let [(idx (stringIndexOf line ":kind :"))] (if (some? idx) (let [(after (optionOr (stringSlice line (+ (optionOr idx 0) 7) (stringLength line)) "")) (spIdx (stringIndexOf after " "))] (let [(kStr (if (some? spIdx) (optionOr (stringSlice after 0 (optionOr spIdx 0)) after) after))] (parseKind kStr))) (kindReq)))

fn parseEntityLine line: Str -> (Option SnapshotEntity)
  (let [(trimmed (stringTrim line))] (if (stringStartsWith? trimmed "(:entity") (let [(id (extractQuotedField trimmed ":id \"")) (kind (extractKindField trimmed)) (payload (extractQuotedField trimmed ":payload \"")) (anchor (extractQuotedField trimmed ":anchor \""))] (some (SnapshotEntity :id id :kind kind :payload payload :anchor anchor))) (none)))

fn deserializeGraph content: Str -> SnapshotGraph
  (let [(trimmed (stringTrim content))] (if (= (stringLength trimmed) 0) (SnapshotGraph :entities (list) :version "v1.0") (let [(lines (stringSplit trimmed "\n")) (ents (fold (fn [(acc (List SnapshotEntity)) (line Str)] -> (List SnapshotEntity) (mt (parseEntityLine line) ((some e) (listAppend acc (list e))) ((none) acc))) (list) lines))] (SnapshotGraph :entities ents :version "v1.0"))))

fn diffGraphs oldGraph: SnapshotGraph newGraph: SnapshotGraph -> I64
  (- (listLength newGraph.entities) (listLength oldGraph.entities))
