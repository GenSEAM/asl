(module aslHarness/evalCorpus :x [EvalInteractionPair EvalCorpus makeEvalCorpus addInteractionPair curateInteractionCorpus exportBenchmarkDataset exportPreferencePairs formatEvalPairAsn] :i [(llmClient :a lc) (traceRecorder :a tr)])

(schema EvalInteractionPair (:f pairId Str) (:f prompt Str) (:f response Str) (:f model Str) (:f verdict Str) (:f rating F64))

(schema EvalCorpus (:f corpusName Str) (:f pairs (List EvalInteractionPair)) (:f totalPairs I64))

fn makeEvalCorpus name: Str -> EvalCorpus
  (EvalCorpus :corpusName name :pairs (list) :totalPairs 0)

fn addInteractionPair corpus: EvalCorpus pair: EvalInteractionPair -> EvalCorpus
  (with corpus :pairs (listAppend corpus.pairs (list pair)) :totalPairs (+ corpus.totalPairs 1))

fn curateInteractionCorpus corpus: EvalCorpus minRating: F64 -> EvalCorpus
  (let [(filtered (fold (fn [(acc (List EvalInteractionPair)) (p EvalInteractionPair)] -> (List EvalInteractionPair) (if (>= p.rating minRating) (listAppend acc (list p)) acc)) (list) corpus.pairs))] (with corpus :pairs filtered :totalPairs (listLength filtered)))

fn formatEvalPairAsn pair: EvalInteractionPair -> Str
  (str "(:eval-pair :id \"" pair.pairId "\" :model \"" pair.model "\" :verdict \"" pair.verdict "\" :rating " (stringFromFloat64 pair.rating) " :prompt \"" pair.prompt "\" :response \"" pair.response "\")")

fn exportBenchmarkDataset corpus: EvalCorpus -> (List Str)
  (fold (fn [(acc (List Str)) (p EvalInteractionPair)] -> (List Str) (listAppend acc (list (str "(:benchmark-fixture :id \"" p.pairId "\" :prompt \"" p.prompt "\" :response \"" p.response "\" :model \"" p.model "\")")))) (list) corpus.pairs)

fn findMatchingFail prompt: Str failing: (List EvalInteractionPair) -> (Option EvalInteractionPair)
  (fold (fn [(found (Option EvalInteractionPair)) (f EvalInteractionPair)] -> (Option EvalInteractionPair) (mt found ((some _) found) ((none) (if (= f.prompt prompt) (some f) (none))))) (none) failing)

fn exportPreferencePairs corpus: EvalCorpus -> (List Str)
  (let [(passing (fold (fn [(acc (List EvalInteractionPair)) (p EvalInteractionPair)] -> (List EvalInteractionPair) (if (= p.verdict "pass") (listAppend acc (list p)) acc)) (list) corpus.pairs)) (failing (fold (fn [(acc (List EvalInteractionPair)) (p EvalInteractionPair)] -> (List EvalInteractionPair) (if (= p.verdict "fail") (listAppend acc (list p)) acc)) (list) corpus.pairs))] (fold (fn [(acc (List Str)) (passP EvalInteractionPair)] -> (List Str) (let [(matchOpt (findMatchingFail passP.prompt failing)) (targetFail (mt matchOpt ((some f) (some f)) ((none) (listHead failing))))] (mt targetFail ((some failP) (listAppend acc (list (str "(:preference-pair :prompt \"" passP.prompt "\" :chosen \"" passP.response "\" :rejected \"" failP.response "\")")))) ((none) acc)))) (list) passing))
