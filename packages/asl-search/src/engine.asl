(module aslWebApiSearch/engine :x [ProxyState ProxyNode SearchEngine SearchQuery SearchResult CurlCommand BipolarQuery isProxyHealthy selectHealthyProxies buildSearchUrl makeCurlCommand buildProviderCurlCmd cleanUrl mergeSearchResults formatResultMarkdown formatRagContext generateBipolarQuery])

(enum ProxyState (:c active [] "active proxy") (:c cooldown [] "cooldown proxy") (:c dead [] "dead proxy"))

(schema ProxyNode (:f endpoint Str) (:f state ProxyState) (:f latencyMs F64) (:f successRate F64))

(enum SearchEngine (:c ddg [] "DuckDuckGo web search") (:c wikipedia [] "Wikipedia OpenSearch") (:c github [] "GitHub code & repositories") (:c arxiv [] "arXiv scientific papers") (:c hackernews [] "HackerNews Algolia") (:c brave [] "Brave Search API") (:c google [] "Google Custom Search") (:c tavily [] "Tavily AI Search"))

(schema SearchQuery (:f text Str) (:f maxResults I64) (:f engines (List Str)))

(schema SearchResult (:f title Str) (:f url Str) (:f snippet Str) (:f engine Str) (:f score F64))

(schema CurlCommand (:f bin Str) (:f args (List Str)) (:f url Str))

fn isProxyHealthy proxy: ProxyNode -> Bool
  (and (< proxy.latencyMs 500.0) (> proxy.successRate 0.9))

fn selectHealthyProxies proxies: (List ProxyNode) -> (List ProxyNode)
  (filter isProxyHealthy proxies)

fn urlEncodeQuery q: Str -> Str
  (let [(q1 (stringReplace q "%" "%25")) (q2 (stringReplace q1 "+" "%2B")) (q3 (stringReplace q2 " " "%20")) (q4 (stringReplace q3 "&" "%26")) (q5 (stringReplace q4 "?" "%3F")) (q6 (stringReplace q5 "=" "%3D")) (q7 (stringReplace q6 "\"" "%22")) (q8 (stringReplace q7 "'" "%27"))] q8)

fn buildSearchUrl engine: Str query: Str limit: I64 -> Str
  (let [(cleanQ (urlEncodeQuery query)) (limStr (stringFromInt64 limit))] (cond ((= engine "wikipedia") (str "https://en.wikipedia.org/w/api.php?action=opensearch&search=" cleanQ "&limit=" limStr "&namespace=0&format=json")) ((= engine "github") (str "https://api.github.com/search/repositories?q=" cleanQ "&per_page=" limStr)) ((= engine "arxiv") (str "https://export.arxiv.org/api/query?search_query=all:" cleanQ "&start=0&max_results=" limStr)) ((= engine "hackernews") (str "https://hn.algolia.com/api/v1/search?query=" cleanQ "&tags=story&hitsPerPage=" limStr)) ((= engine "hn") (str "https://hn.algolia.com/api/v1/search?query=" cleanQ "&tags=story&hitsPerPage=" limStr)) ((= engine "tavily") (str "https://api.tavily.com/search?query=" cleanQ "&max_results=" limStr)) ((= engine "searxng") (str "https://searx.be/search?q=" cleanQ "&format=json")) ((= engine "serper") (str "https://google.serper.dev/search?q=" cleanQ "&num=" limStr)) ((= engine "brave") (str "https://api.search.brave.com/res/v1/web/search?q=" cleanQ "&count=" limStr)) (else (str "https://html.duckduckgo.com/html/?q=" cleanQ))))

fn makeCurlCommand url: Str timeoutSec: I64 userAgent: Str -> CurlCommand
  (let [(safeUrl (if (or (stringStartsWith? url "http://") (stringStartsWith? url "https://")) url "https://invalid.local"))] (CurlCommand :bin "curl" :args (list "-s" "--max-time" (stringFromInt64 timeoutSec) "-H" (str "User-Agent: " userAgent) "--" safeUrl) :url safeUrl))

fn buildProviderCurlCmd engine: Str url: Str apiKey: Str timeoutSec: I64 -> CurlCommand
  (let [(safeUrl (if (or (stringStartsWith? url "http://") (stringStartsWith? url "https://")) url "https://invalid.local")) (authHeader (cond ((= engine "tavily") (str "Authorization: Bearer " apiKey)) ((= engine "serper") (str "X-API-KEY: " apiKey)) ((= engine "brave") (str "X-Subscription-Token: " apiKey)) ((= engine "github") (str "Authorization: token " apiKey)) (else (str "X-API-Key: " apiKey)))) (args (list "-s" "--max-time" (stringFromInt64 timeoutSec) "-H" "Accept: application/json" "-H" authHeader "--" safeUrl))] (CurlCommand :bin "curl" :args args :url safeUrl))

