(module aslWebApiSearch/commonCrawlCli
  :x [main chooseNewestCapture chooseNewestCaptureForUrl filterExactUrl formatQuoteReceipt formatCaptureLine formatCaptureError escapeAsn QuoteLookupPlan quoteLookupPlan selectQuoteCapture parseLookupLimit executeLookupCdx! runLookup!]
  :i [(aslWebApiSearch/commonCrawl :a cc)])

(schema QuoteLookupPlan
  (:f limit Int64)
  (:f select (Fn [(List cc/CcCapture)] -> (Option cc/CcCapture))))

fn hexDigits -> String
  "0123456789ABCDEF"

fn escapeAsnLoop tbl: String hex: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))
          (tok (if (= b 92)
                 "\\\\"
                 (if (= b 34)
                   "\\\""
                   (if (= b 10)
                     "\\n"
                     (if (= b 9)
                       "\\t"
                       (if (= b 13)
                         "\\r"
                         (if (or (< b 32) (= b 127))
                           (let [(hi (/ b 16))
                                 (lo (mod b 16))
                                 (h1 (optionOr (stringSlice hex hi (+ hi 1)) "0"))
                                 (h2 (optionOr (stringSlice hex lo (+ lo 1)) "0"))]
                             (str "\\u00" h1 h2))
                           (optionOr (stringSlice tbl b (+ b 1)) ""))))))))]
      (escapeAsnLoop tbl hex bs (+ i 1) n (cons tok acc))))

fn escapeAsn s: String -> String
  (let [(bs (stringToBytes s))]
    (escapeAsnLoop (cc/ccByteTable) (hexDigits) bs 0 (bytesLength bs) (list)))

fn chooseNewestLoop captures: (List cc/CcCapture) best: (Option cc/CcCapture) -> (Option cc/CcCapture)
  (mt (listHead captures)
    ((none) best)
    ((some c)
     (let [(nextBest (if (!= c.status 200)
                       best
                       (mt best
                         ((none) (some c))
                         ((some b)
                          (if (> c.timestamp b.timestamp)
                            (some c)
                            (some b))))))]
       (chooseNewestLoop (optionOr (listTail captures) (list)) nextBest))))

fn chooseNewestCapture captures: (List cc/CcCapture) -> (Option cc/CcCapture)
  (chooseNewestLoop captures (none))

fn filterExactUrl captures: (List cc/CcCapture) targetUrl: String -> (List cc/CcCapture)
  (filter (fn [(c cc/CcCapture)] -> Bool (= c.url targetUrl)) captures)

fn chooseNewestCaptureForUrl captures: (List cc/CcCapture) targetUrl: String -> (Option cc/CcCapture)
  (chooseNewestCapture (filterExactUrl captures targetUrl))

fn quoteLookupPlan url: String -> QuoteLookupPlan
  (QuoteLookupPlan
    :limit 1000
    :select (fn [(caps (List cc/CcCapture))] -> (Option cc/CcCapture)
              (chooseNewestCaptureForUrl caps url)))

fn formatQuoteReceipt found: Bool c: cc/CcCapture -> String
  (str "(:ccQuote :found " (if found "true" "false")
       " :url \"" (escapeAsn c.url) "\""
       " :crawl \"" (escapeAsn c.crawl) "\""
       " :file \"" (escapeAsn c.filename) "\""
       " :offset " (stringFromInt64 c.offset)
       " :length " (stringFromInt64 c.length)
       " :digest \"" (escapeAsn c.digest) "\""
       " :timestamp \"" (escapeAsn c.timestamp) "\")")

fn formatQuoteError cause: String -> String
  (str "(:ccQuote :err \"" (escapeAsn cause) "\")")

fn formatCaptureError cause: String -> String
  (str "(:ccCapture :err \"" (escapeAsn cause) "\")")

fn formatCaptureLine c: cc/CcCapture -> String
  (str "(:ccCapture :url \"" (escapeAsn c.url) "\""
       " :crawl \"" (escapeAsn c.crawl) "\""
       " :file \"" (escapeAsn c.filename) "\""
       " :offset " (stringFromInt64 c.offset)
       " :length " (stringFromInt64 c.length)
       " :digest \"" (escapeAsn c.digest) "\""
       " :timestamp \"" (escapeAsn c.timestamp) "\""
       " :status " (stringFromInt64 c.status)
       " :mime \"" (escapeAsn c.mime) "\")")

