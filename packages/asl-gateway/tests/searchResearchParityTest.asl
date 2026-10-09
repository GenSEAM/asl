(module ws/searchResearchParityTest
  :x [runTests]
  :i [(asl-json/json :a j)
      (pyText :a pt)
      (search :a srch)
      (research :a rs)])

(schema Case (:f id String) (:f kind String) (:f input j/Json) (:f out String))

(schema Verdict (:f id String) (:f fn String) (:f ok Bool) (:f ms Int64) (:f got String) (:f want String))

fn fixturePath -> String
  "asl/packages/asl-gateway/tests/searchResearchFixture.asn"

fn jstrOf v: j/Json -> String
  (mt v ((j/jstr s) s) (_ ""))

fn arg args: j/Json i: Int64 -> j/Json
  (mt args ((j/jarr xs) (optionOr (listGet xs i) (j/jnull))) (_ (j/jnull)))

fn argS args: j/Json i: Int64 -> String
  (jstrOf (arg args i))

fn argI args: j/Json i: Int64 -> Int64
  (mt (arg args i) ((j/jint k) k) (_ 0))

fn argB args: j/Json i: Int64 -> Bool
  (pt/pyTruthy (arg args i))

fn argL args: j/Json i: Int64 -> (List j/Json)
  (mt (arg args i) ((j/jarr xs) xs) (_ (list)))

fn field v: j/Json k: String -> j/Json
  (optionOr (pt/jget v k) (j/jnull))

fn valueOut v: j/Json -> j/Json
  (j/jobj (list (pair "value" v)))

fn raisesOut e: pt/PyErr -> j/Json
  (j/jobj (list (pair "raises" (j/jstr e.kind)) (pair "message" (j/jstr e.msg))))

fn resOut r: (Result j/Json pt/PyErr) -> j/Json
  (mt r ((ok v) (valueOut v)) ((err e) (raisesOut e)))

fn strsJ xs: (List String) -> j/Json
  (j/jarr (map (fn [(s String)] -> j/Json (j/jstr s)) xs))

fn upFrom ups: j/Json -> (fn [String] -> j/Json)
  (fn [(m String)] -> j/Json (optionOr (pt/jget ups m) (j/jnull)))

fn pureCase fnName: String args: j/Json ups: j/Json -> j/Json
  (cond
    ((= fnName "clean_url") (valueOut (pt/cleanUrl (arg args 0))))
    ((= fnName "classify_source_kind") (valueOut (j/jstr (rs/classifySourceKind (argS args 0)))))
    ((= fnName "extract_outermost_sexpr") (valueOut (mt (rs/extractOutermostSexpr (argS args 0)) ((some s) (j/jstr s)) ((none) (j/jnull)))))
    ((= fnName "strip_tags_and_whitespace") (valueOut (j/jstr (rs/stripTagsAndWhitespace (argS args 0)))))
    ((= fnName "html_unescape") (valueOut (j/jstr (pt/htmlUnescape (argS args 0)))))
    ((= fnName "extract_html_tables") (valueOut (rs/extractHtmlTables (argS args 0) (argI args 1) (argI args 2))))
    ((= fnName "extract_html_code_blocks") (valueOut (rs/extractHtmlCodeBlocks (argS args 0) (argI args 1))))
    ((= fnName "is_spa_shell") (valueOut (j/jbool (rs/isSpaShell (argS args 0) (argS args 1)))))
    ((= fnName "is_waf_challenge") (valueOut (j/jbool (rs/isWafChallenge (argI args 0) (argS args 1)))))
    ((= fnName "escape_asn_str") (valueOut (j/jstr (srch/escapeAsnStr (arg args 0)))))
    ((= fnName "research_relation_asn") (valueOut (j/jstr (rs/researchRelationAsn (argL args 0)))))
    ((= fnName "research_debracket") (valueOut (j/jstr (rs/researchDebracket (argS args 0)))))
    ((= fnName "research_norm") (valueOut (j/jstr (rs/researchNorm (arg args 0)))))
    ((= fnName "research_words") (valueOut (strsJ (rs/researchWords (arg args 0)))))
    ((= fnName "research_quote_found") (valueOut (j/jbool (rs/researchQuoteFound (arg args 0) (arg args 1)))))
    ((= fnName "research_relation")
      (resOut (mt (rs/asnRead (argS args 0))
                ((err e) (err e))
                ((ok forms) (mt (rs/researchRelation (optionOr (listHead forms) (j/jnull))) ((err e) (err e)) ((ok r) (ok (strsJ r))))))))
    ((= fnName "research_parse")
      (resOut (mt (rs/researchParse (arg args 0) (argB args 1)) ((err e) (err e)) ((ok p) (ok (j/jarr (list (pairFirst p) (pairSecond p))))))))
    ((= fnName "research_verify")
      (resOut (mt (rs/researchParse (arg args 0) (argB args 3))
                ((err e) (err e))
                ((ok p) (rs/researchVerify (pairFirst p) (mt (pairSecond p) ((j/jarr xs) xs) (_ (list))) (argS args 1) (argL args 2) (argB args 3))))))
    ((= fnName "research_prompt") (valueOut (j/jstr (rs/researchPrompt (argS args 0) (argS args 1) (arg args 2) (argB args 3)))))
    ((= fnName "research_audit_prompt") (resOut (mt (rs/researchAuditPrompt (argL args 0) (arg args 1)) ((ok s) (ok (j/jstr s))) ((err e) (err e)))))
    ((= fnName "research_entry_label") (resOut (mt (rs/researchEntryLabel (arg args 0)) ((ok p) (ok (j/jarr (list (pairFirst p) (pairSecond p))))) ((err e) (err e)))))
    ((= fnName "research_entry_provider") (resOut (rs/researchEntryProvider (arg args 0) (upFrom ups))))
    ((= fnName "json_dumps") (valueOut (j/jstr (pt/jsonDumps (arg args 0) (mt (arg args 1) ((j/jint k) k) (_ -1))))))
    ((= fnName "json_loads") (resOut (pt/jsonLoads (argS args 0))))
    ((= fnName "format_search_asn") (resOut (mt (srch/formatSearchAsn (arg args 0) (argS args 1)) ((ok s) (ok (j/jstr s))) ((err e) (err e)))))
    ((= fnName "format_research_asn") (resOut (mt (rs/formatResearchAsn (arg args 0) (argB args 1)) ((ok s) (ok (j/jstr s))) ((err e) (err e)))))
    (else (raisesOut (pt/pyErr "NoPort" (str "no replay for " fnName)))))

