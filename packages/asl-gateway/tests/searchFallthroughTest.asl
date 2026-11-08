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
    (assert (= (se/engineOrder) (list "synthetic" "tavily" "brave" "wiki" "serper"))
            "engine order is synthetic, tavily, brave, wikipedia, serper last")
    (assert (= (listLength (se/engineOrder)) 5) "engine order has five engines")
    (assert (= (optionOr (listGet (se/engineOrder) 0) "") "synthetic") "synthetic is first")
    (assert (= (optionOr (listGet (se/engineOrder) 1) "") "tavily") "tavily is second")
    (assert (= (optionOr (listGet (se/engineOrder) 4) "") "serper") "serper is last")
    (refute (listContains? (se/engineOrder) "searxng") "no searxng in the engine order")
    (refute (listContains? (se/engineOrder) "ddg") "no html-scraping ddg in the engine order")
    true)

fn testPlan -> Bool
  (let [(noBrave (hub (list (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (withBrave (hub (list (pair "TAVILY_API_KEY" "tk") (pair "BRAVE_API_KEY" "bk") (pair "SERPER_API_KEY" "sk"))))
        (withSynth (hub (list (pair "SYNTHETIC_API_KEY" "yk") (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (onlySerper (hub (list (pair "SERPER_API_KEY" "sk"))))]
    (do
      (assert (= (names (se/enginePlan noBrave "q" 5)) (list "tavily" "wiki" "serper"))
              "brave absent key is skipped")
      (assert (= (names (se/enginePlan withBrave "q" 5)) (list "tavily" "brave" "wiki" "serper"))
              "brave with a key sits second, before wikipedia")
      (assert (= (names (se/enginePlan withSynth "q" 5)) (list "synthetic" "tavily" "wiki" "serper"))
              "synthetic with a key is planned first")
      (refute (listContains? (names (se/enginePlan noBrave "q" 5)) "synthetic")
              "missing synthetic key skips it")
      (assert (= (names (se/enginePlan onlySerper "q" 5)) (list "wiki" "serper"))
              "serper is last and only planned with a key")
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
    true)
