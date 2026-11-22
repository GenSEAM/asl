(module aslGateway/research
  :x [asnAtom asnRead asnProps asnScalar asnText asnRepr
      classifySourceKind extractOutermostSexpr stripTagsAndWhitespace extractHtmlTables extractHtmlCodeBlocks isSpaShell isWafChallenge
      fetchReq fetchResult fetchSinglePage! parallelCrawlDistill!
      researchPrompt researchEntryLabel researchEntryProvider researchCall! breakerDownFor
      researchDebracket researchParse researchNorm researchWords researchQuoteFound researchVerify researchAuditPrompt researchAudit!
      auditVerdicts researchRelation researchExtract! executeResearchHub! researchRelationAsn formatResearchAsn
      researchModeOf researchParts subQueries executeResearchPlan! stageSeconds stageEntry wallLeftMs
      searchKeyNames withSearchKeys! researchEntryJson researchRoutesFor! researchGatewayRoutes! resolveResearchEntry! routeUpstream researchDepth researchModeAt! researchPipeline!]
  :i [(asl-json/json :a j)
      (pyText :a pt)
      (search :a srch)
      (config :a cfg)])

fn asnAtom s: String -> j/Json
  (j/jobj (list (pair "atom" (j/jstr s))))

fn atomOf v: j/Json -> (Option String)
  (match v
    ((j/jobj kvs) (if (= (listLength kvs) 1) (match (pt/jget v "atom") ((some a) (match a ((j/jstr s) (some s)) (_ (none)))) ((none) (none))) (none)))
    (_ (none)))

fn valueErr msg: String -> pt/PyErr
  (pt/pyErr "ValueError" msg)

fn cpOffset text: String b: Int64 -> String
  (stringFromInt64 (pt/cpCount (pt/sliceB text 0 b)))

fn pushForm stack: (List (List j/Json)) forms: (List j/Json) v: j/Json -> (Pair (List (List j/Json)) (List j/Json))
  (match (listHead stack)
    ((none) (pair stack (cons v forms)))
    ((some top) (pair (cons (cons v top) (optionOr (listTail stack) (list))) forms)))

fn atomEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (>= j n)
    j
    (let [(c (bytesGet bs j))]
      (if (or (= c 32) (= c 9) (= c 13) (= c 10) (= c 40) (= c 41) (= c 34) (= c 59)) j (atomEnd bs n (+ j 1)))))

fn strEnd text: String bs: Bytes n: Int64 start: Int64 j: Int64 seg: Int64 acc: (List String) -> (Result (Pair String Int64) pt/PyErr)
  (if (>= j n)
    (err (valueErr (str "unterminated string at offset " (cpOffset text start))))
    (let [(c (bytesGet bs j))]
      (cond
        ((= c 34) (ok (pair (pt/treeJoin (listReverse (cons (pt/sliceB text seg j) acc))) (+ j 1))))
        ((= c 92)
          (let [(d (if (< (+ j 1) n) (bytesGet bs (+ j 1)) -1))
                (rep (cond ((= d 92) "\\") ((= d 34) "\"") ((= d 110) "\n") ((= d 116) "\t") (else "")))]
            (if (stringEmpty? rep)
              (err (valueErr (str "bad string escape at offset " (cpOffset text j))))
              (strEnd text bs n start (+ j 2) (+ j 2) (cons rep (cons (pt/sliceB text seg j) acc))))))
        (else (strEnd text bs n start (+ j 1) seg acc)))))

fn readLoop text: String bs: Bytes n: Int64 i: Int64 stack: (List (List j/Json)) forms: (List j/Json) -> (Result (List j/Json) pt/PyErr)
  (if (>= i n)
    (if (listEmpty? stack) (ok (listReverse forms)) (err (valueErr (str (stringFromInt64 (listLength stack)) " unclosed ( at end of text"))))
    (let [(c (bytesGet bs i))]
      (cond
        ((or (= c 32) (= c 9) (= c 13) (= c 10)) (readLoop text bs n (+ i 1) stack forms))
        ((= c 59) (let [(k (pt/findFrom bs n (stringToBytes "\n") 1 i))] (readLoop text bs n (if (< k 0) n (+ k 1)) stack forms)))
        ((= c 40) (readLoop text bs n (+ i 1) (cons (list) stack) forms))
        ((= c 41)
          (match (listHead stack)
            ((none) (err (valueErr (str "unbalanced ) at offset " (cpOffset text i)))))
            ((some top)
              (let [(p (pushForm (optionOr (listTail stack) (list)) forms (j/jarr (listReverse top))))]
                (readLoop text bs n (+ i 1) (pairFirst p) (pairSecond p))))))
        ((= c 34)
          (match (strEnd text bs n i (+ i 1) (+ i 1) (list))
            ((err e) (err e))
            ((ok r) (let [(p (pushForm stack forms (j/jstr (pairFirst r))))] (readLoop text bs n (pairSecond r) (pairFirst p) (pairSecond p))))))
        (else
          (let [(k (atomEnd bs n i)) (p (pushForm stack forms (asnAtom (pt/sliceB text i k))))]
            (readLoop text bs n k (pairFirst p) (pairSecond p)))))))

fn asnRead text: String -> (Result (List j/Json) pt/PyErr)
  (let [(bs (stringToBytes text))] (readLoop text bs (bytesLength bs) 0 (list) (list)))

fn asnRepr v: j/Json -> String
  (match (atomOf v)
    ((some s) (pt/pyRepr (j/jstr s)))
    ((none) (match v ((j/jarr xs) (str "[" (pt/joinSep (map asnRepr xs) ", ") "]")) (_ (pt/pyRepr v)))))

fn asnText v: j/Json -> String
  (match (atomOf v)
    ((some s) s)
    ((none) (match v ((j/jstr s) s) ((j/jarr _) (asnRepr v)) (_ (pt/pyStr v)))))

fn propsLoop what: String rest: (List j/Json) acc: j/Json -> (Result j/Json pt/PyErr)
  (match (listHead rest)
    ((none) (ok acc))
    ((some k)
      (let [(tail (optionOr (listTail rest) (list)))
            (v (optionOr (listHead tail) (j/jnull)))
            (name (optionOr (atomOf k) ""))]
        (if (or (none? (atomOf k)) (not (stringStartsWith? name ":")) (< (pt/cpCount name) 2))
          (err (valueErr (str what ": " (asnRepr k) " is not a :keyword")))
          (propsLoop what (optionOr (listTail tail) (list)) (pt/jset acc (pt/sliceB name 1 (stringLength name)) v))))))

fn asnProps form: j/Json head: (Option String) -> (Result j/Json pt/PyErr)
  (let [(what (match head ((some h) (str "(" h " ...)")) ((none) "a property list")))]
    (match form
      ((j/jarr xs)
        (let [(headOk (match head
                        ((none) (ok xs))
                        ((some h)
                          (match (listHead xs)
                            ((none) (err (valueErr (str "expected " what ", found ( ...)"))))
                            ((some f0) (if (= (atomOf f0) (some h)) (ok (optionOr (listTail xs) (list))) (err (valueErr (str "expected " what ", found (" (asnText f0) " ...)")))))))))]
          (match headOk
            ((err e) (err e))
            ((ok rest)
              (if (= (mod (listLength rest) 2) 1)
                (err (valueErr (str what " has an odd number of items")))
                (propsLoop what rest (j/jobj (list))))))))
      (_ (err (valueErr (str "expected " what ", found " (asnRepr form)))))))

fn allDigits bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (let [(c (bytesGet bs i))] (and (>= c 48) (<= c 57) (allDigits bs (+ i 1) n))))

fn stripLeadingZeros s: String -> String
  (if (and (> (stringLength s) 1) (stringStartsWith? s "0") (not (stringStartsWith? s "0."))) (stripLeadingZeros (pt/sliceB s 1 (stringLength s))) s)

fn lstripColon s: String -> String
  (if (stringStartsWith? s ":") (lstripColon (pt/sliceB s 1 (stringLength s))) s)

fn asnScalar v: j/Json -> j/Json
  (match (atomOf v)
    ((none) v)
    ((some s)
      (let [(neg (stringStartsWith? s "-"))
            (body (if neg (pt/sliceB s 1 (stringLength s)) s))
            (bb (stringToBytes body))
            (nb (bytesLength bb))
            (dot (optionOr (stringIndexOf body ".") -1))]
        (cond
          ((= s "true") (j/jbool true))
          ((= s "false") (j/jbool false))
          ((and (> nb 0) (allDigits bb 0 nb))
            (match (stringToInt64 s)
              ((some k) (j/jint k))
              ((none) (match (pt/jsonLoads (str (if neg "-" "") (stripLeadingZeros body) ".0")) ((ok f) f) ((err _) (j/jstr s))))))
          ((and (> dot 0) (< dot (- nb 1)) (allDigits bb 0 dot) (allDigits bb (+ dot 1) nb))
            (match (pt/jsonLoads (str (if neg "-" "") (stripLeadingZeros body))) ((ok f) f) ((err _) (j/jstr s))))
          (else (j/jstr (lstripColon s)))))))

fn anyIn u: String ds: (List String) -> Bool
  (listAny? (fn [(d String)] -> Bool (pt/hasSubstr u d)) ds)

fn classifySourceKind url: String -> String
  (let [(u (pt/pyLower url))]
    (cond
      ((anyIn u (list "arxiv.org" "doi.org" "biorxiv.org")) "peerReviewed")
      ((anyIn u (list "github.com" "gitlab.com" "ietf.org" "/docs" "docs.")) "primaryArtifact")
      ((anyIn u (list "wikipedia.org" "stackoverflow.com" "stackexchange.com")) "crowdsourced")
      ((anyIn u (list "medium.com" "dev.to" "substack.com" "news." "/blog")) "secondaryReport")
      (else "unverifiedWeb")))

fn sexprScan text: String bs: Bytes n: Int64 start: Int64 i: Int64 stack: (List Int64) inStr: Bool esc: Bool -> (Option String)
  (if (>= i n)
    (none)
    (let [(c (bytesGet bs i))]
      (cond
        (esc (sexprScan text bs n start (+ i 1) stack inStr false))
        ((= c 92) (sexprScan text bs n start (+ i 1) stack inStr true))
        ((= c 34) (sexprScan text bs n start (+ i 1) stack (not inStr) false))
        (inStr (sexprScan text bs n start (+ i 1) stack inStr false))
        ((or (= c 40) (= c 91)) (sexprScan text bs n start (+ i 1) (cons c stack) inStr false))
        ((or (= c 41) (= c 93))
          (let [(want (if (= c 41) 40 91))]
            (match (listHead stack)
              ((none) (none))
              ((some top)
                (if (not (= top want))
                  (none)
                  (let [(rest (optionOr (listTail stack) (list)))]
                    (if (listEmpty? rest) (some (pt/sliceB text start (+ i 1))) (sexprScan text bs n start (+ i 1) rest inStr false))))))))
        (else (sexprScan text bs n start (+ i 1) stack inStr false)))))

fn extractOutermostSexpr text: String -> (Option String)
  (if (stringEmpty? text)
    (none)
    (let [(start (fold (fn [(acc Int64) (root String)] -> Int64 (if (>= acc 0) acc (optionOr (stringIndexOf text root) -1)))
                       -1 (list "(:researchReport" "(:researchTriage" "(:searchResults" "(:rawEvidence" "(:")))]
      (if (< start 0)
        (none)
        (let [(bs (stringToBytes text))] (sexprScan text bs (bytesLength bs) start start (list) false false)))))

fn ciAt bs: Bytes n: Int64 i: Int64 lit: String -> Bool
  (let [(lb (stringToBytes lit)) (m (bytesLength lb))]
    (and (<= (+ i m) n) (ciLoop bs i lb 0 m)))

fn ciLoop bs: Bytes i: Int64 lb: Bytes k: Int64 m: Int64 -> Bool
  (if (>= k m) true (and (= (pt/lowerAsciiByte (bytesGet bs (+ i k))) (pt/lowerAsciiByte (bytesGet lb k))) (ciLoop bs i lb (+ k 1) m)))

fn findLit bs: Bytes n: Int64 lit: String from: Int64 -> Int64
  (pt/findFrom bs n (stringToBytes lit) (stringLength lit) from)

fn findCi bs: Bytes n: Int64 lit: String from: Int64 -> Int64
  (pt/findFromCi bs n (stringToBytes lit) (stringLength lit) from)

fn tagPass s: String bs: Bytes n: Int64 i: Int64 seg: Int64 acc: (List String) m: (fn [Int64] -> (Option (Pair Int64 String))) -> String
  (let [(k (findLit bs n "<" i))]
    (if (< k 0)
      (pt/treeJoin (listReverse (cons (pt/sliceB s seg n) acc)))
      (match (m k)
        ((some r) (tagPass s bs n (pairFirst r) (pairFirst r) (cons (pairSecond r) (cons (pt/sliceB s seg k) acc)) m))
        ((none) (tagPass s bs n (+ k 1) seg acc m)))))

fn runPass s: String m: (fn [String Bytes Int64 Int64] -> (Option (Pair Int64 String))) -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (tagPass s bs n 0 0 (list) (fn [(k Int64)] -> (Option (Pair Int64 String)) (m s bs n k))))

fn commentPass s: String bs: Bytes n: Int64 i: Int64 seg: Int64 acc: (List String) -> String
  (let [(k (findLit bs n "<!--" i))]
    (if (< k 0)
      (pt/treeJoin (listReverse (cons (pt/sliceB s seg n) acc)))
      (let [(c (findLit bs n "-->" (+ k 4)))]
        (if (< c 0)
          (pt/treeJoin (listReverse (cons (pt/sliceB s seg n) acc)))
          (commentPass s bs n (+ c 3) (+ c 3) (cons " " (cons (pt/sliceB s seg k) acc)))))))

fn blockTag s: String bs: Bytes n: Int64 k: Int64 -> (Option (Pair Int64 String))
  (match (listHead (filter (fn [(t String)] -> Bool (ciAt bs n (+ k 1) t)) (list "script" "style" "nav" "header" "footer" "noscript" "svg")))
    ((none) (none))
    ((some t)
      (let [(e (findLit bs n ">" (+ k 1 (stringLength t))))]
        (if (< e 0)
          (none)
          (let [(close (str "</" t ">")) (c (findCi bs n close (+ e 1)))]
            (if (< c 0) (none) (some (pair (+ c (stringLength close)) " "))))))))

fn isH16 b: Int64 -> Bool
  (and (>= b 49) (<= b 54))

fn headingClose bs: Bytes n: Int64 from: Int64 -> Int64
  (let [(c (findCi bs n "</h" from))]
    (cond
      ((< c 0) -1)
      ((and (< (+ c 4) n) (isH16 (bytesGet bs (+ c 3))) (= (bytesGet bs (+ c 4)) 62)) c)
      (else (headingClose bs n (+ c 1)))))

fn headingTag s: String bs: Bytes n: Int64 k: Int64 -> (Option (Pair Int64 String))
  (if (and (< (+ k 2) n) (= (pt/lowerAsciiByte (bytesGet bs (+ k 1))) 104) (isH16 (bytesGet bs (+ k 2))))
    (let [(e (findLit bs n ">" (+ k 3)))]
      (if (< e 0)
        (none)
        (let [(c (headingClose bs n (+ e 1)))]
          (if (< c 0) (none) (some (pair (+ c 5) (str "\n\n# " (pt/sliceB s (+ e 1) c) "\n\n")))))))
    (none))

fn wsEnd s: String bs: Bytes n: Int64 j: Int64 -> Int64
  (if (>= j n)
    j
    (let [(b (bytesGet bs j))]
      (if (< b 128)
        (if (pt/isPySpace b) (wsEnd s bs n (+ j 1)) j)
        (let [(cps (pt/cpList (pt/cpPrefix (pt/sliceB s j (min n (+ j 4))) 1)))
              (cp (optionOr (listHead cps) 0))]
          (if (pt/isPySpace cp) (wsEnd s bs n (+ j (stringLength (pt/cpEncode cp)))) j)))))

fn brTag s: String bs: Bytes n: Int64 k: Int64 -> (Option (Pair Int64 String))
  (if (ciAt bs n (+ k 1) "br")
    (let [(j0 (wsEnd s bs n (+ k 3)))
          (j1 (if (and (< j0 n) (= (bytesGet bs j0) 47)) (+ j0 1) j0))]
      (if (and (< j1 n) (= (bytesGet bs j1) 62)) (some (pair (+ j1 1) "\n")) (none)))
    (none))

fn blockBreakTag s: String bs: Bytes n: Int64 k: Int64 -> (Option (Pair Int64 String))
  (let [(j0 (if (and (< (+ k 1) n) (= (bytesGet bs (+ k 1)) 47)) (+ k 2) (+ k 1)))]
    (match (listHead (filter (fn [(t String)] -> Bool (ciAt bs n j0 t)) (list "p" "div" "section" "article" "li")))
      ((none) (none))
      ((some t)
        (let [(e (findLit bs n ">" (+ j0 (stringLength t))))]
          (if (< e 0) (none) (some (pair (+ e 1) "\n")))))))

fn nonEmptyLines s: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map (fn [(l String)] -> String (pt/pyStrip (pt/collapseWs l))) (stringSplit s "\n")))

fn stripTagsAndWhitespace raw: String -> String
  (if (stringEmpty? raw)
    ""
    (let [(bs0 (stringToBytes raw))
          (s1 (commentPass raw bs0 (bytesLength bs0) 0 0 (list)))
          (s2 (runPass s1 blockTag))
          (s3 (runPass s2 headingTag))
          (s4 (runPass s3 brTag))
          (s5 (runPass s4 blockBreakTag))
          (s6 (pt/stripTagRegex s5 " "))
          (s7 (pt/htmlUnescape s6))]
      (pt/joinSep (nonEmptyLines s7) "\n")))

fn findTagged s: String bs: Bytes n: Int64 open: String close: String i: Int64 acc: (List String) -> (List String)
  (let [(k (findCi bs n open i))]
    (if (< k 0)
      (listReverse acc)
      (let [(e (findLit bs n ">" (+ k (stringLength open))))]
        (if (< e 0)
          (listReverse acc)
          (let [(c (findCi bs n close (+ e 1)))]
            (if (< c 0)
              (findTagged s bs n open close (+ k 1) acc)
              (findTagged s bs n open close (+ c (stringLength close)) (cons (pt/sliceB s (+ e 1) c) acc))))))))

fn tagged s: String open: String close: String -> (List String)
  (let [(bs (stringToBytes s))] (findTagged s bs (bytesLength bs) open close 0 (list)))

fn cellText c: String -> String
  (pt/pyStrip (pt/htmlUnescape (pt/stripTagRegex c "")))