fn cliFrom cli: (List j/Json) -> (fn [String j/Json j/Json String] -> (Result j/Json pt/PyErr))
  (fn [(prov String) (model j/Json) (effort j/Json) (prompt String)] -> (Result j/Json pt/PyErr)
    (mt (listHead (filter (fn [(c j/Json)] -> Bool (and (pt/pyEq (field c "prov") (j/jstr prov)) (pt/pyEq (field c "model") model))) cli))
      ((none) (err (pt/pyErr "SystemExit" (str "case has no CLI reply for " prov " " (pt/pyStr model)))))
      ((some c) (mt (pt/jget c "raise") ((some m) (err (pt/pyErr "RuntimeError" (pt/pyStr m)))) ((none) (ok (field c "reply")))))))

fn optList v: j/Json -> (Option (List j/Json))
  (mt v ((j/jarr xs) (some xs)) (_ (none)))

fn asnWrap key: String r: (Result j/Json pt/PyErr) fmt: (fn [j/Json] -> (Result String pt/PyErr)) -> (Result j/Json pt/PyErr)
  (mt r
    ((err e) (err e))
    ((ok v) (mt (fmt v) ((err e) (err e)) ((ok s) (ok (j/jobj (list (pair key v) (pair "asn" (j/jstr s)))))))))

fn ! netCall! st: srch/HubState fnName: String args: j/Json ups: j/Json cli: (List j/Json) -> (Pair (Result j/Json pt/PyErr) srch/HubState)
  (let [(up (upFrom ups)) (disp (cliFrom cli))]
    (cond
      ((= fnName "do_tavily_search") (pair (ok (srch/doTavilySearch! st (argS args 0) (argI args 1) (mt (arg args 2) ((j/jstr k) (some k)) (_ (none))))) st))
      ((= fnName "do_serper_search") (pair (ok (srch/doSerperSearch! st (argS args 0) (argI args 1) (mt (arg args 2) ((j/jstr k) (some k)) (_ (none))))) st))
      ((= fnName "do_wiki_search") (pair (ok (srch/doWikiSearch! st (argS args 0) (argI args 1))) st))
      ((= fnName "do_searxng_search") (pair (srch/doSearxngSearch! st (argS args 0) (argI args 1)) st))
      ((= fnName "do_ddg_search") (let [(p (srch/doDdgSearch! st (argS args 0) (argI args 1)))] (pair (ok (pairFirst p)) (pairSecond p))))
      ((= fnName "parallel_tier1_search") (srch/parallelTier1Search! st (argS args 0) (argI args 1)))
      ((= fnName "execute_search_hub")
        (let [(r (srch/executeSearchHub! st (argS args 0) (argS args 1) (argI args 2)))]
          (pair (asnWrap "res" (pairFirst r) (fn [(v j/Json)] -> (Result String pt/PyErr) (srch/formatSearchAsn v (argS args 0)))) (pairSecond r))))
      ((= fnName "fetch_single_page") (pair (rs/fetchSinglePage! st (argS args 0) (arg args 1) (arg args 2)) st))
      ((= fnName "parallel_crawl_distill") (pair (rs/parallelCrawlDistill! st (argL args 0) (argI args 1) (arg args 2)) st))
      ((= fnName "research_call") (rs/researchCall! st (arg args 0) (argS args 1) up disp))
      ((= fnName "research_extract") (rs/researchExtract! st (argS args 0) (argS args 1) (arg args 2) (argL args 3) (argB args 4) up disp))
      ((= fnName "research_audit") (rs/researchAudit! st (argL args 0) (arg args 1) (argL args 2) up disp))
      ((= fnName "execute_research_hub")
        (let [(triage (argB args 4))
              (r (rs/executeResearchHub! st (argS args 0) (argS args 1) (argL args 2) (arg args 3) triage (optList (arg args 5)) up disp))]
          (pair (asnWrap "rep" (pairFirst r) (fn [(v j/Json)] -> (Result String pt/PyErr) (rs/formatResearchAsn v triage))) (pairSecond r))))
      (else (pair (err (pt/pyErr "NoPort" (str "no replay for " fnName))) st))))

