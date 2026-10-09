(module aslCrawler/crawler
  :x [CrawlJob CrawlResult CrawlPool crawlJob makeCrawlJob makePool poolJobs crawlOk crawlErr statusOk? curlArgs crawlDoc crawlAsn crawlDistilledAsn isSpaShell? makeSuccessResult makeFailureResult isSuccessfulStatus buildCurlFetchArgs crawlToDoc crawlToAsn isValidCrawlUrl? isWafBlocked? cacheFallbackJobs stripCacheDecorations normalizeCrawlResponse crawlWithFallback CrawlMode modeExtension modePatchright modeStaticHttp modeCloudProxy modeAuto modeToString stringToMode crawlWithMode distillHtmlToAsn fetchCurl! fetchStealthBrowser! findStealthBrowser! runArgv! browserFailureText main]
  :i [(aslCrawler/stealth :a st)
      (aslCrawler/browserDetector :a bd)
      (aslCrawler/inBrowserAgent :a iba)
      (aslCrawler/automation :a auto)
      (asl-proc/pool :a proc)
      (asl-proc/coreProcess :a procCore)
      (aslCrawler/session :a sess)
      (asl-text/text :a txt)
      (asl-text/escape :a esc)
      (asl-json/json :a j)])

(schema CrawlPool (:f concurrency I64) (:f timeoutMs I64) (:f profile st/StealthProfile))

(schema CrawlJob (:f url Str) (:f profile st/StealthProfile) (:f timeoutMs I64) (:f followRedirects Bool) (:f maxRetries I64))

(schema CrawlResult (:f url Str) (:f statusCode I64) (:f rawHtml Str) (:f charCount I64) (:f isSuccess Bool) (:f errorMsg Str))

fn crawlJob url: Str profile: st/StealthProfile -> CrawlJob
  (CrawlJob :url url :profile profile :timeoutMs 3500 :followRedirects true :maxRetries 1)

fn makeCrawlJob url: Str profile: st/StealthProfile -> CrawlJob
  (crawlJob url profile)

fn makePool concurrency: I64 profile: st/StealthProfile -> CrawlPool
  (CrawlPool :concurrency concurrency :timeoutMs 3500 :profile profile)

fn poolJobs pool: CrawlPool urls: (List Str) -> (List CrawlJob)
  (map (fn [(url Str)] -> CrawlJob (CrawlJob :url url :profile pool.profile :timeoutMs pool.timeoutMs :followRedirects true :maxRetries 1)) urls)

fn crawlOk url: Str statusCode: I64 rawHtml: Str -> CrawlResult
  (CrawlResult :url url :statusCode statusCode :rawHtml rawHtml :charCount (stringLength rawHtml) :isSuccess true :errorMsg "")

fn crawlErr url: Str errorMsg: Str -> CrawlResult
  (CrawlResult :url url :statusCode 0 :rawHtml "" :charCount 0 :isSuccess false :errorMsg errorMsg)

fn statusOk? status: I64 -> Bool
  (and (>= status 200) (< status 300))

fn noUrlUserInfo? url: Str -> Bool
  (let [(authority (optionOr (extractAfter url "://") ""))
        (host (sliceUntilAny authority (list "/" "?" "#")))]
    (not (stringContains? host "@")))

fn isValidCrawlUrl? url: Str -> Bool
  (let [(clean (stringLower (stringTrim url)))]
    (fold (fn [(ok Bool) (part Bool)] -> Bool (and ok part)) true
      (list
        (not (stringStartsWith? clean "-"))
        (or (stringStartsWith? clean "http://") (stringStartsWith? clean "https://"))
        (not (stringContains? clean "://localhost"))
        (not (stringContains? clean "://127."))
        (not (stringContains? clean "://169.254."))
        (not (stringContains? clean "://10."))
        (not (stringContains? clean "://192.168."))
        (not (stringContains? clean "://172."))
        (not (stringContains? clean "://0."))
        (not (stringContains? clean "$("))
        (not (stringContains? clean "`"))
        (not (stringContains? clean "\""))
        (not (stringContains? clean "\\"))
        (noUrlUserInfo? clean))))

fn curlArgs job: CrawlJob -> (List Str)
  (if (not (isValidCrawlUrl? job.url)) (list) (let [(timeoutSec (/ job.timeoutMs 1000)) (headers (st/buildHeaders job.profile)) (headerArgs (st/curlHeaders headers)) (base (list "-sSL" "--max-time" (stringFromInt64 timeoutSec) "--compressed" "--" job.url))] (listAppend headerArgs base)))

fn crawlDoc result: CrawlResult -> txt/ExtractedDoc
  (if result.isSuccess (txt/extractHtml result.rawHtml result.url) (txt/ExtractedDoc :title result.url :content "" :format "error" :source result.url :charCount 0))

