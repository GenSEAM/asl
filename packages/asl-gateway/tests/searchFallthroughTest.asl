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

fn testOrder -> Bool
  (do
    (assert (= (se/engineOrder) (list "tavily" "brave" "wiki" "serper"))
            "engine order is tavily, brave, wikipedia, serper last")
    (assert (= (listLength (se/engineOrder)) 4) "engine order has four engines")
    (assert (= (optionOr (listGet (se/engineOrder) 0) "") "tavily") "tavily is first")
    (assert (= (optionOr (listGet (se/engineOrder) 3) "") "serper") "serper is last")
    (refute (listContains? (se/engineOrder) "searxng") "no searxng in the engine order")
    (refute (listContains? (se/engineOrder) "ddg") "no html-scraping ddg in the engine order")
    true)

fn testPlan -> Bool
  (let [(noBrave (hub (list (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (withBrave (hub (list (pair "TAVILY_API_KEY" "tk") (pair "BRAVE_API_KEY" "bk") (pair "SERPER_API_KEY" "sk"))))
        (onlySerper (hub (list (pair "SERPER_API_KEY" "sk"))))]
    (do
      (assert (= (names (se/enginePlan noBrave "q" 5)) (list "tavily" "wiki" "serper"))
              "brave absent key is skipped")
      (assert (= (names (se/enginePlan withBrave "q" 5)) (list "tavily" "brave" "wiki" "serper"))
              "brave with a key sits second, before wikipedia")
      (assert (= (names (se/enginePlan onlySerper "q" 5)) (list "wiki" "serper"))
              "serper is last and only planned with a key")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "searxng") "no searxng engine is planned")
      (refute (listContains? (names (se/enginePlan withBrave "q" 5)) "ddg") "no html-scraping engine is planned")
      true))

fn testFallthrough -> Bool
  (let [(tav432 (se/tavilyParse (resp 432 "{\"detail\":\"quota\"}")))
        (braveOk (se/braveParse (resp 200 "{\"web\":{\"results\":[{\"title\":\"B\",\"url\":\"https://b.example\",\"description\":\"brave hit\"}]}}")))
        (wikiEmpty (se/wikiParse (resp 200 "[\"q\",[],[\"\"],[\"\"]]")))
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
        (wikiEmpty (se/wikiParse (resp 200 "[\"q\",[],[\"\"],[\"\"]]")))
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

fn ! runTests -> Bool
  (do
    (assert (testOrder) "testOrder passed")
    (assert (testPlan) "testPlan passed")
    (assert (testFallthrough) "testFallthrough passed")
    (assert (testAllFail) "testAllFail passed")
    (assert (testEmptyFallsThrough) "testEmptyFallsThrough passed")
    true)