fn tableOf tHtml: String maxRows: Int64 -> (Option j/Json)
  (let [(rows (listTake (tagged tHtml "<tr" "</tr>") (max maxRows 0)))
        (acc (fold (fn [(acc (Pair (List j/Json) (List j/Json))) (p (Pair Int64 String))] -> (Pair (List j/Json) (List j/Json))
                     (let [(ths (tagged (pairSecond p) "<th" "</th>"))
                           (tds (tagged (pairSecond p) "<td" "</td>"))
                           (cells (map (fn [(c String)] -> j/Json (j/jstr (cellText c))) (if (listEmpty? ths) tds ths)))]
                       (cond
                         ((and (= (pairFirst p) 0) (not (listEmpty? ths))) (pair cells (pairSecond acc)))
                         ((not (listEmpty? cells)) (pair (pairFirst acc) (listAppend (pairSecond acc) (list (j/jarr cells)))))
                         (else acc))))
                   (pair (list) (list)) (enumerate rows)))]
    (if (and (listEmpty? (pairFirst acc)) (listEmpty? (pairSecond acc)))
      (none)
      (some (j/jobj (list (pair "cols" (j/jarr (pairFirst acc))) (pair "rows" (j/jarr (pairSecond acc))))))))

fn extractHtmlTables raw: String maxTables: Int64 maxRows: Int64 -> j/Json
  (j/jarr (fold (fn [(acc (List j/Json)) (t String)] -> (List j/Json) (match (tableOf t maxRows) ((some x) (listAppend acc (list x))) ((none) acc)))
                (list) (listTake (tagged raw "<table" "</table>") (max maxTables 0))))

fn classChar b: Int64 -> Bool
  (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90)) (and (>= b 48) (<= b 57)) (= b 95) (= b 45))

fn classRunEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (classChar (bytesGet bs j))) (classRunEnd bs n (+ j 1)) j)

fn isQuote bs: Bytes n: Int64 j: Int64 -> Bool
  (and (< j n) (or (= (bytesGet bs j) 34) (= (bytesGet bs j) 39)))

fn classWithPrefix bs: Bytes n: Int64 q: Int64 prefixes: (List String) -> (Option (Pair Int64 Int64))
  (match (listHead prefixes)
    ((none) (none))
    ((some pfx)
      (let [(rest (optionOr (listTail prefixes) (list)))]
        (if (ciAt bs n q pfx)
          (let [(a (+ q (stringLength pfx))) (b (classRunEnd bs n a))]
            (if (and (> b a) (isQuote bs n b)) (some (pair a b)) (classWithPrefix bs n q rest)))
          (classWithPrefix bs n q rest)))))

fn codeClass s: String bs: Bytes n: Int64 j: Int64 -> (Option (Pair Int64 Int64))
  (let [(w (wsEnd s bs n j))]
    (if (and (> w j) (ciAt bs n w "class=") (isQuote bs n (+ w 6)))
      (classWithPrefix bs n (+ w 7) (list "language-" "lang-" ""))
      (none)))

fn codeMatch s: String -> (Option (Pair String String))
  (let [(bs (stringToBytes s)) (n (bytesLength bs))] (codeAt s bs n 0))

fn codeAt s: String bs: Bytes n: Int64 i: Int64 -> (Option (Pair String String))
  (let [(k (findCi bs n "<code" i))]
    (if (< k 0)
      (none)
      (let [(cls (codeClass s bs n (+ k 5)))
            (e (findLit bs n ">" (+ k 5)))
            (c (if (< e 0) -1 (findCi bs n "</code>" (+ e 1))))]
        (if (< c 0)
          (codeAt s bs n (+ k 1))
          (some (pair (match cls ((some r) (pt/sliceB s (pairFirst r) (pairSecond r))) ((none) "")) (pt/sliceB s (+ e 1) c)))))))

fn extractHtmlCodeBlocks raw: String maxBlocks: Int64 -> j/Json
  (j/jarr (fold (fn [(acc (List j/Json)) (p String)] -> (List j/Json)
                  (let [(m (codeMatch p))
                        (lang (match m ((some x) (pairFirst x)) ((none) "")))
                        (code (cellText (match m ((some x) (pairSecond x)) ((none) p))))]
                    (if (stringEmpty? code) acc (listAppend acc (list (j/jobj (list (pair "lang" (j/jstr lang)) (pair "code" (j/jstr (pt/cpPrefix code 500))))))))))
                (list) (listTake (tagged raw "<pre" "</pre>") (max maxBlocks 0))))

fn isSpaShell raw: String clean: String -> Bool
  (and (< (pt/cpCount clean) 300)
       (anyIn raw (list "id=\"root\"" "id='root'" "id=\"app\"" "id='app'" "id=\"__next\"" "id='__next'")))

fn isWafChallenge code: Int64 body: String -> Bool
  (or (listContains? (list 403 503 429) code)
      (anyIn (pt/pyLower body) (list "just a moment..." "checking your browser" "attention required! | cloudflare" "cf-chl-bypass" "please complete the security check")))

fn fetchReq url: String timeout: j/Json -> srch/HttpReq
  (srch/HttpReq :url url
    :headers (list (pair "User-Agent" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36")
                   (pair "Accept" "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
                   (pair "Accept-Language" "en-US,en;q=0.9")
                   (pair "Sec-CH-UA" "\"Chromium\";v=\"128\", \"Not;A=Brand\";v=\"24\", \"Google Chrome\";v=\"128\"")
                   (pair "Sec-Fetch-Dest" "document")
                   (pair "Sec-Fetch-Mode" "navigate")
                   (pair "Sec-Fetch-Site" "none"))
    :data (none) :timeout timeout)

fn notCrawled url: String fallback: j/Json note: String -> j/Json
  (j/jobj (list (pair "url" (j/jstr url)) (pair "distilledText" fallback) (pair "tables" (j/jarr (list))) (pair "codeBlocks" (j/jarr (list)))
                (pair "crawled" (j/jbool false)) (pair "note" (j/jstr note))))

fn fetchResult url: String fallback: j/Json r: srch/HttpResult decoded: (Result String pt/PyErr) -> j/Json
  (match r
    ((srch/httpFail e _) (notCrawled url fallback (str "fetchTimeoutOrError: " e.msg)))
    ((srch/httpResp code _ hs body)
      (if (not (srch/httpOk? code))
        (notCrawled url fallback "fetchTimeoutOrError")
        (match decoded
          ((err e) (notCrawled url fallback (str "fetchTimeoutOrError: " e.msg)))
          ((ok html)
            (if (isWafChallenge code html)
              (notCrawled url fallback "wafChallenge")
              (let [(clean (stripTagsAndWhitespace html))]
                (if (isSpaShell html clean)
                  (notCrawled url fallback "spaShell")
                  (j/jobj (list (pair "url" (j/jstr url))
                                (pair "distilledText" (if (stringEmpty? clean) fallback (j/jstr (pt/cpPrefix clean 1500))))
                                (pair "tables" (extractHtmlTables html 2 5))
                                (pair "codeBlocks" (extractHtmlCodeBlocks html 2))
                                (pair "crawled" (j/jbool true))))))))))))

fn ! fetchDecode! st: srch/HubState r: srch/HttpResult -> (Result String pt/PyErr)
  (match r
    ((srch/httpResp code _ hs body)
      (if (srch/httpOk? code)
        (srch/decodeBody! (pt/sliceB body 0 (min 150000 (stringLength body))) (optionOr (srch/contentCharset hs) "utf-8") st.env)
        (err (pt/pyErr "HTTPError" "status outside 2xx"))))
    ((srch/httpFail e _) (err e)))

fn ! fetchSinglePage! st: srch/HubState url: String fallback: j/Json timeout: j/Json -> (Result j/Json pt/PyErr)
  (match (srch/urlTypeCheck url)
    ((err e) (err e))
    ((ok _) (let [(r (srch/runOne! st (fetchReq url timeout)))] (ok (fetchResult url fallback r (fetchDecode! st r))))))

fn strOrErr v: j/Json what: String -> (Result String pt/PyErr)
  (match v ((j/jstr s) (ok s)) (_ (err (pt/pyErr "TypeError" (str what " must be str, not " (pt/pyTypeName v))))))

fn ! parallelCrawlDistill! st: srch/HubState results: (List j/Json) maxUrls: Int64 timeout: j/Json -> (Result j/Json pt/PyErr)
  (let [(toFetch (listTake results (max maxUrls 0)))
        (targets (fold (fn [(acc (Result (List (Pair String j/Json)) pt/PyErr)) (r j/Json)] -> (Result (List (Pair String j/Json)) pt/PyErr)
                         (match acc
                           ((err e) (err e))
                           ((ok xs)
                             (match (srch/jreq r "url")
                               ((err e) (err e))
                               ((ok u)
                                 (match (pt/jgetOr r "snippet" (j/jstr ""))
                                   ((err e) (err e))
                                   ((ok sn) (match (strOrErr u "url") ((err e) (err e)) ((ok us) (ok (listAppend xs (list (pair us sn)))))))))))))
                       (ok (list)) toFetch))]
    (match targets
      ((err e) (err e))
      ((ok ts)
        (let [(valid (filter (fn [(t (Pair String j/Json))] -> Bool (ok? (srch/urlTypeCheck (pairFirst t)))) ts))
              (outs (srch/runCurlBatch! (map (fn [(t (Pair String j/Json))] -> srch/HttpReq (fetchReq (pairFirst t) timeout)) valid) (srch/curlChildEnv st.env)))]
          (ok (fold (fn [(acc j/Json) (p (Pair (Pair String j/Json) srch/HttpResult))] -> j/Json
                      (let [(u (pairFirst (pairFirst p)))] (pt/jset acc u (fetchResult u (pairSecond (pairFirst p)) (pairSecond p) (fetchDecode! st (pairSecond p))))))
                    (j/jobj (list)) (zip valid outs)))))))

fn researchPrompt topic: String depth: String rawItems: j/Json triage: Bool -> String
  (let [(tEsc (srch/escapeAsnStr (j/jstr topic)))
        (ev (pt/jsonDumps rawItems 2))]
    (if triage
      (pt/treeJoin (list
        "Research triage: the raw evidence below distils into one ASN S-expression, the (:researchTriage ...) form specified at the end.\n"
        "A claim is weighed against primary-source evidence, and the evidence against it (failure modes, boundaries, negative tradeoffs, disconfirming sources) counts as much as the evidence for it.\n"
        "The reply is read by an ASN parser: parentheses only; markdown code fences, JSON, brackets and backticks make it unreadable.\n\n"
        "Topic: " topic "\n"
        "Depth: " depth "\n\n"
        "Schema:\n"
        "1. verificationStatus is one of [:corroborated, :unfalsified, :disputed, :refuted].\n"
        "   :empiricallyVerified is reserved for runner-executed test assertions; web text never carries it.\n"
        "2. At depth 'bipolar' or 'matrix' the facts hold both polarities: at least one affirmative fact (:isFalsifying false) and at least one adversarial fact (:isFalsifying true).\n"
        "3. Every fact has :predicate (:relation \"verb\" :subject \"noun\" :object \"noun\") whose subject is a specific thing the source states something about, never the whole topic, and an integer :srcRef into the :sources list.\n"
        "4. A fact is a claim the source text states; a page title is not a fact.\n\n"
        "Format specification:\n"
        "(:researchTriage\n"
        "  :topic \"" tEsc "\"\n"
        "  :facts (\n"
        "    (:p :id \"fact-1\" :predicate (:relation \"verb\" :subject \"noun\" :object \"noun\") :srcRef 1 :verificationStatus :corroborated :isFalsifying false)\n"
        "    (:p :id \"fact-2\" :predicate (:relation \"verb\" :subject \"noun\" :object \"noun\") :srcRef 2 :verificationStatus :disputed :isFalsifying true))\n"
        "  :sources (\"https://example.com\" ...))\n\n"
        "Raw Evidence:\n" ev))
      (pt/treeJoin (list
        "Research report: the raw evidence below distils into one ASN S-expression, the (:researchReport ...) form specified at the end.\n"
        "A fact carries the verbatim figures, benchmarks or architectural predicates of its source, and the evidence against a claim (failure modes, boundaries, negative tradeoffs, disconfirming sources) counts as much as the evidence for it; a report that only agrees is one-sided.\n"
        "The reply is read by an ASN parser: parentheses only; markdown code fences, JSON, brackets and backticks make it unreadable.\n\n"
        "Topic: " topic "\n"
        "Depth: " depth "\n\n"
        "Schema:\n"
        "1. A fact is one atomic claim the source text states, with verbatim evidence, a metric or a definition from the distilled sources; a page title is not a fact.\n"
        "2. Every fact has a predicate (:relation \"verb\" :subject \"noun\" :object \"noun\") whose subject is a specific thing the source states something about, never the whole topic.\n"
        "3. Every fact has :source, the url of the Raw Evidence item it came from.\n"
        "4. Epistemic classification:\n"
        "   - verificationStatus: one of [:corroborated, :unfalsified, :disputed, :refuted].\n"
        "     :empiricallyVerified is reserved for runner-executed test assertions; web text never carries it.\n"
        "   - sourceKind: one of [:primaryArtifact, :peerReviewed, :crowdsourced, :secondaryReport, :unverifiedWeb].\n"
        "5. Polarity:\n"
        "   - isFalsifying: boolean (true or false).\n"
        "   - At depth 'bipolar' or 'matrix' the facts hold at least one affirmative fact (:isFalsifying false) and at least one adversarial fact or limitation (:isFalsifying true).\n"
        "6. A fact from a crawled web source ('crawled': true in Raw Evidence) carries :crawled true in its (:fact ...) form.\n"
        "7. positiveSynthesis: 1-2 sentences summarizing what the facts support.\n"
        "8. falsificationCritique: 1-2 sentences summarizing limitations, failure modes, counter-evidence, or edge cases the facts show.\n"
        "9. summary: 2-3 sentence executive synthesis.\n\n"
        "Format specification:\n"
        "(:researchReport\n"
        "  :topic \"" tEsc "\"\n"
        "  :summary \"...\"\n"
        "  :positiveSynthesis \"...\"\n"
        "  :falsificationCritique \"...\"\n"
        "  :facts (\n"
        "    (:fact :id \"fact-1\" :predicate (:relation \"verb\" :subject \"noun\" :object \"noun\") :claim \"...\" :evidence \"...\" :source \"https://...\" :sourceKind :primaryArtifact :verificationStatus :corroborated :crawled true :isFalsifying false)\n"
        "    ...)\n"
        "  :sources (\"https://...\" ...))\n\n"
        "Raw Evidence:\n" ev))))

fn researchEntryLabel entry: j/Json -> (Result (Pair j/Json j/Json) pt/PyErr)
  (match entry
    ((j/jobj _) (match (srch/jreq entry "alias") ((err e) (err e)) ((ok a) (match (srch/jreq entry "dispatch") ((err e) (err e)) ((ok d) (ok (pair a d)))))))
    (_ (ok (pair entry entry))))

fn cliName prov: j/Json -> (Option String)
  (match prov
    ((j/jstr p) (cond ((= p "agy-cli") (some "agy")) ((= p "codex-cli") (some "codex")) ((= p "claude-cli") (some "claude")) (else (none))))
    (_ (none)))

fn researchEntryProvider entry: j/Json up: (fn [String] -> j/Json) -> (Result j/Json pt/PyErr)
  (let [(raw (match entry
               ((j/jobj _)
                 (let [(p (optionOr (pt/jget entry "provider") (j/jnull)))]
                   (if (pt/pyTruthy p)
                     (ok p)
                     (let [(u (optionOr (pt/jget entry "upstream") (j/jnull)))]
                       (pt/jgetOr (if (pt/pyTruthy u) u (j/jobj (list))) "provider" (j/jnull))))))
               ((j/jstr s) (pt/jgetOr (up s) "provider" (j/jnull)))
               (_ (err (pt/pyErr "TypeError" (str "entry must be dict or str, not " (pt/pyTypeName entry)))))))]
    (match raw
      ((err e) (err e))
      ((ok p) (ok (match (cliName p) ((some c) (j/jstr c)) ((none) p))))))

fn provKey prov: j/Json -> String
  (pt/pyStr prov)

fn breakerDownFor st: srch/HubState prov: j/Json -> (Pair Float64 srch/HubState)
  (if (not (pt/pyTruthy prov))
    (pair 0.0 st)
    (match (mapGet st.breakerUntil (provKey prov))
      ((none) (pair 0.0 st))
      ((some until)
        (let [(left (- (/ (int64ToFloat64 until) 1000.0) (/ (int64ToFloat64 st.nowMs) 1000.0)))]
          (if (<= left 0.0)
            (pair 0.0 (srch/hubWithBreaker st (mapRemove st.breakerUntil (provKey prov)) st.count503))
            (pair left st))))))

fn markDown st: srch/HubState pool: String -> srch/HubState
  (if (stringEmpty? pool) st (srch/hubWithBreaker st (mapSet st.breakerUntil pool (+ st.nowMs 600000)) (mapSet st.count503 pool 0)))

fn clearBreaker st: srch/HubState pool: String -> srch/HubState
  (if (stringEmpty? pool) st (srch/hubWithBreaker st (mapRemove st.breakerUntil pool) (mapSet st.count503 pool 0)))

fn note503 st: srch/HubState pool: String -> srch/HubState
  (if (stringEmpty? pool)
    st
    (let [(cnt (+ (optionOr (mapGet st.count503 pool) 0) 1))]
      (if (>= cnt 3)
        (srch/hubWithBreaker st (mapSet st.breakerUntil pool (+ st.nowMs 600000)) (mapSet st.count503 pool 0))
        (srch/hubWithBreaker st st.breakerUntil (mapSet st.count503 pool cnt)))))

fn reset503 st: srch/HubState pool: String -> srch/HubState
  (if (stringEmpty? pool) st (srch/hubWithBreaker st st.breakerUntil (mapSet st.count503 pool 0)))

fn quotaUpper t: String -> String
  (pt/asciiUpper (srch/repl (srch/repl (srch/repl (srch/repl t "ſ" "s") "ı" "i") "ﬅ" "st") "ﬆ" "st"))

fn isQuotaError t: String -> Bool
  (let [(u (quotaUpper t))] (or (pt/hasSubstr u "429") (pt/hasSubstr u "RESOURCE_EXHAUSTED") (pt/hasSubstr u "QUOTA")))

fn usageHttpError code: Int64 -> String
  (cond ((= code 429) "429") ((>= code 500) "5xx") (else "4xx"))

fn toSeconds ms: Int64 -> Float64
  (/ (int64ToFloat64 ms) 1000.0)

fn roundHalfEven x: Float64 -> Int64
  (match (float64ToInt64 x)
    ((none) 0)
    ((some f) (let [(d (- x (int64ToFloat64 f)))]
      (cond ((> d 0.5) (+ f 1)) ((< d 0.5) f) ((= (mod f 2) 0) f) (else (+ f 1))))))

fn bucketFill b: srch/Bucket now: Float64 -> srch/Bucket
  (srch/Bucket :tokens (min 1.0 (+ b.tokens (* (- now b.last) b.rate))) :last now :rate b.rate)

fn bucketTake b: srch/Bucket -> srch/Bucket
  (srch/Bucket :tokens (- b.tokens 1.0) :last b.last :rate b.rate)

fn ! bucketAcquire! st: srch/HubState key: String rate: Float64 -> (Pair Bool srch/HubState)
  (let [(now (toSeconds st.nowMs))
        (b0 (optionOr (mapGet st.buckets key) (srch/Bucket :tokens 1.0 :last now :rate rate)))
        (b1 (bucketFill b0 now))]
    (if (>= b1.tokens 1.0)
      (pair true (srch/hubWithBuckets st (mapSet st.buckets key (bucketTake b1))))
      (let [(wait (/ (- 1.0 b1.tokens) b1.rate))]
        (if (> wait 0.5)
          (pair false (srch/hubWithBuckets st (mapSet st.buckets key b1)))
          (let [(st1 (srch/hubSleep! (srch/hubWithBuckets st (mapSet st.buckets key b1)) (roundHalfEven (* wait 1000.0))))
                (b2 (bucketFill b1 (toSeconds st1.nowMs)))]
            (if (>= b2.tokens 1.0)
              (pair true (srch/hubWithBuckets st1 (mapSet st1.buckets key (bucketTake b2))))
              (pair false (srch/hubWithBuckets st1 (mapSet st1.buckets key b2)))))))))

fn runtimeErr msg: String -> pt/PyErr
  (pt/pyErr "RuntimeError" msg)

fn numF v: j/Json -> Float64
  (match v ((j/jint i) (int64ToFloat64 i)) ((j/jfloat f) f) ((j/jnum f) f) ((j/jbool b) (if b 1.0 0.0)) (_ 0.0))

fn afterSlash s: String -> (Option String)
  (match (stringIndexOf s "/") ((some i) (some (pt/sliceB s (+ i 1) (stringLength s)))) ((none) (none)))

(schema Route (:f alias j/Json) (:f name String) (:f upv j/Json) (:f params j/Json) (:f rpm j/Json) (:f timeout j/Json) (:f prov j/Json))

fn routeOf entry: j/Json up: (fn [String] -> j/Json) -> (Result Route pt/PyErr)
  (match entry
    ((j/jobj _)
      (match (srch/jreq entry "alias")
        ((err e) (err e))
        ((ok alias)
          (match (srch/jreq entry "dispatch")
            ((err e) (err e))
            ((ok name)
              (match (srch/jreq entry "upstream")
                ((err e) (err e))
                ((ok upv)
                  (match (srch/jreq entry "params")
                    ((err e) (err e))
                    ((ok params)
                      (match (srch/jreq upv "provider")
                        ((err e) (err e))
                        ((ok prov)
                          (let [(t (optionOr (pt/jget entry "timeoutSec") (j/jnull)))]
                            (match (strOrErr name "dispatch")
                              ((err e) (err e))
                              ((ok nm) (ok (Route :alias alias :name nm :upv upv :params params :rpm (optionOr (pt/jget entry "rpm") (j/jnull))
                                                  :timeout (if (pt/pyTruthy t) t (j/jint 45)) :prov prov))))))))))))))))
    ((j/jstr s)
      (let [(upv (up s))]
        (match (srch/jreq upv "provider")
          ((err e) (err e))
          ((ok prov)
            (let [(nm (if (or (stringStartsWith? s "groq/") (stringStartsWith? s "ollama/")) (optionOr (afterSlash s) s) s))]
              (ok (Route :alias entry :name nm :upv upv :params (j/jobj (list)) :rpm (if (pt/pyEq prov (j/jstr "gemini")) (j/jint 15) (j/jnull))
                         :timeout (if (pt/pyEq prov (j/jstr "ollama")) (j/jfloat 300.0) (j/jint 45)) :prov prov)))))))
    (_ (err (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName entry) "' object has no attribute 'startswith'")))))

