(module aslGateway/search
  :x [Bucket HubState newHubState mkHub hubWithNow hubSleep! hubNote hubCliCall hubStderr hubWithBreaker hubWithBuckets
      HttpReq HttpResult httpResp httpFail curlConfig curlChildEnv parseCurlOutput runCurlBatch! runOne! httpError httpOk? validateReq headerNameOk charsetNameOk runTool! iconvDecode! decodeBody! contentCharset urlTypeCheck repl
      jobj3 engineError respJson jreq
      tavilyReq tavilyParse serperReq serperParse wikiReq wikiParse searxngReq searxngParse ddgReq ddgParse ddgLinks ddgSnippets ddgThrottle!
      doTavilySearch! doSerperSearch! doWikiSearch! doSearxngSearch! doDdgSearch! parallelTier1Search! executeSearchHub!
      escapeAsnStr formatSearchAsn]
  :i [(asl-json/json :a j)
      (pyText :a pt)])

(schema Bucket (:f tokens Float64) (:f last Float64) (:f rate Float64))

(schema HubState
  (:f env (Map String String))
  (:f nowMs Int64)
  (:f cache (Map String (Pair Int64 j/Json)))
  (:f lastDdgMs Int64)
  (:f breakerUntil (Map String Int64))
  (:f count503 (Map String Int64))
  (:f buckets (Map String Bucket))
  (:f usage (List j/Json))
  (:f cliCalls (List j/Json))
  (:f stderr (List String))
  (:f sleeps (List Int64)))

fn mkHub st: HubState nowMs: Int64 cache: (Map String (Pair Int64 j/Json)) lastDdgMs: Int64 until: (Map String Int64) c503: (Map String Int64) buckets: (Map String Bucket) usage: (List j/Json) cli: (List j/Json) errs: (List String) sleeps: (List Int64) -> HubState
  (with st :nowMs nowMs :cache cache :lastDdgMs lastDdgMs :breakerUntil until :count503 c503 :buckets buckets :usage usage :cliCalls cli :stderr errs :sleeps sleeps)

fn newHubState env: (Map String String) nowMs: Int64 lastDdgMs: Int64 until: (Map String Int64) c503: (Map String Int64) -> HubState
  (HubState :env env :nowMs nowMs :cache (mapEmpty) :lastDdgMs lastDdgMs :breakerUntil until :count503 c503 :buckets (mapEmpty)
            :usage (list) :cliCalls (list) :stderr (list) :sleeps (list))

fn hubCopy st: HubState nowMs: Int64 cache: (Map String (Pair Int64 j/Json)) lastDdgMs: Int64 -> HubState
  (mkHub st nowMs cache lastDdgMs st.breakerUntil st.count503 st.buckets st.usage st.cliCalls st.stderr st.sleeps)

fn hubWithNow st: HubState nowMs: Int64 -> HubState
  (hubCopy st nowMs st.cache st.lastDdgMs)

fn hubWithBreaker st: HubState until: (Map String Int64) c503: (Map String Int64) -> HubState
  (mkHub st st.nowMs st.cache st.lastDdgMs until c503 st.buckets st.usage st.cliCalls st.stderr st.sleeps)

fn hubWithBuckets st: HubState b: (Map String Bucket) -> HubState
  (mkHub st st.nowMs st.cache st.lastDdgMs st.breakerUntil st.count503 b st.usage st.cliCalls st.stderr st.sleeps)

fn hubNote st: HubState prov: j/Json alias: j/Json outcome: String usage: j/Json -> HubState
  (mkHub st st.nowMs st.cache st.lastDdgMs st.breakerUntil st.count503 st.buckets
         (listAppend st.usage (list (j/jarr (list prov alias (j/jstr outcome) usage)))) st.cliCalls st.stderr st.sleeps)

fn hubCliCall st: HubState call: j/Json -> HubState
  (mkHub st st.nowMs st.cache st.lastDdgMs st.breakerUntil st.count503 st.buckets
         st.usage (listAppend st.cliCalls (list call)) st.stderr st.sleeps)

fn hubStderr st: HubState line: String -> HubState
  (mkHub st st.nowMs st.cache st.lastDdgMs st.breakerUntil st.count503 st.buckets
         st.usage st.cliCalls (listAppend st.stderr (list line)) st.sleeps)

fn ! hubSleep! st: HubState ms: Int64 -> HubState
  (do
    (if (> ms 0) (sleepMs ms) ())
    (mkHub st (+ st.nowMs ms) st.cache st.lastDdgMs st.breakerUntil st.count503 st.buckets
           st.usage st.cliCalls st.stderr (listAppend st.sleeps (list ms))))

fn repl s: String old: String new: String -> String
  (pt/replaceAll s old new)

fn urlTypeCheck url: String -> (Result Bool pt/PyErr)
  (let [(c (stringIndexOf url ":"))]
    (mt c
      ((some i) (if (and (> i 0) (not (pt/hasSubstr (pt/sliceB url 0 i) "/"))) (ok true) (err (pt/pyErr "ValueError" (str "unknown url type: " (pt/pyRepr (j/jstr url)))))))
      ((none) (err (pt/pyErr "ValueError" (str "unknown url type: " (pt/pyRepr (j/jstr url))))))))

(schema HttpReq (:f url String) (:f headers (List (Pair String String))) (:f data (Option String)) (:f timeout j/Json))

(enum HttpResult
  (:c httpResp [(status Int64) (reason String) (headers (List (Pair String String))) (body String)])
  (:c httpFail [(err pt/PyErr) (timedOut Bool)]))

