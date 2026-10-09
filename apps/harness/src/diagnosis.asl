(module aslHarness/diagnosis :x [DiagnosisHypothesis MinimalReproResult DiagnosisReport makeDiagnosisHypothesis makeMinimalReproResult makeDiagnosisReport ddmin pruneHypotheses selectRootCause verifyThreePointCausality runDiagnosisPipeline partitionList listDifference listContains] :i [])

(schema DiagnosisHypothesis (:f id Str) (:f component Str) (:f description Str) (:f likelihood F64) (:f isPruned Bool) (:f refutingProbe Str))

(schema MinimalReproResult (:f originalLength I64) (:f minimizedLength I64) (:f reductionRatio F64) (:f iterations I64) (:f minimizedInput (List Any)) (:f is1Minimal Bool))

(schema DiagnosisReport (:f targetProperty Str) (:f minimalRepro MinimalReproResult) (:f rootCause DiagnosisHypothesis) (:f evaluatedCount I64) (:f prunedCount I64) (:f isVerifiedCausal Bool) (:f witnessStr Str))

fn makeDiagnosisHypothesis id: Str component: Str desc: Str likelihood: F64 -> DiagnosisHypothesis
  (DiagnosisHypothesis :id id :component component :description desc :likelihood likelihood :isPruned false :refutingProbe "")

fn makeMinimalReproResult origLen: I64 minLen: I64 iters: I64 minInput: (List Any) -> MinimalReproResult
  (let [(ratio (if (> origLen 0) (/ (- (int64ToFloat64 origLen) (int64ToFloat64 minLen)) (int64ToFloat64 origLen)) 0.0))] (MinimalReproResult :originalLength origLen :minimizedLength minLen :reductionRatio ratio :iterations iters :minimizedInput minInput :is1Minimal true))

fn makeDiagnosisReport prop: Str repro: MinimalReproResult cause: DiagnosisHypothesis evalCount: I64 pruneCount: I64 verified: Bool witness: Str -> DiagnosisReport
  (DiagnosisReport :targetProperty prop :minimalRepro repro :rootCause cause :evaluatedCount evalCount :prunedCount pruneCount :isVerifiedCausal verified :witnessStr witness)

fn ddmin inputList: (List Any) failFn: (Fn [(List Any)] -> Bool) -> MinimalReproResult
  (let [(origLen (listLength inputList))] (if (<= origLen 1) (makeMinimalReproResult origLen origLen 1 inputList) (ddminLoop inputList 2 failFn origLen 0)))

fn ddminLoop c: (List Any) k: I64 failFn: (Fn [(List Any)] -> Bool) origLen: I64 stepCount: I64 -> MinimalReproResult
  (let [(n (listLength c)) (effectiveK (if (> k n) n k))] (if (<= n 1) (makeMinimalReproResult origLen n (+ stepCount 1) c) (let [(subsets (partitionList c effectiveK)) (subsetFailure (findFailingSubset subsets failFn))] (mt subsetFailure ((some failingSub) (ddminLoop failingSub 2 failFn origLen (+ stepCount (listLength subsets)))) ((none) (let [(complementFailure (findFailingComplement c subsets failFn))] (mt complementFailure ((some failingComp) (let [(nextK (if (> effectiveK 2) (- effectiveK 1) 2))] (ddminLoop failingComp nextK failFn origLen (+ stepCount (* 2 (listLength subsets)))))) ((none) (if (< effectiveK n) (let [(nextK (if (< (* 2 effectiveK) n) (* 2 effectiveK) n))] (ddminLoop c nextK failFn origLen (+ stepCount (* 2 (listLength subsets))))) (makeMinimalReproResult origLen n (+ stepCount (* 2 (listLength subsets))) c))))))))))

fn findFailingSubset subsets: (List (List Any)) failFn: (Fn [(List Any)] -> Bool) -> (Option (List Any))
  (if (listEmpty? subsets) (none) (let [(firstSub (optionOr (listHead subsets) (list))) (rest (optionOr (listTail subsets) (list)))] (if (failFn firstSub) (some firstSub) (findFailingSubset rest failFn))))

fn findFailingComplement c: (List Any) subsets: (List (List Any)) failFn: (Fn [(List Any)] -> Bool) -> (Option (List Any))
  (if (listEmpty? subsets) (none) (let [(firstSub (optionOr (listHead subsets) (list))) (rest (optionOr (listTail subsets) (list))) (complement (listDifference c firstSub))] (if (and (> (listLength complement) 0) (failFn complement)) (some complement) (findFailingComplement c rest failFn))))

fn partitionList items: (List Any) k: I64 -> (List (List Any))
  (let [(total (listLength items)) (clampedK (if (<= k 0) 1 (if (> k total) total k)))] (partitionHelper items clampedK total 0 (list)))

fn partitionHelper items: (List Any) k: I64 total: I64 idx: I64 acc: (List (List Any)) -> (List (List Any))
  (if (>= idx k) acc (let [(start (/ (* idx total) k)) (end (/ (* (+ idx 1) total) k)) (chunk (sliceList items start end)) (nextAcc (listAppend acc (list chunk)))] (partitionHelper items k total (+ idx 1) nextAcc)))

fn sliceList items: (List Any) start: I64 end: I64 -> (List Any)
  (sliceHelper items 0 start end (list))

fn sliceHelper items: (List Any) curr: I64 start: I64 end: I64 acc: (List Any) -> (List Any)
  (if (>= curr end) acc (mt (listHead items) ((none) acc) ((some headItem) (let [(tailItems (optionOr (listTail items) (list)))] (if (>= curr start) (sliceHelper tailItems (+ curr 1) start end (listAppend acc (list headItem))) (sliceHelper tailItems (+ curr 1) start end acc))))))

