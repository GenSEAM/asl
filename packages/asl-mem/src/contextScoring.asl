(module aslMem/contextScoring :x [ContextScoreRecord ActiveVolumeReport makeContextRecord calculateContextScore penalizeUnreferencedMatches evictRecordsBelowThreshold calculateActiveVolume isVolumeBounded? reportActiveVolume] :i [(math :a m)])

(schema ContextScoreRecord (:f id Str) (:f isInvariant Bool) (:f invariantWeight F64) (:f retrievalCost F64) (:f referenceLinks I64) (:f deltaTurns I64) (:f unreferencedMatches I64) (:f baitPenalty F64) (:f utilityScore F64))

fn calculateContextScore record: ContextScoreRecord lambdaDecay: F64 baitPenaltyRate: F64 -> ContextScoreRecord
  (let [(invTerm (if record.isInvariant record.invariantWeight 0.0)) (costTerm record.retrievalCost) (linksTerm (int64ToFloat64 record.referenceLinks)) (dtFloat (int64ToFloat64 record.deltaTurns)) (dtTerm (* lambdaDecay (m/fastLn (+ 1.0 dtFloat)))) (unrefFloat (int64ToFloat64 record.unreferencedMatches)) (computedBait (* unrefFloat baitPenaltyRate)) (finalScore (- (+ (+ invTerm costTerm) linksTerm) (+ dtTerm computedBait)))] (with record :retrievalCost costTerm :baitPenalty computedBait :utilityScore finalScore))

fn makeContextRecord id: Str isInvariant: Bool retrievalCost: F64 referenceLinks: I64 deltaTurns: I64 -> ContextScoreRecord
  (let [(weight (if isInvariant 50.0 0.0)) (baseRec (ContextScoreRecord :id id :isInvariant isInvariant :invariantWeight weight :retrievalCost retrievalCost :referenceLinks referenceLinks :deltaTurns deltaTurns :unreferencedMatches 0 :baitPenalty 0.0 :utilityScore 0.0))] (calculateContextScore baseRec 1.0 2.5))

fn penalizeUnreferencedMatches record: ContextScoreRecord unreferencedInc: I64 -> ContextScoreRecord
  (let [(newUnref (+ record.unreferencedMatches unreferencedInc)) (updatedRec (with record :unreferencedMatches newUnref))] (calculateContextScore updatedRec 1.0 2.5))

fn evictRecordsBelowThreshold records: (List ContextScoreRecord) threshold: F64 -> (List ContextScoreRecord)
  (fold (fn [(acc (List ContextScoreRecord)) (rec ContextScoreRecord)] -> (List ContextScoreRecord) (if (or rec.isInvariant (>= rec.utilityScore threshold)) (listAppend acc (list rec)) acc)) (list) records)

(schema ActiveVolumeReport (:f volume I64) (:f ceiling I64) (:f bounded Bool))

fn calculateActiveVolume records: (List ContextScoreRecord) -> I64
  (listLength records)

fn isVolumeBounded? volume: I64 ceiling: I64 -> Bool
  (<= volume ceiling)

fn reportActiveVolume records: (List ContextScoreRecord) ceiling: I64 -> ActiveVolumeReport
  (let [(vol (calculateActiveVolume records)) (bounded (isVolumeBounded? vol ceiling))] (ActiveVolumeReport :volume vol :ceiling ceiling :bounded bounded))