fn poolOf prov: j/Json -> String
  (match (cliName prov) ((some c) c) ((none) (if (pt/pyTruthy prov) (provKey prov) "")))

fn paramGet params: j/Json k: String d: j/Json -> (Result j/Json pt/PyErr)
  (pt/jgetOr params k d)

fn ! cliCall! st: srch/HubState r: Route cli: String prompt: String dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(sub (match (afterSlash r.name) ((some x) (j/jstr x)) ((none) (j/jnull))))
        (modelR (cond ((= cli "agy") (ok (if (pt/pyTruthy sub) sub (j/jstr "gemini-3.8-flash")))) (else (ok sub))))
        (effortR (cond ((= cli "agy") (paramGet r.params "effort" (j/jstr "low"))) ((= cli "codex") (paramGet r.params "effort" (j/jstr "medium"))) (else (ok (j/jnull)))))]
    (match modelR
      ((err e) (pair (err e) st))
      ((ok model)
        (match effortR
          ((err e) (pair (err e) st))
          ((ok effort)
            (let [(st1 (srch/hubCliCall st (j/jobj (list (pair "prov" (j/jstr cli)) (pair "model" model) (pair "effort" effort) (pair "noTools" (j/jbool true)) (pair "prompt" (j/jstr prompt))))))]
              (match (dispatch cli model effort prompt)
                ((err e) (pair (err e) st1))
                ((ok res)
                  (match (if (pt/pyTruthy res) (pt/jgetOr res "text" (j/jnull)) (ok (j/jnull)))
                    ((err e) (pair (err e) st1))
                    ((ok text)
                      (if (not (pt/pyTruthy text))
                        (pair (err (runtimeErr (str (provKey r.prov) " returned no text"))) (srch/hubNote st1 r.prov r.alias "failed" (j/jnull)))
                        (pair (ok text) (srch/hubNote st1 r.prov r.alias "ok" (optionOr (pt/jget res "usage") (j/jnull)))))))))))))))

fn chatBody r: Route prompt: String -> (Result String pt/PyErr)
  (match (paramGet r.params "temperature" (j/jfloat 0.2))
    ((err e) (err e))
    ((ok temp)
      (let [(b0 (j/jobj (list (pair "model" (j/jstr r.name))
                              (pair "messages" (j/jarr (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr prompt)))))))
                              (pair "temperature" temp))))
            (b1 (match (pt/jget r.params "maxTokens") ((some m) (pt/jset b0 "max_tokens" m)) ((none) b0)))
            (eff (optionOr (pt/jget r.params "effort") (j/jnull)))
            (b2 (if (and (pt/pyEq r.prov (j/jstr "ollama")) (listAny? (fn [(x String)] -> Bool (pt/pyEq eff (j/jstr x))) (list "low" "medium" "high")))
                  (pt/jset b1 "reasoning_effort" eff)
                  b1))]
        (ok (pt/jsonDumps b2 -1)))))

fn rstripSlashes s: String -> String
  (if (stringEndsWith? s "/") (rstripSlashes (pt/sliceB s 0 (- (stringLength s) 1))) s)

fn replyContent data: j/Json -> (Result j/Json pt/PyErr)
  (match (pt/jgetOr data "choices" (j/jnull))
    ((err e) (err e))
    ((ok ch)
      (match (pt/pyIndex (if (pt/pyTruthy ch) ch (j/jarr (list (j/jobj (list))))) 0)
        ((err e) (err e))
        ((ok first)
          (match (pt/jgetOr first "message" (j/jnull))
            ((err e) (err e))
            ((ok m) (pt/jgetOr (if (pt/pyTruthy m) m (j/jobj (list))) "content" (j/jnull))))))))

fn ! httpCall! st: srch/HubState r: Route prompt: String -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(pool (poolOf r.prov))]
    (match (chatBody r prompt)
      ((err e) (pair (err e) st))
      ((ok body)
        (match (srch/jreq r.upv "url")
          ((err e) (pair (err e) st))
          ((ok urlv)
            (match (strOrErr urlv "url")
              ((err e) (pair (err e) st))
              ((ok u0)
                (let [(url (str (rstripSlashes u0) "/chat/completions"))
                      (key (optionOr (pt/jget r.upv "key") (j/jnull)))]
                  (match (srch/urlTypeCheck url)
                    ((err e) (pair (err e) st))
                    ((ok _)
                      (let [(req (srch/HttpReq :url url
                                   :headers (listAppend (list (pair "Content-Type" "application/json") (pair "User-Agent" "ASL-Gateway/1.0 (Darwin; macOS)"))
                                                        (if (pt/pyTruthy key) (list (pair "Authorization" (str "Bearer " (pt/pyStr key)))) (list)))
                                   :data (some body) :timeout r.timeout))
                            (res (srch/runOne! st req))]
                        (httpOutcome st r pool res))))))))))))

fn ! httpOutcome st: srch/HubState r: Route pool: String res: srch/HttpResult -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (match res
    ((srch/httpFail e timedOut)
      (pair (err e) (srch/hubNote (reset503 st pool) r.prov r.alias (if timedOut "timeout" "other") (j/jnull))))
    ((srch/httpResp code _ _ body)
      (if (not (srch/httpOk? code))
        (let [(st1 (cond ((or (= code 429) (isQuotaError (pt/decodeReplace body))) (markDown st pool)) ((= code 503) (note503 st pool)) (else (reset503 st pool))))]
          (pair (err (runtimeErr (str "HTTP " (stringFromInt64 code)))) (srch/hubNote st1 r.prov r.alias (usageHttpError code) (j/jnull))))
        (match (match (pt/strictUtf8 body) ((err e) (err e)) ((ok text) (pt/jsonLoads text)))
          ((err e) (pair (err e) (srch/hubNote (reset503 st pool) r.prov r.alias "other" (j/jnull))))
          ((ok data)
            (match (replyContent data)
              ((err e) (pair (err e) st))
              ((ok text)
                (match text
                  ((j/jstr s)
                    (if (stringEmpty? (pt/pyStrip s))
                      (pair (err (runtimeErr "empty content")) (srch/hubNote st r.prov r.alias "empty" (j/jnull)))
                      (pair (ok text) (srch/hubNote (clearBreaker st pool) r.prov r.alias "ok" (optionOr (pt/jget data "usage") (j/jnull))))))
                  (_ (pair (err (runtimeErr "empty content")) (srch/hubNote st r.prov r.alias "empty" (j/jnull))))))))))))

fn ! researchCall! st: srch/HubState entry: j/Json prompt: String up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (match (routeOf entry up)
    ((err e) (pair (err e) st))
    ((ok r)
      (match (cliName r.prov)
        ((some cli) (cliCall! st r cli prompt dispatch))
        ((none)
          (if (pt/pyTruthy r.rpm)
            (let [(key (str r.name "\u0000" (stringFromFloat64 (numF r.rpm))))
                  (acq (bucketAcquire! st key (/ (numF r.rpm) 60.0)))]
              (if (pairFirst acq)
                (httpCall! (pairSecond acq) r prompt)
                (pair (err (runtimeErr (str "rate limit of " (pt/pyStr r.rpm) " rpm reached"))) (srch/hubNote (pairSecond acq) r.prov r.alias "throttled" (j/jnull)))))
            (httpCall! st r prompt))))))

fn debracketLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 inStr: Bool esc: Bool acc: (List String) -> String
  (if (>= i n)
    (pt/treeJoin (listReverse (cons (pt/sliceB s seg n) acc)))
    (let [(c (bytesGet bs i))]
      (cond
        (esc (debracketLoop s bs n (+ i 1) seg inStr false acc))
        ((and (= c 92) inStr) (debracketLoop s bs n (+ i 1) seg inStr true acc))
        ((= c 34) (debracketLoop s bs n (+ i 1) seg (not inStr) false acc))
        ((and (not inStr) (or (= c 91) (= c 93))) (debracketLoop s bs n (+ i 1) (+ i 1) inStr false (cons (if (= c 91) "(" ")") (cons (pt/sliceB s seg i) acc))))
        (else (debracketLoop s bs n (+ i 1) seg inStr false acc)))))

fn researchDebracket text: String -> String
  (let [(bs (stringToBytes text))] (debracketLoop text bs (bytesLength bs) 0 0 false false (list)))

fn researchParse text: j/Json triage: Bool -> (Result (Pair j/Json j/Json) pt/PyErr)
  (let [(head (if triage ":researchTriage" ":researchReport"))
        (noForm (valueErr (str "reply holds no (" head " ...) form")))]
    (match (if (pt/pyTruthy text) (strOrErr text "text") (ok ""))
      ((err _) (err (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName text) "' object has no attribute 'find'"))))
      ((ok t)
        (match (extractOutermostSexpr t)
          ((none) (err noForm))
          ((some sx)
            (if (not (stringStartsWith? sx (str "(" head)))
              (err noForm)
              (match (asnRead (researchDebracket sx))
                ((err e) (err e))
                ((ok forms)
                  (match (asnProps (optionOr (listHead forms) (j/jnull)) (some head))
                    ((err e) (err e))
                    ((ok props)
                      (let [(facts (optionOr (pt/jget props "facts") (j/jarr (list))))]
                        (match facts
                          ((j/jarr _) (ok (pair props facts)))
                          (_ (err (valueErr ":facts is not a list")))))))))))))))

fn orEmpty v: j/Json -> String
  (if (pt/pyTruthy v) (asnText v) "")

fn researchNorm v: j/Json -> String
  (pt/pyLower (pt/pyStrip (pt/collapseWs (orEmpty v))))

fn isWordByte b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (and (>= b 97) (<= b 122)))

fn wordsLoop s: String bs: Bytes n: Int64 i: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (>= start 0) (cons (pt/sliceB s start n) acc) acc))
    (if (isWordByte (bytesGet bs i))
      (wordsLoop s bs n (+ i 1) (if (< start 0) i start) acc)
      (wordsLoop s bs n (+ i 1) -1 (if (>= start 0) (cons (pt/sliceB s start i) acc) acc))))

fn researchWords v: j/Json -> (List String)
  (let [(s (pt/pyLower (orEmpty v))) (bs (stringToBytes s))] (wordsLoop s bs (bytesLength bs) 0 -1 (list)))

fn padded ws: (List String) -> String
  (str " " (pt/joinSep ws " ") " ")

fn researchQuoteFound quote: j/Json text: j/Json -> Bool
  (let [(q (researchWords quote)) (t (padded (researchWords text))) (nq (listLength q))]
    (cond
      ((= nq 0) false)
      ((pt/hasSubstr t (padded q)) true)
      (else (and (>= nq 8) (listAny? (fn [(i Int64)] -> Bool (pt/hasSubstr t (padded (listTake (listDrop q i) 8)))) (range 0 (- nq 7)))))))

fn verdictList -> (List String)
  (list "corroborated" "unfalsified" "disputed" "refuted")

fn propGet fp: j/Json k: String d: j/Json -> j/Json
  (optionOr (pt/jget fp k) d)

fn byUrlGet evidence: (List j/Json) u: String -> (Option j/Json)
  (fold (fn [(acc (Option j/Json)) (e j/Json)] -> (Option j/Json) (if (pt/pyEq (optionOr (pt/jget e "url") (j/jnull)) (j/jstr u)) (some e) acc)) (none) evidence)

fn intLike v: j/Json -> (Option Int64)
  (match v ((j/jint i) (some i)) ((j/jbool b) (some (if b 1 0))) (_ (none)))

fn whyRejected triage: Bool fp: j/Json claim: String subject: String obj: String src: String vstat: String titles: (List String) topicN: String evidence: (List j/Json) -> (Option String)
  (let [(evidenceV (propGet fp "evidence" (j/jstr "")))]
    (cond
      ((and (not triage) (stringEmpty? (pt/pyStrip claim))) (some "no claim"))
      ((and (not triage) (listContains? titles (researchNorm (j/jstr claim)))) (some "claim is a search result title"))
      ((and (not triage) (= (researchNorm (j/jstr claim)) topicN)) (some "claim is the topic"))
      ((and (not triage) (stringEmpty? (pt/pyStrip (asnText evidenceV)))) (some "no evidence"))
      ((or (stringEmpty? (pt/pyStrip subject)) (stringEmpty? (pt/pyStrip obj))) (some "predicate lacks a subject or object"))
      ((= (researchNorm (j/jstr subject)) topicN) (some "subject is the whole topic"))
      ((or (listContains? titles (researchNorm (j/jstr subject))) (listContains? titles (researchNorm (j/jstr obj)))) (some "predicate is a search result title"))
      ((none? (byUrlGet evidence src)) (some "source url is not one of the fetched results"))
      ((and (not triage) (not (researchQuoteFound evidenceV (optionOr (pt/jget (optionOr (byUrlGet evidence src) (j/jnull)) "snippet") (j/jstr ""))))) (some "evidence is not found in the fetched text"))
      ((not (listContains? (verdictList) vstat)) (some (str "verificationStatus " (if (stringEmpty? vstat) "missing" vstat))))
      (else (none))))

fn verifyOne triage: Bool head: String i: Int64 form: j/Json llmSources: (List j/Json) titles: (List String) topicN: String evidence: (List j/Json) -> (Result (Pair (Option j/Json) (Option String)) pt/PyErr)
  (match (match (asnProps form (some head)) ((err e) (err e)) ((ok fp) (match (researchRelation (propGet fp "predicate" (j/jnull))) ((err e) (err e)) ((ok rel) (ok (pair fp rel))))))
    ((err e) (if (= e.kind "ValueError") (ok (pair (none) (some (str "fact " (stringFromInt64 (+ i 1)) ": " e.msg)))) (err e)))
    ((ok p)
      (let [(fp (pairFirst p)) (rel (pairSecond p))
            (verb (optionOr (listGet rel 0) "")) (subject (optionOr (listGet rel 1) "")) (obj (optionOr (listGet rel 2) ""))
            (fid (asnText (propGet fp "id" (j/jstr (str "fact-" (stringFromInt64 (+ i 1)))))))
            (claim (if triage "" (asnText (propGet fp "claim" (j/jstr "")))))
            (src0 (if triage "" (asnText (propGet fp "source" (j/jstr "")))))
            (sref (asnScalar (propGet fp "srcRef" (asnAtom "0"))))
            (src (match (intLike sref)
                   ((some k) (if (and (stringEmpty? src0) (>= k 1) (<= k (listLength llmSources))) (asnText (optionOr (listGet llmSources (- k 1)) (j/jnull))) src0))
                   ((none) src0)))
            (vstat (lstripColon (asnText (propGet fp "verificationStatus" (j/jstr "")))))]
        (match (whyRejected triage fp claim subject obj src vstat titles topicN evidence)
          ((some why) (ok (pair (none) (some (str fid ": " why)))))
          ((none)
            (let [(ev (optionOr (byUrlGet evidence src) (j/jnull)))]
              (ok (pair (some (j/jobj (list (pair "id" (j/jstr fid)) (pair "claim" (j/jstr claim)) (pair "evidence" (j/jstr (asnText (propGet fp "evidence" (j/jstr "")))))
                                            (pair "sourceUrl" (j/jstr src)) (pair "sourceKind" (j/jstr (classifySourceKind src))) (pair "verificationStatus" (j/jstr vstat))
                                            (pair "isFalsifying" (j/jbool (= (asnScalar (propGet fp "isFalsifying" (asnAtom "false"))) (j/jbool true))))
                                            (pair "crawled" (j/jbool (pt/pyTruthy (optionOr (pt/jget ev "crawled") (j/jnull)))))
                                            (pair "relation" (j/jarr (list (j/jstr verb) (j/jstr subject) (j/jstr obj)))))))
                        (none)))))))))