fn listDifference all: (List Any) toRemove: (List Any) -> (List Any)
  (mt (listHead all) ((none) (list)) ((some h) (let [(t (optionOr (listTail all) (list)))] (if (listContains toRemove h) (listDifference t toRemove) (cons h (listDifference t toRemove))))))

fn listContains lst: (List Any) item: Any -> Bool
  (mt (listHead lst) ((none) false) ((some h) (if (== h item) true (listContains (optionOr (listTail lst) (list)) item))))

fn pruneHypotheses hypotheses: (List DiagnosisHypothesis) probeResults: (List (List Any)) -> (List DiagnosisHypothesis)
  (pruneHelper hypotheses probeResults (list))

fn pruneHelper remHyp: (List DiagnosisHypothesis) probes: (List (List Any)) acc: (List DiagnosisHypothesis) -> (List DiagnosisHypothesis)
  (if (listEmpty? remHyp) acc (let [(hyp (optionOr (listHead remHyp) (makeDiagnosisHypothesis "" "" "" 0.0))) (tail (optionOr (listTail remHyp) (list))) (compId hyp.component) (refuter (findRefutingProbe compId probes))] (mt refuter ((some probeName) (let [(prunedHyp (DiagnosisHypothesis :id hyp.id :component hyp.component :description hyp.description :likelihood 0.0 :isPruned true :refutingProbe probeName))] (pruneHelper tail probes (listAppend acc (list prunedHyp))))) ((none) (pruneHelper tail probes (listAppend acc (list hyp)))))))

fn findRefutingProbe compId: Str probes: (List (List Any)) -> (Option Str)
  (if (listEmpty? probes) (none) (let [(p (optionOr (listHead probes) (list))) (tail (optionOr (listTail probes) (list))) (targetComp (optionOr (listGet p 0) "")) (isHealthy (optionOr (listGet p 1) false)) (probeId (optionOr (listGet p 2) ""))] (if (and (== targetComp compId) isHealthy) (some probeId) (findRefutingProbe compId tail))))

fn selectRootCause hypotheses: (List DiagnosisHypothesis) -> DiagnosisHypothesis
  (let [(surviving (filterUnpruned hypotheses (list)))] (if (listEmpty? surviving) (makeDiagnosisHypothesis "unknown" "none" "No surviving causal hypothesis" 0.0) (findMaxLikelihood surviving (optionOr (listHead surviving) (makeDiagnosisHypothesis "" "" "" 0.0)))))

fn filterUnpruned lst: (List DiagnosisHypothesis) acc: (List DiagnosisHypothesis) -> (List DiagnosisHypothesis)
  (if (listEmpty? lst) acc (let [(h (optionOr (listHead lst) (makeDiagnosisHypothesis "" "" "" 0.0))) (t (optionOr (listTail lst) (list)))] (if (not h.isPruned) (filterUnpruned t (listAppend acc (list h))) (filterUnpruned t acc))))

fn findMaxLikelihood lst: (List DiagnosisHypothesis) best: DiagnosisHypothesis -> DiagnosisHypothesis
  (if (listEmpty? lst) best (let [(h (optionOr (listHead lst) best)) (t (optionOr (listTail lst) (list)))] (if (> h.likelihood best.likelihood) (findMaxLikelihood t h) (findMaxLikelihood t best))))

fn verifyThreePointCausality input: (List Any) testFn: (Fn [(List Any)] -> Bool) patchFn: (Fn [(List Any)] -> (List Any)) -> Bool
  (let [(baselineFails (not (testFn input))) (patchedInput (patchFn input)) (patchedPasses (testFn patchedInput)) (revertedInput input) (revertedFails (not (testFn revertedInput)))] (and baselineFails (and patchedPasses revertedFails)))

fn runDiagnosisPipeline failingInput: (List Any) testFn: (Fn [(List Any)] -> Bool) candidateHypotheses: (List DiagnosisHypothesis) probes: (List (List Any)) patchFn: (Fn [(List Any)] -> (List Any)) -> DiagnosisReport
  (let [(isFailing (not (testFn failingInput)))] (if (not isFailing) (let [(repro (makeMinimalReproResult (listLength failingInput) 0 1 (list))) (noCause (makeDiagnosisHypothesis "none" "none" "Input already passes test" 1.0))] (makeDiagnosisReport "target" repro noCause (listLength candidateHypotheses) 0 false "Input does not fail baseline")) (let [(failCheck (fn [(subset (List Any))] (not (testFn subset)))) (minRepro (ddmin failingInput failCheck)) (prunedList (pruneHypotheses candidateHypotheses probes)) (prunedCount (countPruned prunedList 0)) (rootCause (selectRootCause prunedList)) (isCausal (verifyThreePointCausality minRepro.minimizedInput testFn patchFn)) (witness (str "Root cause " rootCause.id " in " rootCause.component " isolated via " minRepro.iterations " ddmin steps (reduced by " (roundInt (* 100.0 minRepro.reductionRatio)) "%)"))] (makeDiagnosisReport "target" minRepro rootCause (listLength candidateHypotheses) prunedCount isCausal witness))))

fn countPruned lst: (List DiagnosisHypothesis) acc: I64 -> I64
  (if (listEmpty? lst) acc (let [(h (optionOr (listHead lst) (makeDiagnosisHypothesis "" "" "" 0.0))) (t (optionOr (listTail lst) (list)))] (if h.isPruned (countPruned t (+ acc 1)) (countPruned t acc))))

fn roundInt f: F64 -> I64
  (let [(n (float64ToInt64 (+ f 0.5)))]
    (do (assert (some? n) "roundInt: f must be finite and within Int64")
        (optionOr n 0)))
