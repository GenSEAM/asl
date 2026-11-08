(module aslGateway/tests/searchFallthroughTest
  :x [runTests]
  :i [(asl-json/json :a j) (pyText :a pt) (search :a se)])

fn hub keys: (List (Pair String String)) -> se/HubState
  (se/newHubState
    (fold (fn [(m (Map String String)) (p (Pair String String))] -> (Map String String)
            (mapSet m (pairFirst p) (pairSecond p)))
          (mapSet (mapEmpty) "PATH" "/usr/bin:/bin") keys)
    0 0 (mapEmpty) (mapEmpty))

fn names plan: (List (Pair String se/HttpReq)) -> (List String)
  (map (fn [(p (Pair String se/HttpReq))] -> String (pairFirst p)) plan)

fn resp code: Int64 body: String -> se/HttpResult
  (se/httpResp code "stub" (list) body)

fn chosenName sel: (Pair (Option (Pair String j/Json)) (List j/Json)) -> String
  (match (pairFirst sel) ((some w) (pairFirst w)) ((none) ""))

fn chosenJson sel: (Pair (Option (Pair String j/Json)) (List j/Json)) -> j/Json
  (match (pairFirst sel) ((some w) (pairSecond w)) ((none) (j/jnull)))

fn resultCount d: j/Json -> Int64
  (match (optionOr (pt/jget d "results") (j/jarr (list)))
    ((j/jarr xs) (listLength xs))
    (_ 0))

fn firstResult d: j/Json -> j/Json
  (match (optionOr (pt/jget d "results") (j/jarr (list)))
    ((j/jarr xs) (optionOr (listGet xs 0) (j/jnull)))
    (_ (j/jnull)))

fn fieldStr v: j/Json k: String -> String
  (match (optionOr (pt/jget v k) (j/jnull))
    ((j/jstr s) s)
    (_ ""))

fn testOrder -> Bool
  (do
    (assert (= (se/engineOrder) (list "synthetic" "brave"))
            "tier 1 is synthetic and brave")
    (assert (= (se/tier2Order) (list "tavily" "serper"))
            "tier 2 is tavily then serper")
    (assert (= (listLength (se/engineOrder)) 2) "tier 1 has two engines")
    (assert (= (optionOr (listGet (se/engineOrder) 0) "") "synthetic") "synthetic is first in tier 1")
    (assert (= (optionOr (listGet (se/engineOrder) 1) "") "brave") "brave is second in tier 1")
    (assert (= (optionOr (listGet (se/tier2Order) 1) "") "serper") "serper is last in tier 2")
    (refute (listContains? (se/engineOrder) "wiki") "wiki is not in tier 1")
    (refute (listContains? (se/tier2Order) "wiki") "wiki is not in tier 2")
    (refute (listContains? (se/engineOrder) "searxng") "no searxng in tier 1")
    (refute (listContains? (se/engineOrder) "ddg") "no html-scraping ddg in tier 1")
    true)

fn testPlan -> Bool
  (let [(noBrave (hub (list (pair "SYNTHETIC_API_KEY" "yk") (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (withBrave (hub (list (pair "SYNTHETIC_API_KEY" "yk") (pair "TAVILY_API_KEY" "tk") (pair "BRAVE_API_KEY" "bk") (pair "SERPER_API_KEY" "sk"))))
        (onlySerper (hub (list (pair "SERPER_API_KEY" "sk"))))]
    (do
      (assert (= (names (se/enginePlan withBrave "q" 5)) (list "synthetic" "brave"))
              "synthetic and brave are planned together in tier 1")
      (assert (= (names (se/enginePlan noBrave "q" 5)) (list "synthetic"))
              "a missing brave key leaves synthetic only")
      (assert (= (names (se/enginePlan onlySerper "q" 5)) (list))
              "a tier 2 key does not add a tier 1 request")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "tavily")
              "tavily is not requested in tier 1")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "serper")
              "serper is not requested in tier 1")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "wiki")
              "wiki is never planned by default")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "searxng") "no searxng engine is planned")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "ddg") "no html-scraping engine is planned")
      true))

