(module aslMem/bm25 :x [Bm25Doc Bm25Index Bm25Score tokenizeTerms makeBm25Index computeIdf calcIdf scoreBm25 sortBm25Scores rankBm25] :i [(math :a m) (simhash :a sh)])

(schema Bm25Doc (:f id Str) (:f terms (List Str)) (:f length I64))

(schema Bm25Index (:f docCount I64) (:f avgDocLength F64) (:f docs (List Bm25Doc)) (:f termDocCounts (Map Str I64)))

(schema Bm25Score (:f docId Str) (:f score F64))

fn tokenizeTerms text: Str -> (List Str)
  (let [(cleaned (sh/stripPunct text)) (lowered (stringLower cleaned)) (rawTokens (stringSplit lowered " ")) (trimmed (map stringTrim rawTokens))] (filter (fn [(t Str)] -> Bool (> (stringLength t) 0)) trimmed))

fn dedupTermsLoop terms: (List Str) seen: (Map Str Bool) acc: (List Str) -> (List Str)
  (if (listEmpty? terms) acc (let [(t (optionOr (listHead terms) "")) (rest (optionOr (listTail terms) (list)))] (if (mapHas? seen t) (dedupTermsLoop rest seen acc) (dedupTermsLoop rest (mapSet seen t true) (listAppend acc (list t))))))

fn dedupTerms terms: (List Str) -> (List Str)
  (dedupTermsLoop terms (mapEmpty) (list))

fn countTermFreqLoop terms: (List Str) target: Str count: I64 -> I64
  (if (listEmpty? terms) count (let [(t (optionOr (listHead terms) "")) (rest (optionOr (listTail terms) (list)))] (if (= t target) (countTermFreqLoop rest target (+ count 1)) (countTermFreqLoop rest target count))))

fn termFrequency terms: (List Str) target: Str -> I64
  (countTermFreqLoop terms target 0)

fn updateDfCountsLoop uniqueTerms: (List Str) dfMap: (Map Str I64) -> (Map Str I64)
  (if (listEmpty? uniqueTerms) dfMap (let [(t (optionOr (listHead uniqueTerms) "")) (rest (optionOr (listTail uniqueTerms) (list))) (currDf (mt (mapGet dfMap t) ((some c) c) ((none) 0)))] (updateDfCountsLoop rest (mapSet dfMap t (+ currDf 1)))))

fn buildDfMapLoop docs: (List Bm25Doc) dfMap: (Map Str I64) -> (Map Str I64)
  (if (listEmpty? docs) dfMap (let [(d (optionOr (listHead docs) (Bm25Doc :id "" :terms (list) :length 0))) (rest (optionOr (listTail docs) (list))) (uniqueTerms (dedupTerms d.terms)) (nextDf (updateDfCountsLoop uniqueTerms dfMap))] (buildDfMapLoop rest nextDf)))

fn calcTotalLength docs: (List Bm25Doc) acc: I64 -> I64
  (if (listEmpty? docs) acc (let [(d (optionOr (listHead docs) (Bm25Doc :id "" :terms (list) :length 0))) (rest (optionOr (listTail docs) (list)))] (calcTotalLength rest (+ acc d.length))))

fn makeBm25Index docs: (List Bm25Doc) -> Bm25Index
  (let [(total (listLength docs)) (totLen (calcTotalLength docs 0)) (avgLen (if (= total 0) 0.0 (/ (int64ToFloat64 totLen) (int64ToFloat64 total)))) (dfMap (buildDfMapLoop docs (mapEmpty)))] (Bm25Index :docCount total :avgDocLength avgLen :docs docs :termDocCounts dfMap))

fn computeIdf dfCount: I64 totalDocs: I64 -> F64
  (let [(nF (int64ToFloat64 totalDocs)) (df-f (int64ToFloat64 dfCount)) (numerator (+ (- nF df-f) 0.5)) (denominator (+ df-f 0.5)) (arg (+ 1.0 (/ numerator denominator))) (rawIdf (m/fastLn arg))] (if (< rawIdf 0.01) 0.01 rawIdf))

fn calcIdf dfCount: I64 totalDocs: I64 -> F64
  (computeIdf dfCount totalDocs)

fn scoreBm25Term term: Str doc: Bm25Doc index: Bm25Index k1: F64 b: F64 -> F64
  (let [(tf (termFrequency doc.terms term))] (if (<= tf 0) 0.0 (let [(tfF (int64ToFloat64 tf)) (df-c (mt (mapGet index.termDocCounts term) ((some c) c) ((none) 0))) (idf (computeIdf df-c index.docCount)) (docLen (int64ToFloat64 doc.length)) (avgLen index.avgDocLength) (lenRatio (if (<= avgLen 0.0) 1.0 (/ docLen avgLen))) (kVal (* k1 (+ (- 1.0 b) (* b lenRatio)))) (num (* tfF (+ k1 1.0))) (denom (+ tfF kVal))] (if (<= denom 0.0) 0.0 (* idf (/ num denom))))))

fn scoreBm25Loop qTerms: (List Str) doc: Bm25Doc index: Bm25Index k1: F64 b: F64 acc: F64 -> F64
  (if (listEmpty? qTerms) acc (let [(t (optionOr (listHead qTerms) "")) (rest (optionOr (listTail qTerms) (list))) (termScore (scoreBm25Term t doc index k1 b))] (scoreBm25Loop rest doc index k1 b (+ acc termScore))))

fn scoreBm25 doc: Bm25Doc queryTerms: (List Str) index: Bm25Index k1: F64 b: F64 -> F64
  (let [(uniqueQ (dedupTerms queryTerms))] (scoreBm25Loop uniqueQ doc index k1 b 0.0))

fn insertBm25Score item: Bm25Score sorted: (List Bm25Score) -> (List Bm25Score)
  (if (listEmpty? sorted) (list item) (let [(headS (optionOr (listHead sorted) (Bm25Score :docId "" :score 0.0))) (tailS (optionOr (listTail sorted) (list)))] (if (> item.score headS.score) (cons item sorted) (cons headS (insertBm25Score item tailS)))))

fn sortBm25ScoresLoop unsorted: (List Bm25Score) sorted: (List Bm25Score) -> (List Bm25Score)
  (if (listEmpty? unsorted) sorted (let [(item (optionOr (listHead unsorted) (Bm25Score :docId "" :score 0.0))) (rest (optionOr (listTail unsorted) (list)))] (sortBm25ScoresLoop rest (insertBm25Score item sorted))))

fn sortBm25Scores scores: (List Bm25Score) -> (List Bm25Score)
  (sortBm25ScoresLoop scores (list))

fn scoreAllDocsLoop docs: (List Bm25Doc) qTerms: (List Str) index: Bm25Index k1: F64 b: F64 acc: (List Bm25Score) -> (List Bm25Score)
  (if (listEmpty? docs) acc (let [(d (optionOr (listHead docs) (Bm25Doc :id "" :terms (list) :length 0))) (rest (optionOr (listTail docs) (list))) (s (scoreBm25 d qTerms index k1 b)) (scoreRec (Bm25Score :docId d.id :score s))] (scoreAllDocsLoop rest qTerms index k1 b (listAppend acc (list scoreRec)))))

fn rankBm25 index: Bm25Index query: Str topK: I64 -> (List Bm25Score)
  (let [(qTerms (tokenizeTerms query)) (allScores (scoreAllDocsLoop index.docs qTerms index 1.5 0.75 (list))) (sorted (sortBm25Scores allScores)) (k (max 0 topK))] (listTake sorted (min (listLength sorted) k)))