fn verifyLoop triage: Bool head: String forms: (List (Pair Int64 j/Json)) llm: (List j/Json) titles: (List String) topicN: String evidence: (List j/Json) passed: (List j/Json) rejected: (List j/Json) -> (Result (Pair (List j/Json) (List j/Json)) pt/PyErr)
  (match (listHead forms)
    ((none) (ok (pair (listReverse passed) (listReverse rejected))))
    ((some f)
      (match (verifyOne triage head (pairFirst f) (pairSecond f) llm titles topicN evidence)
        ((err e) (err e))
        ((ok r)
          (verifyLoop triage head (optionOr (listTail forms) (list)) llm titles topicN evidence
                      (match (pairFirst r) ((some x) (cons x passed)) ((none) passed))
                      (match (pairSecond r) ((some x) (cons (j/jstr x) rejected)) ((none) rejected)))))))

fn collectR xs: (List j/Json) f: (fn [j/Json] -> (Result String pt/PyErr)) acc: (List String) -> (Result (List String) pt/PyErr)
  (match (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x) (match (f x) ((err e) (err e)) ((ok v) (collectR (optionOr (listTail xs) (list)) f (cons v acc))))))

fn researchVerify props: j/Json rawFacts: (List j/Json) topic: String evidence: (List j/Json) triage: Bool -> (Result j/Json pt/PyErr)
  (match (collectR evidence (fn [(e j/Json)] -> (Result String pt/PyErr) (match (srch/jreq e "title") ((err x) (err x)) ((ok t) (ok (researchNorm t))))) (list))
    ((err e) (err e))
    ((ok titles)
      (match (collectR evidence (fn [(e j/Json)] -> (Result String pt/PyErr) (match (srch/jreq e "url") ((err x) (err x)) ((ok u) (ok (pt/pyStr u))))) (list))
        ((err e) (err e))
        ((ok _)
          (let [(llm (match (optionOr (pt/jget props "sources") (j/jnull))
                       ((j/jarr xs) (filter (fn [(s j/Json)] -> Bool (or (some? (atomOf s)) (match s ((j/jstr _) true) (_ false)))) xs))
                       (_ (list))))]
            (match (verifyLoop triage (if triage ":p" ":fact") (enumerate rawFacts) llm titles (researchNorm (j/jstr topic)) evidence (list) (list))
              ((err e) (err e))
              ((ok r) (ok (j/jarr (list (j/jarr (pairFirst r)) (j/jarr (pairSecond r))))))))))))

fn researchAuditPrompt facts: (List j/Json) byUrl: j/Json -> (Result String pt/PyErr)
  (match (collectR facts
        (fn [(f j/Json)] -> (Result String pt/PyErr)
          (match (srch/jreq f "id")
            ((err e) (err e))
            ((ok fid)
              (match (srch/jreq f "claim")
                ((err e) (err e))
                ((ok claim)
                  (match (srch/jreq f "sourceUrl")
                    ((err e) (err e))
                    ((ok su)
                      (match (srch/jreq byUrl (pt/pyStr su))
                        ((err e) (err e))
                        ((ok src)
                          (match (pt/jgetOr src "snippet" (j/jstr ""))
                            ((err e) (err e))
                            ((ok sn) (match (strOrErr sn "snippet")
                                       ((err e) (err e))
                                       ((ok s) (ok (str "(:fact :id \"" (pt/pyStr fid) "\" :claim \"" (pt/pyStr claim) "\")\nsource text: " (pt/cpPrefix s 1200) "\n")))))))))))))))
        (list))
    ((err e) (err e))
    ((ok blocks)
      (ok (pt/joinSep (listAppend (list "AUDIT. You are an independent auditor. For each fact decide from its source text alone whether the text supports the claim."
                                        "Reply only with one form per fact: (:check :id \"fact-N\" :verdict :supported|:partial|:unsupported :why \"one short reason\")."
                                        "supported: the text states the claim. partial: the text states part of it or a weaker version. unsupported: the text does not state it."
                                        "")
                                  blocks)
                      "\n"))))

fn ws1 s: String bs: Bytes n: Int64 j: Int64 -> Int64
  (let [(e (wsEnd s bs n j))] (if (> e j) e -1))

fn lowerRunEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (>= (bytesGet bs j) 97) (<= (bytesGet bs j) 122)) (lowerRunEnd bs n (+ j 1)) j)

fn whyBodyEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (>= j n)
    j
    (let [(c (bytesGet bs j))]
      (cond
        ((= c 34) j)
        ((= c 92) (if (and (< (+ j 1) n) (not (= (bytesGet bs (+ j 1)) 10))) (whyBodyEnd bs n (+ j 1 (pt/cpLenAt (bytesGet bs (+ j 1))))) j))
        (else (whyBodyEnd bs n (+ j 1))))))

fn whyGroup s: String bs: Bytes n: Int64 j: Int64 -> (Option (Pair String Int64))
  (let [(a (ws1 s bs n j))]
    (if (and (>= a 0) (ciAtExact bs n a ":why"))
      (let [(b (ws1 s bs n (+ a 4)))]
        (if (and (>= b 0) (< b n) (= (bytesGet bs b) 34))
          (let [(e (whyBodyEnd bs n (+ b 1)))]
            (if (and (< e n) (= (bytesGet bs e) 34)) (some (pair (pt/sliceB s (+ b 1) e) (+ e 1))) (none)))
          (none)))
      (none)))

fn ciAtExact bs: Bytes n: Int64 i: Int64 lit: String -> Bool
  (let [(lb (stringToBytes lit)) (m (bytesLength lb))] (and (<= (+ i m) n) (exactLoop bs i lb 0 m)))

fn exactLoop bs: Bytes i: Int64 lb: Bytes k: Int64 m: Int64 -> Bool
  (if (>= k m) true (and (= (bytesGet bs (+ i k)) (bytesGet lb k)) (exactLoop bs i lb (+ k 1) m)))

fn checkAt s: String bs: Bytes n: Int64 k: Int64 -> (Option (Pair (Pair String (Pair String String)) Int64))
  (let [(a (ws1 s bs n (+ k 7)))]
    (if (and (>= a 0) (ciAtExact bs n a ":id"))
      (let [(b (ws1 s bs n (+ a 3)))]
        (if (and (>= b 0) (< b n) (= (bytesGet bs b) 34))
          (let [(q (findLit bs n "\"" (+ b 1)))]
            (if (> q (+ b 1))
              (let [(c (ws1 s bs n (+ q 1)))]
                (if (and (>= c 0) (ciAtExact bs n c ":verdict"))
                  (let [(d (ws1 s bs n (+ c 8)))]
                    (if (>= d 0)
                      (let [(d1 (if (and (< d n) (= (bytesGet bs d) 58)) (+ d 1) d)) (e (lowerRunEnd bs n d1))]
                        (if (> e d1)
                          (let [(w (whyGroup s bs n e))]
                            (some (pair (pair (pt/sliceB s (+ b 1) q) (pair (pt/sliceB s d1 e) (match w ((some x) (pairFirst x)) ((none) ""))))
                                        (match w ((some x) (pairSecond x)) ((none) e)))))
                          (none)))
                      (none)))
                  (none)))
              (none)))
          (none)))
      (none)))

fn checksLoop s: String bs: Bytes n: Int64 i: Int64 acc: j/Json -> j/Json
  (let [(k (findLit bs n "(:check" i))]
    (if (< k 0)
      acc
      (match (checkAt s bs n k)
        ((none) (checksLoop s bs n (+ k 1) acc))
        ((some m)
          (let [(id (pairFirst (pairFirst m))) (v (pairFirst (pairSecond (pairFirst m)))) (why (pairSecond (pairSecond (pairFirst m))))]
            (checksLoop s bs n (pairSecond m)
                        (if (listContains? (list "supported" "partial" "unsupported") v) (pt/jset acc id (j/jarr (list (j/jstr v) (j/jstr why)))) acc)))))))

fn auditVerdicts text: String -> j/Json
  (let [(bs (stringToBytes text))] (checksLoop text bs (bytesLength bs) 0 (j/jobj (list))))

fn triedRow alias: j/Json name: j/Json e: String -> j/Json
  (j/jobj (list (pair "alias" alias) (pair "model" name) (pair "error" (j/jstr e))))

fn errWord e: pt/PyErr -> String
  (if (stringEmpty? e.msg) e.kind e.msg)

fn breakerSkip st: srch/HubState prov: j/Json alias: j/Json name: j/Json -> (Pair (Option j/Json) srch/HubState)
  (let [(d (breakerDownFor st prov)) (down (pairFirst d)) (st1 (pairSecond d))]
    (if (> down 0.0)
      (let [(secs (stringFromInt64 (match (float64ToInt64 down) ((some i) i) ((none) 0))))]
        (pair (some (triedRow alias name (str "breaker (" secs "s left)")))
              (srch/hubNote (srch/hubStderr st1 (str "[Gateway Breaker] skip " (pt/pyStr prov) " for " secs "s\n")) prov alias (str "breaker " secs "s") (j/jnull))))
      (pair (none) st1)))

(schema Attempt (:f tried (List j/Json)) (:f won (Option j/Json)))

; (:m :ref RESEARCH-DEPTH :do "what one stage may take: its own timeout, cut to the wall that is left, never below one second")
fn stageSeconds own: Int64 leftMs: Int64 -> Int64
  (min own (max 1 (/ (+ leftMs 999) 1000)))

fn entryTimeoutMs entry: j/Json -> Int64
  (match (optionOr (pt/jget entry "timeoutSec") (j/jnull))
    ((j/jint v) (if (> v 0) (* 1000 v) 45000))
    ((j/jfloat f) (if (> f 0.0) (match (float64ToInt64 (* f 1000.0)) ((some i) i) ((none) 45000)) 45000))
    (_ 45000))

; (:m :do "a route entry whose timeout is longer than the wall left gets the wall left as its :timeoutSec; any other entry is returned as it is")
fn stageEntry entry: j/Json leftMs: Int64 -> j/Json
  (match entry
    ((j/jobj _) (if (> (entryTimeoutMs entry) leftMs) (pt/jset entry "timeoutSec" (j/jint (stageSeconds (/ (entryTimeoutMs entry) 1000) leftMs))) entry))
    (_ entry))

fn ! chainLoop! entries: (List j/Json) st: srch/HubState tried: (List j/Json) prompt: String up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) finish: (fn [j/Json] -> (Result j/Json String)) -> (Pair (Result Attempt pt/PyErr) srch/HubState)
  (chainUntil! entries st tried prompt up dispatch finish (fn [(u Int64)] -> Int64 9000000000000))

; (:m :ref RESEARCH-DEPTH :do "the model chain under a wall: every entry attempt asks leftMs first, is not started without wall left and runs no longer than the wall left")
fn ! chainUntil! entries: (List j/Json) st: srch/HubState tried: (List j/Json) prompt: String up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) finish: (fn [j/Json] -> (Result j/Json String)) leftMs: (fn [Int64] -> Int64) -> (Pair (Result Attempt pt/PyErr) srch/HubState)
  (match (listHead entries)
    ((none) (pair (ok (Attempt :tried tried :won (none))) st))
    ((some entry)
      (let [(rest (optionOr (listTail entries) (list)))]
        (match (researchEntryLabel entry)
          ((err e) (pair (err e) st))
          ((ok lab)
            (match (researchEntryProvider entry up)
              ((err e) (pair (err e) st))
              ((ok prov)
                (let [(sk (breakerSkip st prov (pairFirst lab) (pairSecond lab)))]
                  (match (pairFirst sk)
                    ((some row) (chainUntil! rest (pairSecond sk) (listAppend tried (list row)) prompt up dispatch finish leftMs))
                    ((none)
                      (let [(left (leftMs 0))]
                        (if (< left 1)
                          (pair (ok (Attempt :tried (listAppend tried (list (triedRow (pairFirst lab) (pairSecond lab) "no wall left"))) :won (none))) (pairSecond sk))
                          (let [(call (researchCall! (pairSecond sk) (stageEntry entry left) prompt up dispatch)) (st2 (pairSecond call))]
                            (match (pairFirst call)
                              ((err e) (chainUntil! rest st2 (listAppend tried (list (triedRow (pairFirst lab) (pairSecond lab) (errWord e)))) prompt up dispatch finish leftMs))
                              ((ok text)
                                (match (finish text)
                                  ((err why) (chainUntil! rest st2 (listAppend tried (list (triedRow (pairFirst lab) (pairSecond lab) why))) prompt up dispatch finish leftMs))
                                  ((ok won) (pair (ok (Attempt :tried tried :won (some (pt/jset (pt/jset won "alias" (pairFirst lab)) "model" (pairSecond lab))))) st2))))))))))))))))))

fn withTried won: (Option j/Json) tried: (List j/Json) order: (List String) -> j/Json
  (match won
    ((none) (j/jobj (list (pair "tried" (j/jarr tried)))))
    ((some w) (j/jobj (listAppend (map (fn [(k String)] -> (Pair String j/Json) (pair k (optionOr (pt/jget w k) (j/jnull)))) order) (list (pair "tried" (j/jarr tried)))))))

fn attemptJson r: (Pair (Result Attempt pt/PyErr) srch/HubState) order: (List String) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (match (pairFirst r)
    ((err e) (pair (err e) (pairSecond r)))
    ((ok a) (pair (ok (withTried a.won a.tried order)) (pairSecond r))))

fn ! researchAudit! st: srch/HubState facts: (List j/Json) byUrl: j/Json entries: (List j/Json) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (researchAuditUntil! st facts byUrl entries up dispatch (fn [(u Int64)] -> Int64 9000000000000))

fn ! researchAuditUntil! st: srch/HubState facts: (List j/Json) byUrl: j/Json entries: (List j/Json) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) leftMs: (fn [Int64] -> Int64) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (match (researchAuditPrompt facts byUrl)
    ((err e) (pair (err e) st))
    ((ok prompt)
      (attemptJson
        (chainUntil! entries st (list) prompt up dispatch
          (fn [(text j/Json)] -> (Result j/Json String)
            (let [(v (auditVerdicts (pt/pyStr text)))]
              (if (= (listLength (match v ((j/jobj kvs) kvs) (_ (list)))) 0) (err "no (:check) verdicts") (ok (j/jobj (list (pair "verdicts" v)))))))
          leftMs)
        (list "alias" "model" "verdicts"))))

fn researchRelation pred: j/Json -> (Result (List String) pt/PyErr)
  (let [(bad (valueErr "no (:relation ...) predicate"))]
    (match pred
      ((j/jarr xs)
        (match (listHead xs)
          ((none) (err bad))
          ((some h)
            (if (not (= (atomOf h) (some ":relation")))
              (match h ((j/jstr s) (if (= s ":relation") (relationRest (optionOr (listTail xs) (list))) (err bad))) (_ (err bad)))
              (relationRest (optionOr (listTail xs) (list)))))))
      (_ (err bad))))

fn relationRest rest: (List j/Json) -> (Result (List String) pt/PyErr)
  (let [(split (match (listHead rest)
                 ((some r0) (if (none? (atomOf r0)) (pair (asnText r0) (optionOr (listTail rest) (list))) (pair "" rest)))
                 ((none) (pair "" rest))))]
    (match (asnProps (j/jarr (pairSecond split)) (none))
      ((err e) (err e))
      ((ok props) (ok (list (pairFirst split) (asnText (propGet props "subject" (j/jstr ""))) (asnText (propGet props "object" (j/jstr ""))))))))

fn ! researchExtract! st: srch/HubState topic: String depth: String rawItems: j/Json entries: (List j/Json) triage: Bool up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (attemptJson
    (chainLoop! entries st (list) (researchPrompt topic depth rawItems triage) up dispatch
      (fn [(text j/Json)] -> (Result j/Json String)
        (match (researchParse text triage)
          ((err e) (err (errWord e)))
          ((ok p) (ok (j/jobj (list (pair "props" (pairFirst p)) (pair "facts" (pairSecond p)))))))))
    (list "alias" "model" "props" "facts"))

fn done rep: j/Json status: String reason: String st: srch/HubState -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (pair (ok (pt/jset (pt/jset rep "status" (j/jstr status)) "reason" (j/jstr reason))) st)

fn mergeErrors acc: (List j/Json) more: (List j/Json) -> (List j/Json)
  (fold (fn [(a (List j/Json)) (e j/Json)] -> (List j/Json) (if (listAny? (fn [(x j/Json)] -> Bool (pt/pyEq x e)) a) a (listAppend a (list e)))) acc more)

fn ! researchHubMain! st: srch/HubState topic: String depth: String entries: (List j/Json) compact: j/Json triage: Bool auditEntries: (Option (List j/Json)) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(rep0 (j/jobj (list (pair "topic" (j/jstr topic)) (pair "depth" (j/jstr depth)) (pair "facts" (j/jarr (list))) (pair "sources" (j/jarr (list))))))
        (flash (= depth "flash"))]
    (if (stringEmpty? topic)
      (done rep0 "failed" "no topic" st)
      (let [(sp (srch/executeSearchHub! st topic "auto" (if flash 3 5))) (st1 (pairSecond sp))]
        (match (pairFirst sp)
          ((err e) (pair (err e) st1))
          ((ok sd)
            (let [(results (listOf (optionOr (pt/jget sd "results") (j/jarr (list)))))
                  (errors0 (listOf (optionOr (pt/jget sd "errors") (j/jarr (list)))))]
              (if (listEmpty? results)
                (pair (ok (pt/jset (pt/jset (pt/jset rep0 "status" (j/jstr "noEvidence")) "reason" (j/jstr "no search results")) "errors" (j/jarr errors0))) st1)
                (let [(np (if (or (= depth "bipolar") (= depth "matrix"))
                            (srch/executeSearchHub! st1 (str topic " limitations drawbacks failure overhead criticisms") "auto" 3)
                            (pair (ok (j/jobj (list))) st1)))
                      (st2 (pairSecond np))]
                  (match (pairFirst np)
                    ((err e) (pair (err e) st2))
                    ((ok nd)
                      (let [(negResults (listOf (optionOr (pt/jget nd "results") (j/jarr (list)))))
                            (errors (mergeErrors errors0 (listOf (optionOr (pt/jget nd "errors") (j/jarr (list))))))]
                        (match (parallelCrawlDistill! st2 results (if flash 3 5) (j/jfloat 3.5))
                          ((err e) (pair (err e) st2))
                          ((ok crawled0)
                            (match (if (listEmpty? negResults) (ok (j/jobj (list))) (parallelCrawlDistill! st2 negResults 2 (j/jfloat 3.5)))
                              ((err e) (pair (err e) st2))
                              ((ok crawledN)
                                (let [(crawled (match crawledN ((j/jobj kvs) (fold (fn [(acc j/Json) (p (Pair String j/Json))] -> j/Json (pt/jset acc (pairFirst p) (pairSecond p))) crawled0 kvs)) (_ crawled0)))
                                      (tagged (listAppend (map (fn [(r j/Json)] -> (Pair Bool j/Json) (pair false r)) results) (map (fn [(r j/Json)] -> (Pair Bool j/Json) (pair true r)) negResults)))]
                                  (match (buildEvidence tagged crawled (list))
                                    ((err e) (pair (err e) st2))
                                    ((ok evidence)
                                      (let [(rep1 (pt/jset rep0 "searched" (j/jint (listLength evidence))))
                                            (rep2 (if (listEmpty? errors) rep1 (pt/jset rep1 "errors" (j/jarr errors))))
                                            (cstr (pt/pyStr compact))]
                                        (cond
                                          ((not (or (= cstr "1") (= cstr "auto"))) (done rep2 "unverified" (str "extraction disabled by :compact " cstr "; search results are not facts") st2))
                                          ((listEmpty? entries) (done rep2 "failed" "no research route is configured" st2))
                                          (else (researchTail! st2 rep2 topic depth evidence entries triage auditEntries up dispatch))))))))))))))))))))))