fn cq s: String -> String
  (str "\"" (repl (repl (repl (repl (repl (repl s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") (pt/byteStr 11) "\\v") "\"")

fn hasHeader hs: (List (Pair String String)) name: String -> Bool
  (listAny? (fn [(h (Pair String String))] -> Bool (= (pt/asciiLower (pairFirst h)) name)) hs)

fn isTokenByte b: Int64 -> Bool
  (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90)) (and (>= b 48) (<= b 57))
      (listContains? (list 33 35 36 37 38 39 42 43 45 46 94 95 96 124 126) b))

fn allBytes bs: Bytes i: Int64 n: Int64 ok: (fn [Int64] -> Bool) -> Bool
  (if (>= i n) true (and (ok (bytesGet bs i)) (allBytes bs (+ i 1) n ok)))

fn noBytes s: String bad: (fn [Int64] -> Bool) -> Bool
  (let [(bs (stringToBytes s))] (allBytes bs 0 (bytesLength bs) (fn [(b Int64)] -> Bool (not (bad b)))))

fn bytesRepr s: String -> String
  (str "b" (pt/pyRepr (j/jstr s)))

fn firstCtl bs: Bytes i: Int64 -> Int64
  (cond ((>= i (bytesLength bs)) i) ((or (<= (bytesGet bs i) 32) (= (bytesGet bs i) 127)) i) (else (firstCtl bs (+ i 1))))

fn headerNameOk name: String -> Bool
  (let [(bs (stringToBytes name))] (and (> (bytesLength bs) 0) (allBytes bs 0 (bytesLength bs) isTokenByte)))

fn urlSelector url: String -> String
  (mt (stringIndexOf url "://")
    ((none) url)
    ((some i) (let [(rest (pt/sliceB url (+ i 3) (stringLength url)))] (mt (stringIndexOf rest "/") ((some k) (pt/sliceB rest k (stringLength rest))) ((none) "")))))

fn validateReq r: HttpReq -> (Result Bool pt/PyErr)
  (let [(ctl (fn [(b Int64)] -> Bool (or (<= b 32) (= b 127))))
        (crlf (fn [(b Int64)] -> Bool (or (= b 10) (= b 13) (= b 0))))
        (badName (listHead (filter (fn [(h (Pair String String))] -> Bool (not (headerNameOk (pairFirst h)))) r.headers)))
        (badValue (listHead (filter (fn [(h (Pair String String))] -> Bool (not (noBytes (pairSecond h) crlf))) r.headers)))]
    (cond
      ((not (noBytes r.url ctl))
        (err (pt/pyErr "InvalidURL" (str "URL can't contain control characters. " (pt/pyRepr (j/jstr (urlSelector r.url))) " (found at least " (let [(i (firstCtl (stringToBytes r.url) 0))] (pt/pyRepr (j/jstr (pt/sliceB r.url i (+ i 1))))) ")"))))
      ((some? badName) (err (pt/pyErr "ValueError" (str "Invalid header name " (bytesRepr (mt badName ((some h) (pairFirst h)) ((none) "")))))))
      ((some? badValue) (err (pt/pyErr "ValueError" (str "Invalid header value for " (bytesRepr (mt badValue ((some h) (pairFirst h)) ((none) ""))) " (value withheld)"))))
      ((mt r.data ((some d) (not (noBytes d (fn [(b Int64)] -> Bool (= b 0))))) ((none) false)) (err (pt/pyErr "ValueError" "request body contains a NUL byte")))
      (else (ok true))))

fn curlConfig r: HttpReq -> (Result String pt/PyErr)
  (mt (validateReq r)
    ((err e) (err e))
    ((ok _)
      (ok (pt/treeJoin
            (listAppend
              (list "url = " (cq r.url) "\nproto = \"=http,https\"\ngloboff\nhttp1.1\ninclude\nsilent\nshow-error\nsuppress-connect-headers\nmax-time = "
                    (pt/jsonDumps r.timeout -1) "\n")
              (listAppend
                (map (fn [(h (Pair String String))] -> String (str "header = " (cq (str (pairFirst h) ": " (pairSecond h))) "\n")) r.headers)
                (listAppend
                  (list (if (hasHeader r.headers "accept") "" "header = \"Accept:\"\n") "header = \"Expect:\"\n")
                  (mt r.data ((some d) (list "data-raw = " (cq d) "\n")) ((none) (list))))))))))

fn curlChildEnv env: (Map String String) -> (List String)
  (let [(names (list "http_proxy" "https_proxy" "HTTP_PROXY" "HTTPS_PROXY" "no_proxy" "NO_PROXY" "all_proxy" "ALL_PROXY" "SSL_CERT_FILE" "CURL_CA_BUNDLE"))
        (extra (fold (fn [(acc (List String)) (k String)] -> (List String) (mt (mapGet env k) ((some v) (listAppend acc (list (str k "=" v)))) ((none) acc))) (list) names))]
    (cons (str "PATH=" (optionOr (mapGet env "PATH") "/usr/bin:/bin")) extra))

fn headerLines block: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String))
          (mt (stringIndexOf line ":")
            ((some i) (listAppend acc (list (pair (pt/sliceB line 0 i) (pt/pyStrip (pt/sliceB line (+ i 1) (stringLength line)))))))
            ((none) acc)))
        (list) (optionOr (listTail (stringSplit block "\r\n")) (list)))

fn parseCurlOutput out: String -> (Result HttpResult String)
  (if (not (stringStartsWith? out "HTTP/"))
    (err (str "curl output has no status line: " (pt/sliceB out 0 (min 80 (stringLength out)))))
    (mt (stringIndexOf out "\r\n\r\n")
      ((none) (err "curl output has no header terminator"))
      ((some k)
        (let [(block (pt/sliceB out 0 k))
              (rest (pt/sliceB out (+ k 4) (stringLength out)))
              (statusLine (pairFirst (pt/partition block "\r\n")))
              (afterVer (optionOr (pairSecond (pt/partition statusLine " ")) ""))
              (cp (pt/partition afterVer " "))
              (code (optionOr (stringToInt64 (pairFirst cp)) -1))
              (reason (pt/pyStrip (optionOr (pairSecond cp) "")))
              (hs (headerLines block))]
          (cond
            ((< code 0) (err (str "bad status line: " statusLine)))
            ((and (>= code 100) (< code 200)) (parseCurlOutput rest))
            (else (ok (httpResp code reason hs rest))))))))

fn httpOk? code: Int64 -> Bool
  (and (>= code 200) (< code 300))

(schema Slot (:f idx Int64) (:f pid Int64) (:f outFd Int64) (:f errFd Int64) (:f outOpen Bool) (:f errOpen Bool) (:f out (List String)) (:f errs (List String)) (:f code (Option Int64)) (:f fault (Option String)) (:f timedOut Bool))

fn ! writeAll! fd: Int64 s: String -> (Result Int64 String)
  (if (stringEmpty? s)
    (ok 0)
    (mt (fdWrite fd s)
      ((err e) (err e))
      ((ok k) (writeAll! fd (pt/sliceB s k (stringLength s))))))

fn ! reap! pid: Int64 outFd: Int64 errFd: Int64 -> Bool
  (let [(k (procKill (- 0 pid) "SIGKILL")) (w (procWaitPid pid false)) (a (fdClose outFd)) (b (fdClose errFd))]
    (and (ok? w) (ok? a) (ok? b)))

fn ! spawnCurl! idx: Int64 r: HttpReq env: (List String) -> (Result Slot HttpResult)
  (mt (curlConfig r)
    ((err e) (err (httpFail e false)))
    ((ok cfg)
      (mt (procSpawnv (list "curl" "-q" "--config" "-") (none) (some env))
        ((err e) (err (httpFail (pt/pyErr "ToolAbsent" (str "ERR_TOOL_ABSENT: curl did not start (" e ")")) false)))
        ((ok sp)
          (let [(w (writeAll! sp.stdin cfg)) (c (fdClose sp.stdin))]
            (mt w
              ((err e) (do (reap! sp.pid sp.stdout sp.stderr) (err (httpFail (pt/pyErr "URLError" (str "<urlopen error curl stdin: " e ">")) false))))
              ((ok _)
                (mt c
                  ((err e) (do (reap! sp.pid sp.stdout sp.stderr) (err (httpFail (pt/pyErr "URLError" (str "<urlopen error curl stdin close: " e ">")) false))))
                  ((ok _) (ok (Slot :idx idx :pid sp.pid :outFd sp.stdout :errFd sp.stderr :outOpen true :errOpen true :out (list) :errs (list) :code (none) :fault (none) :timedOut false)))))))))))

