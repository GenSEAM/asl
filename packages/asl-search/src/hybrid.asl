(module aslWebApiSearch/hybrid :x [calculateRrfScore deduplicateSerpResults mergeSerpStreams rankSerpResults] :i [(engine :a eng)])

fn calculateRrfScore rank: I64 k: I64 -> F64
  (let [(denom (int64ToFloat64 (+ k rank)))] (if (> denom 0.0) (/ 1.0 denom) 0.0))

fn addOrUpdateRrfItem acc: (List eng/SearchResult) item: eng/SearchResult rrfScore: F64 -> (List eng/SearchResult)
  (let [(cleanTarget (eng/cleanUrl item.url)) (existing (filter (fn [(r eng/SearchResult)] -> Bool (= (eng/cleanUrl r.url) cleanTarget)) acc))] (if (listEmpty? existing) (cons (eng/SearchResult :title item.title :url cleanTarget :snippet item.snippet :engine item.engine :score rrfScore) acc) (map (fn [(r eng/SearchResult)] -> eng/SearchResult (if (= (eng/cleanUrl r.url) cleanTarget) (eng/SearchResult :title r.title :url r.url :snippet (if (> (stringLength item.snippet) (stringLength r.snippet)) item.snippet r.snippet) :engine (str r.engine "+" item.engine) :score (+ r.score rrfScore)) r)) acc)))

fn indexStreamRrf items: (List eng/SearchResult) idx: I64 acc: (List eng/SearchResult) -> (List eng/SearchResult)
  (if (listEmpty? items) acc (let [(h (optionOr (listHead items) (eng/SearchResult :title "" :url "" :snippet "" :engine "" :score 0.0))) (rest (optionOr (listTail items) (list))) (score (calculateRrfScore idx 60)) (nextAcc (addOrUpdateRrfItem acc h score))] (indexStreamRrf rest (+ idx 1) nextAcc)))

fn mergeSerpStreams resultsA: (List eng/SearchResult) resultsB: (List eng/SearchResult) -> (List eng/SearchResult)
  (let [(indexedA (indexStreamRrf resultsA 1 (list))) (indexedBoth (indexStreamRrf resultsB 1 indexedA))] indexedBoth)

fn deduplicateSerpResults results: (List eng/SearchResult) -> (List eng/SearchResult)
  (fold (fn [(acc (List eng/SearchResult)) (item eng/SearchResult)] -> (List eng/SearchResult) (let [(targetUrl (eng/cleanUrl item.url)) (exists (listAny? (fn [(r eng/SearchResult)] -> Bool (= (eng/cleanUrl r.url) targetUrl)) acc))] (if exists acc (cons (eng/SearchResult :title item.title :url targetUrl :snippet item.snippet :engine item.engine :score item.score) acc)))) (list) results)

fn insertSerpResult item: eng/SearchResult sorted: (List eng/SearchResult) -> (List eng/SearchResult)
  (if (listEmpty? sorted) (list item) (let [(headS (optionOr (listHead sorted) (eng/SearchResult :title "" :url "" :snippet "" :engine "" :score 0.0))) (tailS (optionOr (listTail sorted) (list)))] (if (> item.score headS.score) (cons item sorted) (cons headS (insertSerpResult item tailS)))))

fn sortSerpResultsLoop unsorted: (List eng/SearchResult) sorted: (List eng/SearchResult) -> (List eng/SearchResult)
  (if (listEmpty? unsorted) sorted (let [(item (optionOr (listHead unsorted) (eng/SearchResult :title "" :url "" :snippet "" :engine "" :score 0.0))) (rest (optionOr (listTail unsorted) (list)))] (sortSerpResultsLoop rest (insertSerpResult item sorted))))

fn rankSerpResults results: (List eng/SearchResult) -> (List eng/SearchResult)
  (sortSerpResultsLoop results (list))
