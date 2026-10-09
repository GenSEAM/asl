(module aslGateway/poolDispatchTest
  :x [runTests]
  :i [(asl-json/json :a j) (aslGateway/pyText :a pt)])

(schema StubSeen
  (:f path String)
  (:f model String)
  (:f batchSize Int64)
  (:f contents (List String))
  (:f atMs Int64))

(schema StubConn
  (:f fd Int64)
  (:f input String)
  (:f held Bool)
  (:f model String)
  (:f reply String))

(schema Client
  (:f fd Int64)
  (:f tag String)
  (:f sentMs Int64)
  (:f response String)
  (:f done Bool)
  (:f doneMs Int64))

(schema World
  (:f listener Int64)
  (:f gatewayPort Int64)
  (:f stubs (List StubConn))
  (:f seen (List StubSeen))
  (:f clients (List Client))
  (:f hold (List String)))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn withStubs w: World stubs: (List StubConn) seen: (List StubSeen) -> World
  (with w :stubs stubs :seen seen)

fn withClients w: World clients: (List Client) -> World
  (with w :clients clients)

fn withHold w: World hold: (List String) -> World
  (with w :hold hold)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn parseHttp raw: String -> (Option (Pair String String))
  (mt (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (want (contentLength head))
            (start (+ end 4))
            (requestLine (stringSplit (optionOr (listHead (stringSplit head "\r\n")) "") " "))]
        (if (< (- (stringLength raw) start) want) none
          (some (pair (optionOr (listGet requestLine 1) "") (optionOr (stringSlice raw start (+ start want)) "")))))))

fn field v: j/Json key: String -> j/Json
  (mt v ((j/jobj kvs) (optionOr (optionMap pairSecond (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) key)) kvs))) (j/jnull))) (_ (j/jnull)))

fn text v: j/Json -> String
  (mt v ((j/jstr s) s) (_ ""))

fn lastContent body: j/Json -> String
  (mt (field body "messages")
    ((j/jarr xs) (mt (listLast xs) ((some m) (text (field m "content"))) ((none) "")))
    (_ ""))

fn completion model: String content: String -> String
  (str "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"echo:" content
       "\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")

fn httpReply body: String -> String
  (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn observe path: String body: String nowMs: Int64 -> (Pair StubSeen String)
  (let [(parsed (mt (pt/jsonLoads body) ((ok v) v) ((err _) (j/jnull))))
        (batch (field parsed "batch"))
        (items (mt batch ((j/jarr xs) xs) (_ (list parsed))))
        (size (mt batch ((j/jarr xs) (listLength xs)) (_ 0)))
        (model (text (field (optionOr (listHead items) (j/jnull)) "model")))
        (contents (map lastContent items))
        (replies (map (fn [(it j/Json)] -> String (completion (text (field it "model")) (lastContent it))) items))
        (reply (cond
                 ((stringStartsWith? path "/v1/scale-down") "{}")
                 ((> size 0) (str "{\"batch\":[" (stringJoin replies ",") "]}"))
                 (else (optionOr (listHead replies) "{}"))))]
    (pair (StubSeen :path path :model model :batchSize size :contents contents :atMs nowMs) (httpReply reply)))

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (mt (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ! stepStub! w: World conn: StubConn ready: (List (Pair Int64 Int64)) -> World
  (if (or conn.held (not (ready? ready conn.fd))) (withStubs w (listAppend w.stubs (list conn)) w.seen)
    (mt (fdRead conn.fd 65536)
      ((err _) (do (fdClose conn.fd) w))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose conn.fd) w)
          (let [(input (str conn.input chunk))]
            (mt (parseHttp input)
              ((none) (withStubs w (listAppend w.stubs (list (with conn :input input :held false :model "" :reply ""))) w.seen))
              ((some request)
                (let [(o (observe (pairFirst request) (pairSecond request) (nowMs!)))
                      (seen (listAppend w.seen (list (pairFirst o))))
                      (model (pairFirst o).model)]
                  (if (listContains? w.hold model)
                    (withStubs w (listAppend w.stubs (list (with conn :input input :held true :model model :reply (pairSecond o)))) seen)
                    (do (writeAll! conn.fd (pairSecond o)) (fdClose conn.fd) (withStubs w w.stubs seen)))))))))))