fn isTrackingParam? param: Str -> Bool
  (or (stringStartsWith? param "utm_") (or (stringStartsWith? param "fbclid=") (or (stringStartsWith? param "gclid=") (stringStartsWith? param "ref="))))

fn filterQueryParams queryStr: Str -> Str
  (let [(parts (stringSplit queryStr "&")) (cleanParts (filter (fn [(p Str)] -> Bool (not (isTrackingParam? p))) parts))] (stringJoin cleanParts "&"))

fn cleanUrl url: Str -> Str
  (let [(urlParts (stringSplit url "?"))] (mt (listHead urlParts) ((none) url) ((some base) (mt (listTail urlParts) ((none) base) ((some tail) (mt (listHead tail) ((none) base) ((some rawQs) (let [(hashParts (stringSplit rawQs "#")) (pureQs (optionOr (listHead hashParts) rawQs)) (fragTail (optionOr (listTail hashParts) (list))) (fragment (if (listEmpty? fragTail) "" (str "#" (stringJoin fragTail "#")))) (cleanQs (filterQueryParams pureQs))] (if (stringEmpty? cleanQs) (str base fragment) (str base "?" cleanQs fragment))))))))))

fn updateItemOrAdd acc: (List SearchResult) item: SearchResult -> (List SearchResult)
  (let [(url item.url) (found (filter (fn [(r SearchResult)] -> Bool (= r.url url)) acc))] (if (listEmpty? found) (listAppend acc (list item)) (map (fn [(r SearchResult)] -> SearchResult (if (= r.url url) (SearchResult :title r.title :url r.url :snippet (if (> (stringLength item.snippet) (stringLength r.snippet)) item.snippet r.snippet) :engine (str r.engine "+" item.engine) :score (+ r.score item.score)) r)) acc)))

fn mergeSearchResults primary: (List SearchResult) secondary: (List SearchResult) -> (List SearchResult)
  (fold (fn [(acc (List SearchResult)) (item SearchResult)] -> (List SearchResult) (updateItemOrAdd acc item)) primary secondary)

fn escapeMarkdown s: Str -> Str
  (let [(s1 (stringReplace s "[" "\\[")) (s2 (stringReplace s1 "]" "\\]"))] s2)

fn formatResultMarkdown index: I64 res: SearchResult -> Str
  (str (stringFromInt64 index) ". **[" (escapeMarkdown res.title) "](" res.url ")**  `[" (escapeMarkdown res.engine) "]`\n   " res.snippet "\n")

fn formatResultsRagHelper items: (List SearchResult) idx: I64 -> (List Str)
  (if (listEmpty? items) (list) (let [(h (optionOr (listHead items) (SearchResult :title "" :url "" :snippet "" :engine "" :score 0.0))) (rest (optionOr (listTail items) (list)))] (cons (formatResultMarkdown idx h) (formatResultsRagHelper rest (+ idx 1)))))

fn formatRagContext query: Str items: (List SearchResult) -> Str
  (let [(header (str "## Search Results for: '" query "' (" (stringFromInt64 (listLength items)) " items)\n\n")) (formattedItems (formatResultsRagHelper items 1))] (str header (stringJoin formattedItems "\n")))

(schema BipolarQuery (:f positiveQuery Str) (:f negativeQuery Str) (:f domain Str))

fn generateBipolarQuery claim: Str domain: Str -> BipolarQuery
  (let [(d (stringLower domain)) (c (stringTrim claim)) (posSuffix (cond ((= d "architecture") "architecture design advantages performance verified") ((= d "legal") "statute authority ruling precedent compliant") ((= d "security") "audit security certified hardened protection") (else "evidence proof benefits advantages verified"))) (negSuffix (cond ((= d "architecture") "bottleneck failure overhead drawbacks anti-pattern -hype") ((= d "legal") "violation exception liability penalty repealed -opinion") ((= d "security") "exploit cve vulnerability bypass flaw -marketing") (else "failure flaws criticism disadvantages limitations -promo")))] (BipolarQuery :positiveQuery (str c " " posSuffix) :negativeQuery (str c " " negSuffix) :domain domain))