fn crawlAsn result: CrawlResult -> Str
  (let [(doc (crawlDoc result))] (txt/docToAsn doc))

fn makeSuccessResult url: Str statusCode: I64 rawHtml: Str -> CrawlResult
  (crawlOk url statusCode rawHtml)

fn makeFailureResult url: Str errorMsg: Str -> CrawlResult
  (crawlErr url errorMsg)

fn isSuccessfulStatus status: I64 -> Bool
  (statusOk? status)

fn buildCurlFetchArgs job: CrawlJob -> (List Str)
  (curlArgs job)

fn crawlToDoc result: CrawlResult -> txt/ExtractedDoc
  (crawlDoc result)

fn crawlToAsn result: CrawlResult -> Str
  (crawlAsn result)

fn isWafBlocked? statusCode: I64 body: Str -> Bool
  (or (and (or (= statusCode 403) (= statusCode 503)) (or (stringContains? body "Just a moment...") (or (stringContains? body "Checking your browser") (or (stringContains? body "Attention Required! | Cloudflare") (stringContains? body "cf-chl-bypass"))))) (or (= statusCode 429) (stringContains? body "Please complete the security check")))

fn cacheFallbackJobs targetUrl: Str -> (List CrawlJob)
  (list (crawlJob (str "https://web.archive.org/web/" targetUrl) (st/chromeProfile)) (crawlJob (str "https://archive.is/newest/" targetUrl) (st/chromeProfile)) (crawlJob (str "https://archive.today/newest/" targetUrl) (st/chromeProfile)))

fn isSpaShell? result: CrawlResult -> Bool
  (and result.isSuccess (txt/detectSpaEmptyDom result.rawHtml))

fn crawlDistilledAsn result: CrawlResult -> Str
  (if result.isSuccess
    (txt/distilledDocToAsn (txt/distillHtml result.rawHtml result.url))
    (crawlAsn result))

fn stripBetweenMarkers s: Str startTag: Str endTag: Str -> Str
  (if (and (stringContains? s startTag) (stringContains? s endTag)) (mt (stringIndexOf s startTag) ((some sIdx) (let [(remainder (optionOr (stringSlice s sIdx (stringLength s)) ""))] (mt (stringIndexOf remainder endTag) ((some relEIdx) (let [(eIdx (+ sIdx relEIdx)) (endPos (+ eIdx (stringLength endTag))) (prefix (optionOr (stringSlice s 0 sIdx) "")) (suffix (optionOr (stringSlice s endPos (stringLength s)) ""))] (str prefix suffix))) ((none) s)))) ((none) s)) s)

fn stripCacheDecorations html: Str -> Str
  (let [(s1 (stripBetweenMarkers html "<!-- BEGIN WAYBACK TOOLBAR INSERT -->" "<!-- END WAYBACK TOOLBAR INSERT -->")) (s2 (stripBetweenMarkers s1 "<div id=\"wm-ipp-base\"" "</div>"))] (stringTrim s2))

fn normalizeCrawlResponse result: CrawlResult -> CrawlResult
  (if result.isSuccess (let [(cleaned (stripCacheDecorations result.rawHtml))] (with result :rawHtml cleaned :charCount (stringLength cleaned))) result)

fn crawlWithFallback url: Str primaryResult: CrawlResult fallbackHtml: Str -> CrawlResult
  (let [(code (if (= primaryResult.statusCode 0) (if (stringContains? primaryResult.errorMsg "403") 403 (if (stringContains? primaryResult.errorMsg "503") 503 (if (stringContains? primaryResult.errorMsg "429") 429 0))) primaryResult.statusCode)) (body (if (> (stringLength primaryResult.rawHtml) 0) primaryResult.rawHtml primaryResult.errorMsg))] (if (and (not primaryResult.isSuccess) (isWafBlocked? code body)) (crawlOk url 200 (stripCacheDecorations fallbackHtml)) primaryResult))

(enum CrawlMode
  (:c modeExtension [] "Primary in-browser extension agent")
  (:c modePatchright [] "Headless patched CDP automation")
  (:c modeStaticHttp [] "Fast deterministic CPU distillation")
  (:c modeCloudProxy [] "Cloud reader and Wayback failover")
  (:c modeAuto [] "Adaptive sovereign cascade"))

fn modeToString mode: CrawlMode -> Str
  (mt mode
    ((modeExtension) "extension")
    ((modePatchright) "patchright")
    ((modeStaticHttp) "staticHttp")
    ((modeCloudProxy) "cloudProxy")
    ((modeAuto) "auto"))