fn fdReady? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn ! readSide! fd: Int64 -> (Result (Option String) String)
  (mt (fdRead fd 65536)
    ((ok chunk) (if (stringEmpty? chunk) (mt (fdClose fd) ((ok _) (ok (none))) ((err e) (err (str "close: " e)))) (ok (some chunk))))
    ((err e) (do (fdClose fd) (err (str "read: " e)))))

fn ! absorb! s: Slot ready: (List (Pair Int64 Int64)) exited: (List (Pair Int64 Int64)) -> Slot
  (let [(o (if (and s.outOpen (fdReady? ready s.outFd)) (readSide! s.outFd) (ok (some ""))))
        (e (if (and s.errOpen (fdReady? ready s.errFd)) (readSide! s.errFd) (ok (some ""))))
        (ex (filter (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) s.pid)) exited))
        (code (if (some? s.code) s.code (mt (listHead ex) ((some p) (some (pairSecond p))) ((none) (none)))))
        (fault (cond ((some? s.fault) s.fault) ((err? o) (resultToOption (mt o ((err m) (ok m)) ((ok _) (err ""))))) ((err? e) (resultToOption (mt e ((err m) (ok m)) ((ok _) (err ""))))) (else (none))))
        (oc (optionOr (resultToOption o) (none)))
        (ec (optionOr (resultToOption e) (none)))]
    (with s :outOpen (and s.outOpen (ok? o) (some? oc)) :errOpen (and s.errOpen (ok? e) (some? ec)) :out (mt oc ((some c) (if (stringEmpty? c) s.out (cons c s.out))) ((none) s.out)) :errs (mt ec ((some c) (if (stringEmpty? c) s.errs (cons c s.errs))) ((none) s.errs)) :code code :fault fault))

fn slotDone? s: Slot -> Bool
  (and (some? s.code) (not s.outOpen) (not s.errOpen))

fn ! killSlot! s: Slot reason: String timedOut: Bool -> Slot
  (do
    (if (none? s.code) (do (procKill (- 0 s.pid) "SIGKILL") (procWaitPid s.pid false)) (ok (none)))
    (if s.outOpen (fdClose s.outFd) (ok ()))
    (if s.errOpen (fdClose s.errFd) (ok ()))
    (with s :outOpen false :errOpen false :code (some (optionOr s.code -1)) :fault (some reason) :timedOut timedOut))

fn ! pollLoop! running: (List Slot) done: (List Slot) deadlineNs: Int64 -> (List Slot)
  (if (listEmpty? running)
    done
    (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
      (if (<= leftMs 0)
        (listAppend done (map (fn [(s Slot)] -> Slot (killSlot! s "timed out" true)) running))
        (let [(fds (fold (fn [(acc (List (Pair Int64 Int64))) (s Slot)] -> (List (Pair Int64 Int64))
                           (listAppend acc (listAppend (if s.outOpen (list (pair s.outFd 1)) (list)) (if s.errOpen (list (pair s.errFd 1)) (list)))))
                         (list) running))
              (pids (map (fn [(s Slot)] -> Int64 s.pid) (filter (fn [(s Slot)] -> Bool (none? s.code)) running)))]
          (mt (procPoll fds pids leftMs)
            ((err e) (listAppend done (map (fn [(s Slot)] -> Slot (killSlot! s (str "procPoll: " e) false)) running)))
            ((ok rd)
              (let [(slots (map (fn [(s Slot)] -> Slot (absorb! s (pairFirst rd) (pairSecond rd))) running))
                    (faulted (filter (fn [(s Slot)] -> Bool (some? s.fault)) slots))
                    (fine (filter (fn [(s Slot)] -> Bool (none? s.fault)) slots))
                    (killed (map (fn [(s Slot)] -> Slot (killSlot! s (optionOr s.fault "") false)) faulted))]
                (pollLoop! (filter (fn [(s Slot)] -> Bool (not (slotDone? s))) fine) (listAppend done (listAppend killed (filter slotDone? fine))) deadlineNs))))))))

fn charsetNameOk cs: String -> Bool
  (let [(bs (stringToBytes cs)) (n (bytesLength bs))]
    (and (> n 0) (<= n 64) (not (= (bytesGet bs 0) 45))
         (allBytes bs 0 n (fn [(b Int64)] -> Bool (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90)) (and (>= b 48) (<= b 57)) (= b 46) (= b 95) (= b 58) (= b 45))))))

fn ! runTool! argv: (List String) env: (List String) ms: Int64 -> (Result (Pair Int64 String) String)
  (mt (procSpawnv argv (none) (some env))
    ((err e) (err (str "ERR_TOOL_ABSENT: " (optionOr (listHead argv) "") " did not start (" e ")")))
    ((ok sp)
      (mt (fdClose sp.stdin)
        ((err e) (do (reap! sp.pid sp.stdout sp.stderr) (err (str "stdin close: " e))))
        ((ok _)
          (let [(slot (Slot :idx 0 :pid sp.pid :outFd sp.stdout :errFd sp.stderr :outOpen true :errOpen true :out (list) :errs (list) :code (none) :fault (none) :timedOut false))
                (done (pollLoop! (list slot) (list) (+ (monotonicNs) (* ms 1000000))))]
            (mt (listHead done)
              ((none) (err "tool produced no result"))
              ((some s)
                (mt s.fault
                  ((some f) (err f))
                  ((none) (ok (pair (optionOr s.code -1) (pt/treeJoin (listReverse s.out)))))))))))))

fn ! iconvDecode! raw: String cs: String env: (Map String String) -> (Result String pt/PyErr)
  (if (not (charsetNameOk cs))
    (err (pt/pyErr "LookupError" (str "unknown encoding: " cs)))
    (let [(childEnv (list (str "PATH=" (optionOr (mapGet env "PATH") "/usr/bin:/bin"))))]
      (mt (runTool! (list "iconv" "-f" cs "-t" "UTF-8" "/dev/null") childEnv 5000)
        ((err e) (err (pt/pyErr "ToolAbsent" e)))
        ((ok probe)
          (if (not (= (pairFirst probe) 0))
            (err (pt/pyErr "LookupError" (str "unknown encoding: " cs)))
            (let [(path (str "/tmp/aslIconv." (stringFromInt64 (procSelf)) "." (stringFromInt64 (monotonicNs))))]
              (mt (fileWrite path raw)
                ((err e) (err (pt/pyErr "OSError" (str "iconv input: " e))))
                ((ok _)
                  (let [(conv (runTool! (list "iconv" "-c" "-f" cs "-t" "UTF-8" path) childEnv 10000))
                        (removed (pathRemove path))]
                    (mt conv
                      ((err e) (err (pt/pyErr "ToolAbsent" e)))
                      ((ok r) (mt removed ((err e) (err (pt/pyErr "OSError" (str "iconv input cleanup: " e)))) ((ok _) (ok (pairSecond r)))))))))))))))

