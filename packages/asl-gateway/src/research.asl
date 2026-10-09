(module aslGateway/research
  :x [asnAtom asnRead asnProps asnScalar asnText asnRepr
      classifySourceKind extractOutermostSexpr stripTagsAndWhitespace extractHtmlTables extractHtmlCodeBlocks isSpaShell isWafChallenge
      fetchReq fetchResult fetchSinglePage! parallelCrawlDistill!
      researchPrompt researchEntryLabel researchEntryProvider researchCall! breakerDownFor
      researchDebracket researchParse researchNorm researchWords researchQuoteFound researchVerify researchAuditPrompt researchAudit!
      auditVerdicts researchRelation researchExtract! executeResearchHub! researchRelationAsn formatResearchAsn]
  :i [(asl-json/json :a j)
      (pyText :a pt)
      (search :a srch)])

fn asnAtom s: String -> j/Json
  (j/jobj (list (pair "atom" (j/jstr s))))

fn atomOf v: j/Json -> (Option String)
  (mt v
    ((j/jobj kvs) (if (= (listLength kvs) 1) (mt (pt/jget v "atom") ((some a) (mt a ((j/jstr s) (some s)) (_ (none)))) ((none) (none))) (none)))
    (_ (none)))

fn valueErr msg: String -> pt/PyErr
  (pt/pyErr "ValueError" msg)

fn cpOffset text: String b: Int64 -> String
  (stringFromInt64 (pt/cpCount (pt/sliceB text 0 b)))

fn pushForm stack: (List (List j/Json)) forms: (List j/Json) v: j/Json -> (Pair (List (List j/Json)) (List j/Json))
  (mt (listHead stack)
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
          (mt (listHead stack)
            ((none) (err (valueErr (str "unbalanced ) at offset " (cpOffset text i)))))
            ((some top)
              (let [(p (pushForm (optionOr (listTail stack) (list)) forms (j/jarr (listReverse top))))]
                (readLoop text bs n (+ i 1) (pairFirst p) (pairSecond p))))))
        ((= c 34)
          (mt (strEnd text bs n i (+ i 1) (+ i 1) (list))
            ((err e) (err e))
            ((ok r) (let [(p (pushForm stack forms (j/jstr (pairFirst r))))] (readLoop text bs n (pairSecond r) (pairFirst p) (pairSecond p))))))
        (else
          (let [(k (atomEnd bs n i)) (p (pushForm stack forms (asnAtom (pt/sliceB text i k))))]
            (readLoop text bs n k (pairFirst p) (pairSecond p)))))))

fn asnRead text: String -> (Result (List j/Json) pt/PyErr)
  (let [(bs (stringToBytes text))] (readLoop text bs (bytesLength bs) 0 (list) (list)))

fn asnRepr v: j/Json -> String
  (mt (atomOf v)
    ((some s) (pt/pyRepr (j/jstr s)))
    ((none) (mt v ((j/jarr xs) (str "[" (pt/joinSep (map asnRepr xs) ", ") "]")) (_ (pt/pyRepr v)))))

fn asnText v: j/Json -> String
  (mt (atomOf v)
    ((some s) s)
    ((none) (mt v ((j/jstr s) s) ((j/jarr _) (asnRepr v)) (_ (pt/pyStr v)))))

fn propsLoop what: String rest: (List j/Json) acc: j/Json -> (Result j/Json pt/PyErr)
  (mt (listHead rest)
    ((none) (ok acc))
    ((some k)
      (let [(tail (optionOr (listTail rest) (list)))
            (v (optionOr (listHead tail) (j/jnull)))
            (name (optionOr (atomOf k) ""))]
        (if (or (none? (atomOf k)) (not (stringStartsWith? name ":")) (< (pt/cpCount name) 2))
          (err (valueErr (str what ": " (asnRepr k) " is not a :keyword")))
          (propsLoop what (optionOr (listTail tail) (list)) (pt/jset acc (pt/sliceB name 1 (stringLength name)) v))))))