fn testFallthrough -> Bool
  (let [(tav432 (se/tavilyParse (resp 432 "{\"detail\":\"quota\"}")))
        (braveOk (se/braveParse (resp 200 "{\"web\":{\"results\":[{\"title\":\"B\",\"url\":\"https://b.example\",\"description\":\"brave hit\"}]}}")))
        (wikiEmpty (se/wikiParse (resp 200 "[\"q\",[],[ \"\"],[ \"\"]]")))
        (serperOk (se/serperParse (resp 200 "{\"organic\":[{\"title\":\"S\",\"link\":\"https://s.example\",\"snippet\":\"serper hit\"}]}")))
        (sel (se/selectEngine (list (pair "tavily" tav432) (pair "brave" braveOk) (pair "wiki" wikiEmpty) (pair "serper" serperOk))))]
    (do
      (assert (= (chosenName sel) "brave") "tavily 432 falls through to brave")
      (assert (= (resultCount (chosenJson sel)) 1) "brave answer is used")
      (assert (= (listLength (pairSecond sel)) 1) "the tavily 432 error is recorded while brave is used")
      true))

fn testAllFail -> Bool
  (let [(tav432 (se/tavilyParse (resp 432 "{}")))
        (brave500 (se/braveParse (resp 500 "{}")))
        (wikiEmpty (se/wikiParse (resp 200 "[\"q\",[],[ \"\"],[ \"\"]]")))
        (serperOk (se/serperParse (resp 200 "{\"organic\":[{\"title\":\"S\",\"link\":\"https://s.example\",\"snippet\":\"x\"}]}")))
        (sel (se/selectEngine (list (pair "tavily" tav432) (pair "brave" brave500) (pair "wiki" wikiEmpty) (pair "serper" serperOk))))]
    (do
      (assert (and (= (chosenName sel) "serper") (= (listLength (pairSecond sel)) 2)) "all earlier engines fail so serper is tried last and used")
      (assert (= (resultCount (chosenJson sel)) 1) "serper answer is used")
      true))

fn testEmptyFallsThrough -> Bool
  (let [(tavEmpty (se/tavilyParse (resp 200 "{\"answer\":\"\",\"results\":[]}")))
        (braveOk (se/braveParse (resp 200 "{\"web\":{\"results\":[{\"title\":\"B\",\"url\":\"https://b.example\",\"description\":\"hit\"}]}}")))
        (sel (se/selectEngine (list (pair "tavily" tavEmpty) (pair "brave" braveOk))))]
    (do
      (assert (= (chosenName sel) "brave") "zero results falls through to the next engine")
      true))

fn testSyntheticFirst -> Bool
  (let [(synthOk (se/syntheticParse (resp 200 "{\"results\":[{\"url\":\"https://syn.example\",\"title\":\"Syn\",\"text\":\"full text here\",\"highlights\":[\"hl one\",\"hl two\"]}]}")))
        (tavOk (se/tavilyParse (resp 200 "{\"answer\":\"\",\"results\":[{\"title\":\"T\",\"url\":\"https://t.example\",\"content\":\"tav hit\",\"score\":0.9}]}")))
        (sel (se/selectEngine (list (pair "synthetic" synthOk) (pair "tavily" tavOk))))
        (r (firstResult (chosenJson sel)))]
    (do
      (assert (= (chosenName sel) "synthetic") "synthetic 200 answers first")
      (assert (= (resultCount (chosenJson sel)) 1) "synthetic answer is used")
      (assert (= (listLength (pairSecond sel)) 0) "no errors when synthetic answers")
      (assert (= (fieldStr r "title") "Syn") "synthetic title is mapped")
      (assert (pt/hasSubstr (fieldStr r "url") "syn.example") "synthetic url is mapped")
      (assert (= (fieldStr r "snippet") "hl one hl two") "snippet joins highlights")
      (assert (= (fieldStr r "text") "full text here") "full text kept in :text")
      (assert (= (fieldStr r "engine") "synthetic") "engine is synthetic")
      (assert (= (pt/pyStr (optionOr (pt/jget r "score") (j/jnull))) "0.95") "synthetic score is 0.95")
      true))