fn stubScript -> String
  "#!/bin/sh\nd=$(dirname \"$0\")\ncat > \"$d/req.$$\"\nprintf '%s\\n' \"$@\" > \"$d/argv.$$\"\nenv > \"$d/env.$$\"\nurl=$(sed -n 's/^url = \"\\(.*\\)\"$/\\1/p' \"$d/req.$$\")\nn=$(grep -Fxn -e \"$url\" \"$d/urls\" | head -n 1 | cut -d: -f1)\nif [ -z \"$n\" ]; then echo \"stub: no route for $url\" >&2; exit 90; fi\nif [ -f \"$d/r$n.exit\" ]; then cat \"$d/r$n.err\" >&2; exit \"$(cat \"$d/r$n.exit\")\"; fi\ncat \"$d/r$n.head\" \"$d/r$n.body\"\n"

fn b64Val c: Int64 -> Int64
  (cond
    ((and (>= c 65) (<= c 90)) (- c 65))
    ((and (>= c 97) (<= c 122)) (- c 71))
    ((and (>= c 48) (<= c 57)) (+ c 4))
    ((= c 43) 62)
    ((= c 47) 63)
    (else -1))

fn b64Loop! src: Bytes out: Bytes g: Int64 groups: Int64 n: Int64 -> Bytes
  (if (>= g groups)
    out
    (let [(i (* g 4)) (o (* g 3))
          (a (b64Val (bytesGet src i))) (b (b64Val (bytesGet src (+ i 1))))
          (c (max 0 (b64Val (bytesGet src (+ i 2))))) (d (max 0 (b64Val (bytesGet src (+ i 3)))))]
      (do
        (bytesSet out o (+ (* a 4) (/ b 16)))
        (if (< (+ o 1) n) (bytesSet out (+ o 1) (+ (* (mod b 16) 16) (/ c 4))) ())
        (if (< (+ o 2) n) (bytesSet out (+ o 2) (+ (* (mod c 4) 64) d)) ())
        (b64Loop! src out (+ g 1) groups n))))

fn b64Decode! s: String -> Bytes
  (let [(src (stringToBytes s)) (len (bytesLength src))
        (pad (cond ((stringEndsWith? s "==") 2) ((stringEndsWith? s "=") 1) (else 0)))
        (n (- (* (/ len 4) 3) pad))]
    (b64Loop! src (bytesAlloc n) 0 (/ len 4) n))

fn ! must! r: (Result T E) what: String -> Bool
  (mt r ((ok _) true) ((err e) (do (eprintln (str "setup failed: " what)) false)))

fn routeHead r: j/Json -> String
  (pt/treeJoin (listAppend (list "HTTP/1.1 " (pt/pyStr (field r "status")) " " (pt/pyStr (field r "reason")) "\r\n")
                           (listAppend (map (fn [(h j/Json)] -> String (str (pt/pyStr (arg h 0)) ": " (pt/pyStr (arg h 1)) "\r\n")) (mt (field r "headers") ((j/jarr xs) xs) (_ (list))))
                                       (list "\r\n"))))

fn ! writeRoutes! dir: String routes: (List j/Json) -> Bool
  (let [(urls (fold (fn [(acc (List String)) (r j/Json)] -> (List String) (if (listContains? acc (jstrOf (field r "url"))) acc (listAppend acc (list (jstrOf (field r "url")))))) (list) routes))
        (last (fn [(u String)] -> j/Json (fold (fn [(acc j/Json) (r j/Json)] -> j/Json (if (= (jstrOf (field r "url")) u) r acc)) (j/jnull) routes)))
        (okUrls (must! (fileWrite (str dir "/urls") (pt/treeJoin (map (fn [(u String)] -> String (str u "\n")) urls))) "urls"))]
    (fold (fn [(acc Bool) (p (Pair Int64 String))] -> Bool
            (let [(r (last (pairSecond p))) (base (str dir "/r" (stringFromInt64 (+ (pairFirst p) 1))))]
              (and acc
                   (if (some? (pt/jget r "transport"))
                     (and (must! (fileWrite (str base ".exit") (pt/pyStr (field r "exit"))) "exit") (must! (fileWrite (str base ".err") (jstrOf (field r "transport"))) "err"))
                     (and (must! (fileWrite (str base ".head") (routeHead r)) "head")
                          (must! (mt (pt/jget r "bodyB64") ((some b) (fileWrite (str base ".body") (b64Decode! (jstrOf b)))) ((none) (fileWrite (str base ".body") (jstrOf (field r "body"))))) "body"))))))
          okUrls (enumerate urls)))

fn unq s: String -> String
  (let [(inner (if (and (>= (stringLength s) 2) (stringStartsWith? s "\"")) (pt/sliceB s 1 (- (stringLength s) 1)) s))
        (bs (stringToBytes inner))]
    (unqLoop inner bs (bytesLength bs) 0 0 (list)))

fn unqLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 acc: (List String) -> String
  (if (>= i n)
    (pt/treeJoin (listReverse (cons (pt/sliceB s seg n) acc)))
    (if (and (= (bytesGet bs i) 92) (< (+ i 1) n))
      (let [(d (bytesGet bs (+ i 1)))
            (r (cond ((= d 110) "\n") ((= d 114) "\r") ((= d 116) "\t") ((= d 118) (pt/byteStr 11)) (else (pt/byteStr d))))]
        (unqLoop s bs n (+ i 2) (+ i 2) (cons r (cons (pt/sliceB s seg i) acc))))
      (unqLoop s bs n (+ i 1) seg acc)))