fn ! decodeBody! raw: String cs: String env: (Map String String) -> (Result String pt/PyErr)
  (if (pt/nativeCharset? cs) (pt/decodeCharset raw cs) (iconvDecode! raw cs env))

fn slotResult s: Slot -> HttpResult
  (let [(code (optionOr s.code -1))
        (out (pt/treeJoin (listReverse s.out)))
        (errText (pt/pyStrip (pt/treeJoin (listReverse s.errs))))]
    (cond
      (s.timedOut (httpFail (pt/pyErr "URLError" "<urlopen error timed out>") true))
      ((some? s.fault) (httpFail (pt/pyErr "URLError" (str "<urlopen error curl " (optionOr s.fault "") ">")) false))
      ((= code 28) (httpFail (pt/pyErr "URLError" "<urlopen error timed out>") true))
      ((not (= code 0)) (httpFail (pt/pyErr "URLError" (str "<urlopen error " (if (stringEmpty? errText) (str "curl exit " (stringFromInt64 code)) errText) ">")) false))
      (else (mt (parseCurlOutput out) ((ok r) r) ((err e) (httpFail (pt/pyErr "RemoteDisconnected" e) false))))))

fn timeoutMs r: HttpReq -> Int64
  (mt r.timeout
    ((j/jint i) (* i 1000))
    ((j/jfloat f) (mt (float64ToInt64 (* f 1000.0)) ((some i) i) ((none) 60000)))
    (_ 60000))

fn ! runCurlBatch! reqs: (List HttpReq) env: (List String) -> (List HttpResult)
  (let [(started (map (fn [(p (Pair Int64 HttpReq))] -> (Result Slot HttpResult) (spawnCurl! (pairFirst p) (pairSecond p) env)) (enumerate reqs)))
        (slots (fold (fn [(acc (List Slot)) (r (Result Slot HttpResult))] -> (List Slot) (mt r ((ok s) (listAppend acc (list s))) ((err _) acc))) (list) started))
        (guardMs (+ 15000 (fold (fn [(acc Int64) (r HttpReq)] -> Int64 (max acc (timeoutMs r))) 0 reqs)))
        (finished (pollLoop! slots (list) (+ (monotonicNs) (* guardMs 1000000))))]
    (map (fn [(p (Pair Int64 (Result Slot HttpResult)))] -> HttpResult
           (mt (pairSecond p)
             ((err failed) failed)
             ((ok _) (mt (listHead (filter (fn [(s Slot)] -> Bool (= s.idx (pairFirst p))) finished))
                       ((some s) (slotResult s))
                       ((none) (httpFail (pt/pyErr "URLError" "<urlopen error curl slot lost>") false))))))
         (enumerate started)))

fn httpError code: Int64 reason: String -> pt/PyErr
  (pt/pyErr "HTTPError" (str "HTTP Error " (stringFromInt64 code) ": " reason))

fn contentCharset hs: (List (Pair String String)) -> (Option String)
  (mt (listHead (filter (fn [(h (Pair String String))] -> Bool (= (pt/asciiLower (pairFirst h)) "content-type")) hs))
    ((none) (none))
    ((some h)
      (fold (fn [(acc (Option String)) (param String)] -> (Option String)
              (let [(kv (pt/partition (stringTrim param) "="))]
                (if (and (none? acc) (= (pt/asciiLower (stringTrim (pairFirst kv))) "charset") (some? (pairSecond kv)))
                  (let [(v (stringTrim (optionOr (pairSecond kv) "")))
                        (unq (if (and (>= (stringLength v) 2) (stringStartsWith? v "\"") (stringEndsWith? v "\"")) (pt/sliceB v 1 (- (stringLength v) 1)) v))]
                    (some (pt/asciiLower unq)))
                  acc)))
            (none) (optionOr (listTail (stringSplit (pairSecond h) ";")) (list)))))

fn jsonBody r: HttpResult -> (Result j/Json pt/PyErr)
  (mt r
    ((httpFail e _) (err e))
    ((httpResp code reason _ body)
      (if (not (httpOk? code))
        (err (httpError code reason))
        (mt (pt/strictUtf8 body) ((err e) (err e)) ((ok text) (pt/jsonLoads text))))))

fn jobj3 a: String av: j/Json b: String bv: j/Json c: String cv: j/Json -> j/Json
  (j/jobj (list (pair a av) (pair b bv) (pair c cv)))

fn engineError e: pt/PyErr -> j/Json
  (j/jobj (list (pair "error" (j/jstr (pt/pyErrText e)))))

fn resultItem title: j/Json url: j/Json snippet: j/Json engine: String score: j/Json -> j/Json
  (j/jobj (list (pair "title" title) (pair "url" url) (pair "snippet" snippet) (pair "engine" (j/jstr engine)) (pair "score" score)))

fn respJson answer: j/Json results: (List j/Json) -> j/Json
  (j/jobj (list (pair "answer" answer) (pair "results" (j/jarr results))))

fn orErr r: (Result j/Json pt/PyErr) -> j/Json
  (mt r ((ok v) v) ((err e) (engineError e)))

fn collect items: (List j/Json) f: (fn [j/Json] -> (Result (Option j/Json) pt/PyErr)) acc: (List j/Json) -> (Result (List j/Json) pt/PyErr)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some it)
      (mt (f it)
        ((err e) (err e))
        ((ok o) (collect (optionOr (listTail items) (list)) f (mt o ((some v) (cons v acc)) ((none) acc)))))))

fn tavilyReq query: String limit: Int64 key: String -> HttpReq
  (HttpReq :url "https://api.tavily.com/search"
           :headers (list (pair "Content-Type" "application/json") (pair "Authorization" (str "Bearer " key)) (pair "User-Agent" "ASL-Gateway/1.0"))
           :data (some (pt/jsonDumps (jobj3 "query" (j/jstr query) "max_results" (j/jint limit) "include_answer" (j/jbool true)) -1))
           :timeout (j/jint 10))

fn lessThanQuarter sc: j/Json -> (Result Bool pt/PyErr)
  (mt sc
    ((j/jint i) (ok (< (int64ToFloat64 i) 0.25)))
    ((j/jfloat f) (ok (< f 0.25)))
    ((j/jnum f) (ok (< f 0.25)))
    ((j/jbool b) (ok (and (not b) true)))
    (_ (err (pt/pyErr "TypeError" (str "'<' not supported between instances of '" (pt/pyTypeName sc) "' and 'float'")))))