fn testSyntheticSnippetFallback -> Bool
  (let [(synthNoHl (se/syntheticParse (resp 200 "{\"results\":[{\"url\":\"https://s2.example\",\"title\":\"S2\",\"text\":\"abcdef\"}]}")))
        (r (firstResult synthNoHl))]
    (do
      (assert (= (fieldStr r "snippet") "abcdef") "snippet falls back to first 300 chars of text")
      (assert (= (fieldStr r "text") "abcdef") "full text kept even when snippet falls back")
      (assert (= (fieldStr r "engine") "synthetic") "fallback item engine is synthetic")
      true))

fn testSyntheticFallthrough -> Bool
  (let [(synth429 (se/syntheticParse (resp 429 "{}")))
        (tavOk (se/tavilyParse (resp 200 "{\"answer\":\"\",\"results\":[{\"title\":\"T\",\"url\":\"https://t.example\",\"content\":\"tav hit\",\"score\":0.9}]}")))
        (sel (se/selectEngine (list (pair "synthetic" synth429) (pair "tavily" tavOk))))]
    (do
      (assert (= (chosenName sel) "tavily") "synthetic 429 falls through to tavily")
      (assert (= (resultCount (chosenJson sel)) 1) "tavily answer is used after synthetic 429")
      (assert (= (listLength (pairSecond sel)) 1) "the synthetic 429 error is recorded")
      true))

fn headerOf req: se/HttpReq name: String -> String
  (match (listHead (filter (fn [(h (Pair String String))] -> Bool (= (pt/asciiLower (pairFirst h)) name)) req.headers))
    ((some h) (pairSecond h))
    ((none) ""))

fn testSyntheticReq -> Bool
  (let [(r (se/syntheticReq "hello world" 5 "yk"))]
    (do
      (assert (= r.url "https://api.synthetic.new/v2/search") "synthetic endpoint url")
      (assert (= (headerOf r "authorization") "Bearer yk") "synthetic bearer auth header")
      (assert (= (headerOf r "content-type") "application/json") "synthetic json content type")
      (assert (pt/hasSubstr (optionOr r.data "") "hello world") "synthetic body carries the query")
      true))

fn testSyntheticEmpty -> Bool
  (let [(synthEmpty (se/syntheticParse (resp 200 "{\"results\":[]}")))
        (tavOk (se/tavilyParse (resp 200 "{\"answer\":\"\",\"results\":[{\"title\":\"T\",\"url\":\"https://t.example\",\"content\":\"tav hit\",\"score\":0.9}]}")))
        (sel (se/selectEngine (list (pair "synthetic" synthEmpty) (pair "tavily" tavOk))))]
    (do
      (assert (= (chosenName sel) "tavily") "synthetic zero results falls through to tavily")
      (assert (= (resultCount (chosenJson sel)) 1) "tavily answer used after empty synthetic")
      true))

fn testSyntheticTextCap -> Bool
  (let [(synthShort (se/syntheticParse (resp 200 "{\"results\":[{\"url\":\"https://c.example\",\"title\":\"C\",\"text\":\"short text\"}]}")))
        (r (firstResult synthShort))]
    (do
      (assert (= (fieldStr r "text") "short text") "text under the cap is kept whole")
      (assert (= (fieldStr r "snippet") "short text") "snippet falls back to text when no highlights")
      true))

fn dbl! n: Int64 s: String -> String
  (if (= n 0) s (dbl! (- n 1) (str s s)))

