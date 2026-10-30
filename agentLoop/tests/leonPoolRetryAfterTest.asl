(module asl/agentLoop/tests/leonPoolRetryAfterTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/leonPool :a lp) (asl/agentLoop/sessionPool :a sp)
      (asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref HUB-RETRY-POOL :do "two runs share one pool over a stand-in hub whose first request is answered 429 with Retry-After 2: the 429'd run holds (Turn.holdMs from the header, no sleep in the pool thread) while the other run's two calls are answered, so the arrival order is fresh fresh blue fresh blue (a sleeping pool would post the held run's retry before the other run's second call); the hold lasts at least the Retry-After seconds")
(schema Stub
  (:f fd Int64)
  (:f input String)
  (:f replyAt Int64)
  (:f reply String))

(schema Hub
  (:f listener Int64)
  (:f stubs (List Stub))
  (:f seen Int64)
  (:f peak Int64)
  (:f arrived Int64)
  (:f log String)
  (:f firstAt Int64)
  (:f retryAt Int64)
  (:f status Int64))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 20000))

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (= (pairFirst r) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn complete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end) (>= (- (stringLength raw) (+ end 4)) (contentLength (optionOr (stringSlice raw 0 end) "")))))

fn asnQuote text: String -> String
  (stringReplace (stringReplace text "\\" "\\\\") "\"" "\\\"")

; (:m :ref SE3E-HUB-OVERLAP :do "the two scripted model replies of the edit fixture: turn 1 writes blue, turn 2 writes green and is done; the stand-in picks by whether the request already carries the first write")
fn stepOne -> String
  "(:step :op \"write\" :file \"subject.txt\" :content \"blue\\n\")"

fn stepTwo -> String
  "(:step :op \"write\" :file \"subject.txt\" :content \"green\\n\") (:done)"

fn replyFor input: String -> String
  (let [(content (asnQuote (if (stringContains? input "blue") (stepTwo) (stepOne))))
        (body (str "(:reply :content \"" content "\")"))]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/asn+sexpr\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn tooMany status: Int64 -> String
  (let [(body "{\"error\":\"ERR_RATE_LIMITED: no rate-limit token within the queue budget; retry in 2s\"}")]
    (str "HTTP/1.1 " (stringFromInt64 status) " Retry\r\nContent-Type: application/json\r\nRetry-After: 2\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn noted h: Hub input: String -> Hub
  (with h :arrived (+ h.arrived 1) :log (str h.log (if (stringContains? input "blue") "B" "F"))
         :firstAt (if (= h.arrived 0) (nowMs!) h.firstAt)
         :retryAt (if (and (= h.arrived 3) (not (stringContains? input "blue"))) (nowMs!) h.retryAt))

fn withStubs h: Hub stubs: (List Stub) -> Hub
  (with h :stubs stubs)

; (:m :ref SE3E-HUB-OVERLAP :do "requests held by the stand-in at once: the peak of complete requests still waiting for their reply; 8 runs overlapping hold 8, runs one after another hold 1, whatever the load")
fn withPeak h: Hub -> Hub
  (with h :peak (max h.peak (listLength (filter (fn [(s Stub)] -> Bool (> s.replyAt 0)) h.stubs))))

fn withSeen h: Hub seen: Int64 -> Hub
  (with h :seen seen)

fn ! stepStub! h: Hub s: Stub ready: (List (Pair Int64 Int64)) delayMs: Int64 -> Hub
  (cond
    ((> s.replyAt 0)
      (if (>= (nowMs!) s.replyAt)
        (do (fdWrite s.fd s.reply) (fdClose s.fd) (withSeen h (+ h.seen 1)))
        (withStubs h (listAppend h.stubs (list s)))))
    ((not (ready? ready s.fd)) (withStubs h (listAppend h.stubs (list s))))
    (else
      (match (fdRead s.fd 65536)
        ((err _) (do (fdClose s.fd) h))
        ((ok chunk)
          (if (stringEmpty? chunk) (do (fdClose s.fd) h)
            (let [(input (str s.input chunk))]
              (let [(done (complete? input))
                    (h2 (if done (noted h input) h))]
                (withStubs h2 (listAppend h.stubs (list (Stub :fd s.fd :input input :replyAt (if done (+ (nowMs!) delayMs) 0) :reply (if done (if (= h.arrived 0) (tooMany h.status) (replyFor input)) ""))))))))))))

fn ! stepHub! h: Hub ready: (List (Pair Int64 Int64)) delayMs: Int64 -> Hub
  (let [(accepted (if (ready? ready h.listener)
                    (match (sockAccept h.listener)
                      ((ok fd) (withStubs h (listAppend h.stubs (list (Stub :fd fd :input "" :replyAt 0 :reply "")))))
                      ((err _) h))
                    h))]
    (fold (fn [(acc Hub) (s Stub)] -> Hub (stepStub! acc s ready delayMs)) (withStubs accepted (list)) accepted.stubs))

fn hubWatch h: Hub -> (List (Pair Int64 Int64))
  (cons (pair h.listener 1) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) h.stubs))

fn envFor root: String -> pv/ProviderEnv
  (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str root "/.asl/gateway.asn")
    :tmpDir (str root "/tmp") :childEnv (mapEmpty))

