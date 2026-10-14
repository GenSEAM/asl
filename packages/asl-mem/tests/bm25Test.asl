(module aslMem/tests/bm25Test :x [runTests testBm25RankingOrder testRrfFusionScore] :i [(bm25 :a bm) (driver :a drv) (math :a m)])

fn testFastLn -> Bool
  (let [(ln1 (m/fastLn 1.0)) (ln2 (m/fastLn 2.0))] (assert (< ln1 0.01) "ln(1.0) must be approx 0.0") (assert (> ln1 -0.01) "ln(1.0) must be approx 0.0") (assert (< ln2 0.71) "ln(2.0) must be approx 0.693") (assert (> ln2 0.67) "ln(2.0) must be approx 0.693") true)

fn testTokenizeTerms -> Bool
  (let [(tokens (bm/tokenizeTerms "Hello, World! Tokenize-this_now."))] (assert (= (listLength tokens) 5) "Tokens count must be 5") (assert (= (optionOr (listHead tokens) "") "hello") "First token must be hello") true)

fn testComputeIdf -> Bool
  (let [(idfRare (bm/computeIdf 1 100)) (idfCommon (bm/computeIdf 90 100)) (idfAll (bm/computeIdf 100 100))] (assert (> idfRare idfCommon) "Rare term IDF must exceed common term IDF") (assert (>= idfAll 0.01) "Universal term IDF must be bounded below by 0.01") true)

fn testBm25RankingOrder -> Bool
  (let [(d1 (bm/Bm25Doc :id "doc-asl" :terms (bm/tokenizeTerms "pure agentslang okapi bm25 lexical search ranking") :length 7)) (d2 (bm/Bm25Doc :id "doc-vec" :terms (bm/tokenizeTerms "dense vector embeddings cosine similarity memory store") :length 7)) (d3 (bm/Bm25Doc :id "doc-fruit" :terms (bm/tokenizeTerms "unrelated document about fresh apples and oranges") :length 7)) (index (bm/makeBm25Index (list d1 d2 d3))) (ranked (bm/rankBm25 index "okapi bm25 search" 3))] (assert (= (listLength ranked) 3) "Ranked results count must match indexed docs count") (mt (listHead ranked) ((none) (assert false "Top ranked item must exist")) ((some topS) (assert (= topS.docId "doc-asl") "Top ranked document must be doc-asl") (assert (> topS.score 0.0) "Top ranked score must be positive"))) true)

fn testTfSaturation -> Bool
  (let [(d1 (bm/Bm25Doc :id "d1" :terms (bm/tokenizeTerms "search search search search") :length 4)) (d2 (bm/Bm25Doc :id "d2" :terms (bm/tokenizeTerms "search query") :length 2)) (index (bm/makeBm25Index (list d1 d2))) (s1 (bm/scoreBm25 d1 (list "search") index 1.5 0.75)) (s2 (bm/scoreBm25 d2 (list "search") index 1.5 0.75))] (assert (> s1 0.0) "Score 1 must be positive") (assert (> s2 0.0) "Score 2 must be positive") true)

fn testRrfFusionScore -> Bool
  (let [(dense (list "item-a" "item-b" "item-c")) (lexical (list "item-b" "item-a" "item-d")) (fused (drv/fuseRanksRrf dense lexical 60))] (assert (>= (listLength fused) 4) "Fused results must contain all unique items") (mt (listHead fused) ((none) (assert false "Top fused item must exist")) ((some topItem) (assert (or (= topItem.docId "item-a") (= topItem.docId "item-b")) "Consensus items must top rank") (assert (> topItem.rrfScore 0.03) "Consensus item score must exceed 0.03"))) (mt (listGet fused 3) ((none) (assert false "Fourth fused item must exist")) ((some tailItem) (assert (< tailItem.rrfScore 0.02) "Single-source item score must be below 0.02"))) true)

fn runTests -> Bool
  (and (testFastLn) (and (testTokenizeTerms) (and (testComputeIdf) (and (testBm25RankingOrder) (and (testTfSaturation) (testRrfFusionScore))))))