fn stringToMode s: Str -> CrawlMode
  (let [(clean (stringLower (stringTrim s)))]
    (cond
      ((or (== clean "extension") (== clean ":extension")) (modeExtension))
      ((or (== clean "patchright") (== clean ":patchright") (== clean "cdp")) (modePatchright))
      ((or (== clean "statichttp") (== clean "static") (== clean ":statichttp")) (modeStaticHttp))
      ((or (== clean "cloudproxy") (== clean "cloud") (== clean "jina")) (modeCloudProxy))
      (else (modeAuto))))

fn crawlWithMode url: Str mode: CrawlMode -> CrawlJob
  (let [(prof (mt mode
                ((modeExtension) (st/chromeProfile))
                ((modePatchright) (st/chromeProfile))
                ((modeStaticHttp) (st/googlebotProfile))
                ((modeCloudProxy) (st/chromeProfile))
                ((modeAuto) (st/chromeProfile))))]
    (makeCrawlJob url prof))

fn distillHtmlToAsn url: Str html: Str errors: (List Str) -> Str
  (let [(t1 (txt/extractTitleFromHtml html))
        (title (if (stringEmpty? t1) "Untitled Document" t1))
        (cleaned (txt/cleanHtml html))
        (condensed (txt/normalizeWhitespace cleaned))
        (text (if (> (stringLength condensed) 3000) (str (optionOr (stringSlice condensed 0 3000) "") "...") condensed))
        (errField (if (listEmpty? errors)
                    "  :errors ()\n"
                    (str "  :errors (\n" (stringJoin (map (fn [(e Str)] -> Str (str "    " e)) errors) "\n") "\n  )\n")))]
    (str "(:pageSnapshot\n"
         "  :url \"" (esc/escapeAsnStr url) "\"\n"
         "  :title \"" (esc/escapeAsnStr title) "\"\n"
         "  :charCount " (stringFromInt64 (stringLength html)) "\n"
         "  :text \"" (esc/escapeAsnStr text) "\"\n"
         errField
         "  :status :ok)\n"))

fn formatFailedSnapshot url: Str errorMsg: Str errors: (List Str) -> Str
  (let [(errField (if (listEmpty? errors)
                    "  :errors ()\n"
                    (str "  :errors (\n" (stringJoin (map (fn [(e Str)] -> Str (str "    " e)) errors) "\n") "\n  )\n")))]
    (str "(:pageSnapshot\n"
         "  :url \"" (esc/escapeAsnStr url) "\"\n"
         "  :status :failed\n"
         errField
         "  :error \"" (esc/escapeAsnStr errorMsg) "\")\n"))

fn ! runArgv! argv: (List Str) -> (Result proc/PoolResult Str)
  (mt (proc/runPool! (list argv) 1)
    ((err e) (err (str "process failed: " e)))
    ((ok rows)
      (mt (listHead rows)
        ((none) (err "process returned no result"))
        ((some result)
          (mt result.spawnError
            ((some e)
              (let [(bin (optionOr (listHead argv) ""))]
                (err (if (= e "notFound") (str "sh: " bin ": command not found")
                       (if (= e "permission") (str "sh: " bin ": Permission denied")
                         (str "process spawn failed: " e))))))
            ((none) (ok result)))))))

fn findStealthBrowser! -> (Option Str)
  (let [(envChrome (envGet "CHROME_BIN"))]
    (mt envChrome
      ((some b) (if (fileExists? b) (some b) (none)))
      ((none)
        (let [(aslChrome (envGet "ASL_CHROME"))]
          (mt aslChrome
            ((some b) (if (fileExists? b) (some b) (none)))
            ((none)
              (let [(candidates (list "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
                                      "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
                                      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
                                      "/Applications/Chromium.app/Contents/MacOS/Chromium"
                                      "/usr/bin/google-chrome"
                                      "/usr/bin/chromium-browser"
                                      "/usr/bin/chromium"
                                      "/usr/bin/brave-browser"))
                    (existing (filter fileExists? candidates))]
                (mt (listHead existing)
                  ((some c) (some c))
                  ((none)
                    (mt (runArgv! (list "which" "google-chrome" "chromium" "chrome"))
                      ((err _) (none))
                      ((ok whichRes)
                        (if (= whichRes.exitCode 0)
                          (let [(lines (filter (fn [(l Str)] -> Bool (not (stringEmpty? l))) (stringSplit whichRes.stdout "\n")))]
                            (listHead lines))
                        (none)))))))))))))

fn browserFailureText exitCode: I64 stderr: Str -> Str
  (str "Stealth browser execution failed: exit " (stringFromInt64 exitCode) ": " stderr)