fn asnProps form: j/Json head: (Option String) -> (Result j/Json pt/PyErr)
  (let [(what (mt head ((some h) (str "(" h " ...)")) ((none) "a property list")))]
    (mt form
      ((j/jarr xs)
        (let [(headOk (mt head
                        ((none) (ok xs))
                        ((some h)
                          (mt (listHead xs)
                            ((none) (err (valueErr (str "expected " what ", found ( ...)"))))
                            ((some f0) (if (= (atomOf f0) (some h)) (ok (optionOr (listTail xs) (list))) (err (valueErr (str "expected " what ", found (" (asnText f0) " ...)")))))))))]
          (mt headOk
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
  (mt (atomOf v)
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
            (mt (stringToInt64 s)
              ((some k) (j/jint k))
              ((none) (mt (pt/jsonLoads (str (if neg "-" "") (stripLeadingZeros body) ".0")) ((ok f) f) ((err _) (j/jstr s))))))
          ((and (> dot 0) (< dot (- nb 1)) (allDigits bb 0 dot) (allDigits bb (+ dot 1) nb))
            (mt (pt/jsonLoads (str (if neg "-" "") (stripLeadingZeros body))) ((ok f) f) ((err _) (j/jstr s))))
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
            (mt (listHead stack)
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
      (mt (m k)
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
  (mt (listHead (filter (fn [(t String)] -> Bool (ciAt bs n (+ k 1) t)) (list "script" "style" "nav" "header" "footer" "noscript" "svg")))
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
    (mt (listHead (filter (fn [(t String)] -> Bool (ciAt bs n j0 t)) (list "p" "div" "section" "article" "li")))
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
  (j/jarr (fold (fn [(acc (List j/Json)) (t String)] -> (List j/Json) (mt (tableOf t maxRows) ((some x) (listAppend acc (list x))) ((none) acc)))
                (list) (listTake (tagged raw "<table" "</table>") (max maxTables 0))))

fn classChar b: Int64 -> Bool
  (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90)) (and (>= b 48) (<= b 57)) (= b 95) (= b 45))

fn classRunEnd bs: Bytes n: Int64 j: Int64 -> Int64
  (if (and (< j n) (classChar (bytesGet bs j))) (classRunEnd bs n (+ j 1)) j)

fn isQuote bs: Bytes n: Int64 j: Int64 -> Bool
  (and (< j n) (or (= (bytesGet bs j) 34) (= (bytesGet bs j) 39)))

fn classWithPrefix bs: Bytes n: Int64 q: Int64 prefixes: (List String) -> (Option (Pair Int64 Int64))
  (mt (listHead prefixes)
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
          (some (pair (mt cls ((some r) (pt/sliceB s (pairFirst r) (pairSecond r))) ((none) "")) (pt/sliceB s (+ e 1) c)))))))

fn extractHtmlCodeBlocks raw: String maxBlocks: Int64 -> j/Json
  (j/jarr (fold (fn [(acc (List j/Json)) (p String)] -> (List j/Json)
                  (let [(m (codeMatch p))
                        (lang (mt m ((some x) (pairFirst x)) ((none) "")))
                        (code (cellText (mt m ((some x) (pairSecond x)) ((none) p))))]
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
  (mt r
    ((srch/httpFail _ _) (notCrawled url fallback "fetchTimeoutOrError"))
    ((srch/httpResp code _ hs body)
      (if (not (srch/httpOk? code))
        (notCrawled url fallback "fetchTimeoutOrError")
        (mt decoded
          ((err _) (notCrawled url fallback "fetchTimeoutOrError"))
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
  (mt r
    ((srch/httpResp code _ hs body)
      (if (srch/httpOk? code)
        (srch/decodeBody! (pt/sliceB body 0 (min 150000 (stringLength body))) (optionOr (srch/contentCharset hs) "utf-8") st.env)
        (err (pt/pyErr "HTTPError" "status outside 2xx"))))
    ((srch/httpFail e _) (err e)))

fn ! fetchSinglePage! st: srch/HubState url: String fallback: j/Json timeout: j/Json -> (Result j/Json pt/PyErr)
  (mt (srch/urlTypeCheck url)
    ((err e) (err e))
    ((ok _) (let [(r (srch/runOne! st (fetchReq url timeout)))] (ok (fetchResult url fallback r (fetchDecode! st r))))))

fn strOrErr v: j/Json what: String -> (Result String pt/PyErr)
  (mt v ((j/jstr s) (ok s)) (_ (err (pt/pyErr "TypeError" (str what " must be str, not " (pt/pyTypeName v))))))

fn ! parallelCrawlDistill! st: srch/HubState results: (List j/Json) maxUrls: Int64 timeout: j/Json -> (Result j/Json pt/PyErr)
  (let [(toFetch (listTake results (max maxUrls 0)))
        (targets (fold (fn [(acc (Result (List (Pair String j/Json)) pt/PyErr)) (r j/Json)] -> (Result (List (Pair String j/Json)) pt/PyErr)
                         (mt acc
                           ((err e) (err e))
                           ((ok xs)
                             (mt (srch/jreq r "url")
                               ((err e) (err e))
                               ((ok u)
                                 (mt (pt/jgetOr r "snippet" (j/jstr ""))
                                   ((err e) (err e))
                                   ((ok sn) (mt (strOrErr u "url") ((err e) (err e)) ((ok us) (ok (listAppend xs (list (pair us sn)))))))))))))
                       (ok (list)) toFetch))]
    (mt targets
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
  (mt entry
    ((j/jobj _) (mt (srch/jreq entry "alias") ((err e) (err e)) ((ok a) (mt (srch/jreq entry "dispatch") ((err e) (err e)) ((ok d) (ok (pair a d)))))))
    (_ (ok (pair entry entry))))

fn cliName prov: j/Json -> (Option String)
  (mt prov
    ((j/jstr p) (cond ((= p "agy-cli") (some "agy")) ((= p "codex-cli") (some "codex")) ((= p "claude-cli") (some "claude")) (else (none))))
    (_ (none)))

fn researchEntryProvider entry: j/Json up: (fn [String] -> j/Json) -> (Result j/Json pt/PyErr)
  (let [(raw (mt entry
               ((j/jobj _)
                 (let [(p (optionOr (pt/jget entry "provider") (j/jnull)))]
                   (if (pt/pyTruthy p)
                     (ok p)
                     (let [(u (optionOr (pt/jget entry "upstream") (j/jnull)))]
                       (pt/jgetOr (if (pt/pyTruthy u) u (j/jobj (list))) "provider" (j/jnull))))))
               ((j/jstr s) (pt/jgetOr (up s) "provider" (j/jnull)))
               (_ (err (pt/pyErr "TypeError" (str "entry must be dict or str, not " (pt/pyTypeName entry)))))))]
    (mt raw
      ((err e) (err e))
      ((ok p) (ok (mt (cliName p) ((some c) (j/jstr c)) ((none) p))))))

fn provKey prov: j/Json -> String
  (pt/pyStr prov)

fn breakerDownFor st: srch/HubState prov: j/Json -> (Pair Float64 srch/HubState)
  (if (not (pt/pyTruthy prov))
    (pair 0.0 st)
    (mt (mapGet st.breakerUntil (provKey prov))
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
  (mt (float64ToInt64 x)
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
  (mt v ((j/jint i) (int64ToFloat64 i)) ((j/jfloat f) f) ((j/jnum f) f) ((j/jbool b) (if b 1.0 0.0)) (_ 0.0))

fn afterSlash s: String -> (Option String)
  (mt (stringIndexOf s "/") ((some i) (some (pt/sliceB s (+ i 1) (stringLength s)))) ((none) (none)))

(schema Route (:f alias j/Json) (:f name String) (:f upv j/Json) (:f params j/Json) (:f rpm j/Json) (:f timeout j/Json) (:f prov j/Json))

fn routeOf entry: j/Json up: (fn [String] -> j/Json) -> (Result Route pt/PyErr)
  (mt entry
    ((j/jobj _)
      (mt (srch/jreq entry "alias")
        ((err e) (err e))
        ((ok alias)
          (mt (srch/jreq entry "dispatch")
            ((err e) (err e))
            ((ok name)
              (mt (srch/jreq entry "upstream")
                ((err e) (err e))
                ((ok upv)
                  (mt (srch/jreq entry "params")
                    ((err e) (err e))
                    ((ok params)
                      (mt (srch/jreq upv "provider")
                        ((err e) (err e))
                        ((ok prov)
                          (let [(t (optionOr (pt/jget entry "timeoutSec") (j/jnull)))]
                            (mt (strOrErr name "dispatch")
                              ((err e) (err e))
                              ((ok nm) (ok (Route :alias alias :name nm :upv upv :params params :rpm (optionOr (pt/jget entry "rpm") (j/jnull))
                                                  :timeout (if (pt/pyTruthy t) t (j/jint 45)) :prov prov))))))))))))))))
    ((j/jstr s)
      (let [(upv (up s))]
        (mt (srch/jreq upv "provider")
          ((err e) (err e))
          ((ok prov)
            (let [(nm (if (or (stringStartsWith? s "groq/") (stringStartsWith? s "ollama/")) (optionOr (afterSlash s) s) s))]
              (ok (Route :alias entry :name nm :upv upv :params (j/jobj (list)) :rpm (if (pt/pyEq prov (j/jstr "gemini")) (j/jint 15) (j/jnull))
                         :timeout (if (pt/pyEq prov (j/jstr "ollama")) (j/jfloat 300.0) (j/jint 45)) :prov prov)))))))
    (_ (err (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName entry) "' object has no attribute 'startswith'")))))

fn poolOf prov: j/Json -> String
  (mt (cliName prov) ((some c) c) ((none) (if (pt/pyTruthy prov) (provKey prov) "")))

fn paramGet params: j/Json k: String d: j/Json -> (Result j/Json pt/PyErr)
  (pt/jgetOr params k d)

fn ! cliCall! st: srch/HubState r: Route cli: String prompt: String dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(sub (mt (afterSlash r.name) ((some x) (j/jstr x)) ((none) (j/jnull))))
        (modelR (cond ((= cli "agy") (ok (if (pt/pyTruthy sub) sub (j/jstr "gemini-3.8-flash")))) (else (ok sub))))
        (effortR (cond ((= cli "agy") (paramGet r.params "effort" (j/jstr "low"))) ((= cli "codex") (paramGet r.params "effort" (j/jstr "medium"))) (else (ok (j/jnull)))))]
    (mt modelR
      ((err e) (pair (err e) st))
      ((ok model)
        (mt effortR
          ((err e) (pair (err e) st))
          ((ok effort)
            (let [(st1 (srch/hubCliCall st (j/jobj (list (pair "prov" (j/jstr cli)) (pair "model" model) (pair "effort" effort) (pair "noTools" (j/jbool true)) (pair "prompt" (j/jstr prompt))))))]
              (mt (dispatch cli model effort prompt)
                ((err e) (pair (err e) st1))
                ((ok res)
                  (mt (if (pt/pyTruthy res) (pt/jgetOr res "text" (j/jnull)) (ok (j/jnull)))
                    ((err e) (pair (err e) st1))
                    ((ok text)
                      (if (not (pt/pyTruthy text))
                        (pair (err (runtimeErr (str (provKey r.prov) " returned no text"))) (srch/hubNote st1 r.prov r.alias "failed" (j/jnull)))
                        (pair (ok text) (srch/hubNote st1 r.prov r.alias "ok" (optionOr (pt/jget res "usage") (j/jnull)))))))))))))))

fn chatBody r: Route prompt: String -> (Result String pt/PyErr)
  (mt (paramGet r.params "temperature" (j/jfloat 0.2))
    ((err e) (err e))
    ((ok temp)
      (let [(b0 (j/jobj (list (pair "model" (j/jstr r.name))
                              (pair "messages" (j/jarr (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr prompt)))))))
                              (pair "temperature" temp))))
            (b1 (mt (pt/jget r.params "maxTokens") ((some m) (pt/jset b0 "max_tokens" m)) ((none) b0)))
            (eff (optionOr (pt/jget r.params "effort") (j/jnull)))
            (b2 (if (and (pt/pyEq r.prov (j/jstr "ollama")) (listAny? (fn [(x String)] -> Bool (pt/pyEq eff (j/jstr x))) (list "low" "medium" "high")))
                  (pt/jset b1 "reasoning_effort" eff)
                  b1))]
        (ok (pt/jsonDumps b2 -1)))))

fn rstripSlashes s: String -> String
  (if (stringEndsWith? s "/") (rstripSlashes (pt/sliceB s 0 (- (stringLength s) 1))) s)

fn replyContent data: j/Json -> (Result j/Json pt/PyErr)
  (mt (pt/jgetOr data "choices" (j/jnull))
    ((err e) (err e))
    ((ok ch)
      (mt (pt/pyIndex (if (pt/pyTruthy ch) ch (j/jarr (list (j/jobj (list))))) 0)
        ((err e) (err e))
        ((ok first)
          (mt (pt/jgetOr first "message" (j/jnull))
            ((err e) (err e))
            ((ok m) (pt/jgetOr (if (pt/pyTruthy m) m (j/jobj (list))) "content" (j/jnull))))))))

fn ! httpCall! st: srch/HubState r: Route prompt: String -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(pool (poolOf r.prov))]
    (mt (chatBody r prompt)
      ((err e) (pair (err e) st))
      ((ok body)
        (mt (srch/jreq r.upv "url")
          ((err e) (pair (err e) st))
          ((ok urlv)
            (mt (strOrErr urlv "url")
              ((err e) (pair (err e) st))
              ((ok u0)
                (let [(url (str (rstripSlashes u0) "/chat/completions"))
                      (key (optionOr (pt/jget r.upv "key") (j/jnull)))]
                  (mt (srch/urlTypeCheck url)
                    ((err e) (pair (err e) st))
                    ((ok _)
                      (let [(req (srch/HttpReq :url url
                                   :headers (listAppend (list (pair "Content-Type" "application/json") (pair "User-Agent" "ASL-Gateway/1.0 (Darwin; macOS)"))
                                                        (if (pt/pyTruthy key) (list (pair "Authorization" (str "Bearer " (pt/pyStr key)))) (list)))
                                   :data (some body) :timeout r.timeout))
                            (res (srch/runOne! st req))]
                        (httpOutcome st r pool res))))))))))))

fn ! httpOutcome st: srch/HubState r: Route pool: String res: srch/HttpResult -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (mt res
    ((srch/httpFail e timedOut)
      (pair (err e) (srch/hubNote (reset503 st pool) r.prov r.alias (if timedOut "timeout" "other") (j/jnull))))
    ((srch/httpResp code _ _ body)
      (if (not (srch/httpOk? code))
        (let [(st1 (cond ((or (= code 429) (isQuotaError (pt/decodeReplace body))) (markDown st pool)) ((= code 503) (note503 st pool)) (else (reset503 st pool))))]
          (pair (err (runtimeErr (str "HTTP " (stringFromInt64 code)))) (srch/hubNote st1 r.prov r.alias (usageHttpError code) (j/jnull))))
        (mt (mt (pt/strictUtf8 body) ((err e) (err e)) ((ok text) (pt/jsonLoads text)))
          ((err e) (pair (err e) (srch/hubNote (reset503 st pool) r.prov r.alias "other" (j/jnull))))
          ((ok data)
            (mt (replyContent data)
              ((err e) (pair (err e) st))
              ((ok text)
                (mt text
                  ((j/jstr s)
                    (if (stringEmpty? (pt/pyStrip s))
                      (pair (err (runtimeErr "empty content")) (srch/hubNote st r.prov r.alias "empty" (j/jnull)))
                      (pair (ok text) (srch/hubNote (clearBreaker st pool) r.prov r.alias "ok" (optionOr (pt/jget data "usage") (j/jnull))))))
                  (_ (pair (err (runtimeErr "empty content")) (srch/hubNote st r.prov r.alias "empty" (j/jnull))))))))))))

fn ! researchCall! st: srch/HubState entry: j/Json prompt: String up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (mt (routeOf entry up)
    ((err e) (pair (err e) st))
    ((ok r)
      (mt (cliName r.prov)
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
    (mt (if (pt/pyTruthy text) (strOrErr text "text") (ok ""))
      ((err _) (err (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName text) "' object has no attribute 'find'"))))
      ((ok t)
        (mt (extractOutermostSexpr t)
          ((none) (err noForm))
          ((some sx)
            (if (not (stringStartsWith? sx (str "(" head)))
              (err noForm)
              (mt (asnRead (researchDebracket sx))
                ((err e) (err e))
                ((ok forms)
                  (mt (asnProps (optionOr (listHead forms) (j/jnull)) (some head))
                    ((err e) (err e))
                    ((ok props)
                      (let [(facts (optionOr (pt/jget props "facts") (j/jarr (list))))]
                        (mt facts
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
  (mt v ((j/jint i) (some i)) ((j/jbool b) (some (if b 1 0))) (_ (none)))

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
  (mt (mt (asnProps form (some head)) ((err e) (err e)) ((ok fp) (mt (researchRelation (propGet fp "predicate" (j/jnull))) ((err e) (err e)) ((ok rel) (ok (pair fp rel))))))
    ((err e) (if (= e.kind "ValueError") (ok (pair (none) (some (str "fact " (stringFromInt64 (+ i 1)) ": " e.msg)))) (err e)))
    ((ok p)
      (let [(fp (pairFirst p)) (rel (pairSecond p))
            (verb (optionOr (listGet rel 0) "")) (subject (optionOr (listGet rel 1) "")) (obj (optionOr (listGet rel 2) ""))
            (fid (asnText (propGet fp "id" (j/jstr (str "fact-" (stringFromInt64 (+ i 1)))))))
            (claim (if triage "" (asnText (propGet fp "claim" (j/jstr "")))))
            (src0 (if triage "" (asnText (propGet fp "source" (j/jstr "")))))
            (sref (asnScalar (propGet fp "srcRef" (asnAtom "0"))))
            (src (mt (intLike sref)
                   ((some k) (if (and (stringEmpty? src0) (>= k 1) (<= k (listLength llmSources))) (asnText (optionOr (listGet llmSources (- k 1)) (j/jnull))) src0))
                   ((none) src0)))
            (vstat (lstripColon (asnText (propGet fp "verificationStatus" (j/jstr "")))))]
        (mt (whyRejected triage fp claim subject obj src vstat titles topicN evidence)
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
  (mt (listHead forms)
    ((none) (ok (pair (listReverse passed) (listReverse rejected))))
    ((some f)
      (mt (verifyOne triage head (pairFirst f) (pairSecond f) llm titles topicN evidence)
        ((err e) (err e))
        ((ok r)
          (verifyLoop triage head (optionOr (listTail forms) (list)) llm titles topicN evidence
                      (mt (pairFirst r) ((some x) (cons x passed)) ((none) passed))
                      (mt (pairSecond r) ((some x) (cons (j/jstr x) rejected)) ((none) rejected)))))))

fn collectR xs: (List j/Json) f: (fn [j/Json] -> (Result String pt/PyErr)) acc: (List String) -> (Result (List String) pt/PyErr)
  (mt (listHead xs)
    ((none) (ok (listReverse acc)))
    ((some x) (mt (f x) ((err e) (err e)) ((ok v) (collectR (optionOr (listTail xs) (list)) f (cons v acc))))))

fn researchVerify props: j/Json rawFacts: (List j/Json) topic: String evidence: (List j/Json) triage: Bool -> (Result j/Json pt/PyErr)
  (mt (collectR evidence (fn [(e j/Json)] -> (Result String pt/PyErr) (mt (srch/jreq e "title") ((err x) (err x)) ((ok t) (ok (researchNorm t))))) (list))
    ((err e) (err e))
    ((ok titles)
      (mt (collectR evidence (fn [(e j/Json)] -> (Result String pt/PyErr) (mt (srch/jreq e "url") ((err x) (err x)) ((ok u) (ok (pt/pyStr u))))) (list))
        ((err e) (err e))
        ((ok _)
          (let [(llm (mt (optionOr (pt/jget props "sources") (j/jnull))
                       ((j/jarr xs) (filter (fn [(s j/Json)] -> Bool (or (some? (atomOf s)) (mt s ((j/jstr _) true) (_ false)))) xs))
                       (_ (list))))]
            (mt (verifyLoop triage (if triage ":p" ":fact") (enumerate rawFacts) llm titles (researchNorm (j/jstr topic)) evidence (list) (list))
              ((err e) (err e))
              ((ok r) (ok (j/jarr (list (j/jarr (pairFirst r)) (j/jarr (pairSecond r))))))))))))

fn researchAuditPrompt facts: (List j/Json) byUrl: j/Json -> (Result String pt/PyErr)
  (mt (collectR facts
        (fn [(f j/Json)] -> (Result String pt/PyErr)
          (mt (srch/jreq f "id")
            ((err e) (err e))
            ((ok fid)
              (mt (srch/jreq f "claim")
                ((err e) (err e))
                ((ok claim)
                  (mt (srch/jreq f "sourceUrl")
                    ((err e) (err e))
                    ((ok su)
                      (mt (srch/jreq byUrl (pt/pyStr su))
                        ((err e) (err e))
                        ((ok src)
                          (mt (pt/jgetOr src "snippet" (j/jstr ""))
                            ((err e) (err e))
                            ((ok sn) (mt (strOrErr sn "snippet")
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
                            (some (pair (pair (pt/sliceB s (+ b 1) q) (pair (pt/sliceB s d1 e) (mt w ((some x) (pairFirst x)) ((none) ""))))
                                        (mt w ((some x) (pairSecond x)) ((none) e)))))
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
      (mt (checkAt s bs n k)
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
      (let [(secs (stringFromInt64 (mt (float64ToInt64 down) ((some i) i) ((none) 0))))]
        (pair (some (triedRow alias name (str "breaker (" secs "s left)")))
              (srch/hubNote (srch/hubStderr st1 (str "[Gateway Breaker] skip " (pt/pyStr prov) " for " secs "s\n")) prov alias (str "breaker " secs "s") (j/jnull))))
      (pair (none) st1)))

(schema Attempt (:f tried (List j/Json)) (:f won (Option j/Json)))

fn ! chainLoop! entries: (List j/Json) st: srch/HubState tried: (List j/Json) prompt: String up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) finish: (fn [j/Json] -> (Result j/Json String)) -> (Pair (Result Attempt pt/PyErr) srch/HubState)
  (mt (listHead entries)
    ((none) (pair (ok (Attempt :tried tried :won (none))) st))
    ((some entry)
      (let [(rest (optionOr (listTail entries) (list)))]
        (mt (researchEntryLabel entry)
          ((err e) (pair (err e) st))
          ((ok lab)
            (mt (researchEntryProvider entry up)
              ((err e) (pair (err e) st))
              ((ok prov)
                (let [(sk (breakerSkip st prov (pairFirst lab) (pairSecond lab)))]
                  (mt (pairFirst sk)
                    ((some row) (chainLoop! rest (pairSecond sk) (listAppend tried (list row)) prompt up dispatch finish))
                    ((none)
                      (let [(call (researchCall! (pairSecond sk) entry prompt up dispatch)) (st2 (pairSecond call))]
                        (mt (pairFirst call)
                          ((err e) (chainLoop! rest st2 (listAppend tried (list (triedRow (pairFirst lab) (pairSecond lab) (errWord e)))) prompt up dispatch finish))
                          ((ok text)
                            (mt (finish text)
                              ((err why) (chainLoop! rest st2 (listAppend tried (list (triedRow (pairFirst lab) (pairSecond lab) why))) prompt up dispatch finish))
                              ((ok won) (pair (ok (Attempt :tried tried :won (some (pt/jset (pt/jset won "alias" (pairFirst lab)) "model" (pairSecond lab))))) st2))))))))))))))))

fn withTried won: (Option j/Json) tried: (List j/Json) order: (List String) -> j/Json
  (mt won
    ((none) (j/jobj (list (pair "tried" (j/jarr tried)))))
    ((some w) (j/jobj (listAppend (map (fn [(k String)] -> (Pair String j/Json) (pair k (optionOr (pt/jget w k) (j/jnull)))) order) (list (pair "tried" (j/jarr tried)))))))

fn attemptJson r: (Pair (Result Attempt pt/PyErr) srch/HubState) order: (List String) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (mt (pairFirst r)
    ((err e) (pair (err e) (pairSecond r)))
    ((ok a) (pair (ok (withTried a.won a.tried order)) (pairSecond r))))

fn ! researchAudit! st: srch/HubState facts: (List j/Json) byUrl: j/Json entries: (List j/Json) up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (mt (researchAuditPrompt facts byUrl)
    ((err e) (pair (err e) st))
    ((ok prompt)
      (attemptJson
        (chainLoop! entries st (list) prompt up dispatch
          (fn [(text j/Json)] -> (Result j/Json String)
            (let [(v (auditVerdicts (pt/pyStr text)))]
              (if (= (listLength (mt v ((j/jobj kvs) kvs) (_ (list)))) 0) (err "no (:check) verdicts") (ok (j/jobj (list (pair "verdicts" v))))))))
        (list "alias" "model" "verdicts"))))

fn researchRelation pred: j/Json -> (Result (List String) pt/PyErr)
  (let [(bad (valueErr "no (:relation ...) predicate"))]
    (mt pred
      ((j/jarr xs)
        (mt (listHead xs)
          ((none) (err bad))
          ((some h)
            (if (not (= (atomOf h) (some ":relation")))
              (mt h ((j/jstr s) (if (= s ":relation") (relationRest (optionOr (listTail xs) (list))) (err bad))) (_ (err bad)))
              (relationRest (optionOr (listTail xs) (list)))))))
      (_ (err bad))))

fn relationRest rest: (List j/Json) -> (Result (List String) pt/PyErr)
  (let [(split (mt (listHead rest)
                 ((some r0) (if (none? (atomOf r0)) (pair (asnText r0) (optionOr (listTail rest) (list))) (pair "" rest)))
                 ((none) (pair "" rest))))]
    (mt (asnProps (j/jarr (pairSecond split)) (none))
      ((err e) (err e))
      ((ok props) (ok (list (pairFirst split) (asnText (propGet props "subject" (j/jstr ""))) (asnText (propGet props "object" (j/jstr ""))))))))

fn ! researchExtract! st: srch/HubState topic: String depth: String rawItems: j/Json entries: (List j/Json) triage: Bool up: (fn [String] -> j/Json) dispatch: (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr)) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (attemptJson
    (chainLoop! entries st (list) (researchPrompt topic depth rawItems triage) up dispatch
      (fn [(text j/Json)] -> (Result j/Json String)
        (mt (researchParse text triage)
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
        (mt (pairFirst sp)
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
                  (mt (pairFirst np)
                    ((err e) (pair (err e) st2))
                    ((ok nd)
                      (let [(negResults (listOf (optionOr (pt/jget nd "results") (j/jarr (list)))))
                            (errors (mergeErrors errors0 (listOf (optionOr (pt/jget nd "errors") (j/jarr (list))))))]
                        (mt (parallelCrawlDistill! st2 results (if flash 3 5) (j/jfloat 3.5))
                          ((err e) (pair (err e) st2))
                          ((ok crawled0)
                            (mt (if (listEmpty? negResults) (ok (j/jobj (list))) (parallelCrawlDistill! st2 negResults 2 (j/jfloat 3.5)))
                              ((err e) (pair (err e) st2))
                              ((ok crawledN)
                                (let [(crawled (mt crawledN ((j/jobj kvs) (fold (fn [(acc j/Json) (p (Pair String j/Json))] -> j/Json (pt/jset acc (pairFirst p) (pairSecond p))) crawled0 kvs)) (_ crawled0)))
                                      (tagged (listAppend (map (fn [(r j/Json)] -> (Pair Bool j/Json) (pair false r)) results) (map (fn [(r j/Json)] -> (Pair Bool j/Json) (pair true r)) negResults)))]
                                  (mt (buildEvidence tagged crawled (list))
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
  (mt v ((j/jarr xs) xs) (_ (list)))

fn sliceHead v: j/Json k: Int64 -> (Result j/Json pt/PyErr)
  (mt v
    ((j/jstr s) (ok (j/jstr (pt/cpPrefix s k))))
    ((j/jarr xs) (ok (j/jarr (listTake xs k))))
    (_ (err (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object is not subscriptable")))))

fn buildEvidence rs: (List (Pair Bool j/Json)) crawled: j/Json acc: (List j/Json) -> (Result (List j/Json) pt/PyErr)
  (mt (listHead rs)
    ((none) (ok acc))
    ((some ar)
      (let [(rest (optionOr (listTail rs) (list))) (r (pairSecond ar))]
        (mt (srch/jreq r "url")
          ((err e) (err e))
          ((ok u)
            (if (listAny? (fn [(e j/Json)] -> Bool (pt/pyEq (optionOr (pt/jget e "url") (j/jnull)) u)) acc)
              (buildEvidence rest crawled acc)
              (let [(c (mt u ((j/jstr us) (optionOr (pt/jget crawled us) (j/jobj (list)))) (_ (j/jobj (list)))))]
                (mt (srch/jreq r "title")
                  ((err e) (err e))
                  ((ok title)
                    (let [(dt (optionOr (pt/jget c "distilledText") (j/jnull)))]
                      (mt (if (pt/pyTruthy dt) (ok dt) (srch/jreq r "snippet"))
                        ((err e) (err e))
                        ((ok sv)
                          (mt (sliceHead sv 1200)
                            ((err e) (err e))
                            ((ok snippet)
                              (mt (mt u ((j/jstr us) (ok (classifySourceKind us))) (_ (err (pt/pyErr "AttributeError" (str "'" (pt/pyTypeName u) "' object has no attribute 'lower'")))))
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
    (mt (pairFirst xp)
      ((err e) (pair (err e) st1))
      ((ok ext)
        (let [(tried (optionOr (pt/jget ext "tried") (j/jarr (list))))
              (rep1 (pt/jset rep "tried" tried))]
          (mt (pt/jget ext "props")
            ((none) (done rep1 "failed" (str "research chain exhausted after " (stringFromInt64 (listLength (listOf tried))) " model(s)") st1))
            ((some props)
              (let [(facts (listOf (optionOr (pt/jget ext "facts") (j/jarr (list)))))
                    (rep2 (pt/jset (pt/jset rep1 "alias" (optionOr (pt/jget ext "alias") (j/jnull))) "model" (optionOr (pt/jget ext "model") (j/jnull))))]
                (mt (researchVerify props facts topic evidence triage)
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
      (fold (fn [(acc j/Json) (k String)] -> j/Json (mt (pt/jget props k) ((some v) (mt v ((j/jstr s) (pt/jset acc k v)) (_ acc))) ((none) acc))) r1 (list "summary" "positiveSynthesis" "falsificationCritique"))))

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
    (mt (pairFirst ap)
      ((err e) (pair (err e) st1))
      ((ok aud)
        (let [(atried (optionOr (pt/jget aud "tried") (j/jarr (list))))
              (rep1 (pt/jset rep "auditTried" atried))]
          (mt (pt/jget aud "verdicts")
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
    (mt (srch/jreq f "relation")
      ((err x) (err x))
      ((ok rel)
        (let [(pred (researchRelationAsn (listOf rel)))]
          (if triage
            (mt (srch/jreq f "id") ((err x) (err x)) ((ok fid)
              (mt (srch/jreq f "srcRef") ((err x) (err x)) ((ok sref)
                (mt (srch/jreq f "verificationStatus") ((err x) (err x)) ((ok vs)
                  (ok (str "    (:p :id \"" (esc fid) "\" :predicate " pred " :srcRef " (pt/pyStr sref) " :verificationStatus :" (pt/pyStr vs) " :isFalsifying " fals ")"))))))))
            (mt (srch/jreq f "evidence") ((err x) (err x)) ((ok ev)
              (mt (sliceHead ev 800) ((err x) (err x)) ((ok ev8)
                (ok (str "    (:fact :id \"" (esc (repGet f "id")) "\" :predicate " pred " :claim \"" (esc (repGet f "claim")) "\" :evidence \"" (esc ev8)
                         "\" :srcRef " (pt/pyStr (repGet f "srcRef")) " :source \"" (esc (repGet f "sourceUrl")) "\" :sourceKind :" (pt/pyStr (repGet f "sourceKind"))
                         " :verificationStatus :" (pt/pyStr (repGet f "verificationStatus")) (if (pt/pyTruthy (repGet f "crawled")) " :crawled true" "")
                         (if (pt/pyTruthy (repGet f "audit")) (str " :audit :" (pt/pyStr (repGet f "audit"))) "") " :isFalsifying " fals ")")))))))))))

fn formatResearchAsn rep: j/Json triage: Bool -> (Result String pt/PyErr)
  (let [(t (fn [(k String)] -> Bool (pt/pyTruthy (repGet rep k))))]
    (mt (srch/jreq rep "status")
      ((err x) (err x))
      ((ok status)
        (mt (collectR (listOf (repGet rep "facts")) (fn [(f j/Json)] -> (Result String pt/PyErr) (factLine f triage)) (list))
          ((err x) (err x))
          ((ok facts)
            (let [(head (if triage ":researchTriage" ":researchReport"))
                  (lines (list
                    (list (str "(" head " :topic \"" (esc (optionOr (pt/jget rep "topic") (j/jstr ""))) "\" :status :" (pt/pyStr status)))
                    (if (t "depth") (list (str "  :depth :" (pt/pyStr (repGet rep "depth")))) (list))
                    (if (t "profile") (list (str "  :profile \"" (esc (repGet rep "profile")) "\"")) (list))
                    (if (t "alias") (list (str "  :alias \"" (esc (repGet rep "alias")) "\" :model \"" (esc (repGet rep "model")) "\"")) (list))
                    (if (t "auditor") (list (str "  :auditor (:alias \"" (esc (repGet (repGet rep "auditor") "alias")) "\" :model \"" (esc (repGet (repGet rep "auditor") "model")) "\")")) (list))
                    (if (t "reason") (list (str "  :reason \"" (esc (repGet rep "reason")) "\"")) (list))
                    (if (some? (pt/jget rep "searched")) (list (str "  :searched " (pt/pyStr (repGet rep "searched")))) (list))
                    (if (t "tried") (list (triedLine "tried" (repGet rep "tried"))) (list))
                    (if (t "auditTried") (list (triedLine "auditTried" (repGet rep "auditTried"))) (list))
                    (if (t "rejected") (list (str "  :rejected (" (pt/joinSep (map (fn [(r j/Json)] -> String (str "\"" (esc r) "\"")) (listOf (repGet rep "rejected"))) " ") ")")) (list))
                    (if (t "errors") (list (str "  :errors (" (pt/joinSep (map (fn [(x j/Json)] -> String (str "(:engine \"" (esc (optionOr (pt/jget x "engine") (j/jstr ""))) "\" :error \"" (esc (optionOr (pt/jget x "error") (j/jstr ""))) "\")")) (listOf (repGet rep "errors"))) " ") ")")) (list))
                    (if (and (not triage) (pt/pyEq status (j/jstr "verified")))
                      (fold (fn [(acc (List String)) (k String)] -> (List String) (if (t k) (listAppend acc (list (str "  :" k " \"" (esc (repGet rep k)) "\""))) acc)) (list) (list "summary" "positiveSynthesis" "falsificationCritique"))
                      (list))
                    (list (str "  :facts (" (if (listEmpty? facts) "" (str "\n" (pt/joinSep facts "\n"))) ")"))
                    (list (str "  :sources (" (pt/joinSep (map (fn [(s j/Json)] -> String (str "\"" (esc s) "\"")) (listOf (optionOr (pt/jget rep "sources") (j/jarr (list))))) " ") "))"))))]
              (ok (pt/joinSep (fold (fn [(acc (List String)) (l (List String))] -> (List String) (listAppend acc l)) (list) lines) "\n"))))))))