fn ! stepClient! c: Client ready: (List (Pair Int64 Int64)) -> Client
  (if (or c.done (not (ready? ready c.fd))) c
    (mt (fdRead c.fd 65536)
      ((err _) (do (fdClose c.fd) (with c :done true :doneMs (nowMs!))))
      ((ok chunk)
        (if (stringEmpty? chunk)
          (do (fdClose c.fd) (with c :done true :doneMs (nowMs!)))
          (with c :response (str c.response chunk) :done false :doneMs 0)))))

fn ! stepWorld! w: World ready: (List (Pair Int64 Int64)) -> World
  (let [(accepted (if (ready? ready w.listener)
                    (mt (sockAccept w.listener)
                      ((ok fd) (withStubs w (listAppend w.stubs (list (StubConn :fd fd :input "" :held false :model "" :reply ""))) w.seen))
                      ((err _) w))
                    w))
        (stubbed (fold (fn [(acc World) (conn StubConn)] -> World (stepStub! acc conn ready)) (withStubs accepted (list) accepted.seen) accepted.stubs))]
    (withClients stubbed (map (fn [(c Client)] -> Client (stepClient! c ready)) stubbed.clients)))

fn watchOf w: World -> (List (Pair Int64 Int64))
  (listAppend (list (pair w.listener 1))
    (listAppend (map (fn [(s StubConn)] -> (Pair Int64 Int64) (pair s.fd 1)) (filter (fn [(s StubConn)] -> Bool (not s.held)) w.stubs))
      (map (fn [(c Client)] -> (Pair Int64 Int64) (pair c.fd 1)) (filter (fn [(c Client)] -> Bool (not c.done)) w.clients))))

fn ! pump! w: World until: (fn [World] -> Bool) deadline: Int64 -> World
  (if (or (until w) (>= (nowMs!) deadline)) w
    (mt (fdPoll (watchOf w) 20)
      ((err _) (pump! w until deadline))
      ((ok ready) (pump! (stepWorld! w ready) until deadline))))

fn ! pumpFor! w: World ms: Int64 -> World
  (pump! w (fn [(x World)] -> Bool false) (+ (nowMs!) ms))

fn ! release! w: World model: String -> World
  (let [(held (filter (fn [(s StubConn)] -> Bool (and s.held (= s.model model))) w.stubs))
        (kept (filter (fn [(s StubConn)] -> Bool (not (and s.held (= s.model model)))) w.stubs))]
    (do
      (map (fn [(s StubConn)] -> Bool (do (writeAll! s.fd s.reply) (fdClose s.fd) true)) held)
      (withHold (withStubs w kept w.seen) (filter (fn [(m String)] -> Bool (!= m model)) w.hold))))

fn ! send! w: World model: String tag: String -> World
  (let [(body (str "{\"model\":\"" model "\",\"messages\":[{\"role\":\"user\",\"content\":\"" tag "\"}]}"))
        (request (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: "
                      (stringFromInt64 (stringLength body)) "\r\n\r\n" body))]
    (mt (tcpConnect w.gatewayPort)
      ((err _) (withClients w (listAppend w.clients (list (Client :fd -1 :tag tag :sentMs (nowMs!) :response "connect failed" :done true :doneMs (nowMs!))))))
      ((ok fd)
        (do (writeAll! fd request)
          (withClients w (listAppend w.clients (list (Client :fd fd :tag tag :sentMs (nowMs!) :response "" :done false :doneMs 0))))))))

fn clientsDone? w: World tags: (List String) -> Bool
  (listAll? (fn [(t String)] -> Bool (listAny? (fn [(c Client)] -> Bool (and (= c.tag t) c.done)) w.clients)) tags)