fn fetchStealthBrowser! url: Str timeoutSec: I64 -> (Result Str Str)
  (if (not (isValidCrawlUrl? url))
    (err "Invalid URL: must start with http:// or https://, avoid shell metacharacters, and not point to private/loopback address")
    (mt (findStealthBrowser!)
    ((none) (err "No local stealth browser binary found on system"))
    ((some browserBin)
      (let [(budget (stringFromInt64 (* timeoutSec 1000)))
            (argv (list browserBin "--headless=new" "--disable-blink-features=AutomationControlled" "--disable-infobars" "--no-first-run" "--no-default-browser-check" "--autoplay-policy=no-user-gesture-required" (str "--virtual-time-budget=" budget) "--window-size=1920,1080" "--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" "--dump-dom" url))]
        (mt (runArgv! argv)
          ((err e) (err (browserFailureText (if (stringContains? e "Permission denied") 126 127) e)))
          ((ok res)
            (if (= res.exitCode 0)
              (ok res.stdout)
              (err (browserFailureText res.exitCode res.stderr)))))))))

fn fetchCurl! url: Str timeoutSec: I64 -> (Result Str Str)
  (if (not (isValidCrawlUrl? url))
    (err "Invalid URL: must start with http:// or https:// and not point to private/loopback address")
    (let [(config (str "header = \"User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36\"\n"
                       "header = \"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\"\n"
                       "header = \"Accept-Language: en-US,en;q=0.9\"\n"))
          (args (list "--config" "-" "-sSL" "--max-time" (stringFromInt64 timeoutSec)
                      "--compressed" "--" url))
          (cmd (procCore/withStdin
                 (procCore/withTimeout (procCore/cmd "curl" args) (* (+ timeoutSec 5) 1000))
                 config))]
      (mt (procCore/exec! cmd)
        ((err e) (err (mt e
          ((procCore/notFound bin) (str "sh: " bin ": command not found"))
          ((procCore/permissionDenied path) (str "sh: " path ": Permission denied"))
          ((procCore/timeout _) "curl timeout")
          ((procCore/executionFailed _ msg) msg))))
        ((ok res)
          (if (= res.exitCode 0)
            (ok res.stdout)
            (let [(e (stringTrim res.stderr))]
              (err (if (stringEmpty? e) (str "curl exit " (stringFromInt64 res.exitCode)) e))))))))

fn urlEncodeTarget target: Str -> Str
  (let [(encodedPercent (stringReplace target "%" "%25"))
        (encodedSpace (stringReplace encodedPercent " " "%20"))
        (encodedAmp (stringReplace encodedSpace "&" "%26"))
        (encodedEquals (stringReplace encodedAmp "=" "%3D"))
        (encodedQuestion (stringReplace encodedEquals "?" "%3F"))
        (encodedHash (stringReplace encodedQuestion "#" "%23"))
        (encodedPlus (stringReplace encodedHash "+" "%2B"))]
    encodedPlus)

fn gatewayDispatch! payload: Str target: Str browser: Str -> (Result Str Str)
  (let [(port (optionOr (envGet "ASL_GATEWAY_PORT") "8765"))
        (selector (if (not (stringEmpty? target))
                    (str "?target=" (urlEncodeTarget target))
                    (if (not (stringEmpty? browser)) (str "?browser=" browser) "")))
        (url (str "http://127.0.0.1:" port "/api/asl/browser/exec" selector))
        (argv (list "curl" "-sSf" "--max-time" "15" "-X" "POST"
                    "-H" "Content-Type: application/asn+sexpr"
                    "--data-binary" payload "--" url))]
    (mt (runArgv! argv)
      ((err e) (err e))
      ((ok response)
        (if (= response.exitCode 0)
          (ok response.stdout)
          (let [(message (stringTrim response.stderr))]
            (err (if (stringEmpty? message)
                   (str "curl exit " (stringFromInt64 response.exitCode))
                   message)))))))

fn gatewayFailureReceipt! error: Str -> Int64
  (do
    (println (str "(:automationReceipt :id \"act-err\" :status :failed :duration 0 :error \"Gateway browser dispatch error: "
                  (esc/escapeAsnStr error) "\")"))
    1)

fn dispatchGateway! payload: Str target: Str browser: Str -> Int64
  (mt (gatewayDispatch! payload target browser)
    ((err e) (gatewayFailureReceipt! e))
    ((ok receipt) (do (print receipt) (if (stringContains? receipt ":status :failed") 1 0))))

fn ! runCrawlPatchright! url: Str distill: Str -> Int64
  (mt (fetchStealthBrowser! url 20)
    ((ok html)
      (do
        (cond
          ((= distill "raw") (println html))
          ((= distill "asn") (print (distillHtmlToAsn url html (list))))
          (else (let [(t (txt/extractTitleFromHtml html))
                      (title (if (stringEmpty? t) "Untitled" t))]
                  (println (str "[" title "] " url)))))
        0))
    ((err e)
      (runCrawlHttp! url distill (list (str "(:engine patchright :error \"" (esc/escapeAsnStr e) "\")")))))

