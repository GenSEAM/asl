(module aslAgent/reviewBreaker :x [ReviewDecision ReviewExchange revApproved revRejected revEscalated makeReviewExchange recordReviewCritique recordReviewApproval isReviewTripped? isReviewPassed? formatEscalationReport] :i [])

(enum ReviewDecision (:c revApproved [] "Review passed cleanly, implementation approved") (:c revRejected [] "Review rejected with feedback, returned for revision") (:c revEscalated [] "Review iterations exhausted, escalated to human maintainer"))

(schema ReviewExchange (:f roundIdx I64) (:f maxRounds I64) (:f draftSummary Str) (:f rejectionCount I64) (:f lastCritique Str) (:f decision ReviewDecision))

fn makeReviewExchange draftSummary: Str maxRounds: I64 -> ReviewExchange
  (let [(limit (if (<= maxRounds 0) 2 maxRounds))] (ReviewExchange :roundIdx 1 :maxRounds limit :draftSummary draftSummary :rejectionCount 0 :lastCritique "" :decision (revRejected)))

fn recordReviewCritique ex: ReviewExchange critique: Str -> ReviewExchange
  (let [(newRejections (+ ex.rejectionCount 1)) (curRound ex.roundIdx) (limit ex.maxRounds) (isTripped (>= newRejections limit)) (newDecision (if isTripped (revEscalated) (revRejected)))] (with ex :roundIdx (+ curRound 1) :maxRounds limit :rejectionCount newRejections :lastCritique critique :decision newDecision))

fn recordReviewApproval ex: ReviewExchange -> ReviewExchange
  (with ex :lastCritique "" :decision (revApproved))

fn isReviewTripped? ex: ReviewExchange -> Bool
  (mt ex.decision ((revEscalated) true) ((revApproved) false) ((revRejected) false))

fn isReviewPassed? ex: ReviewExchange -> Bool
  (mt ex.decision ((revApproved) true) ((revEscalated) false) ((revRejected) false))

fn formatEscalationReport ex: ReviewExchange -> Str
  (str "REVIEW ESCALATION: Mutual review ceiling reached (" (stringFromInt64 ex.rejectionCount) "/" (stringFromInt64 ex.maxRounds) " rounds). Target: \"" ex.draftSummary "\" | Last critique: " ex.lastCritique " | Awaiting human maintainer direction.")