fn testSyntheticTextCapBoundary -> Bool
  (let [(big (pt/sliceB (dbl! 15 "a") 0 20005))
        (body (pt/jsonDumps (j/jobj (list (pair "results" (j/jarr (list (j/jobj (list (pair "url" (j/jstr "https://cap.example")) (pair "title" (j/jstr "Cap")) (pair "text" (j/jstr big))))))))) -1))
        (d (se/syntheticParse (resp 200 body)))
        (r (firstResult d))]
    (do
      (assert (= (stringLength (fieldStr r "text")) 20000) "text is capped at 20000 chars")
      (assert (= (stringLength (fieldStr r "snippet")) 300) "snippet falls back to first 300 chars of long text")
      true))

fn okJson r: (Result j/Json pt/PyErr) -> j/Json
  (match r
    ((ok v) v)
    ((err e) (j/jnull)))

fn resultAt d: j/Json i: Int64 -> j/Json
  (match (optionOr (pt/jget d "results") (j/jarr (list)))
    ((j/jarr xs) (optionOr (listGet xs i) (j/jnull)))
    (_ (j/jnull)))

fn errorRows d: j/Json -> (List j/Json)
  (match (optionOr (pt/jget d "errors") (j/jarr (list)))
    ((j/jarr xs) xs)
    (_ (list)))

fn errorCount d: j/Json -> Int64
  (listLength (errorRows d))

fn testTier1Merge -> Bool
  (let [(synthOk (se/syntheticParse (resp 200 "{\"results\":[{\"url\":\"https://same.example\",\"title\":\"Syn shared\",\"text\":\"syn text\"},{\"url\":\"https://syn-only.example\",\"title\":\"Syn only\",\"text\":\"syn only text\"}]}")))
        (braveOk (se/braveParse (resp 200 "{\"web\":{\"results\":[{\"title\":\"Brave shared\",\"url\":\"https://same.example\",\"description\":\"brave duplicate\"},{\"title\":\"Brave only\",\"url\":\"https://brave-only.example\",\"description\":\"brave only\"}]}}")))
        (d (okJson (se/tier1Select (list (pair "synthetic" synthOk) (pair "brave" braveOk)) 10)))]
    (do
      (assert (= (resultCount d) 3) "both good tier 1 answers merge without a duplicate url")
      (assert (= (fieldStr (resultAt d 0) "title") "Syn shared") "synthetic wins the shared url")
      (assert (= (fieldStr (resultAt d 0) "engine") "synthetic") "synthetic rows precede brave rows")
      (assert (= (fieldStr (resultAt d 1) "url") "https://syn-only.example") "the second synthetic row is kept")
      (assert (= (fieldStr (resultAt d 2) "title") "Brave only") "the unique brave row is kept")
      (assert (= (errorCount d) 0) "two good tier 1 answers have no errors")
      true))