fn cfgValue line: String key: String -> (Option String)
  (if (stringStartsWith? line (str key " = ")) (some (pt/sliceB line (+ (stringLength key) 3) (stringLength line))) (none))

fn configToRequest cfg: String -> String
  (let [(lines (stringSplit cfg "\n"))
        (pick (fn [(k String)] -> (List String) (fold (fn [(acc (List String)) (l String)] -> (List String) (mt (cfgValue l k) ((some v) (listAppend acc (list v))) ((none) acc))) (list) lines)))
        (url (unq (optionOr (listHead (pick "url")) "")))
        (data (mt (listHead (pick "data-raw")) ((some d) (j/jstr (unq d))) ((none) (j/jnull))))
        (timeout (mt (pt/jsonLoads (optionOr (listHead (pick "max-time")) "null")) ((ok v) v) ((err _) (j/jnull))))
        (hdrs (fold (fn [(acc (List (Pair String j/Json))) (h String)] -> (List (Pair String j/Json))
                      (let [(t (unq h))]
                        (if (or (= t "Accept:") (= t "Expect:"))
                          acc
                          (let [(p (pt/partition t ": "))]
                            (listAppend acc (list (pair (str (pt/asciiLower (pairFirst p)) "\u0000" (optionOr (pairSecond p) ""))
                                                        (j/jarr (list (j/jstr (pt/asciiLower (pairFirst p))) (j/jstr (optionOr (pairSecond p) "")))))))))))
                    (list) (pick "header")))
        (sorted (map (fn [(p (Pair String j/Json))] -> j/Json (pairSecond p)) (listSortBy (fn [(p (Pair String j/Json))] -> String (pairFirst p)) hdrs)))]
    (pt/jsonDumps (j/jobj (list (pair "data" data) (pair "headers" (j/jarr sorted)) (pair "method" (j/jstr (if (pt/pyTruthy data) "POST" (mt data ((j/jstr _) "POST") (_ "GET")))))
                                (pair "timeout" timeout) (pair "url" (j/jstr url))))
                  -1))

fn filesWith! dir: String prefix: String -> (List String)
  (mt (dirList dir)
    ((ok names) (map (fn [(nm String)] -> String (str dir "/" nm)) (filter (fn [(nm String)] -> Bool (stringStartsWith? nm prefix)) names)))
    ((err _) (list)))

fn readAll! paths: (List String) -> (List String)
  (map (fn [(p String)] -> String (mt (fileReadString p) ((ok s) s) ((err e) (str "unreadable " p)))) paths)

fn mapFromMs v: j/Json -> (Map String Int64)
  (mt v ((j/jobj kvs) (fold (fn [(m (Map String Int64)) (p (Pair String j/Json))] -> (Map String Int64) (mapSet m (pairFirst p) (mt (pairSecond p) ((j/jint k) k) (_ 0)))) (mapEmpty) kvs)) (_ (mapEmpty)))

fn sortedObj m: (Map String Int64) keep: (fn [Int64] -> Bool) -> j/Json
  (j/jobj (map (fn [(k String)] -> (Pair String j/Json) (pair k (j/jint (optionOr (mapGet m k) 0))))
               (listSort (filter (fn [(k String)] -> Bool (keep (optionOr (mapGet m k) 0))) (mapKeys m)))))

fn secretsOf input: j/Json -> (List String)
  (let [(envKeys (mt (field input "env") ((j/jobj kvs) (map (fn [(p (Pair String j/Json))] -> String (jstrOf (pairSecond p))) (filter (fn [(p (Pair String j/Json))] -> Bool (stringEndsWith? (pairFirst p) "_API_KEY")) kvs))) (_ (list))))
        (argKeys (keysIn (field input "calls")))]
    (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (listAppend envKeys argKeys)))

fn keysIn v: j/Json -> (List String)
  (mt v
    ((j/jobj kvs) (fold (fn [(acc (List String)) (p (Pair String j/Json))] -> (List String)
                          (listAppend acc (if (= (pairFirst p) "key") (list (jstrOf (pairSecond p))) (keysIn (pairSecond p)))))
                        (list) kvs))
    ((j/jarr xs) (fold (fn [(acc (List String)) (x j/Json)] -> (List String) (listAppend acc (keysIn x))) (list) xs))
    ((j/jstr s) (if (or (stringStartsWith? s "tvly-") (stringStartsWith? s "sk-") (stringStartsWith? s "serper-")) (list s) (list)))
    (_ (list)))

fn ! chmodX! path: String -> Bool
  (mt (procSpawnv (list "/bin/chmod" "755" path) (none) (some (list "PATH=/usr/bin:/bin")))
    ((err e) (do (eprintln (str "setup failed: chmod " e)) false))
    ((ok sp)
      (let [(c0 (fdClose sp.stdin))
            (w (procWaitPid sp.pid false))
            (c1 (fdClose sp.stdout))
            (c2 (fdClose sp.stderr))]
        (mt w ((ok o) (= o (some 0))) ((err _) false)))))