fn printCaptures! captures: (List cc/CcCapture) -> Unit
  (mt (listHead captures)
    ((none) ())
    ((some c)
     (do
       (println (formatCaptureLine c))
       (printCaptures! (optionOr (listTail captures) (list))))))

fn selectQuoteCapture plan: QuoteLookupPlan text: String crawl: String -> (Result (Option cc/CcCapture) String)
  (mt (cc/ccParseCdxLines text crawl)
    ((err e) (err e))
    ((ok captures)
     (ok (plan.select captures))))

fn parseLookupLimit optLimit: (Option String) -> Int64
  (mt optLimit
    ((none) 5)
    ((some limStr) (optionOr (stringToInt64 limStr) 5)))

fn runQuote! url: String quote: String -> (Result Int64 String)
  (let [(plan (quoteLookupPlan url))]
    (mt (cc/ccLatestCrawl!)
      ((err e)
       (do
         (println (formatQuoteError (str "crawl lookup failed: " e)))
         (ok 1)))
      ((ok crawl)
       (let [(args (cc/ccBuildLookupArgs crawl url plan.limit))]
         (mt (cc/ccRunCurl! args)
           ((err e)
            (do
              (println (formatQuoteError (str "curl failed: " e)))
              (ok 1)))
           ((ok res)
            (if (!= res.exitCode 0)
              (do
                (println (formatQuoteError (str "curl failed: " res.stderr)))
                (ok 1))
              (mt (selectQuoteCapture plan res.stdout crawl)
             ((err e)
              (do
                (println (formatQuoteError (str "CDX lookup failed: " e)))
                (ok 1)))
             ((ok optCap)
              (mt optCap
                ((none)
                 (do
                   (println (formatQuoteError "no status 200 capture found"))
                   (ok 1)))
                ((some c)
                 (mt (cc/ccFetch! c)
                   ((err e)
                    (do
                      (println (formatQuoteError (str "fetch failed: " e)))
                      (ok 1)))
                   ((ok rec)
                    (let [(found (cc/ccQuoteInPage? rec quote))]
                      (do
                        (println (formatQuoteReceipt found c))
                        (ok 0))))))))))))))))

fn executeLookupCdx! text: String crawl: String -> (Result Int64 String)
  (mt (cc/ccParseCdxLines text crawl)
    ((err e)
     (do
       (println (formatCaptureError (str "CDX lookup failed: " e)))
       (ok 1)))
    ((ok captures)
     (do
       (printCaptures! captures)
       (ok 0))))

fn runLookup! pattern: String limit: Int64 -> (Result Int64 String)
  (mt (cc/ccLatestCrawl!)
    ((err e)
     (do
       (println (formatCaptureError (str "crawl lookup failed: " e)))
       (ok 1)))
    ((ok crawl)
     (mt (cc/ccRunCurl! (cc/ccBuildLookupArgs crawl pattern limit))
       ((err e)
        (do
          (println (formatCaptureError (str "curl failed: " e)))
          (ok 1)))
       ((ok res)
        (if (!= res.exitCode 0)
          (do
            (println (formatCaptureError (str "curl failed: " res.stderr)))
            (ok 1))
          (executeLookupCdx! res.stdout crawl))))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (listHead args)
    ((none)
     (do
       (println "(:ccQuote :err \"missing command: quote or lookup\")")
       (ok 1)))
    ((some cmd)
     (if (= cmd "quote")
       (let [(optUrl (listGet args 1))
             (optQuote (listGet args 2))]
         (if (or (none? optUrl) (none? optQuote))
           (do
             (println "(:ccQuote :err \"usage: quote <url> <quote>\")")
             (ok 1))
           (runQuote! (optionOr optUrl "") (optionOr optQuote ""))))
       (if (= cmd "lookup")
         (let [(optPat (listGet args 1))
               (optLimit (listGet args 2))]
           (if (none? optPat)
             (do
               (println "(:ccCapture :err \"usage: lookup <urlPattern> [limit]\")")
               (ok 1))
             (let [(pat (optionOr optPat ""))
                   (limit (parseLookupLimit optLimit))]
               (runLookup! pat limit))))
         (do
           (println (str "(:ccQuote :err \"unknown command: " (escapeAsn cmd) "\")"))
           (ok 1))))))