fn runCrawl! url: Str mode: Str distill: Str inject: Bool target: Str browser: Str -> Int64
  (if (or (not (stringEmpty? target)) (not (stringEmpty? browser)))
    (dispatchGateway! (str "(:automationAction :id \"act-crawl-" (stringFromInt64 (monotonicNs))
                           "\" :op \"navigate\" :target \"" (esc/escapeAsnStr url)
                           "\" :timeoutMs 10000)\n") target browser)
    (if (= mode "extension")
      (dispatchExtensionCrawl! (str "(:automationAction :id \"act-crawl-" (stringFromInt64 (monotonicNs))
                             "\" :op \"navigate\" :target \"" (esc/escapeAsnStr url)
                             "\" :timeoutMs 10000)\n") url distill)
  (let [(effMode (if (= mode "auto")
                   (if (browserGatewayActive?)
                     "extension"
                     (mt (findStealthBrowser!)
                       ((some _) "patchright")
                       ((none) "staticHttp")))
                   mode))]
    (cond
      ((= effMode "patchright") (runCrawlPatchright! url distill))
      ((= effMode "extension")
        (dispatchExtensionCrawl! (str "(:automationAction :id \"act-crawl-" (stringFromInt64 (monotonicNs))
                               "\" :op \"navigate\" :target \"" (esc/escapeAsnStr url)
                               "\" :timeoutMs 10000)\n") url distill))
      ((= effMode "cloudProxy")
        (let [(jinaUrl (str "https://r.jina.ai/" url))]
          (mt (fetchCurl! jinaUrl 15)
            ((ok html)
              (do
                (cond
                  ((= distill "raw") (println html))
                  ((= distill "asn") (print (distillHtmlToAsn url html (list))))
                  (else (let [(t (txt/extractTitleFromHtml html))
                              (title (if (stringEmpty? t) "Untitled" t))]
                          (println (str "[" title "] " url)))))
                0))
            ((err e)
              (do (print (formatFailedSnapshot url e (list (str "(:engine cloudProxy :error \"" (esc/escapeAsnStr e) "\")")))) 1)))))
      (else
        (runCrawlHttp! url distill (list)))))))

fn runCrawlHttp! url: Str distill: Str prevErrors: (List Str) -> Int64
  (mt (fetchCurl! url 10)
    ((ok html)
      (do
        (cond
          ((= distill "raw") (println html))
          ((= distill "asn") (print (distillHtmlToAsn url html prevErrors)))
          (else (let [(t (txt/extractTitleFromHtml html))
                      (title (if (stringEmpty? t) "Untitled" t))]
                  (println (str "[" title "] " url)))))
        0))
    ((err e)
      (let [(errs1 (listAppend prevErrors (list (str "(:engine staticHttp :error \"" (esc/escapeAsnStr e) "\")"))))
            (jinaUrl (str "https://r.jina.ai/" url))]
        (mt (fetchCurl! jinaUrl 10)
          ((ok jinaHtml)
            (do (print (distillHtmlToAsn url jinaHtml errs1)) 0))
          ((err e2)
            (let [(allErrs (listAppend errs1 (list (str "(:engine jina :error \"" (esc/escapeAsnStr e2) "\")"))))]
              (do (print (formatFailedSnapshot url (str e " (jina: " e2 ")") allErrs)) 1)))))))

fn ! browserGatewayActive? -> Bool
  (let [(port (optionOr (envGet "ASL_GATEWAY_PORT") "8765"))
        (statusUrl (str "http://127.0.0.1:" port "/api/asl/browser/status"))
        (argv (list "curl" "-sS" "--max-time" "1" "--" statusUrl))]
    (mt (runArgv! argv)
      ((err _) false)
      ((ok response) (and (= response.exitCode 0) (stringContains? response.stdout "extension-primary")))))

fn ! dispatchExtensionCrawl! payload: Str url: Str distill: Str -> Int64
  (mt (gatewayDispatch! payload "" "")
    ((err _) (runCrawlFallback! url distill))
    ((ok receipt) (if (stringContains? receipt ":snapshot") (do (print receipt) 0) (runCrawlFallback! url distill))))

fn ! runCrawlFallback! url: Str distill: Str -> Int64
  (mt (findStealthBrowser!)
    ((some _) (runCrawlPatchright! url distill))
    ((none) (runCrawlHttp! url distill (list))))

fn extractAfter s: Str mark: Str -> (Option Str)
  (mt (stringIndexOf s mark)
    ((none) (none))
    ((some i) (stringSlice s (+ i (stringLength mark)) (stringLength s))))

fn sliceUntilAny s: Str delims: (List Str) -> Str
  (let [(indices (filter (fn [(idx Int64)] -> Bool (>= idx 0))
                         (map (fn [(d Str)] -> Int64 (optionOr (stringIndexOf s d) -1)) delims)))]
    (if (listEmpty? indices)
      s
      (let [(minIdx (fold (fn [(acc Int64) (v Int64)] -> Int64 (min acc v)) (stringLength s) indices))]
        (optionOr (stringSlice s 0 minIdx) s))))

