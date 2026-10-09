(module aslMem/driver :x [VectorRecord createRecord RrfScore sortRrfScores fuseRanksRrf reciprocalRankFusion] :i [(math :a m)])

(schema VectorRecord (:f id Str) (:f content Str) (:f embedding (List F64)))

(schema RrfScore (:f docId Str) (:f rrfScore F64) (:f denseRank I64) (:f bm25Rank I64))

fn createRecord id: Str text: Str emb: (List F64) -> VectorRecord
  (VectorRecord :id id :content text :embedding emb)

fn findRankLoop id: Str items: (List Str) idx: I64 -> I64
  (if (listEmpty? items) -1 (let [(h (optionOr (listHead items) "")) (rest (optionOr (listTail items) (list)))] (if (= h id) idx (findRankLoop id rest (+ idx 1)))))

fn findRank id: Str items: (List Str) -> I64
  (findRankLoop id items 1)

fn dedupStrLoop items: (List Str) seen: (Map Str Bool) acc: (List Str) -> (List Str)
  (if (listEmpty? items) acc (let [(h (optionOr (listHead items) "")) (rest (optionOr (listTail items) (list)))] (if (mapHas? seen h) (dedupStrLoop rest seen acc) (dedupStrLoop rest (mapSet seen h true) (listAppend acc (list h))))))

fn dedupStrList items: (List Str) -> (List Str)
  (dedupStrLoop items (mapEmpty) (list))

fn computeSingleRrf id: Str denseIds: (List Str) lexicalIds: (List Str) k: I64 -> RrfScore
  (let [(dRank (findRank id denseIds)) (lRank (findRank id lexicalIds)) (kF (int64ToFloat64 (max 1 k))) (dScore (if (> dRank 0) (/ 1.0 (+ kF (int64ToFloat64 dRank))) 0.0)) (lScore (if (> lRank 0) (/ 1.0 (+ kF (int64ToFloat64 lRank))) 0.0)) (totalScore (+ dScore lScore))] (RrfScore :docId id :rrfScore totalScore :denseRank dRank :bm25Rank lRank))

fn insertRrfScore item: RrfScore sorted: (List RrfScore) -> (List RrfScore)
  (if (listEmpty? sorted) (list item) (let [(headS (optionOr (listHead sorted) (RrfScore :docId "" :rrfScore 0.0 :denseRank 0 :bm25Rank 0))) (tailS (optionOr (listTail sorted) (list)))] (if (> item.rrfScore headS.rrfScore) (cons item sorted) (cons headS (insertRrfScore item tailS)))))

fn sortRrfScoresLoop unsorted: (List RrfScore) sorted: (List RrfScore) -> (List RrfScore)
  (if (listEmpty? unsorted) sorted (let [(item (optionOr (listHead unsorted) (RrfScore :docId "" :rrfScore 0.0 :denseRank 0 :bm25Rank 0))) (rest (optionOr (listTail unsorted) (list)))] (sortRrfScoresLoop rest (insertRrfScore item sorted))))

fn sortRrfScores scores: (List RrfScore) -> (List RrfScore)
  (sortRrfScoresLoop scores (list))

fn fuseRanksRrf denseIds: (List Str) lexicalIds: (List Str) k: I64 -> (List RrfScore)
  (let [(allIds (dedupStrList (listAppend denseIds lexicalIds))) (kVal (if (<= k 0) 60 k)) (scores (map (fn [(id Str)] -> RrfScore (computeSingleRrf id denseIds lexicalIds kVal)) allIds))] (sortRrfScores scores))

fn reciprocalRankFusion denseIds: (List Str) lexicalIds: (List Str) k: I64 -> (List RrfScore)
  (fuseRanksRrf denseIds lexicalIds k)
