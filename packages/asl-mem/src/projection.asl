(module aslMem/projection :x [ProjectionState makeProjectionState hasEntity? getEntityCount getMetricTotal replayWalEntry replayWalBatch extractIntField] :i [(aslMem/wal :a wal)])

(schema ProjectionState (:f partitionId Str) (:f appliedSeq I64) (:f entities (Map Str Str)) (:f metrics (Map Str I64)))

fn makeProjectionState partitionId: Str -> ProjectionState
  (ProjectionState :partitionId partitionId :appliedSeq 0 :entities (mapEmpty) :metrics (mapEmpty))

fn hasEntity? p: ProjectionState key: Str -> Bool
  (mapHas? p.entities key)

fn getEntityCount p: ProjectionState -> I64
  (mapSize p.entities)

fn getMetricTotal p: ProjectionState name: Str -> I64
  (optionOr (mapGet p.metrics name) 0)

fn extractIntField payload: Str fieldKey: Str -> (Option I64)
  (let [(pattern (str "\"" fieldKey "\":")) (altPattern (str "\"" fieldKey "\": "))] (let [(targetIdx (mt (stringIndexOf payload pattern) ((some idx) (some (+ idx (stringLength pattern)))) ((none) (mt (stringIndexOf payload altPattern) ((some idx2) (some (+ idx2 (stringLength altPattern)))) ((none) (none))))))] (mt targetIdx ((none) (none)) ((some startPos) (let [(tail (optionOr (stringSlice payload startPos (stringLength payload)) "")) (trimmed (stringTrim tail)) (digits (fold (fn [(acc Str) (c Str)] -> Str (if (and (stringEmpty? acc) (= c "-")) "-" (if (or (= c "0") (or (= c "1") (or (= c "2") (or (= c "3") (or (= c "4") (or (= c "5") (or (= c "6") (or (= c "7") (or (= c "8") (= c "9")))))))))) (str acc c) acc))) "" (stringChars trimmed)))] (stringToInt64 digits))))))

fn replayWalEntry p: ProjectionState e: wal/WalEntry -> ProjectionState
  (let [(seq e.seqNum) (watermark p.appliedSeq)] (if (<= seq watermark) p (let [(op e.opType) (key e.key) (payload e.payload)] (mt op ((wal/opPutNode) (let [(nextEntities (mapSet p.entities key payload)) (optAmount (extractIntField payload "amount")) (nextMetrics (mt optAmount ((some amt) (let [(curCount (getMetricTotal p "orderCount")) (curRev (getMetricTotal p "totalRevenue")) (m1 (mapSet p.metrics "orderCount" (+ curCount 1)))] (mapSet m1 "totalRevenue" (+ curRev amt)))) ((none) p.metrics)))] (with p :appliedSeq seq :entities nextEntities :metrics nextMetrics))) ((wal/opDelNode) (let [(nextEntities (mapRemove p.entities key))] (with p :appliedSeq seq :entities nextEntities))) (_ (with p :appliedSeq seq))))))

fn replayWalBatch p: ProjectionState entries: (List wal/WalEntry) -> ProjectionState
  (fold (fn [(acc ProjectionState) (e wal/WalEntry)] -> ProjectionState (replayWalEntry acc e)) p entries)