fn jsonScalarText value: j/Json -> Str
  (mt value
    ((j/jstr s) s)
    ((j/jint n) (stringFromInt64 n))
    ((j/jfloat n) (stringFromFloat64 n))
    ((j/jnum n) (stringFromFloat64 n))
    (_ ""))

fn jsonFieldText obj: j/Json key: Str -> Str
  (mt (j/jsonGet obj key)
    ((some value) (jsonScalarText value))
    (_ ""))

fn extractTikTokMetadata! url: Str html: Str -> (Result Str Str)
  (let [(script (optionOr (extractAfter html "<script id=\"SIGI_STATE\"") ""))
        (jsonTail (optionOr (extractAfter script ">") ""))
        (jsonText (sliceUntilAny jsonTail (list "</script>")))
        (vid (mt (extractAfter url "/video/")
              ((some rest) (sliceUntilAny rest (list "?" "/" "&" "#")))
              (_ "")))
        (parsed (j/jsonParse jsonText))]
    (mt parsed
      ((err e) (err (str "TikTok SIGI_STATE metadata could not be parsed: " e)))
      ((ok root)
        (let [(module (optionOr (j/jsonGet root "ItemModule") (j/jnull)))
              (item (optionOr (j/jsonGet module vid) (j/jnull)))
              (authorObj (optionOr (j/jsonGet item "author") (j/jnull)))
              (stats (optionOr (j/jsonGet item "stats") (j/jnull)))
              (music (optionOr (j/jsonGet item "music") (j/jnull)))
              (author (jsonFieldText authorObj "uniqueId"))
              (caption (jsonFieldText item "desc"))
              (likes (optionOr (stringToInt64 (jsonFieldText stats "diggCount")) -1))
              (comments (optionOr (stringToInt64 (jsonFieldText stats "commentCount")) -1))
              (sound (jsonFieldText music "title"))]
          (if (or (stringEmpty? vid)
                  (or (stringEmpty? author)
                    (or (stringEmpty? caption)
                      (or (< likes 0)
                        (or (< comments 0) (stringEmpty? sound))))))
            (err "TikTok metadata is incomplete for the requested video")
            (let [(receipt (auto/makeMediaMetadataReceipt
                             (str "meta-tt-" (stringFromInt64 (monotonicNs)))
                             "tiktok" vid (str "@" author) caption likes comments sound))]
              (ok (auto/formatMediaMetadataAsn receipt))))))))

fn runTikTokWatch! url: Str watch: I64 -> Int64
  (dispatchGateway! (str "(:automationAction :id \"act-tt-" (stringFromInt64 (monotonicNs))
                         "\" :op \"watchMedia\" :target \"" (esc/escapeAsnStr url)
                         "\" :duration " (stringFromInt64 watch)
                         " :extractMetadata true)\n") "" "")

fn runTiktok! url: Str extract: Bool watch: I64 -> Int64
  (if extract
    (mt (fetchCurl! url 20)
      ((err e) (do (eprintln (str "TikTok extraction failed: " e)) 1))
      ((ok html)
        (mt (extractTikTokMetadata! url html)
          ((err e) (do (eprintln (str "TikTok extraction failed: " e)) 1))
          ((ok receipt) (do (println receipt) 0)))))
    (runTikTokWatch! url watch))

fn runAutomate! scriptFile: Str -> Int64
  (if (not (fileExists? scriptFile))
    (do (println "(:automationReceipt :status :failed :error \"script file does not exist\")") 1)
    (mt (fileReadString scriptFile)
      ((err e) (do (println (str "(:automationReceipt :status :failed :error \"" (esc/escapeAsnStr e) "\")")) 1))
      ((ok content) (dispatchGateway! content "" ""))))

fn lastPathSeparator path: Str index: I64 last: I64 -> I64
  (if (>= index (stringLength path))
    last
    (let [(char (optionOr (stringSlice path index (+ index 1)) ""))]
      (lastPathSeparator path (+ index 1) (if (= char "/") index last))))

fn exportAgentScript! exportFile: Str script: Str -> Int64
  (let [(separator (lastPathSeparator exportFile 0 -1))
        (parent (if (< separator 0) "" (optionOr (stringSlice exportFile 0 separator) "")))]
    (if (stringEmpty? parent)
      (mt (fileWrite exportFile script)
        ((ok _) (do (println (str "(:agentBundle :exported \"" (esc/escapeAsnStr exportFile) "\" :bytes " (stringFromInt64 (stringLength script)) " :status :ok)")) 0))
        ((err e) (do (eprintln (str "Export failed: " e)) 1)))
      (mt (dirCreate parent)
        ((err e) (do (eprintln (str "Export failed: " e)) 1))
        ((ok _) (mt (fileWrite exportFile script)
          ((ok _) (do (println (str "(:agentBundle :exported \"" (esc/escapeAsnStr exportFile) "\" :bytes " (stringFromInt64 (stringLength script)) " :status :ok)")) 0))
          ((err e) (do (eprintln (str "Export failed: " e)) 1)))))))