fn testBraveMissingSyntheticOnly -> Bool
  (let [(st (hub (list (pair "SYNTHETIC_API_KEY" "yk") (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (synthOk (se/syntheticParse (resp 200 "{\"results\":[{\"url\":\"https://syn.example\",\"title\":\"Syn\",\"text\":\"full text\"}]}")))
        (d (okJson (se/tier1Select (list (pair "synthetic" synthOk)) 5)))]
    (do
      (assert (= (names (se/enginePlan st "q" 5)) (list "synthetic")) "without a brave key only synthetic is requested")
      (assert (= (resultCount d) 1) "the synthetic answer is kept")
      (assert (= (fieldStr (firstResult d) "engine") "synthetic") "no brave row appears without its key")
      true))

fn testTier2TavilyAfterTier1Fail -> Bool
  (let [(synth429 (se/syntheticParse (resp 429 "{}")))
        (brave500 (se/braveParse (resp 500 "{}")))
        (t1 (okJson (se/tier1Select (list (pair "synthetic" synth429) (pair "brave" brave500)) 5)))
        (tavOk (se/tavilyParse (resp 200 "{\"answer\":\"tavily answer\",\"results\":[{\"title\":\"T\",\"url\":\"https://t.example\",\"content\":\"tav hit\",\"score\":0.9}]}")))
        (serperOk (se/serperParse (resp 200 "{\"organic\":[{\"title\":\"S\",\"link\":\"https://s.example\",\"snippet\":\"serper hit\"}]}")))
        (d (okJson (se/tier2Select (list (pair "tavily" tavOk) (pair "serper" serperOk)) 5 (errorRows t1))))]
    (do
      (assert (= (resultCount t1) 0) "failed tier 1 responses produce no answer")
      (assert (= (errorCount t1) 2) "both tier 1 failures are recorded")
      (assert (= (resultCount d) 1) "tavily supplies the tier 2 answer")
      (assert (= (fieldStr (firstResult d) "engine") "tavily") "tavily is the first good tier 2 answer")
      (assert (= (fieldStr d "answer") "tavily answer") "the tavily answer text is retained")
      (assert (= (errorCount d) 2) "tier 1 errors survive the tier 2 fallback")
      true))

fn testTier2SerperAfterTavilyFail -> Bool
  (let [(tav432 (se/tavilyParse (resp 432 "{}")))
        (serperOk (se/serperParse (resp 200 "{\"organic\":[{\"title\":\"S\",\"link\":\"https://s.example\",\"snippet\":\"serper hit\"}]}")))
        (d (okJson (se/tier2Select (list (pair "tavily" tav432) (pair "serper" serperOk)) 5 (list))))]
    (do
      (assert (= (resultCount d) 1) "serper supplies the answer after tavily fails")
      (assert (= (fieldStr (firstResult d) "engine") "serper") "serper is last and used after tavily")
      (assert (= (errorCount d) 1) "the tavily failure is recorded")
      true))

fn testWikiNeverDefault -> Bool
  (let [(st (hub (list (pair "SYNTHETIC_API_KEY" "yk") (pair "BRAVE_API_KEY" "bk") (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (planNames (names (se/enginePlan st "q" 5)))]
    (do
      (refute (listContains? (se/engineOrder) "wiki") "wiki is outside the default tier 1 path")
      (refute (listContains? (se/tier2Order) "wiki") "wiki is outside the default tier 2 path")
      (refute (listContains? planNames "wiki") "no wiki request is planned by default")
      (assert (= planNames (list "synthetic" "brave")) "the default request batch contains only tier 1 engines")
      true))

fn ! runTests -> Bool
  (do
    (assert (testOrder) "testOrder passed")
    (assert (testPlan) "testPlan passed")
    (assert (testFallthrough) "testFallthrough passed")
    (assert (testAllFail) "testAllFail passed")
    (assert (testEmptyFallsThrough) "testEmptyFallsThrough passed")
    (assert (testSyntheticFirst) "testSyntheticFirst passed")
    (assert (testSyntheticSnippetFallback) "testSyntheticSnippetFallback passed")
    (assert (testSyntheticFallthrough) "testSyntheticFallthrough passed")
    (assert (testSyntheticReq) "testSyntheticReq passed")
    (assert (testSyntheticEmpty) "testSyntheticEmpty passed")
    (assert (testSyntheticTextCap) "testSyntheticTextCap passed")
    (assert (testSyntheticTextCapBoundary) "testSyntheticTextCapBoundary passed")
    (assert (testTier1Merge) "testTier1Merge passed")
    (assert (testBraveMissingSyntheticOnly) "testBraveMissingSyntheticOnly passed")
    (assert (testTier2TavilyAfterTier1Fail) "testTier2TavilyAfterTier1Fail passed")
    (assert (testTier2SerperAfterTavilyFail) "testTier2SerperAfterTavilyFail passed")
    (assert (testWikiNeverDefault) "testWikiNeverDefault passed")
    true)
