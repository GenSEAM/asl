(module asl-mesh/vectorClock
  :x [VectorClock makeVectorClock getClockValue getClockValueWithHorizon getBaseHorizon vectorClockTick vectorClockMerge vectorClockPrune vectorClockPruneWithHorizon isCausalPredecessor? isConcurrent? areClocksEqual? pruneStaleNodes]
  :i [])

(schema VectorClock
  (:f nodeId String)
  (:f entries (Map String Int64))
  (:f baseHorizon Int64))

fn makeVectorClock nodeId: String -> VectorClock
  (let [(m (mapSet (mapEmpty) nodeId 0))]
    (VectorClock :nodeId nodeId :entries m :baseHorizon 0))

fn getClockValue vc: VectorClock targetId: String -> Int64
  (optionOr (mapGet vc.entries targetId) 0)

fn getBaseHorizon vc: VectorClock -> Int64
  vc.baseHorizon

fn getClockValueWithHorizon vc: VectorClock targetId: String -> Int64
  (mt (mapGet vc.entries targetId)
    ((some v) v)
    ((none) vc.baseHorizon))

fn vectorClockTick vc: VectorClock -> VectorClock
  (let [(selfId vc.nodeId)
        (curVal (getClockValue vc selfId))
        (updatedMap (mapSet vc.entries selfId (+ curVal 1)))]
    (with vc :nodeId selfId :entries updatedMap))

fn vectorClockMerge vc1: VectorClock vc2: VectorClock -> VectorClock
  (let [(mergedMap (fold (fn [(acc (Map String Int64)) (k String)] -> (Map String Int64)
                           (let [(v1 (getClockValue vc1 k))
                                 (v2 (getClockValue vc2 k))
                                 (maxV (if (> v1 v2) v1 v2))]
                             (mapSet acc k maxV)))
                         vc1.entries
                         (mapKeys vc2.entries)))
        (h1 vc1.baseHorizon)
        (h2 vc2.baseHorizon)
        (maxH (if (> h1 h2) h1 h2))]
    (with vc1 :entries mergedMap :baseHorizon maxH))

fn vectorClockPrune vc: VectorClock activeNodes: (List String) -> VectorClock
  (let [(selfId vc.nodeId)
        (prunedMap (fold (fn [(acc (Map String Int64)) (k String)] -> (Map String Int64)
                           (if (or (= k selfId) (listContains? activeNodes k))
                             (mapSet acc k (getClockValue vc k))
                             acc))
                         (mapEmpty)
                         (mapKeys vc.entries)))]
    (with vc :nodeId selfId :entries prunedMap))

fn vectorClockPruneWithHorizon vc: VectorClock activeNodes: (List String) -> VectorClock
  (let [(selfId vc.nodeId)
        (maxPruned (fold (fn [(acc Int64) (k String)] -> Int64
                           (if (or (= k selfId) (listContains? activeNodes k))
                             acc
                             (let [(v (getClockValue vc k))]
                               (if (> v acc) v acc))))
                         vc.baseHorizon
                         (mapKeys vc.entries)))
        (prunedMap (fold (fn [(acc (Map String Int64)) (k String)] -> (Map String Int64)
                           (if (or (= k selfId) (listContains? activeNodes k))
                             (mapSet acc k (getClockValue vc k))
                             acc))
                         (mapEmpty)
                         (mapKeys vc.entries)))]
    (VectorClock :nodeId selfId :entries prunedMap :baseHorizon maxPruned))

fn pruneStaleNodes vc: VectorClock cutoffTick: Int64 -> VectorClock
  (let [(selfId vc.nodeId)
        (activeKeys (filter (fn [(k String)] (or (= k selfId) (>= (getClockValue vc k) cutoffTick))) (mapKeys vc.entries)))]
    (vectorClockPruneWithHorizon vc activeKeys))

fn areClocksEqual? vc1: VectorClock vc2: VectorClock -> Bool
  (let [(keys1 (mapKeys vc1.entries))
        (keys2 (mapKeys vc2.entries))
        (allKeys (listAppend keys1 keys2))]
    (listAll? (fn [(k String)] (= (getClockValueWithHorizon vc1 k) (getClockValueWithHorizon vc2 k))) allKeys))

fn isCausalPredecessor? vc1: VectorClock vc2: VectorClock -> Bool
  (let [(keys1 (mapKeys vc1.entries))
        (keys2 (mapKeys vc2.entries))
        (allKeys (listAppend keys1 keys2))
        (allLessEq (listAll? (fn [(k String)] (<= (getClockValueWithHorizon vc1 k) (getClockValueWithHorizon vc2 k))) allKeys))
        (strictlyLess (listAny? (fn [(k String)] (< (getClockValueWithHorizon vc1 k) (getClockValueWithHorizon vc2 k))) allKeys))]
    (and allLessEq strictlyLess))

fn isConcurrent? vc1: VectorClock vc2: VectorClock -> Bool
  (and (not (isCausalPredecessor? vc1 vc2))
       (and (not (isCausalPredecessor? vc2 vc1))
            (not (areClocksEqual? vc1 vc2))))
