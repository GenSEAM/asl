(module aslGateway/tests/archiveEnginesTest
  :x [runTests]
  :i [(asl-json/json :a j) (pyText :a pt) (search :a se)])

fn hub keys: (List (Pair String String)) -> se/HubState
  (se/newHubState
    (fold (fn [(m (Map String String)) (p (Pair String String))] -> (Map String String)
            (mapSet m (pairFirst p) (pairSecond p)))
          (mapSet (mapEmpty) "PATH" "/usr/bin:/bin") keys)
    0 0 (mapEmpty) (mapEmpty))

fn resp code: Int64 body: String -> se/HttpResult
  (se/httpResp code "stub" (list) body)

fn firstResult d: j/Json -> j/Json
  (match (optionOr (pt/jget d "results") (j/jarr (list)))
    ((j/jarr xs) (optionOr (listGet xs 0) (j/jnull)))
    (_ (j/jnull)))

fn resultCount d: j/Json -> Int64
  (match (optionOr (pt/jget d "results") (j/jarr (list)))
    ((j/jarr xs) (listLength xs))
    (_ 0))

fn fieldStr v: j/Json k: String -> String
  (match (optionOr (pt/jget v k) (j/jnull))
    ((j/jstr s) s)
    (_ ""))

fn reqUrl r: (Option se/HttpReq) -> String
  (match r ((some q) q.url) ((none) ""))

fn names plan: (List (Pair String se/HttpReq)) -> (List String)
  (map (fn [(p (Pair String se/HttpReq))] -> String (pairFirst p)) plan)

fn testRequests -> Bool
  (let [(st (hub (list)))]
    (do
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "arxiv" "hello world" 3)) "https://export.arxiv.org/api/query?search_query=all:")
              "arxiv is requested only by its explicit engine name")
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "arxiv" "hello world" 3)) "&max_results=3")
              "arxiv request carries the result limit")
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "wayback" "https://example.com/" 3)) "https://archive.org/wayback/available?url=")
              "wayback uses the availability endpoint")
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "cdx" "https://example.com/" 4)) "https://web.archive.org/cdx/search/cdx?url=")
              "cdx uses the CDX endpoint")
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "cdx" "https://example.com/" 4)) "&output=json&limit=4&fl=timestamp,original,statuscode")
              "cdx request selects timestamp original and statuscode")
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "iasearch" "hello" 2)) "https://archive.org/advancedsearch.php?q=")
              "iasearch uses advancedsearch")
      (assert (pt/hasSubstr (reqUrl (se/engineReq st "iasearch" "hello" 2)) "&fl[]=identifier&fl[]=title&rows=2&output=json")
              "iasearch request selects identifier and title")
      (refute (pt/hasSubstr (reqUrl (se/engineReq st "wayback" "https://example.com/" 3)) "/save")
              "wayback availability never calls the save endpoint")
      true))

fn testArxiv -> Bool
  (let [(d (se/arxivParse (resp 200 "<feed><entry><title>Paper One</title><id>https://arxiv.org/abs/1234.5678</id><summary>Abstract one</summary></entry></feed>")))
        (r (firstResult d))]
    (do
      (assert (= (resultCount d) 1) "arxiv Atom entry becomes one row")
      (assert (= (fieldStr r "title") "Paper One") "arxiv title is parsed")
      (assert (= (fieldStr r "url") "https://arxiv.org/abs/1234.5678") "arxiv id becomes the url")
      (assert (= (fieldStr r "snippet") "Abstract one") "arxiv summary becomes the snippet")
      (assert (= (fieldStr r "engine") "arxiv") "arxiv row names its engine")
      true))

fn testWayback -> Bool
  (let [(d (se/waybackParse (resp 200 "{\"url\":\"https://example.com/\",\"archived_snapshots\":{\"closest\":{\"available\":true,\"url\":\"https://web.archive.org/web/20240102030405/https://example.com/\",\"timestamp\":\"20240102030405\",\"status\":\"200\"}}}")))
        (r (firstResult d))]
    (do
      (assert (= (resultCount d) 1) "wayback closest snapshot becomes one row")
      (assert (= (fieldStr r "title") "https://example.com/") "wayback title identifies the original url")
      (assert (pt/hasSubstr (fieldStr r "url") "20240102030405id_/https://example.com/") "wayback row uses the raw id_ page")
      (assert (pt/hasSubstr (fieldStr r "snippet") "20240102030405") "wayback snippet retains the timestamp")
      (assert (pt/hasSubstr (fieldStr r "snippet") "Closest snapshot") "wayback snippet retains the closest snapshot")
      (assert (= (fieldStr r "engine") "wayback") "wayback row names its engine")
      (assert (= (resultCount (se/waybackParse (resp 200 "{\"archived_snapshots\":{}}"))) 0) "missing wayback snapshot returns no rows")
      true))

