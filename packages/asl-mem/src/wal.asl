(module aslMem/wal :x [WalOpType WalEntry WalState WalStreamResult makeWalEntry computeWalChecksum makeWalState appendWalEntry formatWalFrame parseWalFrame parseWalStream parseWalStreamStrict isWalSuccess? isWalGap? isWalCorrupt? walDrainUnflushed walRollbackUnflushed walCheckpointMarker opTypeToString stringToOpType] :i [(asl-transpile/asn :a asn) (asl-text/escape :a esc) (aslMem/simhash :a sh)])

(enum WalOpType (:c opPutVector [] "Vector embedding insertion") (:c opPutNode [] "Knowledge graph node addition") (:c opPutEdge [] "Knowledge graph edge addition") (:c opDelNode [] "Knowledge graph node deletion") (:c opCheckpoint [] "Compaction checkpoint snapshot marker"))

(schema WalEntry (:f seqNum I64) (:f timestampEpoch I64) (:f opType WalOpType) (:f key Str) (:f payload Str) (:f checksum I64))

(schema WalState (:f logPath Str) (:f currentSeq I64) (:f unflushed (List WalEntry)) (:f totalCommitted I64))

(enum WalStreamResult (:c walSuccess [(entries (List WalEntry))]) (:c walGap [(expectedSeq I64) (actualSeq I64)]) (:c walCorrupt [(lineIndex I64) (reason Str)]))

fn isWalSuccess? res: WalStreamResult -> Bool
  (mt res ((walSuccess _) true) (_ false))

fn isWalGap? res: WalStreamResult -> Bool
  (mt res ((walGap _ _) true) (_ false))

fn isWalCorrupt? res: WalStreamResult -> Bool
  (mt res ((walCorrupt _ _) true) (_ false))

fn opTypeToString op: WalOpType -> Str
  (mt op ((opPutVector) "v+") ((opPutNode) "n+") ((opPutEdge) "e+") ((opDelNode) "n-") ((opCheckpoint) "ckpt"))

fn stringToOpType s: Str -> (Option WalOpType)
  (cond ((or (= s "v+") (= s "PUT-VECTOR")) (some (opPutVector))) ((or (= s "n+") (= s "PUT-NODE")) (some (opPutNode))) ((or (= s "e+") (= s "PUT-EDGE")) (some (opPutEdge))) ((or (= s "n-") (= s "DEL-NODE")) (some (opDelNode))) ((or (= s "ckpt") (= s "CHECKPOINT")) (some (opCheckpoint))) (else (none)))

fn computeWalChecksum seq: I64 epoch: I64 opStr: Str key: Str payload: Str -> I64
  (let [(data (str (stringFromInt64 seq) ":" (stringFromInt64 epoch) ":" opStr ":" key ":" payload))] (sh/fnv1a64 data))

fn makeWalEntry seq: I64 epoch: I64 op: WalOpType key: Str payload: Str -> WalEntry
  (let [(opS (opTypeToString op)) (crc (computeWalChecksum seq epoch opS key payload))] (WalEntry :seqNum seq :timestampEpoch epoch :opType op :key key :payload payload :checksum crc))

fn makeWalState path: Str -> WalState
  (WalState :logPath path :currentSeq 0 :unflushed (list) :totalCommitted 0)

fn formatWalFrame e: WalEntry -> Str
  (let [(seqStr (stringFromInt64 e.seqNum)) (epochStr (stringFromInt64 e.timestampEpoch)) (opStr (opTypeToString e.opType)) (keyEsc (esc/escapeAsnStr e.key)) (payloadEsc (esc/escapeAsnStr e.payload)) (crc (computeWalChecksum e.seqNum e.timestampEpoch opStr e.key e.payload)) (crcStr (stringFromInt64 crc))] (asn/asnWrite (asn/asnCtor "WalEntry" (list (asn/AsnField :key ":seq" :val (asn/asnInt seqStr)) (asn/AsnField :key ":epoch" :val (asn/asnInt epochStr)) (asn/AsnField :key ":op" :val (asn/asnStr (str "\"" opStr "\""))) (asn/AsnField :key ":key" :val (asn/asnStr (str "\"" keyEsc "\""))) (asn/AsnField :key ":payload" :val (asn/asnStr (str "\"" payloadEsc "\""))) (asn/AsnField :key ":crc" :val (asn/asnInt crcStr))))))