fn clientOf w: World tag: String -> Client
  (optionOr (listHead (filter (fn [(c Client)] -> Bool (= c.tag tag)) w.clients))
    (Client :fd -1 :tag tag :sentMs 0 :response "" :done false :doneMs 0))

fn answered? w: World tag: String -> Bool
  (let [(c (clientOf w tag))]
    (and c.done (and (stringStartsWith? c.response "HTTP/1.1 200")
      (and (stringContains? c.response (str "echo:" tag)) (stringContains? c.response "\"asl\": {\"alias\": ")))))

fn seenFor w: World model: String -> (List StubSeen)
  (filter (fn [(s StubSeen)] -> Bool (= s.model model)) w.seen)

fn scaleDowns w: World -> (List StubSeen)
  (filter (fn [(s StubSeen)] -> Bool (stringStartsWith? s.path "/v1/scale-down")) w.seen)

fn heldCount w: World model: String -> Int64
  (listLength (filter (fn [(s StubConn)] -> Bool (and s.held (= s.model model))) w.stubs))

fn sizes seen: (List StubSeen) -> (List Int64)
  (map (fn [(s StubSeen)] -> Int64 s.batchSize) seen)

fn provider id: String base: String pool: String -> String
  (str "(:provider :id " id " :kind openai :base \"" base "\"" (if (stringEmpty? pool) "" (str " :pool " pool)) ")")

fn modelRow id: String prov: String name: String -> String
  (str "(:model :id " id " :provider " prov " :name \"" name "\")")

fn gatewayConfig base: String -> String
  (str "(:gateway :v 2 :providers ("
       (provider "poolBatch" base "(:windowMs 400 :peakCount 10 :bypassWhileBusy false :requestTimeoutMs 8000 :batch true)") " "
       (provider "poolPeak" base "(:windowMs 60000 :peakCount 2 :bypassWhileBusy false :requestTimeoutMs 30000 :batch true)") " "
       (provider "poolBypass" base "(:windowMs 300 :peakCount 3 :bypassWhileBusy true :requestTimeoutMs 30000 :batch true :scaleDownPath \"/scale-down\")") " "
       (provider "poolQueue" base "(:windowMs 1500 :peakCount 3 :bypassWhileBusy false :requestTimeoutMs 30000 :batch true)") " "
       (provider "poolTimeout" base "(:windowMs 50 :peakCount 1 :bypassWhileBusy false :requestTimeoutMs 300)") " "
       (provider "direct" base "") ") :models ("
       (modelRow "mBatch" "poolBatch" "batch-target") " " (modelRow "mPeak" "poolPeak" "peak-target") " "
       (modelRow "mBypass" "poolBypass" "bypass-target") " " (modelRow "mQueue" "poolQueue" "queue-target") " "
       (modelRow "mTimeout" "poolTimeout" "timeout-target") " " (modelRow "mDirect" "direct" "direct-target")
       ") :profiles ((:profile :id default :routes ((:intent any :chain (mDirect))))) :uses ((:use :for default :profile default)))\n")