fn tavilyParse r: HttpResult -> j/Json
  (orErr
    (mt (jsonBody r)
      ((err e) (err e))
      ((ok data)
        (mt (pt/jgetOr data "answer" (j/jstr ""))
          ((err e) (err e))
          ((ok answer)
            (mt (pt/jgetOr data "results" (j/jarr (list)))
              ((err e) (err e))
              ((ok rs)
                (mt (pt/pyIter rs)
                  ((err e) (err e))
                  ((ok items)
                    (mt (collect items
                          (fn [(it j/Json)] -> (Result (Option j/Json) pt/PyErr)
                            (mt (pt/jgetOr it "score" (j/jfloat 0.9))
                              ((err e) (err e))
                              ((ok sc)
                                (mt (lessThanQuarter sc)
                                  ((err e) (err e))
                                  ((ok low) (if low (ok (none)) (ok (some (resultItem (optionOr (pt/jget it "title") (j/jstr "")) (pt/cleanUrl (optionOr (pt/jget it "url") (j/jstr "")))
                                                                  (optionOr (pt/jget it "content") (j/jstr "")) "tavily" sc)))))))))
                          (list))
                      ((err e) (err e))
                      ((ok results) (ok (respJson answer results)))))))))))))

fn envGetNonEmpty st: HubState k: String -> String
  (optionOr (mapGet st.env k) "")

fn ! runOne! st: HubState r: HttpReq -> HttpResult
  (optionOr (listHead (runCurlBatch! (list r) (curlChildEnv st.env))) (httpFail (pt/pyErr "URLError" "<urlopen error no result>") false))

fn ! doTavilySearch! st: HubState query: String limit: Int64 apiKey: (Option String) -> j/Json
  (let [(key (mt apiKey ((some k) (if (stringEmpty? k) (envGetNonEmpty st "TAVILY_API_KEY") k)) ((none) (envGetNonEmpty st "TAVILY_API_KEY"))))]
    (if (stringEmpty? key) (j/jnull) (tavilyParse (runOne! st (tavilyReq query limit key)))))

fn serperReq query: String limit: Int64 key: String -> HttpReq
  (HttpReq :url "https://google.serper.dev/search"
           :headers (list (pair "Content-Type" "application/json") (pair "X-API-KEY" key) (pair "User-Agent" "ASL-Gateway/1.0"))
           :data (some (pt/jsonDumps (j/jobj (list (pair "q" (j/jstr query)) (pair "num" (j/jint limit)))) -1))
           :timeout (j/jint 10))

fn serperParse r: HttpResult -> j/Json
  (orErr
    (mt (jsonBody r)
      ((err e) (err e))
      ((ok data)
        (mt (pt/jgetOr data "organic" (j/jarr (list)))
          ((err e) (err e))
          ((ok rs)
            (mt (pt/pyIter rs)
              ((err e) (err e))
              ((ok items)
                (mt (collect items
                      (fn [(it j/Json)] -> (Result (Option j/Json) pt/PyErr)
                        (mt (pt/jgetOr it "title" (j/jstr ""))
                          ((err e) (err e))
                          ((ok title) (ok (some (resultItem title (pt/cleanUrl (optionOr (pt/jget it "link") (j/jstr ""))) (optionOr (pt/jget it "snippet") (j/jstr "")) "serper" (j/jfloat 0.85)))))))
                      (list))
                  ((err e) (err e))
                  ((ok results) (ok (respJson (j/jstr "") results)))))))))))

fn ! doSerperSearch! st: HubState query: String limit: Int64 apiKey: (Option String) -> j/Json
  (let [(key (mt apiKey ((some k) (if (stringEmpty? k) (envGetNonEmpty st "SERPER_API_KEY") k)) ((none) (envGetNonEmpty st "SERPER_API_KEY"))))]
    (if (stringEmpty? key) (j/jnull) (serperParse (runOne! st (serperReq query limit key)))))

fn wikiReq query: String limit: Int64 -> HttpReq
  (HttpReq :url (str "https://en.wikipedia.org/w/api.php?action=opensearch&search=" (pt/urlQuote query "/") "&limit=" (stringFromInt64 limit) "&namespace=0&format=json")
           :headers (list (pair "User-Agent" "ASL-Gateway/1.0")) :data (none) :timeout (j/jint 8))

fn wikiRows titles: j/Json urls: j/Json snippets: j/Json i: Int64 n: Int64 acc: (List j/Json) -> (Result (List j/Json) pt/PyErr)
  (if (>= i n)
    (ok (listReverse acc))
    (mt (pt/pyIndex titles i)
      ((err e) (err e))
      ((ok t)
        (mt (pt/pyIndex urls i)
          ((err e) (err e))
          ((ok u)
            (mt (pt/pyIndex snippets i)
              ((err e) (err e))
              ((ok s) (wikiRows titles urls snippets (+ i 1) n (cons (resultItem t u s "wikipedia" (j/jfloat 0.8)) acc)))))))))

fn wikiParse r: HttpResult -> j/Json
  (orErr
    (mt (jsonBody r)
      ((err e) (err e))
      ((ok data)
        (mt (pt/jlen data)
          ((err e) (err e))
          ((ok n)
            (if (< n 4)
              (ok (respJson (j/jstr "") (list)))
              (mt (pt/pyIndex data 1)
                ((err e) (err e))
                ((ok titles)
                  (mt (pt/pyIndex data 2)
                    ((err e) (err e))
                    ((ok snippets)
                      (mt (pt/pyIndex data 3)
                        ((err e) (err e))
                        ((ok urls)
                          (mt (pt/jlen titles)
                            ((err e) (err e))
                            ((ok tn) (mt (wikiRows titles urls snippets 0 tn (list)) ((err e) (err e)) ((ok rows) (ok (respJson (j/jstr "") rows))))))))))))))))))

fn ! doWikiSearch! st: HubState query: String limit: Int64 -> j/Json
  (wikiParse (runOne! st (wikiReq query limit)))

fn rstripSlash s: String -> String
  (if (stringEndsWith? s "/") (rstripSlash (pt/sliceB s 0 (- (stringLength s) 1))) s)

fn searxngReq base: String query: String -> HttpReq
  (HttpReq :url (str base "/search?q=" (pt/urlQuote query "/") "&format=json&categories=general")
           :headers (list (pair "User-Agent" "ASL-Gateway/1.0") (pair "Accept" "application/json")) :data (none) :timeout (j/jint 6))

fn searxngParse r: HttpResult limit: Int64 -> j/Json
  (orErr
    (mt (jsonBody r)
      ((err e) (err e))
      ((ok data)
        (mt (pt/jgetOr data "results" (j/jarr (list)))
          ((err e) (err e))
          ((ok rs)
            (mt (pt/pyIter rs)
              ((err e) (err e))
              ((ok items) (mt (searxRows items limit (list)) ((err e) (err e)) ((ok rows) (ok (respJson (j/jstr "") rows)))))))))))

fn searxRows items: (List j/Json) limit: Int64 acc: (List j/Json) -> (Result (List j/Json) pt/PyErr)
  (mt (listHead items)
    ((none) (ok (listReverse acc)))
    ((some it)
      (if (>= (listLength acc) limit)
        (ok (listReverse acc))
        (mt (pt/jgetOr it "title" (j/jstr ""))
          ((err e) (err e))
          ((ok title)
            (searxRows (optionOr (listTail items) (list)) limit
                       (cons (resultItem title (pt/cleanUrl (optionOr (pt/jget it "url") (j/jstr ""))) (optionOr (pt/jget it "content") (j/jstr "")) "searxng" (j/jfloat 0.95)) acc)))))))