fn findField fs: (List asn/AsnField) key: Str -> (Option asn/AsnValue)
  (let [(matches (filter (fn [(f asn/AsnField)] -> Bool (= f.key key)) fs))] (mt (listHead matches) ((some f) (some f.val)) ((none) (none))))

fn getFieldInt fs: (List asn/AsnField) key: Str -> I64
  (mt (findField fs key) ((some v) (mt v ((asn/asnInt s) (optionOr (stringToInt64 s) 0)) (_ 0))) ((none) 0))

fn getFieldStr fs: (List asn/AsnField) key: Str -> Str
  (mt (findField fs key) ((some v) (optionOr (asn/asnStringValue v) "")) ((none) ""))

fn getFieldStrUnescaped fs: (List asn/AsnField) key: Str -> Str
  (mt (findField fs key) ((some v) (esc/unescapeAsnStr (optionOr (asn/asnStringValue v) ""))) ((none) ""))

fn parseWalFrame raw: Str -> (Option WalEntry)
  (mt (asn/asnRead raw) ((ok v) (mt v ((asn/asnCtor name fs) (if (= name "WalEntry") (let [(seq (getFieldInt fs ":seq")) (epoch (getFieldInt fs ":epoch")) (opS (getFieldStr fs ":op")) (keyS (getFieldStr fs ":key")) (payloadS (getFieldStr fs ":payload")) (parsedCrc (getFieldInt fs ":crc")) (expectedCrc (computeWalChecksum seq epoch opS keyS payloadS))] (if (and (> parsedCrc 0) (!= parsedCrc expectedCrc)) (none) (mt (stringToOpType opS) ((some op) (some (WalEntry :seqNum seq :timestampEpoch epoch :opType op :key keyS :payload payloadS :checksum expectedCrc))) ((none) (none))))) (none))) (_ (none)))) ((err _) (none)))

fn parseWalStream rawLog: Str -> (List WalEntry)
  (let [(lines (filter (fn [(l Str)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit rawLog "\n")))] (fold (fn [(acc (List WalEntry)) (line Str)] -> (List WalEntry) (mt (parseWalFrame line) ((some entry) (listAppend acc (list entry))) ((none) acc))) (list) lines))

fn parseWalStreamLoop lines: (List Str) expectedSeq: I64 lineIdx: I64 acc: (List WalEntry) -> WalStreamResult
  (if (listEmpty? lines) (walSuccess acc) (mt (listHead lines) ((none) (walSuccess acc)) ((some line) (let [(restLines (optionOr (listTail lines) (list)))] (mt (parseWalFrame line) ((none) (walCorrupt lineIdx (str "Malformed or CRC-corrupted WAL frame at line " (stringFromInt64 lineIdx)))) ((some entry) (let [(actSeq entry.seqNum)] (if (!= actSeq expectedSeq) (walGap expectedSeq actSeq) (parseWalStreamLoop restLines (+ expectedSeq 1) (+ lineIdx 1) (listAppend acc (list entry)))))))))))

fn parseWalStreamStrict rawLog: Str startSeq: I64 -> WalStreamResult
  (let [(lines (filter (fn [(l Str)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringSplit rawLog "\n")))] (parseWalStreamLoop lines startSeq 1 (list)))

fn appendWalEntry st: WalState op: WalOpType key: Str payload: Str epoch: I64 -> (Pair WalState WalEntry)
  (let [(nextSeq (+ st.currentSeq 1)) (entry (makeWalEntry nextSeq epoch op key payload)) (nextUnflushed (listAppend st.unflushed (list entry))) (nextSt (with st :currentSeq nextSeq :unflushed nextUnflushed :totalCommitted (+ st.totalCommitted 1)))] (pair nextSt entry))

fn walDrainUnflushed st: WalState -> (Pair WalState (List WalEntry))
  (let [(drained st.unflushed) (nextSt (with st :unflushed (list)))] (pair nextSt drained))

fn walRollbackUnflushed st: WalState -> WalState
  (with st :currentSeq (- st.currentSeq (listLength st.unflushed)) :unflushed (list))

fn walCheckpointMarker st: WalState epoch: I64 snapshotHash: Str -> (Pair WalState WalEntry)
  (appendWalEntry st (opCheckpoint) snapshotHash "CHECKPOINT" epoch)