fn listOf v: j/Json -> (List j/Json)
  (match v ((j/jarr xs) xs) (_ (list)))

fn sliceHead v: j/Json k: Int64 -> (Result j/Json pt/PyErr)
  (match v
    ((j/jstr s) (ok (j/jstr (pt/cpPrefix s k))))
    ((j/jarr xs) (ok (j/jarr (listTake xs k))))
    (_ (err (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object is not subscriptable")))))

fn buildEvidence rs: (List (Pair Bool j/Json)) crawled: j/Json acc: (List j/Json) -> (Result (List j/Json) pt/PyErr)
  (match (listHead rs)
    ((none) (ok acc))
    ((some ar)
      (let [(rest (optionOr (listTail rs) (list))) (r (pairSecond ar))]
        (match (srch/jreq r "url")
          ((err e) (err e))
          ((ok u)
            (if (listAny? (fn [(e j/Json)] -> Bool (pt/pyEq (optionOr (pt/jget e "url") (j/jnull)) u)) acc)
              (buildEvidence rest crawled acc)
              (let [(c (match u ((j/jstr us) (optionOr (pt/jget crawled us) (j/jobj (list)))) (_ (j/jobj (list)))))]
                (match (srch/jreq r "title")
                  ((err e) (err e))
                  ((ok title)
                    (let [(dt (optionOr (pt/jget c "distilledText") (j/jnull)))]
                      (match (if (pt/pyTruthy dt) (ok dt) (srch/jreq r "snippet"))
                        ((err e) (err e))
                        ((ok sv)
                          (match (sliceHead sv 1200)
                            ((err e) (err e))
                            ((ok snippet)
                              (match (match u ((j/jstr us) (ok (classifySourceKind us))) (_ (err (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName u) "' object has no attribute 'lower'")))))
                                ((err e) (err e))
                                ((ok kind)
                                  (let [(item0 (j/jobj (list (pair "id" (j/jstr (str "item-" (stringFromInt64 (+ (listLength acc) 1))))) (pair "title" title) (pair "snippet" snippet)
                                                             (pair "url" u) (pair "sourceKind" (j/jstr kind)) (pair "isFalsifying" (j/jbool (pairFirst ar)))
                                                             (pair "crawled" (optionOr (pt/jget c "crawled") (j/jbool false))))))
                                        (tb (optionOr (pt/jget c "tables") (j/jnull)))
                                        (cb (optionOr (pt/jget c "codeBlocks") (j/jnull)))
                                        (item1 (if (pt/pyTruthy tb) (pt/jset item0 "tables" tb) item0))
                                        (item2 (if (pt/pyTruthy cb) (pt/jset item1 "codeBlocks" cb) item1))]
                                    (buildEvidence rest crawled (listAppend acc (list item2))))))))))))))))))))

fn assignRefs facts: (List j/Json) -> (Pair (List j/Json) (List j/Json))
  (fold (fn [(acc (Pair (List j/Json) (List j/Json))) (f j/Json)] -> (Pair (List j/Json) (List j/Json))
          (let [(su (optionOr (pt/jget f "sourceUrl") (j/jnull)))
                (srcs (if (listAny? (fn [(x j/Json)] -> Bool (pt/pyEq x su)) (pairSecond acc)) (pairSecond acc) (listAppend (pairSecond acc) (list su))))
                (idx (fold (fn [(a Int64) (p (Pair Int64 j/Json))] -> Int64 (if (and (< a 0) (pt/pyEq (pairSecond p) su)) (pairFirst p) a)) -1 (enumerate srcs)))]
            (pair (listAppend (pairFirst acc) (list (pt/jset f "srcRef" (j/jint (+ idx 1))))) srcs)))
        (pair (list) (list)) facts)

fn ! researchTail! st: srch/HubState rep: j/Json topic: String depth: String evidence: (List j/Json) entries: (List j/Json) triage: Bool auditEntries: (Option (List j/Json)) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(xp (researchExtract! st topic depth (j/jarr evidence) entries triage up dispatch)) (st1 (pairSecond xp))]
    (match (pairFirst xp)
      ((err e) (pair (err e) st1))
      ((ok ext)
        (let [(tried (optionOr (pt/jget ext "tried") (j/jarr (list))))
              (rep1 (pt/jset rep "tried" tried))]
          (match (pt/jget ext "props")
            ((none) (done rep1 "failed" (str "research chain exhausted after " (stringFromInt64 (listLength (listOf tried))) " model(s)") st1))
            ((some props)
              (let [(facts (listOf (optionOr (pt/jget ext "facts") (j/jarr (list)))))
                    (rep2 (pt/jset (pt/jset rep1 "alias" (optionOr (pt/jget ext "alias") (j/jnull))) "model" (optionOr (pt/jget ext "model") (j/jnull))))]
                (match (researchVerify props facts topic evidence triage)
                  ((err e) (pair (err e) st1))
                  ((ok vr)
                    (let [(passed0 (listOf (optionOr (listGet (listOf vr) 0) (j/jnull))))
                          (rejected (listOf (optionOr (listGet (listOf vr) 1) (j/jnull))))
                          (refs (assignRefs passed0))
                          (passed (pairFirst refs))
                          (rep3 (pt/jset (pt/jset (pt/jset rep2 "rejected" (j/jarr rejected)) "sources" (j/jarr (pairSecond refs))) "facts" (j/jarr passed)))]
                      (cond
                        ((listEmpty? passed) (done rep3 "unverified" (str "0 of " (stringFromInt64 (listLength facts)) " extracted facts passed verification") st1))
                        ((and (not triage) (some? auditEntries)) (auditStage! st1 rep3 props evidence passed rejected (optionOr auditEntries (list)) up dispatch))
                        (else (pair (ok (finishVerified rep3 props triage)) st1)))))))))))))

fn finishVerified rep: j/Json props: j/Json triage: Bool -> j/Json
  (let [(r1 (pt/jset rep "status" (j/jstr "verified")))]
    (if triage
      r1
      (fold (fn [(acc j/Json) (k String)] -> j/Json (match (pt/jget props k) ((some v) (match v ((j/jstr s) (pt/jset acc k v)) (_ acc))) ((none) acc))) r1 (list "summary" "positiveSynthesis" "falsificationCritique"))))

fn auditSort verdicts: j/Json rejected: (List j/Json) passed: (List j/Json) -> (Pair (List j/Json) (List j/Json))
  (fold (fn [(acc (Pair (List j/Json) (List j/Json))) (f j/Json)] -> (Pair (List j/Json) (List j/Json))
          (let [(fid (pt/pyStr (optionOr (pt/jget f "id") (j/jnull))))
                (vw (listOf (optionOr (pt/jget verdicts fid) (j/jarr (list (j/jstr "unsupported") (j/jstr "no verdict from the auditor"))))))
                (verdict (pt/pyStr (optionOr (listGet vw 0) (j/jnull))))
                (why (pt/pyStr (optionOr (listGet vw 1) (j/jnull))))
                (f1 (pt/jset f "audit" (j/jstr verdict)))]
            (cond
              ((= verdict "unsupported") (pair (pairFirst acc) (listAppend (pairSecond acc) (list (j/jstr (str fid ": auditor unsupported: " why))))))
              ((= verdict "partial") (pair (listAppend (pairFirst acc) (list (pt/jset f1 "verificationStatus" (j/jstr "disputed")))) (pairSecond acc)))
              (else (pair (listAppend (pairFirst acc) (list f1)) (pairSecond acc))))))
        (pair (list) rejected) passed)

fn ! auditStage! st: srch/HubState rep: j/Json props: j/Json evidence: (List j/Json) passed: (List j/Json) rejected: (List j/Json) auditEntries: (List j/Json) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(byUrl (fold (fn [(acc j/Json) (e j/Json)] -> j/Json (pt/jset acc (pt/pyStr (optionOr (pt/jget e "url") (j/jnull))) e)) (j/jobj (list)) evidence))
        (ap (researchAudit! st passed byUrl auditEntries up dispatch))
        (st1 (pairSecond ap))]
    (match (pairFirst ap)
      ((err e) (pair (err e) st1))
      ((ok aud)
        (let [(atried (optionOr (pt/jget aud "tried") (j/jarr (list))))
              (rep1 (pt/jset rep "auditTried" atried))]
          (match (pt/jget aud "verdicts")
            ((none)
              (done (pt/jset rep1 "facts" (j/jarr (list))) "unverified"
                    (str "auditor unavailable after " (stringFromInt64 (listLength (listOf atried))) " model(s); " (stringFromInt64 (listLength passed)) " fact(s) not audited") st1))
            ((some verdicts)
              (let [(rep2 (pt/jset rep1 "auditor" (j/jobj (list (pair "alias" (optionOr (pt/jget aud "alias") (j/jnull))) (pair "model" (optionOr (pt/jget aud "model") (j/jnull)))))))
                    (sorted (auditSort verdicts rejected passed))
                    (refs (assignRefs (pairFirst sorted)))
                    (kept (pairFirst refs))
                    (rep3 (pt/jset (pt/jset (pt/jset rep2 "rejected" (j/jarr (pairSecond sorted))) "sources" (j/jarr (pairSecond refs))) "facts" (j/jarr kept)))]
                (if (listEmpty? kept)
                  (done rep3 "unverified" "the auditor supported none of the facts" st1)
                  (pair (ok (finishVerified rep3 props false)) st1)))))))))

fn ! executeResearchHub! st: srch/HubState topic: String depth: String entries: (List j/Json) compact: j/Json triage: Bool auditEntries: (Option (List j/Json)) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (researchHubMain! st topic depth entries compact triage auditEntries up dispatch)

fn researchRelationAsn rel: (List j/Json) -> String
  (let [(verb (optionOr (listGet rel 0) (j/jnull)))
        ]
    (str "(:relation \"" (esc (if (pt/pyTruthy verb) verb (j/jstr "asserts"))) "\" :subject \"" (esc (optionOr (listGet rel 1) (j/jnull)))
         "\" :object \"" (esc (optionOr (listGet rel 2) (j/jnull))) "\")"))

fn esc v: j/Json -> String
  (srch/escapeAsnStr v)

fn repGet rep: j/Json k: String -> j/Json
  (optionOr (pt/jget rep k) (j/jnull))

fn triedLine key: String rows: j/Json -> String
  (str "  :" key " (" (pt/joinSep (map (fn [(t j/Json)] -> String (str "(:alias \"" (srch/escapeAsnStr (repGet t "alias")) "\" :model \"" (srch/escapeAsnStr (repGet t "model")) "\" :error \"" (srch/escapeAsnStr (repGet t "error")) "\")")) (listOf rows)) " ") ")")

fn factLine f: j/Json triage: Bool -> (Result String pt/PyErr)
  (let [(fals (if (pt/pyTruthy (repGet f "isFalsifying")) "true" "false"))]
    (match (srch/jreq f "relation")
      ((err x) (err x))
      ((ok rel)
        (let [(pred (researchRelationAsn (listOf rel)))]
          (if triage
            (match (srch/jreq f "id") ((err x) (err x)) ((ok fid)
              (match (srch/jreq f "srcRef") ((err x) (err x)) ((ok sref)
                (match (srch/jreq f "verificationStatus") ((err x) (err x)) ((ok vs)
                  (ok (str "    (:p :id \"" (esc fid) "\" :predicate " pred " :srcRef " (pt/pyStr sref) " :verificationStatus :" (pt/pyStr vs) " :isFalsifying " fals ")"))))))))
            (match (srch/jreq f "evidence") ((err x) (err x)) ((ok ev)
              (match (sliceHead ev 800) ((err x) (err x)) ((ok ev8)
                (ok (str "    (:fact :id \"" (esc (repGet f "id")) "\" :predicate " pred " :claim \"" (esc (repGet f "claim")) "\" :evidence \"" (esc ev8)
                         "\" :srcRef " (pt/pyStr (repGet f "srcRef")) " :source \"" (esc (repGet f "sourceUrl")) "\" :sourceKind :" (pt/pyStr (repGet f "sourceKind"))
                         " :verificationStatus :" (pt/pyStr (repGet f "verificationStatus")) (if (pt/pyTruthy (repGet f "crawled")) " :crawled true" "")
                         (if (pt/pyTruthy (repGet f "audit")) (str " :audit :" (pt/pyStr (repGet f "audit"))) "") (if (pt/pyTruthy (repGet f "sub")) (str " :sub \"" (esc (repGet f "sub")) "\"") "") " :isFalsifying " fals ")")))))))))))

fn formatResearchAsn rep: j/Json triage: Bool -> (Result String pt/PyErr)
  (let [(t (fn [(k String)] -> Bool (pt/pyTruthy (repGet rep k))))]
    (match (srch/jreq rep "status")
      ((err x) (err x))
      ((ok status)
        (match (collectR (listOf (repGet rep "facts")) (fn [(f j/Json)] -> (Result String pt/PyErr) (factLine f triage)) (list))
          ((err x) (err x))
          ((ok facts)
            (let [(head (if triage ":researchTriage" ":researchReport"))
                  (lines (list
                    (list (str "(" head " :topic \"" (esc (optionOr (pt/jget rep "topic") (j/jstr ""))) "\" :status :" (pt/pyStr status)))
                    (if (t "depth") (list (str "  :depth :" (pt/pyStr (repGet rep "depth")))) (list))
                    (if (t "profile") (list (str "  :profile \"" (esc (repGet rep "profile")) "\"")) (list))
                    (if (t "alias") (list (str "  :alias \"" (esc (repGet rep "alias")) "\" :model \"" (esc (repGet rep "model")) "\"")) (list))
                    (if (t "auditor") (list (str "  :auditor (:alias \"" (esc (repGet (repGet rep "auditor") "alias")) "\" :model \"" (esc (repGet (repGet rep "auditor") "model")) "\")")) (list))
                    (if (t "auditorIndependent") (list (str "  :auditorIndependent " (pt/pyStr (repGet rep "auditorIndependent")) (if (t "auditNote") (str " :auditNote \"" (esc (repGet rep "auditNote")) "\"") ""))) (list))
                    (if (t "reason") (list (str "  :reason \"" (esc (repGet rep "reason")) "\"")) (list))
                    (if (some? (pt/jget rep "searched")) (list (str "  :searched " (pt/pyStr (repGet rep "searched")))) (list))
                    (if (t "tried") (list (triedLine "tried" (repGet rep "tried"))) (list))
                    (if (t "auditTried") (list (triedLine "auditTried" (repGet rep "auditTried"))) (list))
                    (if (t "rejected") (list (str "  :rejected (" (pt/joinSep (map (fn [(r j/Json)] -> String (str "\"" (esc r) "\"")) (listOf (repGet rep "rejected"))) " ") ")")) (list))
                    (if (t "errors") (list (str "  :errors (" (pt/joinSep (map (fn [(x j/Json)] -> String (str "(:engine \"" (esc (optionOr (pt/jget x "engine") (j/jstr ""))) "\" :error \"" (esc (optionOr (pt/jget x "error") (j/jstr ""))) "\")")) (listOf (repGet rep "errors"))) " ") ")")) (list))
                    (planLines rep)
                    (if (and (not triage) (pt/pyEq status (j/jstr "verified")))
                      (fold (fn [(acc (List String)) (k String)] -> (List String) (if (t k) (listAppend acc (list (str "  :" k " \"" (esc (repGet rep k)) "\""))) acc)) (list) (list "summary" "positiveSynthesis" "falsificationCritique"))
                      (list))
                    (list (str "  :facts (" (if (listEmpty? facts) "" (str "\n" (pt/joinSep facts "\n"))) ")"))
                    (list (str "  :sources (" (pt/joinSep (map (fn [(s j/Json)] -> String (str "\"" (esc s) "\"")) (listOf (optionOr (pt/jget rep "sources") (j/jarr (list))))) " ") "))"))))]
              (ok (pt/joinSep (fold (fn [(acc (List String)) (l (List String))] -> (List String) (listAppend acc l)) (list) lines) "\n"))))))))

; (:m :ref RESEARCH-DEPTH :do "depth as a declared mode: a (:mode ...) row of asl/packages/asl-gateway/researchModes.asn names every budget; pipeline plan = decompose the topic, research each sub-question as its own bounded unit, follow up only below the coverage floor, audit once, report coverage per sub-question; pipeline single is researchHubMain! unchanged")
(schema PlanState (:f st srch/HubState) (:f searches Int64) (:f fetches Int64) (:f modelCalls Int64) (:f stopped String) (:f tried (List j/Json)) (:f errors (List j/Json)) (:f alias j/Json) (:f model j/Json) (:f dropped (List String)) (:f seen (List j/Json)) (:f writers (List j/Json)))

fn modeInt mode: j/Json k: String -> Int64
  (match (optionOr (pt/jget mode k) (j/jnull)) ((j/jint v) v) (_ 0))

fn modeStr mode: j/Json k: String -> String
  (match (optionOr (pt/jget mode k) (j/jnull)) ((j/jstr s) s) (_ ""))

fn modeIntKeys -> (List String)
  (list "subQuestions" "queriesPerSub" "resultsPerQuery" "fetchPerQuery" "batchSources" "maxSourcesPerSub" "saturationBatches" "resolveMargin" "maxDepth" "maxChildren" "maxNodes" "childSharedTerms" "childChars" "minFacts" "minSources" "followUpRounds" "followUpQueries" "maxSearches" "maxFetches" "maxModelCalls" "wallSeconds" "queryChars")

fn modeRow forms: (List j/Json) id: String -> (Option j/Json)
  (fold (fn [(acc (Option j/Json)) (f j/Json)] -> (Option j/Json)
          (if (some? acc)
            acc
            (match (asnProps f (some ":mode"))
              ((err _) (none))
              ((ok p) (if (= (lstripColon (asnText (propGet p "id" (j/jstr "")))) id) (some p) (none))))))
        (none) forms)

fn modeAtom p: j/Json k: String d: String -> j/Json
  (j/jstr (lstripColon (asnText (propGet p k (j/jstr d)))))

