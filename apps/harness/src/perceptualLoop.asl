(module aslHarness/perceptualLoop :x [PerceptualCandidate PerceptualLoopResult makePerceptualCandidate makePerceptualLoopResult calculateCompositeLoss detectBlurAttack evaluateConjointGate spatialPatchRefinement runPerceptualLoop defaultWeights defaultTolerances] :i [])

(schema PerceptualCandidate (:f id Str) (:f params (List F64)) (:f ssim F64) (:f chamfer F64) (:f deltaE F64) (:f compositeLoss F64) (:f isBlurAttack Bool) (:f accepted Bool))

(schema PerceptualLoopResult (:f iterations I64) (:f converged Bool) (:f initialLoss F64) (:f finalLoss F64) (:f lossReduction F64) (:f rejectedCount I64) (:f bestCandidate PerceptualCandidate) (:f history (List PerceptualCandidate)))

fn defaultWeights -> (List F64)
  (list 0.4 0.4 0.2)

fn defaultTolerances -> (List F64)
  (list 0.85 0.15 0.20)

fn calculateCompositeLoss ssim: F64 chamfer: F64 deltaE: F64 wSsim: F64 wChamfer: F64 wDeltaE: F64 -> F64
  (let [(clampedSsim (if (< ssim 0.0) 0.0 (if (> ssim 1.0) 1.0 ssim))) (ssimLoss (- 1.0 clampedSsim)) (termSsim (* wSsim ssimLoss)) (termChamfer (* wChamfer chamfer)) (termDeltaE (* wDeltaE deltaE))] (+ termSsim (+ termChamfer termDeltaE)))

fn detectBlurAttack ssim: F64 chamfer: F64 ssimThresh: F64 chamferThresh: F64 -> Bool
  (and (>= ssim ssimThresh) (> chamfer chamferThresh))

fn makePerceptualCandidate id: Str params: (List F64) ssim: F64 chamfer: F64 deltaE: F64 weights: (List F64) -> PerceptualCandidate
  (let [(w1 (optionOr (listGet weights 0) 0.4)) (w2 (optionOr (listGet weights 1) 0.4)) (w3 (optionOr (listGet weights 2) 0.2)) (loss (calculateCompositeLoss ssim chamfer deltaE w1 w2 w3)) (isBlur (detectBlurAttack ssim chamfer 0.88 0.12))] (PerceptualCandidate :id id :params params :ssim ssim :chamfer chamfer :deltaE deltaE :compositeLoss loss :isBlurAttack isBlur :accepted false))

fn evaluateConjointGate candidate: PerceptualCandidate currentBestLoss: F64 tolerances: (List F64) -> Bool
  (let [(ssimMin (optionOr (listGet tolerances 0) 0.85)) (chamferMax (optionOr (listGet tolerances 1) 0.15)) (deltaEMax (optionOr (listGet tolerances 2) 0.20)) (isBlur candidate.isBlurAttack) (chamfer candidate.chamfer) (deltaE candidate.deltaE) (loss candidate.compositeLoss)] (if isBlur false (if (> chamfer chamferMax) false (if (> deltaE deltaEMax) false (< loss currentBestLoss)))))

fn spatialPatchRefinement baseCand: PerceptualCandidate stepId: Str deltaParams: (List F64) newSsim: F64 newChamfer: F64 newDeltaE: F64 weights: (List F64) -> PerceptualCandidate
  (let [(oldParams baseCand.params) (refinedParams (addParamVectors oldParams deltaParams)) (cand (makePerceptualCandidate stepId refinedParams newSsim newChamfer newDeltaE weights))] cand)

fn addParamVectors v1: (List F64) v2: (List F64) -> (List F64)
  (if (listEmpty? v1) v2 (if (listEmpty? v2) v1 (let [(h1 (optionOr (listHead v1) 0.0)) (t1 (optionOr (listTail v1) (list))) (h2 (optionOr (listHead v2) 0.0)) (t2 (optionOr (listTail v2) (list))) (sum (+ h1 h2))] (cons sum (addParamVectors t1 t2)))))

fn runPerceptualLoop initialCand: PerceptualCandidate candidateProposals: (List PerceptualCandidate) maxIter: I64 convergenceTol: F64 tolerances: (List F64) -> PerceptualLoopResult
  (let [(effectiveMax (if (> maxIter 3) 3 maxIter)) (initialLoss initialCand.compositeLoss)] (loopStep 0 effectiveMax initialCand initialCand (list initialCand) 0 candidateProposals convergenceTol tolerances initialLoss))

fn loopStep iter: I64 maxIter: I64 bestCand: PerceptualCandidate currCand: PerceptualCandidate history: (List PerceptualCandidate) rejected: I64 remainingProposals: (List PerceptualCandidate) tol: F64 tolerances: (List F64) initialLoss: F64 -> PerceptualLoopResult
  (let [(bestLoss bestCand.compositeLoss)] (if (or (>= iter maxIter) (<= bestLoss tol) (listEmpty? remainingProposals)) (let [(converged (<= bestLoss tol)) (finalLoss bestLoss) (reduction (- initialLoss finalLoss))] (PerceptualLoopResult :iterations iter :converged converged :initialLoss initialLoss :finalLoss finalLoss :lossReduction reduction :rejectedCount rejected :bestCandidate bestCand :history history)) (let [(proposal (optionOr (listHead remainingProposals) bestCand)) (restProposals (optionOr (listTail remainingProposals) (list))) (passed (evaluateConjointGate proposal bestLoss tolerances))] (if passed (let [(acceptedCand (markAccepted proposal true)) (newHistory (listAppend history (list acceptedCand)))] (loopStep (+ iter 1) maxIter acceptedCand acceptedCand newHistory rejected restProposals tol tolerances initialLoss)) (let [(rejectedCand (markAccepted proposal false)) (newHistory (listAppend history (list rejectedCand)))] (loopStep (+ iter 1) maxIter bestCand currCand newHistory (+ rejected 1) restProposals tol tolerances initialLoss))))))

fn markAccepted cand: PerceptualCandidate status: Bool -> PerceptualCandidate
  (with cand :accepted status)