(schema Wire (:f argvOk Bool) (:f pathOk Bool) (:f leaked (List String)) (:f viaStdin Int64) (:f runs Int64) (:f unsafe Int64) (:f configs Int64))

fn unsafeConfig? cfg: String -> Bool
  (let [(ls (map pt/pyStrip (stringSplit cfg "\n")))]
    (or (not (listContains? ls "proto = \"=http,https\""))
        (listAny? (fn [(l String)] -> Bool (or (stringStartsWith? l "insecure") (stringStartsWith? l "-k") (stringStartsWith? l "location") (stringStartsWith? l "--location") (stringStartsWith? l "proxy-insecure"))) ls)))

fn wireOf! dir: String secrets: (List String) -> Wire
  (let [(argvs (readAll! (filesWith! dir "argv.")))
        (envs (readAll! (filesWith! dir "env.")))
        (reqs (readAll! (filesWith! dir "req.")))
        (pathLine (str "PATH=" dir ":/usr/bin:/bin"))]
    (Wire :argvOk (listAll? (fn [(a String)] -> Bool (= a "-q\n--config\n-\n")) argvs)
          :pathOk (listAll? (fn [(e String)] -> Bool (listContains? (stringSplit e "\n") pathLine)) envs)
          :leaked (filter (fn [(s String)] -> Bool (listAny? (fn [(t String)] -> Bool (pt/hasSubstr t s)) (listAppend argvs envs))) secrets)
          :viaStdin (listLength (filter (fn [(s String)] -> Bool (listAny? (fn [(t String)] -> Bool (pt/hasSubstr t s)) reqs)) secrets))
          :runs (listLength argvs)
          :unsafe (listLength (filter unsafeConfig? reqs))
          :configs (listLength reqs)))

fn envMap input: j/Json dir: String -> (Map String String)
  (let [(base (mt (field input "env") ((j/jobj kvs) (fold (fn [(m (Map String String)) (p (Pair String j/Json))] -> (Map String String) (mapSet m (pairFirst p) (jstrOf (pairSecond p)))) (mapEmpty) kvs)) (_ (mapEmpty))))]
    (mapSet base "PATH" (str dir ":/usr/bin:/bin")))

fn ! callsLoop! st: srch/HubState calls: (List j/Json) ups: j/Json cli: (List j/Json) acc: (List j/Json) -> (Pair (List j/Json) srch/HubState)
  (mt (listHead calls)
    ((none) (pair acc st))
    ((some c)
      (let [(st0 (srch/hubWithNow st (mt (field c "clockMs") ((j/jint k) k) (_ 0))))
            (n0 (listLength st0.sleeps))
            (r (netCall! st0 (jstrOf (field c "fn")) (field c "args") ups cli))
            (st1 (pairSecond r))
            (sleeps (j/jarr (map (fn [(ms Int64)] -> j/Json (j/jint ms)) (listDrop st1.sleeps n0))))
            (row (mt (pairFirst r)
                   ((ok v) (j/jobj (list (pair "value" v) (pair "sleeps" sleeps))))
                   ((err e) (j/jobj (list (pair "raises" (j/jstr e.kind)) (pair "message" (j/jstr e.msg)) (pair "sleeps" sleeps))))))]
        (callsLoop! st1 (optionOr (listTail calls) (list)) ups cli (listAppend acc (list row))))))

fn ! netCase! input: j/Json dir: String -> (Pair j/Json Wire)
  (let [(made (and (must! (dirCreate dir) "dir")
                   (must! (fileWrite (str dir "/curl") (stubScript)) "stub")
                   (chmodX! (str dir "/curl"))))
        (routesOk (writeRoutes! dir (mt (field input "routes") ((j/jarr xs) xs) (_ (list)))))
        (st0 (srch/newHubState (envMap input dir) 0 (mt (field input "lastDdgMs") ((j/jint k) k) (_ 0))
                               (mapFromMs (field input "breaker")) (mapFromMs (field input "count503"))))
        (run (callsLoop! st0 (mt (field input "calls") ((j/jarr xs) xs) (_ (list))) (field input "upstreams") (mt (field input "cli") ((j/jarr xs) xs) (_ (list))) (list)))
        (st (pairSecond run))
        (reqs (listSort (map configToRequest (readAll! (filesWith! dir "req.")))))
        (out (j/jobj (list (pair "results" (j/jarr (pairFirst run)))
                           (pair "requests" (strsJ reqs))
                           (pair "usage" (j/jarr st.usage))
                           (pair "cliCalls" (j/jarr st.cliCalls))
                           (pair "stderr" (j/jstr (pt/treeJoin st.stderr)))
                           (pair "lastDdgMs" (j/jint st.lastDdgMs))
                           (pair "breaker" (sortedObj st.breakerUntil (fn [(v Int64)] -> Bool true)))
                           (pair "count503" (sortedObj st.count503 (fn [(v Int64)] -> Bool (not (= v 0)))))
                           (pair "cacheKeys" (strsJ (listSort (mapKeys st.cache)))))))
        (wire (wireOf! dir (secretsOf input)))]
    (pair (if (and made routesOk) out (j/jobj (list (pair "setupFailed" (j/jstr dir))))) wire))

