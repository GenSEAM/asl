(module aslHarness/consensusCouncil
  :x [CouncilModel CouncilVote ConsensusVerdict makeCouncilVote calculateConsensusRatio isConsensusCertified? evaluateCouncilDeliberation formatConsensusReceipt defaultCouncilModelNames fastReserveCouncilModelNames]
  :i [(aslTools/consilium :a c)])

(schema CouncilModel (:f id Str) (:f name Str) (:f isFallback Bool))

(schema CouncilVote (:f modelId Str) (:f verdict Str) (:f confidence F64) (:f elapsedSec F64))

(schema ConsensusVerdict (:f target Str) (:f consensusRatio F64) (:f certified Bool) (:f approvedCount I64) (:f totalVotes I64) (:f activeLenses (List Str)))

fn defaultCouncilModelNames -> (List Str)
  (c/defaultCouncilModelNames)

fn fastReserveCouncilModelNames -> (List Str)
  (c/fastReserveCouncilModelNames)

fn makeCouncilVote mId: Str verdict: Str conf: F64 elapsed: F64 -> CouncilVote
  (CouncilVote :modelId mId :verdict verdict :confidence conf :elapsedSec elapsed)

fn countApprovedVotes votes: (List CouncilVote) -> I64
  (fold (fn [(acc I64) (v CouncilVote)] -> I64 (if (or (= v.verdict ":approved") (= v.verdict "approved")) (+ acc 1) acc)) 0 votes)

fn calculateConsensusRatio votes: (List CouncilVote) -> F64
  (let [(tot (listLength votes))]
    (if (<= tot 0) 0.0
      (/ (int64ToFloat64 (countApprovedVotes votes)) (int64ToFloat64 tot))))

fn isConsensusCertified? ratio: F64 -> Bool
  (c/isConsensusCertified? ratio)

fn evaluateCouncilDeliberation target: Str votes: (List CouncilVote) lenses: (List Str) -> ConsensusVerdict
  (let [(tot (listLength votes))
        (ratio (calculateConsensusRatio votes))
        (cert (isConsensusCertified? ratio))
        (appr (countApprovedVotes votes))]
    (ConsensusVerdict :target target :consensusRatio ratio :certified cert :approvedCount appr :totalVotes tot :activeLenses lenses))

fn formatConsensusReceipt verdict: ConsensusVerdict -> Str
  (let [(status (if verdict.certified ":certified" ":gapsDetected"))]
    (str "(:consensus-receipt :target \"" verdict.target "\" :consensus-ratio " (stringFromFloat64 verdict.consensusRatio) " :status " status " :approved " (stringFromInt64 verdict.approvedCount) " :total " (stringFromInt64 verdict.totalVotes) ")"))