fn runAgent! status: Bool exportFile: Str maxNodes: I64 stealth: Bool kinetics: Bool -> Int64
  (if status
    (let [(browser (optionOr (findStealthBrowser!) "none"))]
      (do
        (println (str "(:inBrowserAgent :runtime :unverified :browserBinary \""
                      (esc/escapeAsnStr browser) "\" :ready :unknown)"))
        0))
    (let [(cfg (iba/InBrowserAgentConfig
                 :agentId "asl-in-page-agent"
                 :version "1.0.0"
                 :gatewayUrl "http://127.0.0.1:8765"
                 :stealthEvasions stealth
                 :kineticsEnabled kinetics
                 :behavioralNoise true
                 :maxSnapshotNodes maxNodes))
          (script (iba/generateInBrowserAgentBootstrap cfg))]
      (if (not (stringEmpty? exportFile))
        (exportAgentScript! exportFile script)
        (do (println script) 0))))

fn cmdStatus! -> Int64
  (let [(browser (optionOr (findStealthBrowser!) "none"))]
    (do
      (println "(:crawlerStatus")
      (println "  :extensionActive :unverified")
      (println (str "  :localStealthBrowser \"" browser "\""))
      (println "  :inBrowserAgentReady :unknown")
      (println "  :supportedModes [:patchright :staticHttp :cloudProxy :auto :extension]")
      (println "  :unavailableModes []")
      (println "  :note \"Extension, target, automation, and media-watch actions dispatch through the browser gateway\"")
      (println ")")
      0))

fn cmdSession! service: Str -> Int64
  (let [(preset (sess/getServicePreset service))]
    (do (println (str "(:sessionInfo :service \"" (esc/escapeAsnStr preset.serviceName)
                      "\" :status :unverified :authenticated :unknown)"))
        1))

fn parseCrawlArgs! rest: (List Str) url: Str mode: Str distill: Str inject: Bool target: Str browser: Str -> Int64
  (mt (listHead rest)
    ((none)
      (if (stringEmpty? url)
        (do (eprintln "Error: url is required for crawl") 2)
        (runCrawl! url mode distill inject target browser)))
    ((some arg)
      (let [(tail (optionOr (listTail rest) (list)))]
        (cond
          ((or (= arg "--help") (= arg "-h"))
            (do (println "Usage: asl-crawler crawl <url> [--mode auto|extension|patchright|staticHttp|cloudProxy] [--distill asn|text|raw] [--inject-agent] [--target <id>|--browser <chrome|safari|steel|cdp>]") 0))
          ((or (= arg "--mode") (= arg "-m"))
            (parseCrawlArgs! (optionOr (listTail tail) (list)) url (optionOr (listHead tail) "auto") distill inject target browser))
          ((or (= arg "--distill") (= arg "-d"))
            (parseCrawlArgs! (optionOr (listTail tail) (list)) url mode (optionOr (listHead tail) "asn") inject target browser))
          ((= arg "--inject-agent")
            (parseCrawlArgs! tail url mode distill true target browser))
          ((= arg "--target")
            (if (listEmpty? tail)
              (do (eprintln "Missing value for --target") 2)
              (parseCrawlArgs! (optionOr (listTail tail) (list)) url mode distill inject (optionOr (listHead tail) "") browser)))
          ((= arg "--browser")
            (if (listEmpty? tail)
              (do (eprintln "Missing value for --browser") 2)
              (let [(family (optionOr (listHead tail) ""))]
                (if (listContains? (list "chrome" "safari" "steel" "cdp") family)
                  (parseCrawlArgs! (optionOr (listTail tail) (list)) url mode distill inject target family)
                  (do (eprintln (str "Unsupported browser family: " family)) 2)))))
          ((stringStartsWith? arg "--mode=")
            (parseCrawlArgs! tail url (optionOr (stringSlice arg 7 (stringLength arg)) "auto") distill inject target browser))
          ((stringStartsWith? arg "--distill=")
            (parseCrawlArgs! tail url mode (optionOr (stringSlice arg 10 (stringLength arg)) "asn") inject target browser))
          ((stringStartsWith? arg "-")
            (do (eprintln (str "Unsupported crawl option: " arg)) 2))
          (else
            (parseCrawlArgs! tail (if (stringEmpty? url) arg url) mode distill inject target browser))))))