fn testCdx -> Bool
  (let [(d (se/cdxParse (resp 200 "[[\"timestamp\",\"original\",\"statuscode\"],[\"20240102030405\",\"https://example.com/\",\"200\"]]")))
        (r (firstResult d))]
    (do
      (assert (= (resultCount d) 1) "cdx header is not returned as a result")
      (assert (= (fieldStr r "title") "https://example.com/") "cdx original becomes the title")
      (assert (pt/hasSubstr (fieldStr r "url") "example.com") "cdx original becomes the url")
      (assert (pt/hasSubstr (fieldStr r "snippet") "20240102030405") "cdx snippet retains the timestamp")
      (assert (pt/hasSubstr (fieldStr r "snippet") "200") "cdx snippet retains the status")
      (assert (= (fieldStr r "engine") "cdx") "cdx row names its engine")
      true))

fn testIasearch -> Bool
  (let [(d (se/iasearchParse (resp 200 "{\"response\":{\"docs\":[{\"identifier\":\"item-one\",\"title\":\"Item One\"}]}}")))
        (r (firstResult d))]
    (do
      (assert (= (resultCount d) 1) "iasearch document becomes one row")
      (assert (= (fieldStr r "title") "Item One") "iasearch title is parsed")
      (assert (= (fieldStr r "url") "https://archive.org/details/item-one") "iasearch identifier becomes the details url")
      (assert (pt/hasSubstr (fieldStr r "snippet") "item-one") "iasearch snippet retains the identifier")
      (assert (= (fieldStr r "engine") "iasearch") "iasearch row names its engine")
      true))

fn testDefaultNeverArchives -> Bool
  (let [(st (hub (list (pair "SYNTHETIC_API_KEY" "yk") (pair "BRAVE_API_KEY" "bk") (pair "TAVILY_API_KEY" "tk") (pair "SERPER_API_KEY" "sk"))))
        (planNames (names (se/enginePlan st "q" 5)))]
    (do
      (assert (= planNames (list "synthetic" "brave")) "default auto search plans only its existing tier")
      (refute (listContains? (se/engineOrder) "arxiv") "arxiv is outside default tier 1")
      (refute (listContains? (se/engineOrder) "wayback") "wayback is outside default tier 1")
      (refute (listContains? (se/engineOrder) "cdx") "cdx is outside default tier 1")
      (refute (listContains? (se/engineOrder) "iasearch") "iasearch is outside default tier 1")
      (refute (listContains? (se/tier2Order) "arxiv") "arxiv is outside default tier 2")
      (refute (listContains? (se/tier2Order) "wayback") "wayback is outside default tier 2")
      (refute (listContains? (se/tier2Order) "cdx") "cdx is outside default tier 2")
      (refute (listContains? (se/tier2Order) "iasearch") "iasearch is outside default tier 2")
      (refute (listContains? planNames "arxiv") "default auto search never requests arxiv")
      (refute (listContains? planNames "wayback") "default auto search never requests wayback")
      (refute (listContains? planNames "cdx") "default auto search never requests cdx")
      (refute (listContains? planNames "iasearch") "default auto search never requests iasearch")
      true))

fn testParseDispatch -> Bool
  (let [(d (se/parseEngine "iasearch" (resp 200 "{\"response\":{\"docs\":[{\"identifier\":\"dispatch\",\"title\":\"Dispatch\"}]}}") 5))]
    (do
      (assert (= (fieldStr (firstResult d) "engine") "iasearch") "engine-name dispatch reaches the archive parser")
      true))

fn runTests -> Bool
  (do
    (assert (testRequests) "testRequests passed")
    (assert (testArxiv) "testArxiv passed")
    (assert (testWayback) "testWayback passed")
    (assert (testCdx) "testCdx passed")
    (assert (testIasearch) "testIasearch passed")
    (assert (testDefaultNeverArchives) "testDefaultNeverArchives passed")
    (assert (testParseDispatch) "testParseDispatch passed")
    true)