fn ! waitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (mt (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none)
      ((some port) (if (> port 0) port (do (sleepMs 20) (waitPort! path (- attempts 1)))))
      ((none) (do (sleepMs 20) (waitPort! path (- attempts 1))))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (processRun "/usr/bin/mktemp -d /tmp/poolDispatchTest.XXXXXX").stdout))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort) "/v1"))
        (wrote (and (ok? (dirCreate (str temp "/.asl")))
                 (ok? (fileWrite (str temp "/.asl/gateway.asn") (gatewayConfig base)))))
        (host (resultOr (procExePath) ""))
        (server (resultOr (realPath "asl/packages/asl-gateway/src/server.asl") ""))
        (readyPath (str temp "/ready"))
        (command (str "exec " host " run " server " serve --port 0 --upstream " base " --ready " readyPath " 2>" temp "/gateway.err"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
                   (str "ASL_CALIBRATION_INDEX=" temp "/absent.asn")))
        (spawned (procSpawnv (list "/bin/sh" "-c" command) (none) (some env)))
        (pid (mt spawned ((ok sp) sp.pid) ((err _) 0)))
        (gatewayPort (if (> pid 0) (waitPort! readyPath 500) 0))
        (w0 (World :listener listener :gatewayPort gatewayPort :stubs (list) :seen (list) :clients (list) :hold (list "bypass-target" "queue-target" "timeout-target")))

        (w1 (pump! (send! (send! (send! w0 "mBatch" "b1") "mBatch" "b2") "mBatch" "b3")
              (fn [(x World)] -> Bool (clientsDone? x (list "b1" "b2" "b3"))) (+ (nowMs!) 10000)))
        (batchSeen (seenFor w1 "batch-target"))

        (peakStart (nowMs!))
        (w2 (pump! (send! (send! w1 "mPeak" "p1") "mPeak" "p2")
              (fn [(x World)] -> Bool (clientsDone? x (list "p1" "p2"))) (+ (nowMs!) 10000)))
        (peakSeen (seenFor w2 "peak-target"))
        (peakMs (- (clientOf w2 "p2").doneMs peakStart))

        (w3a (pump! (send! (send! (send! w2 "mBypass" "y1") "mBypass" "y2") "mBypass" "y3")
               (fn [(x World)] -> Bool (>= (listLength (seenFor x "bypass-target")) 1)) (+ (nowMs!) 5000)))
        (w3b (pump! (send! w3a "mBypass" "y4")
               (fn [(x World)] -> Bool (>= (listLength (seenFor x "bypass-target")) 2)) (+ (nowMs!) 3000)))
        (bypassHeld (heldCount w3b "bypass-target"))
        (bypassSeen (seenFor w3b "bypass-target"))
        (scaleBefore (listLength (scaleDowns w3b)))
        (w3c (pump! (release! w3b "bypass-target")
               (fn [(x World)] -> Bool (and (clientsDone? x (list "y1" "y2" "y3" "y4")) (>= (listLength (scaleDowns x)) 1))) (+ (nowMs!) 10000)))
        (w3d (pumpFor! w3c 600))
        (scaleSeen (scaleDowns w3d))
        (lastBypassDone (fold (fn [(acc Int64) (t String)] -> Int64 (max acc (clientOf w3d t).doneMs)) 0 (list "y1" "y2" "y3" "y4")))

        (w4a (pump! (send! (send! (send! w3d "mQueue" "q1") "mQueue" "q2") "mQueue" "q3")
               (fn [(x World)] -> Bool (>= (listLength (seenFor x "queue-target")) 1)) (+ (nowMs!) 5000)))
        (w4b (pumpFor! (send! w4a "mQueue" "q4") 500))
        (queueSeenBusy (seenFor w4b "queue-target"))
        (w4c (pump! (release! w4b "queue-target")
               (fn [(x World)] -> Bool (clientsDone? x (list "q1" "q2" "q3" "q4"))) (+ (nowMs!) 10000)))
        (queueSeen (seenFor w4c "queue-target"))

        (w5a (pump! (send! w4c "mTimeout" "t1") (fn [(x World)] -> Bool (clientsDone? x (list "t1"))) (+ (nowMs!) 5000)))
        (timeoutClient (clientOf w5a "t1"))
        (timeoutMs (- timeoutClient.doneMs timeoutClient.sentMs))
        (w5b (pumpFor! (release! w5a "timeout-target") 400))

        (w6 (pump! (send! (send! (send! w5b "mDirect" "d1") "mDirect" "d2") "mDirect" "d3")
              (fn [(x World)] -> Bool (clientsDone? x (list "d1" "d2" "d3"))) (+ (nowMs!) 10000)))
        (directSeen (seenFor w6 "direct-target"))
        (wEnd (pumpFor! w6 200))

        (killed (if (> pid 0) (do (procKill (- 0 pid) "SIGTERM") (procWaitPid pid false) true) false))
        (closed (do (map (fn [(s StubConn)] -> Bool (do (fdClose s.fd) true)) wEnd.stubs)
                  (map (fn [(c Client)] -> Bool (if c.done true (do (fdClose c.fd) true))) wEnd.clients)
                  (fdClose listener) true))
        (gatewayErr (resultOr (fileReadString (str temp "/gateway.err")) ""))
        (removed (= (processRun (str "/bin/rm -rf " temp)).exitCode 0))]
    (do
      (assert (and (and wrote (> gatewayPort 0)) (= (sizes batchSeen) (list 3)))
        (str "case 1: three requests inside the window reach the stub as one batch of three, saw " (sizes batchSeen) " " gatewayErr))
      (assert (and (answered? w1 "b1") (and (answered? w1 "b2") (answered? w1 "b3"))) "case 1: each client gets its own completion from the batched reply")
      (assert (= (sizes peakSeen) (list 2)) (str "case 2: peakCount 2 dispatches one batch of two, saw " (sizes peakSeen)))
      (assert (and (answered? w2 "p1") (and (answered? w2 "p2") (< peakMs 10000))) (str "case 2: both replies arrive long before the 60 s window, after " peakMs " ms"))
      (assert (= (sizes bypassSeen) (list 3 1)) (str "case 3: bypassWhileBusy sends the fourth request while the batch of three is in flight, saw " (sizes bypassSeen)))
      (assert (and (= bypassHeld 2) (= scaleBefore 0)) "case 3: the batch of three was still held upstream, with no scale-down yet, when the bypass request arrived")
      (assert (listAll? (fn [(t String)] -> Bool (answered? w3d t)) (list "y1" "y2" "y3" "y4")) "case 3: all bypass clients are answered after release")
      (assert (= (sizes queueSeenBusy) (list 3)) (str "case 3: with bypass off the fourth request stays queued while the batch is busy, saw " (sizes queueSeenBusy)))
      (assert (= (sizes queueSeen) (list 3 1)) (str "case 3: the queued request leaves on its window after the batch, saw " (sizes queueSeen)))
      (assert (listAll? (fn [(t String)] -> Bool (answered? w4c t)) (list "q1" "q2" "q3" "q4")) "case 3: all queued clients are answered")
      (assert (= (listLength scaleSeen) 1) (str "case 4: the scale-down hook is called exactly once, saw " (listLength scaleSeen)))
      (assert (stringContains? (stringJoin (map (fn [(s StubSeen)] -> String (str s.path s.model)) scaleSeen) "") "/v1/scale-down")
        "case 4: the hook posts to the provider's scale-down path")
      (assert (>= (optionOr (listHead scaleSeen) (StubSeen :path "" :model "" :batchSize 0 :contents (list) :atMs -1)).atMs (- lastBypassDone 200))
        "case 4: the scale-down follows the last batch completion")
      (assert (and (stringStartsWith? timeoutClient.response "HTTP/1.1 502") (stringContains? timeoutClient.response "ERR_POOL_TIMEOUT"))
        (str "case 5: a request past requestTimeoutMs gets a typed timeout reply: " timeoutClient.response))
      (assert (and (>= timeoutMs 250) (< timeoutMs 3000)) (str "case 5: the timeout reply comes near requestTimeoutMs 300, after " timeoutMs " ms"))
      (assert (= (sizes directSeen) (list 0 0 0)) (str "case 6: a provider without :pool makes one unbatched upstream call per request, saw " (sizes directSeen)))
      (assert (and (and (answered? w6 "d1") (and (answered? w6 "d2") (answered? w6 "d3"))) (and killed (and closed removed)))
        "case 6: direct clients are answered by the gateway handler; the gateway process, sockets and temp dir are cleaned up")
      true))