fn parseTiktokArgs! rest: (List Str) url: Str extract: Bool watch: I64 -> Int64
  (mt (listHead rest)
    ((none)
      (if (stringEmpty? url)
        (do (eprintln "Error: url is required for tiktok") 2)
        (if extract
          (runTiktok! url true watch)
          (runTikTokWatch! url watch))))
    ((some arg)
      (let [(tail (optionOr (listTail rest) (list)))]
        (cond
          ((= arg "--extract")
            (parseTiktokArgs! tail url true watch))
          ((= arg "--watch")
            (parseTiktokArgs! (optionOr (listTail tail) (list)) url extract (optionOr (stringToInt64 (optionOr (listHead tail) "10")) 10)))
          ((stringStartsWith? arg "--watch=")
            (parseTiktokArgs! tail url extract (optionOr (stringToInt64 (optionOr (stringSlice arg 8 (stringLength arg)) "10")) 10)))
          ((stringStartsWith? arg "-")
            (do (eprintln (str "Unsupported tiktok option: " arg)) 2))
          (else
            (parseTiktokArgs! tail (if (stringEmpty? url) arg url) extract watch))))))

fn parseAgentArgs! rest: (List Str) status: Bool exportFile: Str maxNodes: I64 stealth: Bool kinetics: Bool -> Int64
  (mt (listHead rest)
    ((none)
      (runAgent! status exportFile maxNodes stealth kinetics))
    ((some arg)
      (let [(tail (optionOr (listTail rest) (list)))]
        (cond
          ((= arg "--status")
            (parseAgentArgs! tail true exportFile maxNodes stealth kinetics))
          ((= arg "--export")
            (parseAgentArgs! (optionOr (listTail tail) (list)) status (optionOr (listHead tail) "") maxNodes stealth kinetics))
          ((stringStartsWith? arg "--export=")
            (parseAgentArgs! tail status (optionOr (stringSlice arg 9 (stringLength arg)) "") maxNodes stealth kinetics))
          ((= arg "--max-nodes")
            (if (listEmpty? tail)
              (do (eprintln "Missing value for --max-nodes") 2)
              (let [(raw (optionOr (listHead tail) "100"))
                    (parsed (stringToInt64 raw))]
                (mt parsed
                  ((none) (do (eprintln (str "Invalid --max-nodes value: " raw)) 2))
                  ((some value)
                    (if (> value 0)
                      (parseAgentArgs! (optionOr (listTail tail) (list)) status exportFile value stealth kinetics)
                      (do (eprintln "Invalid --max-nodes value: expected a positive integer") 2)))))))
          ((= arg "--no-stealth")
            (parseAgentArgs! tail status exportFile maxNodes false kinetics))
          ((= arg "--no-kinetics")
            (parseAgentArgs! tail status exportFile maxNodes stealth false))
          (else
            (parseAgentArgs! tail status exportFile maxNodes stealth kinetics))))))

fn showUsage! -> Int64
  (do
    (println "asl-crawler: Sovereign Web Crawler, In-Browser Automation, and Semantic Parsing Nexus")
    (println "Usage: crawler <crawl|tiktok|automate|agent|status|session> [args...]")
    (println "  crawl <url> [--mode auto|extension|patchright|staticHttp|cloudProxy] [--distill asn|text|raw] [--inject-agent] [--target <id>|--browser <family>]")
    (println "  tiktok <url> [--watch <sec>] [--extract]")
    (println "  automate <script_file>")
    (println "  agent [--status] [--export <path>] [--max-nodes <n>] [--no-stealth] [--no-kinetics]")
    (println "  status")
    (println "  session <service>")
    0)

fn ! main args: (List String) -> (Result Int64 String)
  (if (listEmpty? args)
    (ok (showUsage!))
    (let [(sub (optionOr (listHead args) ""))
          (rest (optionOr (listTail args) (list)))]
      (cond
        ((or (= sub "-h") (or (= sub "--help") (= sub "help")))
          (ok (showUsage!)))
        ((or (= sub "crawl") (= sub ":crawl"))
          (ok (parseCrawlArgs! rest "" "auto" "asn" false "" "")))
        ((or (= sub "tiktok") (= sub ":tiktok"))
          (ok (parseTiktokArgs! rest "" false 10)))
        ((or (= sub "automate") (= sub ":automate"))
          (ok (runAutomate! (optionOr (listHead rest) ""))))
        ((or (= sub "agent") (= sub ":agent"))
          (ok (parseAgentArgs! rest false "" 100 true true)))
        ((or (= sub "status") (= sub ":status"))
          (ok (cmdStatus!)))
        ((or (= sub "session") (= sub ":session"))
          (ok (cmdSession! (optionOr (listHead rest) "generic"))))
        (else
          (do (eprintln (str "Unknown crawler subcommand: " sub))
              (ok 2))))))