fn caseOf line: String -> (Option Case)
  (mt (rs/asnRead line)
    ((err _) (none))
    ((ok forms)
      (mt (rs/asnProps (optionOr (listHead forms) (j/jnull)) (some ":case"))
        ((err _) (none))
        ((ok p)
          (mt (pt/jsonLoads (jstrOf (field p "in")))
            ((err _) (none))
            ((ok input) (some (Case :id (jstrOf (field p "id")) :kind (jstrOf (field p "kind")) :input input :out (jstrOf (field p "out"))))))))))

(schema Run (:f verdicts (List Verdict)) (:f wires (List Wire)))

fn ! replay! cases: (List Case) base: String -> Run
  (fold (fn [(acc Run) (c Case)] -> Run
          (let [(t0 (monotonicNs))
                (fnName (if (= c.kind "pure") (jstrOf (field c.input "fn")) (jstrOf (field (arg (field c.input "calls") 0) "fn"))))
                (res (if (= c.kind "pure")
                       (pair (pureCase fnName (field c.input "args") (field c.input "upstreams")) (none))
                       (let [(r (netCase! c.input (str base "/" c.id)))] (pair (pairFirst r) (some (pairSecond r))))))
                (got (pt/jsonDumps (pairFirst res) -1))
                (v (Verdict :id c.id :fn fnName :ok (= got c.out) :ms (/ (- (monotonicNs) t0) 1000000) :got got :want c.out))]
            (do
              (if v.ok () (eprintln (str "MISMATCH " c.id " " fnName "\n got  " (pt/sliceB got 0 (min 2000 (stringLength got))) "\n want " (pt/sliceB c.out 0 (min 2000 (stringLength c.out))))))
              (Run :verdicts (listAppend acc.verdicts (list v))
                   :wires (mt (pairSecond res) ((some w) (listAppend acc.wires (list w))) ((none) acc.wires))))))
        (Run :verdicts (list) :wires (list)) cases)

fn group run: Run fnName: String -> (List Verdict)
  (filter (fn [(v Verdict)] -> Bool (= v.fn fnName)) run.verdicts)

fn groupOk run: Run fnName: String -> Bool
  (let [(vs (group run fnName))] (and (> (listLength vs) 0) (listAll? (fn [(v Verdict)] -> Bool v.ok) vs)))

fn repeatJoin piece: String k: Int64 -> String
  (pt/treeJoin (map (fn [(i Int64)] -> String piece) (range 0 k)))

fn elapsedMs! t0: Int64 -> Int64
  (/ (- (monotonicNs) t0) 1000000)

