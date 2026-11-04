(module aslAgent/tests/leonPoolHubTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/leonPool :a lp) (aslAgent/sessionPool :a sp)
      (aslAgent/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref SE3E-HUB-OVERLAP :do "Leon runs over a stand-in hub socket that holds every reply 3000 ms: 8 runs of 2 hub calls share one pool and one process, all end ok, and their pool wall is over one hold and under twice the wall of one such run alone, so the calls of different runs wait together instead of one after another")
(schema Stub
  (:f fd Int64)
  (:f input String)
  (:f replyAt Int64)
  (:f reply String))

(schema Hub
  (:f listener Int64)
  (:f stubs (List Stub))
  (:f seen Int64)
  (:f peak Int64))

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
              (withStubs h (listAppend h.stubs (list (Stub :fd s.fd :input input :replyAt (if (complete? input) (+ (nowMs!) delayMs) 0) :reply (if (complete? input) (replyFor input) "")))))))))))

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

fn ! runSet! temp: String name: String n: Int64 repoRoot: String holdMs: Int64 -> (Pair Int64 (Pair Int64 (Pair Int64 Int64)))
  (let [(sock (str temp "/" name ".sock"))
        (roots (map (fn [(i Int64)] -> String (str temp "/" name (stringFromInt64 i))) (range 0 n)))
        (prepared (listAll? (fn [(r String)] -> Bool (prepRoot! r sock)) roots))
        (spill (str temp "/" name "-spill"))
        (made (dirCreate spill))
        (listener (resultOr (unixListen sock) -1))
        (opened (openAll! (list) (sp/newPool sock 16 64 60000 spill) roots repoRoot))
        (t0 (nowMs!))
        (out (pump! (pairFirst opened) (Hub :listener listener :stubs (list) :seen 0 :peak 0) (pairSecond opened) holdMs (+ t0 240000)))
        (wall (- (nowMs!) t0))
        (book (pairSecond (pairSecond out)))
        (okRuns (listLength (filter (fn [(r String)] -> Bool (= (lp/leonExit book (stringReplace r "/" "_")) 0)) roots)))
        (closed (do (map (fn [(s Stub)] -> Bool (do (fdClose s.fd) true)) (pairFirst out).stubs) (fdClose listener) (pathRemove sock) true))]
    (pair wall (pair okRuns (pair (if prepared (pairFirst out).seen -1) (pairFirst out).peak))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonPoolHubTest.XXXXXX" 5000) "")))
        (repoRoot (resultOr (realPath ".") "."))
        (one (runSet! temp "one" 1 repoRoot 3000))
        (eight (runSet! temp "eight" 8 repoRoot 3000))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and (= (pairFirst (pairSecond one)) 1) (= (pairFirst (pairSecond eight)) 8)) (str "all runs ended ok: one " (stringFromInt64 (pairFirst (pairSecond one))) ", eight " (stringFromInt64 (pairFirst (pairSecond eight)))))
      (assert (and (= (pairFirst (pairSecond (pairSecond one))) 2) (= (pairFirst (pairSecond (pairSecond eight))) 16)) (str "the stand-in answered 2 and 16 hub calls: " (stringFromInt64 (pairFirst (pairSecond (pairSecond one)))) ", " (stringFromInt64 (pairFirst (pairSecond (pairSecond eight))))))
      (assert (> (pairFirst one) 3000) (str "one run waited at least one hold: " (stringFromInt64 (pairFirst one)) " ms"))
      (assert (and (= (pairSecond (pairSecond (pairSecond one))) 1) (>= (pairSecond (pairSecond (pairSecond eight))) 8)) (str "the stand-in held " (stringFromInt64 (pairSecond (pairSecond (pairSecond eight)))) " requests at once for 8 runs and " (stringFromInt64 (pairSecond (pairSecond (pairSecond one)))) " for one (walls " (stringFromInt64 (pairFirst eight)) " ms and " (stringFromInt64 (pairFirst one)) " ms)"))
      (assert removed "temp dir removed")
      true))