fn prepRoot! root: String sock: String -> Bool
  (and (sh! (str "/bin/mkdir -p " root "/.asl " root "/tmp"))
    (and (ok? (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n"))
      (and (ok? (fileWrite (str root "/.asl/hub.asn") (str "(:hub :sock \"" sock "\" :class \"lead\")\n")))
        (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
          (sh! (str "cd " root " && git init -q -b main && git config user.name leonPool && git config user.email leon-pool@example.invalid && git add -- subject.txt && git commit -q -m initial"))))))

fn form -> String
  "(:agent :task \"write then gate\" :backend \"agy\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\") :nativeTools \"off\")"

fn ! pump! p: sp/Pool h: Hub book: (List (Pair String lp/Live)) delayMs: Int64 deadline: Int64 -> (Pair Hub (Pair sp/Pool (List (Pair String lp/Live))))
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) (pair h (pair p book))
    (match (fdPoll (listAppend (hubWatch h) (sp/poolWatch p)) 10)
      ((err _) (pump! p h book delayMs deadline))
      ((ok ready)
        (let [(stepped (sp/poolStepG! p ready lp/leonTurn! book (nowMs!)))]
          (pump! (pairFirst stepped) (withPeak (stepHub! h ready delayMs)) (pairSecond stepped) delayMs deadline)))))

fn ! openAll! book: (List (Pair String lp/Live)) p: sp/Pool roots: (List String) repoRoot: String -> (Pair sp/Pool (List (Pair String lp/Live)))
  (fold (fn [(acc (Pair sp/Pool (List (Pair String lp/Live)))) (root String)] -> (Pair sp/Pool (List (Pair String lp/Live)))
          (let [(id (stringReplace root "/" "_"))
                (opened (lp/leonOpen! (pairSecond acc) id (form) repoRoot root (envFor root)))]
            (match (pairSecond opened)
              ((some _) (pair (pairFirst acc) (pairFirst opened)))
              ((none) (pair (sp/poolSubmit! (pairFirst acc) id id (nowMs!)) (pairFirst opened))))))
    (pair p book) roots)

fn ! runSet! temp: String name: String n: Int64 repoRoot: String status: Int64 -> (Pair Hub Int64)
  (let [(sock (str temp "/" name ".sock"))
        (roots (map (fn [(i Int64)] -> String (str temp "/" name (stringFromInt64 i))) (range 0 n)))
        (prepared (listAll? (fn [(r String)] -> Bool (prepRoot! r sock)) roots))
        (spill (str temp "/" name "-spill"))
        (made (dirCreate spill))
        (listener (resultOr (unixListen sock) -1))
        (opened (openAll! (list) (sp/newPool sock 16 64 60000 spill) roots repoRoot))
        (t0 (nowMs!))
        (out (pump! (pairFirst opened) (Hub :listener listener :stubs (list) :seen 0 :peak 0 :arrived 0 :log "" :firstAt 0 :retryAt 0 :status status) (pairSecond opened) 0 (+ t0 240000)))
        (book (pairSecond (pairSecond out)))
        (okRuns (listLength (filter (fn [(r String)] -> Bool (= (lp/leonExit book (stringReplace r "/" "_")) 0)) roots)))
        (closed (do (map (fn [(s Stub)] -> Bool (do (fdClose s.fd) true)) (pairFirst out).stubs) (fdClose listener) (pathRemove sock) true))]
    (pair (pairFirst out) (if prepared okRuns -1)))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonPoolRetryAfterTest.XXXXXX" 5000) "")))
        (repoRoot (resultOr (realPath ".") "."))
        (two (runSet! temp "two" 2 repoRoot 429))
        (busy (runSet! temp "busy" 2 repoRoot 503))
        (hub (pairFirst two))
        (busyHub (pairFirst busy))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (= (pairSecond two) 2) (str "both runs ended ok: " (stringFromInt64 (pairSecond two))))
      (assert (= hub.log "FFBFB") (str "the other run's calls were answered during the hold, the held run reposted after them: " hub.log))
      (assert (>= (- hub.retryAt hub.firstAt) 2000) (str "the repost came at least Retry-After seconds after the 429 (lower bound only): " (stringFromInt64 (- hub.retryAt hub.firstAt)) " ms"))
      (assert (= (pairSecond busy) 2) (str "503: both runs ended ok: " (stringFromInt64 (pairSecond busy))))
      (assert (= busyHub.log "FFBFB") (str "503: the other run's calls were answered during the hold: " busyHub.log))
      (assert (>= (- busyHub.retryAt busyHub.firstAt) 2000) (str "503: the repost came at least Retry-After seconds later (lower bound only): " (stringFromInt64 (- busyHub.retryAt busyHub.firstAt)) " ms"))
      (assert removed "temp dir removed")
      true))
