(module aslMem/rrf :x [RankedCandidate computeRrfScore fuseRankedChannels hybridCodeSearch] :i [])

(schema RankedCandidate (:f id Str) (:f score F64) (:f rank I64))

fn computeRrfScore rank: I64 k: I64 -> F64
  (if (<= rank 0) 0.0 (let [(kVal (if (<= k 0) 60 k)) (denom (+ (int64ToFloat64 kVal) (int64ToFloat64 rank)))] (/ 1.0 denom)))

fn accumulateChannel channel: (List RankedCandidate) k: I64 accMap: (Map Str F64) -> (Map Str F64)
  (if (listEmpty? channel) accMap (let [(cand (optionOr (listHead channel) (RankedCandidate :id "" :score 0.0 :rank 0))) (rest (optionOr (listTail channel) (list))) (id cand.id) (r cand.rank) (s (computeRrfScore r k)) (prev (mt (mapGet accMap id) ((some val) val) ((none) 0.0))) (nextMap (mapSet accMap id (+ prev s)))] (accumulateChannel rest k nextMap)))

fn insertCandidate item: RankedCandidate sorted: (List RankedCandidate) -> (List RankedCandidate)
  (if (listEmpty? sorted) (list item) (let [(headC (optionOr (listHead sorted) (RankedCandidate :id "" :score 0.0 :rank 0))) (tailC (optionOr (listTail sorted) (list)))] (if (> item.score headC.score) (cons item sorted) (cons headC (insertCandidate item tailC)))))

fn sortCandidatesLoop unsorted: (List RankedCandidate) sorted: (List RankedCandidate) -> (List RankedCandidate)
  (if (listEmpty? unsorted) sorted (let [(item (optionOr (listHead unsorted) (RankedCandidate :id "" :score 0.0 :rank 0))) (rest (optionOr (listTail unsorted) (list)))] (sortCandidatesLoop rest (insertCandidate item sorted))))

fn sortCandidates candidates: (List RankedCandidate) -> (List RankedCandidate)
  (sortCandidatesLoop candidates (list))

fn assignRanksLoop candidates: (List RankedCandidate) currentRank: I64 acc: (List RankedCandidate) -> (List RankedCandidate)
  (if (listEmpty? candidates) acc (let [(cand (optionOr (listHead candidates) (RankedCandidate :id "" :score 0.0 :rank 0))) (rest (optionOr (listTail candidates) (list))) (updated (RankedCandidate :id cand.id :score cand.score :rank currentRank))] (assignRanksLoop rest (+ currentRank 1) (listAppend acc (list updated)))))

fn assignRanks candidates: (List RankedCandidate) -> (List RankedCandidate)
  (assignRanksLoop candidates 1 (list))

fn mapToCandidates keys: (List Str) scores: (Map Str F64) -> (List RankedCandidate)
  (if (listEmpty? keys) (list) (let [(k (optionOr (listHead keys) "")) (rest (optionOr (listTail keys) (list))) (s (mt (mapGet scores k) ((some v) v) ((none) 0.0))) (cand (RankedCandidate :id k :score s :rank 0))] (cons cand (mapToCandidates rest scores))))

fn fuseRankedChannels channelA: (List RankedCandidate) channelB: (List RankedCandidate) k: I64 -> (List RankedCandidate)
  (let [(kVal (if (<= k 0) 60 k)) (mapA (accumulateChannel channelA kVal (mapEmpty))) (mapBoth (accumulateChannel channelB kVal mapA)) (keys (mapKeys mapBoth)) (unsorted (mapToCandidates keys mapBoth)) (sorted (sortCandidates unsorted))] (assignRanks sorted))

fn hybridCodeSearch bm25Results: (List RankedCandidate) simhashResults: (List RankedCandidate) -> (List RankedCandidate)
  (fuseRankedChannels bm25Results simhashResults 60)