fn researchModeOf text: String id: String -> (Result j/Json pt/PyErr)
  (match (asnRead text)
    ((err e) (err e))
    ((ok forms)
      (match (if (> (modeCount forms id) 1) (none) (modeRow forms id))
        ((none) (err (valueErr (str "research mode table has " (if (> (modeCount forms id) 1) "more than one" "no") " (:mode :id " id " ...) row"))))
        ((some p)
          (let [(pipeline (pt/pyStr (modeAtom p "pipeline" "")))
                (base (j/jobj (list (pair "id" (j/jstr id)) (pair "pipeline" (j/jstr pipeline)) (pair "depth" (modeAtom p "depth" "targeted"))
                                    (pair "engine" (modeAtom p "engine" "auto")) (pair "decompose" (modeAtom p "decompose" "enumerated"))
                                    (pair "counterQuery" (j/jbool (pt/pyEq (asnScalar (propGet p "counterQuery" (asnAtom "false"))) (j/jbool true))))
                                    (pair "reformulations" (j/jarr (filter (fn [(r j/Json)] -> Bool (match r ((j/jstr s) (not (stringEmpty? s))) (_ false))) (listOf (propGet p "reformulations" (j/jarr (list))))))))))]
            (cond
              ((not (match (propGet p "reformulations" (j/jarr (list))) ((j/jarr _) true) (_ false))) (err (valueErr (str "research mode " id " needs :reformulations as a list of strings"))))
              ((= pipeline "single") (ok base))
              ((not (= pipeline "plan")) (err (valueErr (str "research mode " id " has :pipeline \"" pipeline "\"; allowed: single plan"))))
              (else
                (match (fold (fn [(acc (Result j/Json pt/PyErr)) (k String)] -> (Result j/Json pt/PyErr)
                               (match acc
                                 ((err e) (err e))
                                 ((ok m)
                                   (match (asnScalar (propGet p k (j/jnull)))
                                     ((j/jint v) (if (>= v 0) (ok (pt/jset m k (j/jint v))) (err (valueErr (str "research mode " id " has a negative :" k)))))
                                     (_ (err (valueErr (str "research mode " id " lacks an integer :" k))))))))
                             (ok base) (modeIntKeys))
                  ((err e) (err e))
                  ((ok m)
                    (match (listHead (filter (fn [(k String)] -> Bool (< (modeInt m k) 1)) (list "subQuestions" "queriesPerSub" "resultsPerQuery" "fetchPerQuery" "batchSources" "maxSourcesPerSub" "maxNodes" "maxSearches" "maxFetches" "maxModelCalls" "wallSeconds")))
                      ((some k) (err (valueErr (str "research mode " id " needs :" k " of at least 1"))))
                      ((none) (ok m))))))))))))

; (:m :do "a marker opens a part only at a part boundary: the start of the text, or after sentence or line punctuation (spaces between do not count), so option 1) or version 1. 2 in running text is not an enumeration")
fn partBoundary? bs: Bytes at: Int64 -> Bool
  (if (< at 1)
    true
    (let [(b (bytesGet bs (- at 1)))]
      (if (or (= b 32) (= b 9))
        (partBoundary? bs (- at 1))
        (or (= b 10) (= b 59) (= b 58) (= b 44) (= b 46)))))

fn enumMarks bs: Bytes n: Int64 opener: String closer: String k: Int64 from: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (> k 32)
    acc
    (let [(lit (stringToBytes (str opener (stringFromInt64 k) closer))) (m (bytesLength lit)) (at (pt/findFrom bs n lit m from))
          (end (+ at m))
          (spaced (or (not (= closer ".")) (>= end n) (= (bytesGet bs end) 32) (= (bytesGet bs end) 10) (= (bytesGet bs end) 9)))]
      (cond
        ((< at 0) acc)
        ((and (partBoundary? bs at) spaced) (enumMarks bs n opener closer (+ k 1) end (listAppend acc (list (pair at end)))))
        (else (enumMarks bs n opener closer k (+ at 1) acc)))))

; (:m :do "markers count from 1 and ascend by 1: when the next number already stands before the last marker found, the text is not one enumeration")
fn orderedMarks bs: Bytes n: Int64 opener: String closer: String -> (List (Pair Int64 Int64))
  (let [(marks (enumMarks bs n opener closer 1 0 (list)))
        (lastAt (match (listGet marks (- (listLength marks) 1)) ((some m) (pairFirst m)) ((none) 0)))
        (stray (enumMarks bs n opener closer (+ (listLength marks) 1) 0 (list)))]
    (if (match (listHead stray) ((some s) (< (pairFirst s) lastAt)) ((none) false)) (list) marks))

fn modeCount forms: (List j/Json) id: String -> Int64
  (listLength (filter (fn [(f j/Json)] -> Bool (match (asnProps f (some ":mode")) ((err _) false) ((ok p) (= (lstripColon (asnText (propGet p "id" (j/jstr "")))) id)))) forms))

fn psSeen ps: PlanState urls: (List j/Json) -> PlanState
  (with ps :seen (mergeErrors ps.seen urls))

fn failSub sub: j/Json e: pt/PyErr -> j/Json
  (pt/jset (pt/jset (pt/jset sub "state" (j/jstr "failed")) "stop" (j/jstr "error")) "errors" (j/jarr (listAppend (subList sub "errors") (list (j/jstr (str e.kind ": " e.msg))))))

fn rstripPunct s: String -> String
  (let [(t (pt/pyStrip s))]
    (if (or (stringEndsWith? t ";") (stringEndsWith? t ",") (stringEndsWith? t ":") (stringEndsWith? t "."))
      (rstripPunct (pt/sliceB t 0 (- (stringLength t) 1)))
      t))

; (:m :do "the topic's own enumeration wins over any model split: (1) (2) .., then 1) 2) .., then 1. 2. ..; the stem is the text before the first marker")
fn researchParts topic: String -> (Pair String (List String))
  (let [(bs (stringToBytes topic)) (n (bytesLength bs))
        (marks (fold (fn [(acc (List (Pair Int64 Int64))) (s (Pair String String))] -> (List (Pair Int64 Int64))
                       (if (>= (listLength acc) 2) acc (orderedMarks bs n (pairFirst s) (pairSecond s))))
                     (list) (list (pair "(" ")") (pair "" ")") (pair "" "."))))
        (parts (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
                       (map (fn [(p (Pair Int64 (Pair Int64 Int64)))] -> String
                              (rstripPunct (pt/sliceB topic (pairSecond (pairSecond p)) (match (listGet marks (+ (pairFirst p) 1)) ((some nx) (pairFirst nx)) ((none) n)))))
                            (enumerate marks))))]
    (if (< (listLength parts) 2)
      (pair "" (list))
      (pair (rstripPunct (pt/sliceB topic 0 (match (listHead marks) ((some m) (pairFirst m)) ((none) 0)))) parts)))

fn stemClause stem: String -> String
  (pt/pyStrip (optionOr (listHead (stringSplit stem ",")) stem))

; (:m :do "query variants of one sub-question, in the order rounds consume them: stem clause + part, the bare part, then the part with each declared reformulation; the counter-evidence query belongs to the first round only")
fn subQueries mode: j/Json stem: String part: String -> (List (Pair Bool String))
  (let [(clip (fn [(s String)] -> String (pt/pyStrip (pt/cpPrefix s (max 16 (modeInt mode "queryChars"))))))
        (sc (stemClause stem))
        (lead (if (stringEmpty? sc) (list (pair false (clip part))) (list (pair false (clip (str sc " " part))) (pair false (clip part)))))]
    (listAppend lead (map (fn [(r j/Json)] -> (Pair Bool String) (pair false (clip (str part " " (pt/pyStr r))))) (listOf (optionOr (pt/jget mode "reformulations") (j/jarr (list)))))))

fn subList sub: j/Json k: String -> (List j/Json)
  (listOf (optionOr (pt/jget sub k) (j/jarr (list))))

fn subStr sub: j/Json k: String -> String
  (match (optionOr (pt/jget sub k) (j/jnull)) ((j/jstr s) s) (_ ""))

fn newSub i: Int64 question: String part: String state: String -> j/Json
  (j/jobj (list (pair "id" (j/jstr (str "s" (stringFromInt64 (+ i 1))))) (pair "question" (j/jstr question)) (pair "part" (j/jstr part)) (pair "state" (j/jstr state))
                (pair "evidence" (j/jarr (list))) (pair "facts" (j/jarr (list))) (pair "rejected" (j/jarr (list))) (pair "queries" (j/jarr (list))) (pair "stop" (j/jstr ""))
                (pair "errors" (j/jarr (list)))))

fn distinctJ xs: (List j/Json) -> (List j/Json)
  (mergeErrors (list) xs)

fn urlDomain u: j/Json -> j/Json
  (j/jstr (pt/pyLower (optionOr (listGet (stringSplit (pt/pyStr u) "/") 2) "")))

; (:m :do "the registrable host of a url: no port, no www, the last two labels, or three under a two-letter country code with a generic second level (co.uk, com.au)")
fn sourceDomain u: j/Json -> j/Json
  (let [(host (optionOr (listHead (stringSplit (pt/pyStr (urlDomain u)) ":")) ""))
        (labels (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit host ".")))
        (n (listLength labels))
        (tld (optionOr (listGet labels (- n 1)) ""))
        (second (optionOr (listGet labels (- n 2)) ""))
        (keep (if (and (> n 2) (= (stringLength tld) 2) (listContains? (list "co" "com" "org" "net" "ac" "gov" "edu") second)) 3 2))]
    (j/jstr (pt/joinSep (listDrop labels (max 0 (- n keep))) ".")))

; (:m :do "facts whose evidence text is the same after normalising to lower-case word tokens count once: a mirror or a tracking-parameter copy is not a second finding")
fn distinctEvidence facts: (List j/Json) -> (List j/Json)
  (pairFirst (fold (fn [(acc (Pair (List j/Json) (List String))) (f j/Json)] -> (Pair (List j/Json) (List String))
                     (let [(key (wordNorm (pt/pyStr (optionOr (pt/jget f "evidence") (j/jstr "")))))]
                       (if (and (not (stringEmpty? key)) (listContains? (pairSecond acc) key))
                         acc
                         (pair (listAppend (pairFirst acc) (list f)) (listAppend (pairSecond acc) (list key))))))
                   (pair (list) (list)) facts))

; (:m :do "independent sources of a set of facts: distinct registrable hosts, after facts with the same evidence text are counted once")
fn factSources facts: (List j/Json) -> (List j/Json)
  (distinctJ (map (fn [(f j/Json)] -> j/Json (sourceDomain (optionOr (pt/jget f "sourceUrl") (j/jnull)))) (distinctEvidence facts)))

fn subCovered? mode: j/Json facts: (List j/Json) -> Bool
  (and (>= (listLength (distinctEvidence facts)) (max 1 (modeInt mode "minFacts"))) (>= (listLength (factSources facts)) (modeInt mode "minSources")))

fn wallLeftMs mode: j/Json startMs: Int64 clock: (fn [Int64] -> Int64) -> Int64
  (- (* 1000 (modeInt mode "wallSeconds")) (- (clock 0) startMs))

; (:m :do "empty = the run may go on; a model stage keeps :reserve stages back for the audit")
fn budgetStop ps: PlanState mode: j/Json model: Bool reserve: Int64 startMs: Int64 clock: (fn [Int64] -> Int64) -> String
  (cond
    ((< (wallLeftMs mode startMs clock) 1) "wall")
    ((and model (>= (+ ps.modelCalls reserve) (modeInt mode "maxModelCalls"))) "modelCalls")
    ((and (not model) (>= ps.searches (modeInt mode "maxSearches"))) "searches")
    (else ""))

; (:m :do "a round needs both a search and a model stage: with either budget spent a sub-question is not started and a follow-up is not run")
fn roundStop ps: PlanState mode: j/Json reserve: Int64 startMs: Int64 clock: (fn [Int64] -> Int64) -> String
  (let [(s (budgetStop ps mode false 0 startMs clock))]
    (if (stringEmpty? s) (budgetStop ps mode true reserve startMs clock) s))

fn noteStop ps: PlanState why: String -> PlanState
  (if (stringEmpty? ps.stopped) (with ps :stopped why) ps)

fn psSearched ps: PlanState st: srch/HubState -> PlanState
  (with ps :st st :searches (+ ps.searches 1))

fn psModelCall ps: PlanState st: srch/HubState -> PlanState
  (with ps :st st :modelCalls (+ ps.modelCalls 1))

fn psFetched ps: PlanState k: Int64 -> PlanState
  (with ps :fetches (+ ps.fetches k))

fn psErrors ps: PlanState more: (List j/Json) -> PlanState
  (with ps :errors (mergeErrors ps.errors more))

fn psTried ps: PlanState more: (List j/Json) -> PlanState
  (with ps :tried (mergeErrors ps.tried more))

fn psWriter ps: PlanState alias: j/Json model: j/Json -> PlanState
  (let [(w (if (pt/pyTruthy model) (mergeErrors ps.writers (list model)) ps.writers))]
    (if (pt/pyTruthy ps.model) (with ps :writers w) (with ps :alias alias :model model :writers w)))

fn subInt sub: j/Json k: String -> Int64
  (match (optionOr (pt/jget sub k) (j/jnull)) ((j/jint v) v) (_ 0))

fn setStop sub: j/Json why: String -> j/Json
  (if (stringEmpty? (subStr sub "stop")) (pt/jset sub "stop" (j/jstr why)) sub)

fn counterQueryOf mode: j/Json part: String -> String
  (pt/pyStrip (pt/cpPrefix (str part " limitations drawbacks failure criticisms") (max 16 (modeInt mode "queryChars"))))

fn factCon? f: j/Json -> Bool
  (or (pt/pyTruthy (optionOr (pt/jget f "isFalsifying") (j/jnull)))
      (listContains? (list "disputed" "refuted") (pt/pyStr (optionOr (pt/jget f "verificationStatus") (j/jstr "")))))

; (:m :do "sources contradict each other while both polarities hold verified facts and neither leads by :resolveMargin distinct sources")
fn subConflict? mode: j/Json facts: (List j/Json) -> Bool
  (let [(con (listLength (factSources (filter factCon? facts))))
        (pro (listLength (factSources (filter (fn [(f j/Json)] -> Bool (not (factCon? f))) facts))))]
    (and (> con 0) (> pro 0) (< (if (> pro con) (- pro con) (- con pro)) (max 1 (modeInt mode "resolveMargin")))))

; (:m :do "extract and verify the facts of one batch of evidence against the sub-question; a chain with no reply is an error row on the sub-question, not a failed run")
fn ! batchFacts! ps: PlanState mode: j/Json sub: j/Json fresh: (List j/Json) entries: (List j/Json) triage: Bool up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) leftMs: (fn [Int64] -> Int64) -> (Pair (Result j/Json pt/PyErr) PlanState)
  (cond
    ((listEmpty? fresh) (pair (ok sub) ps))
    ((< (leftMs 0) 1) (pair (ok (setStop sub "budget")) (noteStop ps "wall")))
    (else
    (let [(question (subStr sub "question"))
          (xp (planExtract! ps.st (planPrompt mode question fresh triage) entries triage up dispatch leftMs))
          (ps1 (psModelCall ps (pairSecond xp)))]
      (match (pairFirst xp)
        ((err e) (pair (err e) ps1))
        ((ok ext)
          (let [(ps2 (psTried ps1 (listOf (optionOr (pt/jget ext "tried") (j/jarr (list))))))]
            (match (pt/jget ext "props")
              ((none) (pair (ok (pt/jset sub "errors" (j/jarr (listAppend (subList sub "errors") (list (j/jstr "research chain exhausted")))))) ps2))
              ((some props)
                (match (researchVerify props (listOf (optionOr (pt/jget ext "facts") (j/jarr (list)))) question fresh triage)
                  ((err e) (pair (err e) ps2))
                  ((ok vr)
                    (let [(sid (subStr sub "id"))
                          (passed (map (fn [(f j/Json)] -> j/Json (pt/jset f "sub" (j/jstr sid))) (listOf (optionOr (listGet (listOf vr) 0) (j/jnull)))))
                          (rejected (map (fn [(r j/Json)] -> j/Json (j/jstr (str sid " " (pt/pyStr r)))) (listOf (optionOr (listGet (listOf vr) 1) (j/jnull)))))
                          (opened (filter (fn [(q j/Json)] -> Bool (pt/pyTruthy q)) (map (fn [(q j/Json)] -> j/Json (j/jstr (childText mode q))) (listOf (optionOr (pt/jget props "openQuestions") (j/jarr (list)))))))
                          (sub1 (pt/jset (pt/jset (pt/jset sub "facts" (j/jarr (listAppend (subList sub "facts") passed))) "rejected" (j/jarr (listAppend (subList sub "rejected") rejected))) "open" (j/jarr (distinctJ (listAppend (subList sub "open") opened)))))]
                      (pair (ok sub1) (psWriter ps2 (optionOr (pt/jget ext "alias") (j/jnull)) (optionOr (pt/jget ext "model") (j/jnull)))))))))))))))