fn ! runTests -> Bool
  (let [(text (optionOr (resultToOption (fileReadString (fixturePath))) ""))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:case ")) (stringSplit text "\n")))
        (header (optionOr (listHead (stringSplit text "\n")) ""))
        (declared (mt (rs/asnRead header)
                    ((ok forms) (mt (rs/asnProps (optionOr (listHead forms) (j/jnull)) (some ":fixture")) ((ok p) (mt (rs/asnScalar (field p "caseCount")) ((j/jint k) k) (_ -1))) ((err _) -1)))
                    ((err _) -1)))
        (pin (mt (rs/asnRead header) ((ok forms) (mt (rs/asnProps (optionOr (listHead forms) (j/jnull)) (some ":fixture")) ((ok p) (jstrOf (field p "pin"))) ((err _) ""))) ((err _) "")))
        (cases (fold (fn [(acc (List Case)) (l String)] -> (List Case) (mt (caseOf l) ((some c) (listAppend acc (list c))) ((none) acc))) (list) lines))
        (base (str "/tmp/aslU9parity." (stringFromInt64 (procSelf))))
        (cleanStart (pathRemove base))
        (run (replay! cases base))
        (wires run.wires)
        (failed (map (fn [(v Verdict)] -> String v.id) (filter (fn [(v Verdict)] -> Bool (not v.ok)) run.verdicts)))
        (absentDir (str base "/noCurl"))
        (absentMade (dirCreate absentDir))
        (absentHub (srch/newHubState (mapSet (mapEmpty) "PATH" absentDir) 1000000 0 (mapEmpty) (mapEmpty)))
        (absent (srch/doWikiSearch! absentHub "x" 5))
        (bigEsc (repeatJoin "\"\\" 8000))
        (t1 (monotonicNs))
        (escaped (srch/escapeAsnStr (j/jstr bigEsc)))
        (cfg (mt (srch/curlConfig (srch/HttpReq :url "https://x/" :headers (list) :data (some bigEsc) :timeout (j/jint 5))) ((ok c) c) ((err e) e.msg)))
        (roundTrip (configToRequest cfg))
        (escMs (elapsedMs! t1))
        (litCfg (srch/curlConfig (srch/HttpReq :url "https://api.example/s?q=x" :headers (list (pair "X-Key" "v\"w\\x")) :data (some "a\"b\\c\nd") :timeout (j/jfloat 3.5))))
        (rejects (map (fn [(r srch/HttpReq)] -> String (mt (srch/curlConfig r) ((ok _) "accepted") ((err e) e.kind)))
                      (list (srch/HttpReq :url "https://x/" :headers (list (pair "@/etc/passwd" "v")) :data (none) :timeout (j/jint 5))
                            (srch/HttpReq :url "https://x/" :headers (list (pair "X Bad" "v")) :data (none) :timeout (j/jint 5))
                            (srch/HttpReq :url "https://x/" :headers (list (pair "X-K\nInjected" "v")) :data (none) :timeout (j/jint 5))
                            (srch/HttpReq :url "https://x/" :headers (list (pair "Authorization" "Bearer k\nX-Evil: 1")) :data (none) :timeout (j/jint 5))
                            (srch/HttpReq :url "https://x/" :headers (list (pair "Authorization" "Bearer k\rX-Evil: 1")) :data (none) :timeout (j/jint 5))
                            (srch/HttpReq :url "https://x/\nHost: evil" :headers (list) :data (none) :timeout (j/jint 5))
                            (srch/HttpReq :url "https://x/\r" :headers (list) :data (none) :timeout (j/jint 5)))))
        (rejectedHub (srch/newHubState (mapSet (mapSet (mapEmpty) "PATH" absentDir) "SEARXNG_URL" "http://x/\nHost: evil") 1000000 0 (mapEmpty) (mapEmpty)))
        (rejectedRun (srch/doSearxngSearch! rejectedHub "q" 3))
        (keyReject (srch/curlConfig (srch/HttpReq :url "https://x/" :headers (list (pair "X-API-KEY" "sk-KEYMARK42\nX-Evil: 1")) :data (none) :timeout (j/jint 5))))
        (keyHub (srch/newHubState (mapSet (mapSet (mapEmpty) "PATH" absentDir) "SERPER_API_KEY" "sk-KEYMARK42\r\nX-Evil: 1") 1000000 0 (mapEmpty) (mapEmpty)))
        (keyRun (pt/jsonDumps (srch/doSerperSearch! keyHub "q" 3 (none)) -1))
        (names (map srch/charsetNameOk (list "Shift_JIS" "windows-1251" "iso-8859-15" "-c" "a b" "../x" "bad$name" "" "x\ny")))
        (noIconv (srch/iconvDecode! "abc" "windows-1251" (mapSet (mapEmpty) "PATH" absentDir)))
        (bigAsn (repeatJoin "(:fact :id \"f\" :claim \"c \\\" d\" :srcRef 1)\n" 4000))
        (t2 (monotonicNs))
        (readBig (rs/asnRead bigAsn))
        (asnMs (elapsedMs! t2))
        (bigWords (repeatJoin "alpha beta gamma delta " 4000))
        (t3 (monotonicNs))
        (found (rs/researchQuoteFound (j/jstr "gamma delta alpha beta gamma delta alpha beta gamma") (j/jstr bigWords)))
        (wordsMs (elapsedMs! t3))
        (cleaned (pathRemove base))]
    (do
      (if (listEmpty? failed) () (eprintln (str "failed cases: " (pt/joinSep failed " "))))
      (assert (> declared 0) "fixture header declares a case count")
      (assert (= (listLength cases) declared) "every declared case line parses")
      (assert (= pin "02aff5d0") "fixture is pinned to the U9 base commit")
      (assert (listEmpty? failed) "every recorded case replays exactly")
      (assert (groupOk run "clean_url") "clean_url replays")
      (assert (groupOk run "classify_source_kind") "classify_source_kind replays")
      (assert (groupOk run "extract_outermost_sexpr") "extract_outermost_sexpr replays")
      (assert (groupOk run "strip_tags_and_whitespace") "strip_tags_and_whitespace replays")
      (assert (groupOk run "html_unescape") "html.unescape replays")
      (assert (groupOk run "extract_html_tables") "extract_html_tables replays")
      (assert (groupOk run "extract_html_code_blocks") "extract_html_code_blocks replays")
      (assert (groupOk run "is_spa_shell") "is_spa_shell replays")
      (assert (groupOk run "is_waf_challenge") "is_waf_challenge replays")
      (assert (groupOk run "escape_asn_str") "escape_asn_str replays")
      (assert (groupOk run "research_relation_asn") "research_relation_asn replays")
      (assert (groupOk run "research_debracket") "research_debracket replays")
      (assert (groupOk run "research_norm") "research_norm replays")
      (assert (groupOk run "research_words") "research_words replays")
      (assert (groupOk run "research_quote_found") "research_quote_found replays")
      (assert (groupOk run "research_relation") "research_relation replays")
      (assert (groupOk run "research_parse") "research_parse replays")
      (assert (groupOk run "research_verify") "research_verify replays")
      (assert (groupOk run "research_prompt") "research_prompt replays")
      (assert (groupOk run "research_audit_prompt") "research_audit_prompt replays")
      (assert (groupOk run "research_entry_label") "research_entry_label replays")
      (assert (groupOk run "research_entry_provider") "research_entry_provider replays")
      (assert (groupOk run "json_dumps") "json.dumps replays")
      (assert (groupOk run "json_loads") "json.loads replays")
      (assert (groupOk run "format_search_asn") "format_search_asn replays")
      (assert (groupOk run "format_research_asn") "format_research_asn replays")
      (assert (groupOk run "do_tavily_search") "do_tavily_search replays over the stub curl")
      (assert (groupOk run "do_serper_search") "do_serper_search replays over the stub curl")
      (assert (groupOk run "do_wiki_search") "do_wiki_search replays over the stub curl")
      (assert (groupOk run "do_searxng_search") "do_searxng_search replays over the stub curl")
      (assert (groupOk run "do_ddg_search") "do_ddg_search replays over the stub curl")
      (assert (groupOk run "parallel_tier1_search") "parallel_tier1_search replays over the stub curl")
      (assert (groupOk run "execute_search_hub") "execute_search_hub replays over the stub curl")
      (assert (groupOk run "fetch_single_page") "fetch_single_page replays over the stub curl")
      (assert (groupOk run "parallel_crawl_distill") "parallel_crawl_distill replays over the stub curl")
      (assert (groupOk run "research_call") "research_call replays over the stub curl and CLI replies")
      (assert (groupOk run "research_extract") "research_extract replays")
      (assert (groupOk run "research_audit") "research_audit replays")
      (assert (groupOk run "execute_research_hub") "execute_research_hub replays")
      (assert (> (listLength wires) 0) "net cases ran")
      (assert (listAll? (fn [(w Wire)] -> Bool w.argvOk) wires) "curl argv is exactly -q --config - in every run")
      (assert (listAll? (fn [(w Wire)] -> Bool w.pathOk) wires) "child PATH is the stub dir plus /usr/bin:/bin only")
      (assert (listAll? (fn [(w Wire)] -> Bool (listEmpty? w.leaked)) wires) "no key reaches curl argv or env")
      (assert (> (fold (fn [(acc Int64) (w Wire)] -> Int64 (+ acc w.viaStdin)) 0 wires) 0) "keys reach curl through the stdin config")
      (assert (> (fold (fn [(acc Int64) (w Wire)] -> Int64 (+ acc w.runs)) 0 wires) 100) "the stub curl ran for the net cases")
      (assert (pt/hasSubstr (pt/pyStr (optionOr (pt/jget absent "error") (j/jnull))) "ERR_TOOL_ABSENT") "a missing curl is an error, not a fallback")
      (assert (and (= (stringLength escaped) 32000) (pt/hasSubstr roundTrip (pt/jsonDumps (j/jstr bigEsc) -1))) "8000 escapes survive escape_asn_str and the curl config")
      (assert (< escMs 3000) "8000-escape string and config under 3 s")
      (assert (mt readBig ((ok fs) (= (listLength fs) 4000)) ((err _) false)) "4000-line ASN text reads to 4000 forms")
      (assert (< asnMs 3000) "4000-line ASN read under 3 s")
      (assert (and found (< wordsMs 3000)) "research_quote_found over 16000 words under 3 s")
      (assert (< (fold (fn [(acc Int64) (v Verdict)] -> Int64 (max acc v.ms)) 0 (group run "html_unescape")) 5000) "8000-reference html.unescape case under 5 s")
      (assert (< (fold (fn [(acc Int64) (v Verdict)] -> Int64 (max acc v.ms)) 0 (group run "strip_tags_and_whitespace")) 5000) "4000-line strip_tags case under 5 s")
      (assert (< (fold (fn [(acc Int64) (v Verdict)] -> Int64 (max acc v.ms)) 0 (group run "clean_url")) 5000) "4000-parameter clean_url case under 5 s")
      (assert (< (fold (fn [(acc Int64) (v Verdict)] -> Int64 (max acc v.ms)) 0 (group run "do_ddg_search")) 8000) "4000-result DDG page case under 8 s")
      (assert (mt litCfg ((ok c) (= c "url = \"https://api.example/s?q=x\"\nproto = \"=http,https\"\ngloboff\nhttp1.1\ninclude\nsilent\nshow-error\nsuppress-connect-headers\nmax-time = 3.5\nheader = \"X-Key: v\\\"w\\\\x\"\nheader = \"Accept:\"\nheader = \"Expect:\"\ndata-raw = \"a\\\"b\\\\c\\nd\"\n")) ((err _) false)) "curl config equals the literal expected lines")
      (assert (mt litCfg ((ok c) (not (unsafeConfig? c))) ((err _) false)) "config has proto =http,https and no insecure, -k or location line")
      (assert (= rejects (list "ValueError" "ValueError" "ValueError" "ValueError" "ValueError" "InvalidURL" "InvalidURL")) "bad header names, CR/LF values and control-char URLs are rejected")
      (assert (mt rejectedRun ((ok v) (pt/hasSubstr (pt/pyStr (optionOr (pt/jget v "error") (j/jnull))) "URL can't contain control characters")) ((err _) false)) "an injected SEARXNG_URL fails before curl is spawned")
      (assert (= (fold (fn [(acc Int64) (w Wire)] -> Int64 (+ acc w.unsafe)) 0 wires) 0) "no recorded config has insecure, -k, location or a missing proto line")
      (assert (> (fold (fn [(acc Int64) (w Wire)] -> Int64 (+ acc w.configs)) 0 wires) 100) "configs were recorded for the net cases")
      (assert (mt keyReject ((ok _) false) ((err e) (and (= e.kind "ValueError") (not (pt/hasSubstr e.msg "KEYMARK42"))))) "a rejected header value is not echoed in the error")
      (assert (and (pt/hasSubstr keyRun "Invalid header value") (not (pt/hasSubstr keyRun "KEYMARK42"))) "a CR/LF Serper key fails without its value in the result")
      (assert (= names (list true true true false false false false false false)) "only strict charset names reach iconv argv")
      (assert (mt noIconv ((ok _) false) ((err e) (and (= e.kind "ToolAbsent") (pt/hasSubstr e.msg "ERR_TOOL_ABSENT")))) "a missing iconv is an error")
      (assert (ok? cleaned) "stub directories removed")
      true))
