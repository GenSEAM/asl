(module aslMem/engine :x [StorageMode StorageConfig MemoryEngine EngineStats makeEngine enginePutVector enginePutNode enginePutEdge engineDelNode engineCheckpoint engineApplyWalEntry engineRecover engineStats] :i [(store :a s) (graph :a g) (ring :a r) (wal :a w) (snapshot :a snap)])

(enum StorageMode (:c modeEphemeral [] "100% in-memory ring buffer, zero disk I/O") (:c modeSnapshot [] "In-memory with periodic or manual atomic snapshotting") (:c modeJournaledWal [] "In-memory ring buffer backed by append-only WAL on disk"))

(schema StorageConfig (:f mode StorageMode) (:f ringCapacity I64) (:f walPath Str) (:f snapshotPath Str))

(schema MemoryEngine (:f config StorageConfig) (:f ring r/RingBuffer) (:f vectors s/VectorStore) (:f graph g/KnowledgeGraph) (:f wal w/WalState) (:f lastCheckpointEpoch I64))

(schema EngineStats (:f modeName Str) (:f ringUtilization I64) (:f vectorCount I64) (:f nodeCount I64) (:f edgeCount I64) (:f walEntriesCommitted I64) (:f evictedCount I64))

fn makeEngine mode: StorageMode ringCap: I64 walPath: Str snapPath: Str -> MemoryEngine
  (let [(cfg (StorageConfig :mode mode :ringCapacity ringCap :walPath walPath :snapshotPath snapPath)) (ringBuf (r/makeRingBuffer ringCap (r/policySpill))) (vStore (s/VectorStore :name "default" :dimensions 384 :items (list))) (kGraph (g/KnowledgeGraph :nodes (list) :edges (list))) (walSt (w/makeWalState walPath))] (MemoryEngine :config cfg :ring ringBuf :vectors vStore :graph kGraph :wal walSt :lastCheckpointEpoch 0))

fn enginePutVector eng: MemoryEngine id: Str text: Str v: (List F64) epoch: I64 -> MemoryEngine
  (let [(item (s/VectorItem :id id :text text :vector v)) (nextVectors (s/VectorStore :name eng.vectors.name :dimensions eng.vectors.dimensions :items (listAppend eng.vectors.items (list item)))) (frame (snap/serializeVectorItem item)) (pushRes (r/ringPush eng.ring frame)) (walRes (mt eng.config.mode ((modeJournaledWal) (let [(pairRes (w/appendWalEntry eng.wal (w/opPutVector) id frame epoch))] (pairFirst pairRes))) ((modeEphemeral) eng.wal) ((modeSnapshot) eng.wal)))] (with eng :ring pushRes.buffer :vectors nextVectors :wal walRes))

fn enginePutNode eng: MemoryEngine node: g/GraphNode epoch: I64 -> MemoryEngine
  (let [(nextGraph (g/addNode eng.graph node)) (frame (snap/serializeGraphNodeFrame node)) (pushRes (r/ringPush eng.ring frame)) (walRes (mt eng.config.mode ((modeJournaledWal) (let [(pairRes (w/appendWalEntry eng.wal (w/opPutNode) node.id frame epoch))] (pairFirst pairRes))) ((modeEphemeral) eng.wal) ((modeSnapshot) eng.wal)))] (with eng :ring pushRes.buffer :graph nextGraph :wal walRes))

fn enginePutEdge eng: MemoryEngine edge: g/GraphEdge epoch: I64 -> MemoryEngine
  (let [(nextGraph (g/addEdge eng.graph edge)) (frame (snap/serializeGraphEdge edge)) (pushRes (r/ringPush eng.ring frame)) (walRes (mt eng.config.mode ((modeJournaledWal) (let [(pairRes (w/appendWalEntry eng.wal (w/opPutEdge) edge.sourceId frame epoch))] (pairFirst pairRes))) ((modeEphemeral) eng.wal) ((modeSnapshot) eng.wal)))] (with eng :ring pushRes.buffer :graph nextGraph :wal walRes))

fn engineCheckpoint eng: MemoryEngine epoch: I64 -> (Pair MemoryEngine Str)
  (let [(snapStr (snap/formatSnapshotLedger eng.vectors eng.graph epoch)) (nextWal (mt eng.config.mode ((modeJournaledWal) (let [(pairRes (w/walCheckpointMarker eng.wal epoch ":snapshot-manifest"))] (pairFirst pairRes))) ((modeEphemeral) eng.wal) ((modeSnapshot) eng.wal))) (nextEng (with eng :wal nextWal :lastCheckpointEpoch epoch))] (pair nextEng snapStr))

fn engineStats eng: MemoryEngine -> EngineStats
  (let [(mStr (mt eng.config.mode ((modeEphemeral) "ephemeral") ((modeSnapshot) "snapshot") ((modeJournaledWal) "journaled-wal")))] (EngineStats :modeName mStr :ringUtilization (r/ringUtilization eng.ring) :vectorCount (listLength eng.vectors.items) :nodeCount (listLength eng.graph.nodes) :edgeCount (listLength eng.graph.edges) :walEntriesCommitted eng.wal.totalCommitted :evictedCount (r/ringEvictedCount eng.ring)))