; (:m :ref RESEARCH-DEPTH :do "one research unit, as much work as is necessary and sufficient: sources are taken in batches of :batchSources from the results of one query at a time, and after every batch the unit stops as sufficient (floor met, initial queries asked, no open contradiction), goes on while sources contradict each other (a counter-evidence query is added once), stops as saturated after :saturationBatches batches without a new verified fact, as ceiling at :maxSourcesPerSub, as queriesExhausted when its queries are used up, as budget when a shared budget is spent")
fn ! unit! ps: PlanState mode: j/Json sub: j/Json queries: (List (Pair Bool String)) queue: (List (Pair Bool j/Json)) taken: Int64 entries: (List j/Json) triage: Bool reserve: Int64 up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) startMs: Int64 clock: (fn [Int64] -> Int64) -> (Pair (Result j/Json pt/PyErr) PlanState)
  (let [(sources (listLength (subList sub "evidence")))
        (room (min (min (modeInt mode "batchSources") (- (modeInt mode "fetchPerQuery") taken)) (- (modeInt mode "maxSourcesPerSub") sources)))]
    (cond
      ((not (stringEmpty? (subStr sub "stop"))) (pair (ok sub) ps))
      ((>= sources (modeInt mode "maxSourcesPerSub")) (pair (ok (setStop sub "ceiling")) ps))
      ((or (listEmpty? queue) (< room 1))
        (match (listHead queries)
          ((none) (pair (ok (setStop sub "queriesExhausted")) ps))
          ((some q)
            (let [(stop (roundStop ps mode reserve startMs clock))]
              (if (not (stringEmpty? stop))
                (pair (ok (setStop sub "budget")) (noteStop ps stop))
                (let [(sp (srch/executeSearchHub! ps.st (pairSecond q) (modeStr mode "engine") (modeInt mode "resultsPerQuery")))
                      (ps1 (psSearched ps (pairSecond sp)))
                      (sub1 (pt/jset (pt/jset sub "queries" (j/jarr (listAppend (subList sub "queries") (list (j/jstr (pairSecond q)))))) "initialLeft" (j/jint (max 0 (- (subInt sub "initialLeft") 1)))))
                      (rest (optionOr (listTail queries) (list)))]
                  (match (pairFirst sp)
                    ((err e) (unit! (psErrors ps1 (list (j/jobj (list (pair "engine" (j/jstr "search")) (pair "error" (j/jstr (errWord e))))))) mode sub1 rest (list) 0 entries triage reserve up dispatch startMs clock))
                    ((ok sd)
                      (let [(seen ps1.seen)
                            (results (filter (fn [(r j/Json)] -> Bool (not (listAny? (fn [(u j/Json)] -> Bool (pt/pyEq u (optionOr (pt/jget r "url") (j/jnull)))) seen)))
                                             (listOf (optionOr (pt/jget sd "results") (j/jarr (list))))))]
                        (unit! (psErrors ps1 (listOf (optionOr (pt/jget sd "errors") (j/jarr (list))))) mode sub1 rest
                               (map (fn [(r j/Json)] -> (Pair Bool j/Json) (pair (pairFirst q) r)) results) 0 entries triage reserve up dispatch startMs clock))))))))))
      (else
        (let [(mstop (budgetStop ps mode true reserve startMs clock))
              (leftMs (fn [(u Int64)] -> Int64 (wallLeftMs mode startMs clock)))
              (n (min room (- (modeInt mode "maxFetches") ps.fetches)))]
          (cond
            ((not (stringEmpty? mstop)) (pair (ok (setStop sub "budget")) (noteStop ps mstop)))
            ((< n 1) (pair (ok (setStop sub "budget")) (noteStop ps "fetches")))
            (else
              (let [(batch (listTake queue n))
                    (later (listDrop queue n))]
                (match (parallelCrawlDistill! ps.st (map (fn [(b (Pair Bool j/Json))] -> j/Json (pairSecond b)) batch) n (j/jfloat (min 3.5 (/ (int64ToFloat64 (max 1 (leftMs 0))) 1000.0))))
                  ((err e) (pair (err e) ps))
                  ((ok crawled)
                    (match (buildEvidence batch crawled (subList sub "evidence"))
                      ((err e) (pair (err e) ps))
                      ((ok evidence)
                        (let [(xp (batchFacts! (psSeen (psFetched ps (listLength batch)) (map (fn [(b (Pair Bool j/Json))] -> j/Json (optionOr (pt/jget (pairSecond b) "url") (j/jnull))) batch)) mode (pt/jset sub "evidence" (j/jarr evidence)) (listDrop evidence sources) entries triage up dispatch leftMs))
                              (ps1 (pairSecond xp))]
                          (match (pairFirst xp)
                            ((err e) (pair (err e) ps1))
                            ((ok sub2)
                              (let [(facts (subList sub2 "facts"))
                                    (chainDead (> (listLength (subList sub2 "errors")) (listLength (subList sub "errors"))))
                                    (live (listAny? (fn [(e j/Json)] -> Bool (pt/pyTruthy (optionOr (pt/jget e "crawled") (j/jnull)))) (listDrop evidence sources)))
                                    (streak (cond
                                              ((> (listLength facts) (listLength (subList sub "facts"))) 0)
                                              ((or chainDead (not live)) (subInt sub "streak"))
                                              (else (+ (subInt sub "streak") 1))))
                                    (conflict (subConflict? mode facts))
                                    (settled (and (subCovered? mode facts) (not conflict)))
                                    (counter (and conflict (not (pt/pyTruthy (optionOr (pt/jget sub2 "countered") (j/jnull))))))
                                    (sub3 (pt/jset (pt/jset sub2 "streak" (j/jint streak)) "countered" (j/jbool (or counter (pt/pyTruthy (optionOr (pt/jget sub2 "countered") (j/jnull)))))))
                                    (queries1 (if counter (cons (pair true (counterQueryOf mode (subStr sub "part"))) queries) queries))
                                    (took (+ taken (listLength batch)))]
                                (cond
                                  ((and settled (< (subInt sub3 "initialLeft") 1)) (pair (ok (setStop sub3 "sufficient")) ps1))
                                  (settled (unit! ps1 mode sub3 queries1 (list) 0 entries triage reserve up dispatch startMs clock))
                                  (conflict (unit! ps1 mode sub3 queries1 later took entries triage reserve up dispatch startMs clock))
                                  ((>= streak (max 1 (modeInt mode "saturationBatches"))) (pair (ok (setStop sub3 "saturated")) ps1))
                                  (else (unit! ps1 mode sub3 queries1 later took entries triage reserve up dispatch startMs clock))))))))))))))))))

fn psDropped ps: PlanState more: (List String) -> PlanState
  (with ps :dropped (listAppend ps.dropped more))

; (:m :ref RESEARCH-DEPTH :do "the extraction prompt of a mode that may grow children asks, after the pinned research prompt, for an optional :openQuestions list; a mode of depth 0 sends the pinned prompt unchanged")
fn planPrompt mode: j/Json question: String fresh: (List j/Json) triage: Bool -> String
  (let [(base (researchPrompt question (modeStr mode "depth") (j/jarr fresh) triage))]
    (if (< (modeInt mode "maxDepth") 1)
      base
      (str base "\n\nOpen questions: beside :facts the form may carry :openQuestions (\"...\" ...) with at most " (stringFromInt64 (max 1 (modeInt mode "maxChildren")))
           " short questions a web search can answer, each raised but not answered by the evidence above: a gap, a point on which the sources contradict each other, or a term the facts depend on that no source defines. Without such a question the key is left out.\n")))

fn ! planExtract! st: srch/HubState prompt: String entries: (List j/Json) triage: Bool up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) leftMs: (fn [Int64] -> Int64) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (attemptJson
    (chainUntil! entries st (list) prompt up dispatch
      (fn [(text j/Json)] -> (Result j/Json String)
        (match (researchParse text triage)
          ((err e) (err (errWord e)))
          ((ok p) (ok (j/jobj (list (pair "props" (pairFirst p)) (pair "facts" (pairSecond p))))))))
      leftMs)
    (list "alias" "model" "props" "facts"))

; (:m :do "a child question is data, never plan control: only the string items of the extractor's :openQuestions field, rebuilt from their word tokens in lower case and cut to :childChars")
fn childText mode: j/Json v: j/Json -> String
  (match v
    ((j/jstr s) (pt/pyStrip (pt/cpPrefix (pt/joinSep (researchWords (j/jstr s)) " ") (max 8 (modeInt mode "childChars")))))
    (_ ""))

fn wordNorm s: String -> String
  (pt/joinSep (researchWords (j/jstr s)) " ")

fn keyTerms s: String -> (List String)
  (filter (fn [(w String)] -> Bool (>= (stringLength w) 4)) (researchWords (j/jstr s)))

; (:m :ref RESEARCH-DEPTH :do "children of a finished unit, regulated by the mode row: none below :maxDepth, none that repeats a node by normalised text, none that shares fewer than :childSharedTerms key terms with the root topic or the parent question, at most :maxChildren per node and :maxNodes in the tree; every candidate not spawned is counted by its reason")
fn growChildren mode: j/Json root: String sub: j/Json known: (List String) total: Int64 -> (Pair (List j/Json) (List String))
  (let [(depth (subInt sub "depth"))
        (pid (subStr sub "id"))
        (anchor (listAppend (keyTerms root) (keyTerms (subStr sub "question"))))
        (out (fold (fn [(acc (Pair (List j/Json) (List String))) (c j/Json)] -> (Pair (List j/Json) (List String))
                     (let [(text (pt/pyStr c))
                           (kids (pairFirst acc))
                           (taken (listAppend known (map (fn [(k j/Json)] -> String (wordNorm (subStr k "part"))) kids)))
                           (shared (listLength (filter (fn [(w String)] -> Bool (listContains? anchor w)) (keyTerms text))))
                           (why (cond
                                  ((= (subStr sub "stop") "budget") "budget")
                                  ((>= depth (modeInt mode "maxDepth")) "depth")
                                  ((listContains? taken (wordNorm text)) "duplicate")
                                  ((< shared (max 1 (modeInt mode "childSharedTerms"))) "irrelevant")
                                  ((>= (listLength kids) (modeInt mode "maxChildren")) "children")
                                  ((>= (+ total (listLength kids)) (modeInt mode "maxNodes")) "nodes")
                                  (else "")))]
                       (if (stringEmpty? why)
                         (pair (listAppend kids (list (pt/jset (pt/jset (pt/jset (newSub 0 text text "") "id" (j/jstr (str pid "." (stringFromInt64 (+ (listLength kids) 1))))) "parent" (j/jstr pid)) "depth" (j/jint (+ depth 1)))))
                               (pairSecond acc))
                         (pair kids (listAppend (pairSecond acc) (list why))))))
                   (pair (list) (list)) (subList sub "open")))]
    out)

; (:m :ref RESEARCH-DEPTH :do "the research tree, breadth first: every node is one unit; a finished node may append children to the queue; all nodes share the run's budgets")
fn ! planSubs! ps: PlanState mode: j/Json stem: String root: String subs: (List j/Json) acc: (List j/Json) entries: (List j/Json) triage: Bool reserve: Int64 up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) startMs: Int64 clock: (fn [Int64] -> Int64) -> (Pair (Result (List j/Json) pt/PyErr) PlanState)
  (match (listHead subs)
    ((none) (pair (ok acc) ps))
    ((some sub)
      (let [(rest (optionOr (listTail subs) (list)))
            (stop (roundStop ps mode reserve startMs clock))]
        (cond
          ((= (subStr sub "state") "budget") (planSubs! (noteStop ps "subQuestions") mode stem root rest (listAppend acc (list (setStop sub "budget"))) entries triage reserve up dispatch startMs clock))
          ((not (stringEmpty? stop)) (planSubs! (noteStop ps stop) mode stem root rest (listAppend acc (list (setStop (pt/jset sub "state" (j/jstr "budget")) "budget"))) entries triage reserve up dispatch startMs clock))
          (else
            (let [(part (subStr sub "part"))
                  (variants (subQueries mode (if (> (subInt sub "depth") 0) "" stem) part))
                  (pre (pt/pyTruthy (optionOr (pt/jget mode "counterQuery") (j/jnull))))
                  (initial (listAppend (listTake variants (modeInt mode "queriesPerSub")) (if pre (list (pair true (counterQueryOf mode part))) (list))))
                  (follow (listTake (listDrop variants (modeInt mode "queriesPerSub")) (* (modeInt mode "followUpRounds") (modeInt mode "followUpQueries"))))
                  (sub0 (pt/jset (pt/jset sub "initialLeft" (j/jint (listLength initial))) "countered" (j/jbool pre)))
                  (rp (unit! ps mode sub0 (listAppend initial follow) (list) 0 entries triage reserve up dispatch startMs clock))]
              (match (pairFirst rp)
                ((err e) (planSubs! (pairSecond rp) mode stem root rest (listAppend acc (list (failSub sub0 e))) entries triage reserve up dispatch startMs clock))
                ((ok sub1)
                  (let [(grown (growChildren mode root sub1 (map (fn [(k j/Json)] -> String (wordNorm (subStr k "part"))) (listAppend acc (cons sub1 rest))) (+ (+ (listLength acc) 1) (listLength rest))))
                        (ps1 (psDropped (pairSecond rp) (pairSecond grown)))]
                    (planSubs! (if (listContains? (pairSecond grown) "nodes") (noteStop ps1 "nodes") ps1) mode stem root (listAppend rest (pairFirst grown)) (listAppend acc (list sub1)) entries triage reserve up dispatch startMs clock))))))))))

fn decomposePrompt topic: String k: Int64 -> String
  (pt/treeJoin (list
    "Research planning: the topic below splits into at most " (stringFromInt64 k) " independent sub-questions that together cover it.\n"
    "Each sub-question is one short line a web search engine can answer on its own, naming its subject in full; none repeats another.\n"
    "The reply is read by an ASN parser: one form only, parentheses only; markdown code fences, JSON, brackets and backticks make it unreadable.\n\n"
    "Format specification:\n(:subQuestions \"first sub-question\" \"second sub-question\" ...)\n\n"
    "Topic: " topic "\n"))

fn parseSubQuestions text: j/Json k: Int64 -> (Result j/Json String)
  (match (extractOutermostSexpr (pt/pyStr text))
    ((none) (err "reply holds no (:subQuestions ...) form"))
    ((some sx)
      (match (asnRead (researchDebracket sx))
        ((err e) (err (errWord e)))
        ((ok forms)
          (match (optionOr (listHead forms) (j/jnull))
            ((j/jarr xs)
              (let [(qs (listTake (filter (fn [(q j/Json)] -> Bool (match q ((j/jstr s) (not (stringEmpty? (pt/pyStrip s)))) (_ false))) (optionOr (listTail xs) (list))) (max k 0)))]
                (cond
                  ((not (= (optionOr (atomOf (optionOr (listHead xs) (j/jnull))) "") ":subQuestions")) (err "reply holds no (:subQuestions ...) form"))
                  ((< (listLength qs) 2) (err "fewer than two sub-questions"))
                  (else (ok (j/jobj (list (pair "questions" (j/jarr qs)))))))))
            (_ (err "reply holds no (:subQuestions ...) form")))))))

; (:m :do "sub-questions and their origin: the topic's own enumerated parts; else, when the mode says :decompose model, one model stage; else the topic itself as the only unit. Parts beyond :subQuestions stay in the plan as state budget so the report names them")
fn ! decompose! ps: PlanState mode: j/Json topic: String entries: (List j/Json) reserve: Int64 up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) startMs: Int64 clock: (fn [Int64] -> Int64) -> (Pair (Result (Pair (Pair String String) (List j/Json)) pt/PyErr) PlanState)
  (let [(cap (modeInt mode "subQuestions"))
        (sp (researchParts topic))
        (stem (pairFirst sp))
        (subsOf (fn [(qs (List String)) (st0 String)] -> (List j/Json)
                  (map (fn [(p (Pair Int64 String))] -> j/Json
                         (newSub (pairFirst p) (if (stringEmpty? st0) (pairSecond p) (str st0 ": " (pairSecond p))) (pairSecond p) (if (< (pairFirst p) cap) "" "budget")))
                       (enumerate qs))))]
    (cond
      ((and (not (= (modeStr mode "decompose") "none")) (not (listEmpty? (pairSecond sp)))) (pair (ok (pair (pair "enumerated" stem) (subsOf (pairSecond sp) stem))) ps))
      ((or (not (= (modeStr mode "decompose") "model")) (< cap 2) (not (stringEmpty? (budgetStop ps mode true reserve startMs clock))))
        (pair (ok (pair (pair "none" "") (subsOf (list topic) ""))) ps))
      (else
        (let [(ap (attemptJson (chainUntil! entries ps.st (list) (decomposePrompt topic cap) up dispatch (fn [(text j/Json)] -> (Result j/Json String) (parseSubQuestions text cap)) (fn [(u Int64)] -> Int64 (wallLeftMs mode startMs clock))) (list "alias" "model" "questions")))
              (ps1 (psModelCall ps (pairSecond ap)))]
          (match (pairFirst ap)
            ((err e) (pair (err e) ps1))
            ((ok won)
              (let [(qs (map (fn [(q j/Json)] -> String (pt/pyStrip (pt/pyStr q))) (listOf (optionOr (pt/jget won "questions") (j/jarr (list))))))
                    (ps2 (psTried ps1 (listOf (optionOr (pt/jget won "tried") (j/jarr (list))))))]
                (if (< (listLength qs) 2)
                  (pair (ok (pair (pair "none" "") (subsOf (list topic) ""))) ps2)
                  (pair (ok (pair (pair "model" "") (subsOf qs ""))) ps2)))))))))

; (:m :do "an auditor that is not the writer's model goes first; the report says whether the one that answered is independent")
fn auditOrder entries: (List j/Json) writers: (List j/Json) -> (List j/Json)
  (let [(same (fn [(e j/Json)] -> Bool (match (researchEntryLabel e) ((ok lab) (listAny? (fn [(w j/Json)] -> Bool (pt/pyEq (pairSecond lab) w)) writers)) ((err _) false))))]
    (listAppend (filter (fn [(e j/Json)] -> Bool (not (same e))) entries) (filter same entries)))

fn coverageRow mode: j/Json sub: j/Json kept: (List j/Json) -> j/Json
  (let [(sid (subStr sub "id"))
        (facts (filter (fn [(f j/Json)] -> Bool (pt/pyEq (optionOr (pt/jget f "sub") (j/jnull)) (j/jstr sid))) kept))
        (state (cond
                 ((= (subStr sub "state") "failed") "failed")
                 ((= (subStr sub "state") "budget") "budget")
                 ((subConflict? mode facts) "contested")
                 ((subCovered? mode facts) "covered")
                 ((listEmpty? facts) "noEvidence")
                 (else "thin")))]
    (j/jobj (list (pair "id" (j/jstr sid)) (pair "state" (j/jstr state)) (pair "stop" (j/jstr (if (stringEmpty? (subStr sub "stop")) "budget" (subStr sub "stop")))) (pair "facts" (j/jint (listLength facts))) (pair "factSources" (j/jint (listLength (factSources facts))))
                  (pair "sourcesTaken" (j/jint (listLength (subList sub "evidence")))) (pair "searches" (j/jint (listLength (subList sub "queries"))))
                  (pair "error" (optionOr (listHead (subList sub "errors")) (j/jstr ""))) (pair "parent" (j/jstr (subStr sub "parent"))) (pair "depth" (j/jint (subInt sub "depth"))) (pair "question" (j/jstr (subStr sub "question"))))))