fn ! doSearxngSearch! st: HubState query: String limit: Int64 -> (Result j/Json pt/PyErr)
  (let [(base (rstripSlash (envGetNonEmpty st "SEARXNG_URL")))]
    (if (stringEmpty? base)
      (ok (j/jnull))
      (let [(req (searxngReq base query))]
        (mt (urlTypeCheck req.url) ((err e) (err e)) ((ok _) (ok (searxngParse (runOne! st req) limit)))))))

fn ddgReq query: String -> HttpReq
  (HttpReq :url (str "https://html.duckduckgo.com/html/?q=" (pt/urlQuote query "/"))
           :headers (list (pair "User-Agent" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")
                          (pair "Accept" "text/html,application/xhtml+xml"))
           :data (none) :timeout (j/jint 8))

fn ! ddgThrottle! st: HubState -> HubState
  (let [(elapsed (- st.nowMs st.lastDdgMs))
        (st1 (if (< elapsed 1000) (hubSleep! st (- 1000 elapsed)) st))]
    (hubCopy st1 st1.nowMs st1.cache st1.nowMs))

fn allFrom bs: Bytes n: Int64 pat: Bytes m: Int64 from: Int64 upto: Int64 acc: (List Int64) -> (List Int64)
  (let [(k (pt/findFrom bs n pat m from))]
    (if (or (< k 0) (> k upto)) acc (allFrom bs n pat m (+ k 1) upto (cons k acc))))

fn byteFind bs: Bytes n: Int64 lit: String from: Int64 -> Int64
  (pt/findFrom bs n (stringToBytes lit) (stringLength lit) from)

fn gtOrEnd bs: Bytes n: Int64 from: Int64 -> Int64
  (let [(k (byteFind bs n ">" from))] (if (< k 0) n k))

fn linkTryHrefs s: String bs: Bytes n: Int64 hs: (List Int64) -> (Option (Pair (Pair String String) Int64))
  (mt (listHead hs)
    ((none) (none))
    ((some h)
      (let [(t (byteFind bs n "\"" (+ h 6)))
            (e2 (if (> t (+ h 6)) (byteFind bs n ">" (+ t 1)) -1))
            (u (if (>= e2 0) (byteFind bs n "<" (+ e2 1)) -1))]
        (if (and (> t (+ h 6)) (>= e2 0) (> u (+ e2 1)) (= (pt/sliceB s u (+ u 4)) "</a>"))
          (some (pair (pair (pt/sliceB s (+ h 6) t) (pt/sliceB s (+ e2 1) u)) (+ u 4)))
          (linkTryHrefs s bs n (optionOr (listTail hs) (list)))))))

fn linkTryClasses s: String bs: Bytes n: Int64 ps: (List Int64) -> (Option (Pair (Pair String String) Int64))
  (mt (listHead ps)
    ((none) (none))
    ((some p)
      (let [(q (+ p 7)) (r (byteFind bs n "\"" q))]
        (if (and (>= r 0) (pt/hasSubstr (pt/sliceB s q r) "result__url"))
          (let [(e1 (gtOrEnd bs n (+ r 1)))
                (hs (allFrom bs n (stringToBytes "href=\"") 6 (+ r 1) (- e1 6) (list)))]
            (mt (linkTryHrefs s bs n hs)
              ((some m) (some m))
              ((none) (linkTryClasses s bs n (optionOr (listTail ps) (list))))))
          (linkTryClasses s bs n (optionOr (listTail ps) (list)))))))

fn linksLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (let [(k (byteFind bs n "<a" i))]
    (if (< k 0)
      (listReverse acc)
      (let [(e0 (gtOrEnd bs n (+ k 2)))
            (ps (allFrom bs n (stringToBytes "class=\"") 7 (+ k 3) (- e0 7) (list)))]
        (mt (linkTryClasses s bs n ps)
          ((some m) (linksLoop s bs n (pairSecond m) (cons (pairFirst m) acc)))
          ((none) (linksLoop s bs n (+ k 1) acc))))))

fn ddgLinks html: String -> (List (Pair String String))
  (let [(bs (stringToBytes html))] (linksLoop html bs (bytesLength bs) 0 (list)))

fn snipTryClasses s: String bs: Bytes n: Int64 ps: (List Int64) -> (Option (Pair String Int64))
  (mt (listHead ps)
    ((none) (none))
    ((some p)
      (let [(q (+ p 7)) (r (byteFind bs n "\"" q))]
        (if (and (>= r 0) (pt/hasSubstr (pt/sliceB s q r) "result__snippet"))
          (let [(e1 (byteFind bs n ">" (+ r 1)))
                (v (if (>= e1 0) (byteFind bs n "</a>" (+ e1 1)) -1))]
            (if (>= v 0)
              (some (pair (pt/sliceB s (+ e1 1) v) (+ v 4)))
              (snipTryClasses s bs n (optionOr (listTail ps) (list)))))
          (snipTryClasses s bs n (optionOr (listTail ps) (list)))))))

fn snipsLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [(k (byteFind bs n "<a" i))]
    (if (< k 0)
      (listReverse acc)
      (let [(e0 (gtOrEnd bs n (+ k 2)))
            (ps (allFrom bs n (stringToBytes "class=\"") 7 (+ k 3) (- e0 7) (list)))]
        (mt (snipTryClasses s bs n ps)
          ((some m) (snipsLoop s bs n (pairSecond m) (cons (pairFirst m) acc)))
          ((none) (snipsLoop s bs n (+ k 1) acc))))))

fn ddgSnippets html: String -> (List String)
  (let [(bs (stringToBytes html))] (snipsLoop html bs (bytesLength bs) 0 (list)))

fn uddgOf link: String -> (Option String)
  (let [(bs (stringToBytes link)) (n (bytesLength bs))] (uddgFrom link bs n 0))

fn uddgFrom link: String bs: Bytes n: Int64 i: Int64 -> (Option String)
  (let [(k (byteFind bs n "uddg=" i))]
    (if (< k 0)
      (none)
      (let [(amp (byteFind bs n "&" (+ k 5))) (e (if (< amp 0) n amp))]
        (if (> e (+ k 5)) (some (pt/sliceB link (+ k 5) e)) (uddgFrom link bs n (+ k 1))))))