fn engineDelNode eng: MemoryEngine nodeId: Str epoch: I64 -> MemoryEngine
  (let [(nextGraph (g/removeNode eng.graph nodeId)) (walRes (mt eng.config.mode ((modeJournaledWal) (let [(pairRes (w/appendWalEntry eng.wal (w/opDelNode) nodeId "DELETED" epoch))] (pairFirst pairRes))) ((modeEphemeral) eng.wal) ((modeSnapshot) eng.wal)))] (with eng :graph nextGraph :wal walRes))

fn parseNodeFrame frame: Str -> (Option g/GraphNode)
  (let [(trimmed (stringTrim frame))] (if (and (stringStartsWith? trimmed "n:{") (stringEndsWith? trimmed "}")) (let [(startIdx 3) (innerLen (- (stringLength trimmed) 4)) (inner (optionOr (stringSlice trimmed startIdx (+ startIdx innerLen)) "")) (parts (stringSplit inner "|"))] (if (>= (listLength parts) 5) (let [(id (optionOr (listHead parts) "")) (p1 (optionOr (listTail parts) (list))) (label (optionOr (listHead p1) "")) (p2 (optionOr (listTail p1) (list))) (epochS (optionOr (listHead p2) "0")) (p3 (optionOr (listTail p2) (list))) (confS (optionOr (listHead p3) "1.0")) (p4 (optionOr (listTail p3) (list))) (content (stringJoin p4 "|"))] (some (g/GraphNode :id id :label label :content content :timestampEpoch (optionOr (stringToInt64 epochS) 0) :confidence (optionOr (stringToFloat64 confS) 1.0)))) (none))) (none)))

fn parseEdgeFrame frame: Str -> (Option g/GraphEdge)
  (let [(trimmed (stringTrim frame))] (if (and (stringStartsWith? trimmed "e:{") (stringEndsWith? trimmed "}")) (let [(startIdx 3) (innerLen (- (stringLength trimmed) 4)) (inner (optionOr (stringSlice trimmed startIdx (+ startIdx innerLen)) "")) (parts (stringSplit inner "|"))] (if (>= (listLength parts) 5) (let [(src (optionOr (listHead parts) "")) (p1 (optionOr (listTail parts) (list))) (tgt (optionOr (listHead p1) "")) (p2 (optionOr (listTail p1) (list))) (rel (optionOr (listHead p2) "")) (p3 (optionOr (listTail p2) (list))) (wtS (optionOr (listHead p3) "1.0")) (p4 (optionOr (listTail p3) (list))) (epochS (optionOr (listHead p4) "0"))] (some (g/GraphEdge :sourceId src :targetId tgt :relation rel :weight (optionOr (stringToFloat64 wtS) 1.0) :timestampEpoch (optionOr (stringToInt64 epochS) 0)))) (none))) (none)))

fn parseVectorFrame frame: Str -> (Option s/VectorItem)
  (let [(trimmed (stringTrim frame))] (if (and (stringStartsWith? trimmed "v:{") (stringEndsWith? trimmed "}")) (let [(startIdx 3) (innerLen (- (stringLength trimmed) 4)) (inner (optionOr (stringSlice trimmed startIdx (+ startIdx innerLen)) "")) (parts (stringSplit inner "|"))] (if (>= (listLength parts) 3) (let [(id (optionOr (listHead parts) "")) (p1 (optionOr (listTail parts) (list))) (text (optionOr (listHead p1) "")) (p2 (optionOr (listTail p1) (list))) (rawVec (optionOr (listHead p2) "[]")) (cleanVec (stringReplace (stringReplace rawVec "[" "") "]" "")) (numStrs (if (stringEmpty? cleanVec) (list) (stringSplit cleanVec ","))) (vec (map (fn [(s Str)] -> F64 (optionOr (stringToFloat64 (stringTrim s)) 0.0)) numStrs))] (some (s/VectorItem :id id :text text :vector vec))) (none))) (none)))

fn engineApplyWalEntry eng: MemoryEngine entry: w/WalEntry -> MemoryEngine
  (let [(nextWal (w/WalState :logPath eng.wal.logPath :currentSeq entry.seqNum :unflushed (list) :totalCommitted entry.seqNum))] (mt entry.opType ((opDelNode) (with eng :graph (g/removeNode eng.graph entry.key) :wal nextWal)) ((opCheckpoint) (with eng :wal nextWal :lastCheckpointEpoch entry.timestampEpoch)) ((opPutNode) (mt (parseNodeFrame entry.payload) ((some n) (with eng :graph (g/addNode eng.graph n) :wal nextWal)) ((none) eng))) ((opPutEdge) (mt (parseEdgeFrame entry.payload) ((some e) (with eng :graph (g/addEdge eng.graph e) :wal nextWal)) ((none) eng))) ((opPutVector) (mt (parseVectorFrame entry.payload) ((some item) (let [(nextVectors (s/VectorStore :name eng.vectors.name :dimensions eng.vectors.dimensions :items (listAppend eng.vectors.items (list item))))] (with eng :vectors nextVectors :wal nextWal))) ((none) eng)))))

fn engineRecover eng: MemoryEngine rawWalLog: Str -> MemoryEngine
  (let [(entries (w/parseWalStream rawWalLog))] (fold engineApplyWalEntry eng entries))