fn planReport rep: j/Json mode: j/Json origin: String subs: (List j/Json) ps: PlanState kept: (List j/Json) rejected: (List j/Json) evidence: (List j/Json) -> j/Json
  (let [(refs (assignRefs kept))
        (rows (map (fn [(s j/Json)] -> j/Json (coverageRow mode s (pairFirst refs))) subs))
        (tops (filter (fn [(r j/Json)] -> Bool (pt/pyEq (optionOr (pt/jget r "depth") (j/jnull)) (j/jint 0))) rows))
        (gaps (filter (fn [(r j/Json)] -> Bool (not (pt/pyEq (optionOr (pt/jget r "state") (j/jnull)) (j/jstr "covered")))) tops))
        (count (fn [(why String)] -> j/Json (j/jint (listLength (filter (fn [(d String)] -> Bool (= d why)) ps.dropped)))))
        (urls (distinctJ (map (fn [(e j/Json)] -> j/Json (optionOr (pt/jget e "url") (j/jnull))) evidence)))
        (plan (j/jobj (list (pair "mode" (j/jstr (modeStr mode "id"))) (pair "decomposition" (j/jstr origin)) (pair "subQuestions" (j/jint (listLength tops)))
                            (pair "tree" (j/jobj (list (pair "nodes" (j/jint (listLength subs))) (pair "depthCeiling" (j/jint (modeInt mode "maxDepth"))) (pair "childrenCeiling" (j/jint (modeInt mode "maxChildren"))) (pair "nodeCeiling" (j/jint (modeInt mode "maxNodes")))
                                                       (pair "duplicate" (count "duplicate")) (pair "irrelevant" (count "irrelevant")) (pair "depth" (count "depth")) (pair "children" (count "children")) (pair "nodes!" (count "nodes")) (pair "budget" (count "budget")))))
                            (pair "floor" (j/jobj (list (pair "minFacts" (j/jint (max 1 (modeInt mode "minFacts")))) (pair "minSources" (j/jint (modeInt mode "minSources"))))))
                            (pair "followUpRounds" (j/jint (modeInt mode "followUpRounds"))) (pair "batchSources" (j/jint (modeInt mode "batchSources"))) (pair "sourceCeiling" (j/jint (modeInt mode "maxSourcesPerSub")))
                            (pair "budget" (j/jobj (list (pair "searches" (j/jint (modeInt mode "maxSearches"))) (pair "fetches" (j/jint (modeInt mode "maxFetches")))
                                                         (pair "modelCalls" (j/jint (modeInt mode "maxModelCalls"))) (pair "wallSeconds" (j/jint (modeInt mode "wallSeconds"))))))
                            (pair "spent" (j/jobj (list (pair "searches" (j/jint ps.searches)) (pair "fetches" (j/jint ps.fetches)) (pair "modelCalls" (j/jint ps.modelCalls)))))
                            (pair "stoppedBy" (j/jstr (if (stringEmpty? ps.stopped) "none" ps.stopped)))
                            (pair "domains" (j/jint (listLength (distinctJ (map urlDomain urls))))))))
        (r1 (pt/jset (pt/jset (pt/jset (pt/jset rep "plan" plan) "coverage" (j/jarr rows)) "uncovered" (j/jarr (map (fn [(r j/Json)] -> j/Json (optionOr (pt/jget r "question") (j/jnull))) gaps))) "searched" (j/jint (listLength urls))))
        (r2 (pt/jset (pt/jset (pt/jset r1 "facts" (j/jarr (pairFirst refs))) "sources" (j/jarr (pairSecond refs))) "rejected" (j/jarr rejected)))
        (r3 (if (listEmpty? ps.tried) r2 (pt/jset r2 "tried" (j/jarr ps.tried))))
        (r4 (if (listEmpty? ps.errors) r3 (pt/jset r3 "errors" (j/jarr ps.errors))))
        (r5 (if (pt/pyTruthy ps.model) (pt/jset (pt/jset r4 "alias" ps.alias) "model" ps.model) r4))
        (covered (- (listLength tops) (listLength gaps)))
        (gap (if (listEmpty? gaps) "" (str (stringFromInt64 (listLength gaps)) " of " (stringFromInt64 (listLength tops)) " sub-questions below the coverage floor"
                                           (if (stringEmpty? ps.stopped) "" (str "; stopped by the " ps.stopped " budget")))))]
    (cond
      ((listEmpty? evidence) (pt/jset (pt/jset r5 "status" (j/jstr "noEvidence")) "reason" (j/jstr (if (stringEmpty? ps.stopped) "no search results" (str "no search results; stopped by the " ps.stopped " budget")))))
      ((listEmpty? kept) (pt/jset (pt/jset r5 "status" (j/jstr "unverified")) "reason" (j/jstr (str "no fact passed verification; " gap))))
      (else
        (let [(r6 (pt/jset (pt/jset r5 "status" (j/jstr "verified")) "summary"
                           (j/jstr (str (stringFromInt64 covered) " of " (stringFromInt64 (listLength tops)) " sub-questions reached the coverage floor; "
                                        (if (listEmpty? gaps) "none stayed open" (str "without enough evidence: " (pt/joinSep (map (fn [(r j/Json)] -> String (pt/pyStr (optionOr (pt/jget r "question") (j/jnull)))) gaps) " | ")))))))]
          (if (stringEmpty? gap) r6 (pt/jset r6 "reason" (j/jstr gap)))))))

fn ! planAudit! ps: PlanState rep: j/Json mode: j/Json origin: String subs: (List j/Json) facts: (List j/Json) rejected: (List j/Json) evidence: (List j/Json) auditEntries: (List j/Json) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) leftMs: (fn [Int64] -> Int64) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(byUrl (fold (fn [(acc j/Json) (e j/Json)] -> j/Json (pt/jset acc (pt/pyStr (optionOr (pt/jget e "url") (j/jnull))) e)) (j/jobj (list)) evidence))
        (ap (researchAuditUntil! ps.st facts byUrl (auditOrder auditEntries ps.writers) up dispatch leftMs))
        (ps1 (psModelCall ps (pairSecond ap)))]
    (match (pairFirst ap)
      ((err e) (pair (err e) ps1.st))
      ((ok aud)
        (let [(rep1 (pt/jset rep "auditTried" (optionOr (pt/jget aud "tried") (j/jarr (list)))))]
          (match (pt/jget aud "verdicts")
            ((none)
              (let [(r (planReport rep1 mode origin subs ps1 (list) rejected evidence))]
                (pair (ok (pt/jset (pt/jset r "status" (j/jstr "unverified")) "reason"
                                   (j/jstr (str "auditor unavailable after " (stringFromInt64 (listLength (listOf (optionOr (pt/jget aud "tried") (j/jarr (list)))))) " model(s); " (stringFromInt64 (listLength facts)) " fact(s) not audited"))))
                      ps1.st)))
            ((some verdicts)
              (let [(amodel (optionOr (pt/jget aud "model") (j/jnull)))
                    (independent (not (listAny? (fn [(w j/Json)] -> Bool (pt/pyEq amodel w)) ps1.writers)))
                    (rep2 (pt/jset (pt/jset rep1 "auditor" (j/jobj (list (pair "alias" (optionOr (pt/jget aud "alias") (j/jnull))) (pair "model" amodel)))) "auditorIndependent" (j/jstr (if independent "true" "false"))))
                    (rep3 (if independent rep2 (pt/jset rep2 "auditNote" (j/jstr "the auditor is the writer's model: the audit chain of this profile has no other entry that answered"))))
                    (sorted (auditSort verdicts rejected facts))]
                (pair (ok (planReport rep3 mode origin subs ps1 (pairFirst sorted) (pairSecond sorted) evidence)) ps1.st))))))))

fn ! executeResearchPlan! st: srch/HubState topic: String mode: j/Json entries: (List j/Json) triage: Bool auditEntries: (Option (List j/Json)) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) startMs: Int64 clock: (fn [Int64] -> Int64) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(rep0 (j/jobj (list (pair "topic" (j/jstr topic)) (pair "depth" (j/jstr (modeStr mode "id"))) (pair "facts" (j/jarr (list))) (pair "sources" (j/jarr (list))))))
        (audits (if triage (list) (optionOr auditEntries (list))))
        (reserve (if (listEmpty? audits) 0 1))
        (ps0 (PlanState :st st :searches 0 :fetches 0 :modelCalls 0 :stopped "" :tried (list) :errors (list) :alias (j/jnull) :model (j/jnull) :dropped (list) :seen (list) :writers (list)))]
    (cond
      ((stringEmpty? topic) (done rep0 "failed" "no topic" st))
      ((listEmpty? entries) (done rep0 "failed" "no research route is configured" st))
      (else
        (let [(dp (decompose! ps0 mode topic entries reserve up dispatch startMs clock)) (ps1 (pairSecond dp))]
          (match (pairFirst dp)
            ((err e) (pair (err e) ps1.st))
            ((ok d)
              (let [(origin (pairFirst (pairFirst d)))
                    (sp (planSubs! ps1 mode (pairSecond (pairFirst d)) topic (pairSecond d) (list) entries triage reserve up dispatch startMs clock))
                    (ps2 (pairSecond sp))]
                (match (pairFirst sp)
                  ((err e) (pair (err e) ps2.st))
                  ((ok subs)
                    (let [(gatherAll (fn [(k String)] -> (List j/Json) (fold (fn [(acc (List j/Json)) (s j/Json)] -> (List j/Json) (listAppend acc (subList s k))) (list) subs)))
                          (facts (map (fn [(p (Pair Int64 j/Json))] -> j/Json (pt/jset (pairSecond p) "id" (j/jstr (str "fact-" (stringFromInt64 (+ (pairFirst p) 1)))))) (enumerate (gatherAll "facts"))))
                          (rejected (gatherAll "rejected"))
                          (evidence (gatherAll "evidence"))]
                      (cond
                        ((or (listEmpty? facts) (listEmpty? audits)) (pair (ok (planReport rep0 mode origin subs ps2 facts rejected evidence)) ps2.st))
                        ((= (budgetStop ps2 mode false 0 startMs clock) "wall")
                          (pair (ok (pt/jset (pt/jset (planReport rep0 mode origin subs (noteStop ps2 "wall") facts rejected evidence) "status" (j/jstr "unverified")) "reason" (j/jstr "the wall budget was spent before the audit stage; the facts are not audited"))) ps2.st))
                        (else (planAudit! ps2 rep0 mode origin subs facts rejected evidence audits up dispatch (fn [(u Int64)] -> Int64 (wallLeftMs mode startMs clock)))))))))))))))

fn planLines rep: j/Json -> (List String)
  (match (pt/jget rep "plan")
    ((none) (list))
    ((some p)
      (let [(g (fn [(o j/Json) (k String)] -> String (pt/pyStr (repGet o k))))
            (b (repGet p "budget")) (s (repGet p "spent")) (f (repGet p "floor")) (t (repGet p "tree"))]
        (list (str "  :plan (:mode :" (g p "mode") " :decomposition :" (g p "decomposition") " :subQuestions " (g p "subQuestions")
                   " :floor (:minFacts " (g f "minFacts") " :minSources " (g f "minSources") ") :batchSources " (g p "batchSources") " :sourceCeiling " (g p "sourceCeiling") " :followUpRounds " (g p "followUpRounds")
                   " :budget (:searches " (g b "searches") " :fetches " (g b "fetches") " :modelCalls " (g b "modelCalls") " :wallSeconds " (g b "wallSeconds")
                   ") :spent (:searches " (g s "searches") " :fetches " (g s "fetches") " :modelCalls " (g s "modelCalls") ") :stoppedBy :" (g p "stoppedBy") " :domains " (g p "domains")
                   " :tree (:nodes " (g t "nodes") " :depthCeiling " (g t "depthCeiling") " :childrenCeiling " (g t "childrenCeiling") " :nodeCeiling " (g t "nodeCeiling")
                   " :notSpawned (:duplicate " (g t "duplicate") " :irrelevant " (g t "irrelevant") " :depth " (g t "depth") " :children " (g t "children") " :nodes " (g t "nodes!") " :budget " (g t "budget") ")))")
              (str "  :coverage ("
                   (pt/treeJoin (map (fn [(r j/Json)] -> String
                                       (str "\n    (:sub :id \"" (esc (repGet r "id")) "\" :state :" (g r "state") " :stop :" (g r "stop") " :facts " (g r "facts") " :factSources " (g r "factSources") " :sourcesTaken " (g r "sourcesTaken")
                                            " :searches " (g r "searches") (if (pt/pyTruthy (repGet r "error")) (str " :error \"" (esc (repGet r "error")) "\"") "") (if (pt/pyTruthy (repGet r "parent")) (str " :parent \"" (esc (repGet r "parent")) "\"") "") " :question \"" (esc (repGet r "question")) "\")"))
                                     (listOf (repGet rep "coverage"))))
                   ")")
              (str "  :uncovered (" (pt/joinSep (map (fn [(q j/Json)] -> String (str "\"" (esc q) "\"")) (listOf (repGet rep "uncovered"))) " ") ")")))))

; (:m :ref SEARCH-KEYS-FILE :do "search engine keys absent from the process env (bounded.asl and Leon runs strip it) come from the key files the gateway reads, so (:search) and (:research) see SYNTHETIC/TAVILY/BRAVE/SERPER without exporting them")
fn searchKeyNames -> (List String)
  (list "SYNTHETIC_API_KEY" "TAVILY_API_KEY" "BRAVE_API_KEY" "SERPER_API_KEY")

fn ! withSearchKeys! env: (Map String String) paths: (List String) -> (Map String String)
  (fold (fn [(m (Map String String)) (k String)] -> (Map String String)
          (if (stringEmpty? (optionOr (mapGet m k) ""))
            (match (cfg/keyFileLookup! paths k) ((some v) (mapSet m k v)) ((none) m))
            m))
        env (searchKeyNames))

fn researchTemp p: cfg/GatewayParams -> (List (Pair String j/Json))
  (match p.temperature ((some v) (list (pair "temperature" (j/jfloat v)))) ((none) (list)))

fn researchEffort p: cfg/GatewayParams -> (List (Pair String j/Json))
  (match p.effort ((some v) (list (pair "effort" (j/jstr v)))) ((none) (list)))

fn researchMaxTokens p: cfg/GatewayParams -> (List (Pair String j/Json))
  (match p.maxTokens ((some v) (list (pair "maxTokens" (j/jint v)))) ((none) (list)))

fn researchParams p: cfg/GatewayParams -> j/Json
  (j/jobj (listAppend (listAppend (researchTemp p) (researchEffort p)) (researchMaxTokens p)))

fn researchEntryJson e: cfg/GatewayEntry -> j/Json
  (let [(u e.upstream)]
    (j/jobj (list (pair "alias" (j/jstr e.alias))
      (pair "dispatch" (j/jstr e.dispatch))
      (pair "upstream" (j/jobj (list
        (pair "provider" (j/jstr u.provider))
        (pair "url" (j/jstr u.url))
        (pair "key" (j/jstr u.key)))))
      (pair "params" (researchParams e.params))
      (pair "timeoutSec" (j/jfloat e.timeoutSec))
      (pair "rpm" (match e.rpm ((some v) (j/jfloat v)) ((none) (j/jnull)))))))

fn resolvedResearchEntry r: cfg/GatewayResolvedEntry -> (Result j/Json pt/PyErr)
  (match r
    ((cfg/entryResolved e) (ok (researchEntryJson e)))
    ((cfg/entryUnresolved a) (err (pt/pyErr "ValueError" (str "unresolved research route " a)))))

fn resolvedResearchEntries entries: (List cfg/GatewayResolvedEntry) -> (Result (List j/Json) pt/PyErr)
  (match (listHead entries)
    ((none) (ok (list)))
    ((some entry)
      (match (resolvedResearchEntry entry)
        ((err e) (err e))
        ((ok json)
          (match (resolvedResearchEntries (optionOr (listTail entries) (list)))
            ((err e) (err e))
            ((ok rest) (ok (cons json rest))))))))

fn researchLabelMatches entry: j/Json model: String -> Bool
  (or (stringContains? (pt/pyStr (optionOr (pt/jget entry "alias") (j/jstr ""))) model)
      (stringContains? (pt/pyStr (optionOr (pt/jget entry "dispatch") (j/jstr ""))) model))

fn researchRoutesFor! table: cfg/GatewayTable profile: (Option String) intent: String model: String -> (Result (Pair String (List j/Json)) pt/PyErr)
  (match (cfg/gatewayRouteEntries! table (list) profile intent)
    ((err message) (err (pt/pyErr "ValueError" message)))
    ((ok routes)
      (match (resolvedResearchEntries routes.entries)
        ((err e) (err e))
        ((ok entries)
          (let [(selected (if (stringEmpty? model) entries (filter (fn [(e j/Json)] -> Bool (researchLabelMatches e model)) entries)))]
            (if (and (listEmpty? selected) (!= intent "audit"))
              (err (pt/pyErr "ValueError" (if (stringEmpty? model) (str "gateway profile has no " intent " route") (str "model " model " is not in the " intent " route of profile " routes.name))))
              (ok (pair routes.name selected))))))))

fn researchGatewayRoutes! table: cfg/GatewayTable profile: (Option String) model: String -> (Result (Pair String (Pair (List j/Json) (List j/Json))) pt/PyErr)
  (match (researchRoutesFor! table profile "research" model)
    ((err e) (err e))
    ((ok research)
      (match (researchRoutesFor! table (some (pairFirst research)) "audit" "")
        ((err e) (err e))
        ((ok audit) (ok (pair (pairFirst research) (pair (pairSecond research) (pairSecond audit))))))))

fn resolveResearchEntry! table: cfg/GatewayTable model: String profile: (Option String) -> (Result j/Json pt/PyErr)
  (match (researchRoutesFor! table profile "research" model)
    ((err e) (err e))
    ((ok routes) (match (listHead (pairSecond routes)) ((none) (err (pt/pyErr "ValueError" "gateway profile has no research route"))) ((some entry) (ok entry)))))

fn routeUpstream entries: (List j/Json) name: String -> j/Json
  (match (listHead entries)
    ((none) (j/jnull))
    ((some entry)
      (if (or (= name (pt/pyStr (optionOr (pt/jget entry "dispatch") (j/jstr ""))))
              (= name (pt/pyStr (optionOr (pt/jget entry "alias") (j/jstr "")))))
        (optionOr (pt/jget entry "upstream") (j/jnull))
        (routeUpstream (optionOr (listTail entries) (list)) name))))

; (:m :ref RESEARCH-DEPTH :do "the depth names; what each one spends is a (:mode ...) row of researchModes.asn, read by researchStep")
fn researchDepth depth: String -> String
  (cond ((= depth "flash") "flash") ((= depth "deep") "targeted") ((= depth "exhaustive") "matrix") (else ""))

; (:m :ref RESEARCH-DEPTH :do "the mode row of a depth: the workspace table when it exists, else the package table; an unreadable table is an error for every depth but :flash, which then runs the single pipeline; a readable table with a missing or invalid row is an error for every depth")
fn ! researchModeAt! wsTable: String pkgTable: String depth: String -> (Result j/Json pt/PyErr)
  (let [(tablePath (if (fileExists? wsTable) wsTable pkgTable))]
    (match (fileReadString tablePath)
      ((err _) (if (= depth "flash")
                 (ok (j/jobj (list (pair "pipeline" (j/jstr "single")) (pair "depth" (j/jstr "flash")))))
                 (err (pt/pyErr "ValueError" (str "research mode table is unreadable: " tablePath)))))
      ((ok text) (researchModeOf text depth))))

; (:m :ref HUB-GETROUTES-WIRING :do "the one research pipeline both callers run: the (:research) op of the agent plane and the hub's POST /api/asl/research hand it the routes of the active profile, the mode row and their model dispatchers; a :pipeline plan row runs executeResearchPlan!, every other row the single-pass executeResearchHub!, and the profile name is stamped on the report")
fn ! researchPipeline! topic: String dTarget: String mode: j/Json triage: Bool routes: (Pair String (Pair (List j/Json) (List j/Json))) env: (Map String String) disp: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) planDisp: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) nowMs: Int64 clock: (fn [Int64] -> Int64) -> (Result j/Json pt/PyErr)
  (let [(st (srch/newHubState env nowMs 0 (mapEmpty) (mapEmpty)))
        (entries (pairFirst (pairSecond routes)))
        (auditEntries (pairSecond (pairSecond routes)))
        (up (fn [(m String)] -> j/Json (routeUpstream (listAppend entries auditEntries) m)))
        (auditOpt (if (listEmpty? auditEntries) (none) (some auditEntries)))
        (resPair (if (= (pt/pyStr (optionOr (pt/jget mode "pipeline") (j/jstr ""))) "plan")
                   (executeResearchPlan! st topic mode entries triage auditOpt up planDisp nowMs clock)
                   (executeResearchHub! st topic (pt/pyStr (optionOr (pt/jget mode "depth") (j/jstr dTarget))) entries (j/jstr "auto") triage auditOpt up disp)))]
    (match (pairFirst resPair)
      ((err e) (err e))
      ((ok rawRep) (ok (pt/jset rawRep "profile" (j/jstr (pairFirst routes)))))))