fn ddgParse r: HttpResult limit: Int64 -> j/Json
  (mt r
    ((httpFail e _) (engineError e))
    ((httpResp code reason _ body)
      (if (not (httpOk? code))
        (engineError (httpError code reason))
        (let [(html (pt/decodeReplace body))
              (links (ddgLinks html))
              (snips (ddgSnippets html))
              (k (min limit (listLength links)))
              (rows (map (fn [(i Int64)] -> j/Json
                           (let [(lk (optionOr (listGet links i) (pair "" "")))
                                 (raw (pairFirst lk))
                                 (actual (mt (uddgOf raw) ((some g) (pt/urlUnquote g)) ((none) raw)))
                                 (title (pt/pyStrip (pt/stripTagRegex (pairSecond lk) "")))
                                 (snippet (if (< i (listLength snips)) (pt/pyStrip (pt/stripTagRegex (optionOr (listGet snips i) "") "")) ""))]
                             (resultItem (j/jstr (if (stringEmpty? title) "Search Result" title)) (pt/cleanUrl (j/jstr actual)) (j/jstr snippet) "ddg" (j/jfloat 0.75))))
                         (range 0 (max k 0))))]
          (respJson (j/jstr "") rows)))))

fn ! doDdgSearch! st: HubState query: String limit: Int64 -> (Pair j/Json HubState)
  (let [(st1 (ddgThrottle! st))]
    (pair (ddgParse (runOne! st1 (ddgReq query)) limit) st1))

fn engErr eng: String msg: j/Json -> j/Json
  (j/jobj (list (pair "engine" (j/jstr eng)) (pair "error" msg)))

fn hashKey v: j/Json -> (Result String pt/PyErr)
  (mt v
    ((j/jstr s) (ok (str "s:" s)))
    ((j/jnull) (ok "none"))
    ((j/jarr _) (err (pt/pyErr "TypeError" "unhashable type: 'list'")))
    ((j/jobj _) (err (pt/pyErr "TypeError" "unhashable type: 'dict'")))
    (_ (ok (str "n:" (pt/jsonDumps v -1)))))

fn mergeLoop items: (List j/Json) seen: (List String) merged: (List j/Json) limit: Int64 -> (Result (Pair (List String) (List j/Json)) pt/PyErr)
  (mt (listHead items)
    ((none) (ok (pair seen merged)))
    ((some r)
      (let [(u (pt/cleanUrl (optionOr (pt/jget r "url") (j/jnull))))]
        (mt (hashKey u)
          ((err e) (err e))
          ((ok key)
            (if (and (not (listContains? seen key)) (< (listLength merged) limit))
              (mergeLoop (optionOr (listTail items) (list)) (cons key seen) (listAppend merged (list (pt/jset r "url" u))) limit)
              (mergeLoop (optionOr (listTail items) (list)) seen merged limit)))))))

fn ! parallelTier1Search! st: HubState query: String limit: Int64 -> (Pair (Result j/Json pt/PyErr) HubState)
  (let [(tav (envGetNonEmpty st "TAVILY_API_KEY"))
        (ser (envGetNonEmpty st "SERPER_API_KEY"))
        (mid (cond ((not (stringEmpty? tav)) (some (pair "tavily" (tavilyReq query limit tav)))) ((not (stringEmpty? ser)) (some (pair "serper" (serperReq query limit ser)))) (else (none))))
        (st1 (ddgThrottle! st))
        (engines (listAppend (list (pair "wiki" (wikiReq query limit))) (listAppend (mt mid ((some m) (list m)) ((none) (list))) (list (pair "ddg" (ddgReq query))))))
        (outs (runCurlBatch! (map (fn [(e (Pair String HttpReq))] -> HttpReq (pairSecond e)) engines) (curlChildEnv st1.env)))
        (datas (map (fn [(p (Pair (Pair String HttpReq) HttpResult))] -> (Pair String j/Json)
                      (let [(name (pairFirst (pairFirst p))) (r (pairSecond p))]
                        (pair name (cond ((= name "wiki") (wikiParse r)) ((= name "tavily") (tavilyParse r)) ((= name "serper") (serperParse r)) (else (ddgParse r limit))))))
                    (zip engines outs)))
        (errors (fold (fn [(acc (List j/Json)) (p (Pair String j/Json))] -> (List j/Json)
                        (let [(d (pairSecond p))]
                          (if (and (pt/pyTruthy d) (pt/pyTruthy (optionOr (pt/jget d "error") (j/jnull))))
                            (listAppend acc (list (engErr (pairFirst p) (optionOr (pt/jget d "error") (j/jnull)))))
                            acc)))
                      (list) datas))
        (good (filter (fn [(p (Pair String j/Json))] -> Bool
                        (let [(d (pairSecond p))] (and (pt/pyTruthy d) (not (pt/pyTruthy (optionOr (pt/jget d "error") (j/jnull)))) (pt/pyTruthy (optionOr (pt/jget d "results") (j/jnull))))))
                      datas))
        (byName (fn [(name String)] -> (Option j/Json) (mt (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) name)) good)) ((some p) (some (pairSecond p))) ((none) (none)))))
        (answer (mt (byName "tavily") ((some d) (let [(a (optionOr (pt/jget d "answer") (j/jnull)))] (if (pt/pyTruthy a) a (j/jstr "")))) ((none) (j/jstr ""))))
        (ordered (fold (fn [(acc (List j/Json)) (name String)] -> (List j/Json)
                         (mt (byName name) ((some d) (listAppend acc (mt (optionOr (pt/jget d "results") (j/jarr (list))) ((j/jarr xs) xs) (_ (list))))) ((none) acc)))
                       (list) (list "wiki" "tavily" "serper" "ddg")))]
    (mt (mergeLoop ordered (list) (list) limit)
      ((err e) (pair (err e) st1))
      ((ok m) (pair (ok (j/jobj (list (pair "answer" answer) (pair "results" (j/jarr (pairSecond m))) (pair "errors" (j/jarr errors))))) st1))))

fn errorsOf v: j/Json -> (List j/Json)
  (mt (optionOr (pt/jget v "errors") (j/jarr (list))) ((j/jarr xs) xs) (_ (list)))

fn jremove v: j/Json k: String -> j/Json
  (mt v ((j/jobj kvs) (j/jobj (filter (fn [(p (Pair String j/Json))] -> Bool (not (= (pairFirst p) k))) kvs))) (_ v))

fn ! executeSearchHub! st: HubState query: String engine: String limit: Int64 -> (Pair (Result j/Json pt/PyErr) HubState)
  (if (stringEmpty? query)
    (pair (ok (respJson (j/jstr "") (list))) st)
    (let [(ckey (str engine ":" (stringFromInt64 limit) ":" (pt/pyStrip (pt/pyLower query))))
          (now st.nowMs)
          (hit (mt (mapGet st.cache ckey) ((some c) (if (< (- now (pairFirst c)) 900000) (some (pairSecond c)) (none))) ((none) (none))))]
      (mt hit
        ((some cached) (pair (ok cached) st))
        ((none)
          (let [(choice (pt/pyLower engine))
                (step (cond
                        ((= choice "searxng") (pair (mt (doSearxngSearch! st query limit) ((ok v) (ok (pair v (list)))) ((err e) (err e))) st))
                        ((= choice "tavily") (pair (ok (pair (doTavilySearch! st query limit (none)) (list))) st))
                        ((= choice "serper") (pair (ok (pair (doSerperSearch! st query limit (none)) (list))) st))
                        ((or (= choice "wikipedia") (= choice "wiki")) (pair (ok (pair (doWikiSearch! st query limit) (list))) st))
                        ((= choice "ddg") (let [(d (doDdgSearch! st query limit))] (pair (ok (pair (pairFirst d) (list))) (pairSecond d))))
                        (else (autoSearch! st query limit))))
                (st1 (pairSecond step))]
            (mt (pairFirst step)
              ((err e) (pair (err e) st1))
              ((ok sp)
                (let [(res0 (pairFirst sp)) (errs0 (pairSecond sp))
                      (resErr (and (pt/pyTruthy res0) (pt/pyTruthy (optionOr (pt/jget res0 "error") (j/jnull)))))
                      (errs1 (if resErr (listAppend errs0 (list (engErr choice (optionOr (pt/jget res0 "error") (j/jnull))))) errs0))
                      (res1 (if (or resErr (not (pt/pyTruthy res0))) (respJson (j/jstr "") (list)) res0))
                      (errs2 (fold (fn [(acc (List j/Json)) (e j/Json)] -> (List j/Json) (if (listAny? (fn [(x j/Json)] -> Bool (pt/pyEq x e)) errs1) acc (listAppend acc (list e)))) errs1 (errorsOf res1)))
                      (res2 (if (listEmpty? errs2) (jremove res1 "errors") (pt/jset res1 "errors" (j/jarr errs2))))
                      (cacheIt (or (pt/pyTruthy (optionOr (pt/jget res2 "results") (j/jnull))) (listEmpty? errs2)))
                      (st2 (if cacheIt (hubCopy st1 st1.nowMs (mapSet st1.cache ckey (pair now res2)) st1.lastDdgMs) st1))]
                  (pair (ok res2) st2)))))))))

fn ! autoSearch! st: HubState query: String limit: Int64 -> (Pair (Result (Pair j/Json (List j/Json)) pt/PyErr) HubState)
  (mt (if (stringEmpty? (envGetNonEmpty st "SEARXNG_URL")) (ok (j/jnull)) (doSearxngSearch! st query limit))
    ((err e) (pair (err e) st))
    ((ok sx)
      (let [(sxErr (and (pt/pyTruthy sx) (pt/pyTruthy (optionOr (pt/jget sx "error") (j/jnull)))))
            (errs (if sxErr (list (engErr "searxng" (optionOr (pt/jget sx "error") (j/jnull)))) (list)))]
        (if (or (not (pt/pyTruthy sx)) (not (pt/pyTruthy (optionOr (pt/jget sx "results") (j/jnull)))))
          (let [(t (parallelTier1Search! st query limit))]
            (mt (pairFirst t)
              ((err e) (pair (err e) (pairSecond t)))
              ((ok v) (pair (ok (pair v errs)) (pairSecond t)))))
          (pair (ok (pair sx errs)) st)))))

fn escapeAsnStr v: j/Json -> String
  (mt v
    ((j/jnull) "")
    (_ (repl (repl (repl (repl (repl (pt/pyStr v) "\\" "\\\\") "\"" "\\\"") "\n" " ") "\r" " ") "\t" " ")))

fn keyErr k: String -> pt/PyErr
  (pt/pyErr "KeyError" (str "'" k "'"))

fn jreq v: j/Json k: String -> (Result j/Json pt/PyErr)
  (mt v
    ((j/jobj _) (mt (pt/jget v k) ((some x) (ok x)) ((none) (err (keyErr k)))))
    ((j/jarr _) (err (pt/pyErr "TypeError" "list indices must be integers or slices, not str")))
    (_ (err (pt/pyErr "TypeError" (str "'" (pt/pyTypeName v) "' object is not subscriptable")))))

fn indexOfEq xs: (List j/Json) v: j/Json i: Int64 -> Int64
  (mt (listHead xs) ((none) -1) ((some x) (if (pt/pyEq x v) i (indexOfEq (optionOr (listTail xs) (list)) v (+ i 1)))))

fn searchItems rs: (List j/Json) sources: (List j/Json) acc: (List String) -> (Result (Pair (List String) (List j/Json)) pt/PyErr)
  (mt (listHead rs)
    ((none) (ok (pair (listReverse acc) sources)))
    ((some r)
      (mt (jreq r "url")
        ((err e) (err e))
        ((ok u)
          (let [(src1 (if (>= (indexOfEq sources u 0) 0) sources (listAppend sources (list u))))
                (sref (+ (indexOfEq src1 u 0) 1))]
            (mt (jreq r "title")
              ((err e) (err e))
              ((ok title)
                (mt (jreq r "snippet")
                  ((err e) (err e))
                  ((ok snippet)
                    (mt (jreq r "engine")
                      ((err e) (err e))
                      ((ok eng)
                        (let [(sc (optionOr (pt/jget r "score") (j/jfloat 0.85)))
                              (item (str "(:item :title \"" (escapeAsnStr title) "\" :url \"" (escapeAsnStr u) "\" :srcRef " (stringFromInt64 sref)
                                         " :snippet \"" (escapeAsnStr snippet) "\" :engine \"" (pt/pyStr eng) "\" :score " (pt/pyStr sc) ")"))]
                          (searchItems (optionOr (listTail rs) (list)) src1 (cons item acc))))))))))))))

fn formatSearchAsn res: j/Json query: String -> (Result String pt/PyErr)
  (mt (pt/jgetOr res "results" (j/jarr (list)))
    ((err e) (err e))
    ((ok rsv)
      (mt (pt/pyIter rsv)
        ((err e) (err e))
        ((ok rs)
          (mt (searchItems rs (list) (list))
            ((err e) (err e))
            ((ok is)
              (let [(itemsStr (pt/joinSep (pairFirst is) "\n    "))
                    (sourcesStr (pt/joinSep (map (fn [(s j/Json)] -> String (str "\"" (escapeAsnStr s) "\"")) (pairSecond is)) " "))
                    (ans (escapeAsnStr (optionOr (pt/jget res "answer") (j/jstr ""))))
                    (ansField (if (stringEmpty? ans) "" (str " :answer \"" ans "\"")))
                    (errsL (map (fn [(e j/Json)] -> String (str "(:engine \"" (escapeAsnStr (optionOr (pt/jget e "engine") (j/jnull))) "\" :error \"" (escapeAsnStr (optionOr (pt/jget e "error") (j/jnull))) "\")")) (errorsOf res)))
                    (errs (pt/joinSep errsL " "))
                    (errsField (if (stringEmpty? errs) "" (str "  :errors (" errs ")\n")))]
                (ok (str "(:searchResults\n  :query \"" (escapeAsnStr (j/jstr query)) "\"\n  :total " (stringFromInt64 (listLength rs)) "\n" errsField ansField
                         "  :sources [" sourcesStr "]\n  :items [\n    " itemsStr "\n  ])")))))))))
