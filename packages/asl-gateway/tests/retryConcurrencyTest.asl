(module aslGateway/tests/retryConcurrencyTest
  :x [runTests]
  :i [(asl-json/json :a j) (aslGateway/pyText :a pt) (asl-tools/fleet/run :a fr)])

; (:m :tags (retry) :do "an end-to-end sanity companion to serverTest.asl's testEffSleepMsDoesNotBlockReactor, which is the actual red/green proof of non-blocking (a deterministic 5000 ms timing bound with no network or jitter involved). Since GW-FREE-RETRY-3, the stub's Retry-After: 2 header is honored (headers now flow through u/UpstreamResponse/u/httpFailure into retryAfterSecOf), so aDoneMs below has a real minimum-wait assertion instead of only the always-true ordering check; this is still kept as a live-process check that the whole retry-then-succeed path (429, backoff, retried call, success) works end to end alongside a second concurrent client, not as the sole concurrency proof")

(schema StubConn
  (:f fd Int64)
  (:f input String))

(schema Seen
  (:f model String)
  (:f atMs Int64))

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
  (:f seen (List Seen))
  (:f clients (List Client)))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn withStubs w: World stubs: (List StubConn) seen: (List Seen) -> World
  (with w :stubs stubs :seen seen)

fn withClients w: World clients: (List Client) -> World
  (with w :clients clients)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn parseHttpBody raw: String -> (Option String)
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (want (contentLength head))
            (start (+ end 4))]
        (if (< (- (stringLength raw) start) want) none
          (some (optionOr (stringSlice raw start (+ start want)) ""))))))

fn field v: j/Json key: String -> j/Json
  (match v ((j/jobj kvs) (optionOr (optionMap pairSecond (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) key)) kvs))) (j/jnull))) (_ (j/jnull)))

fn text v: j/Json -> String
  (match v ((j/jstr s) s) (_ ""))

fn modelOf body: String -> String
  (text (field (match (pt/jsonLoads body) ((ok v) v) ((err _) (j/jnull))) "model"))

fn completion model: String -> String
  (str "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"ok\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")

fn httpOk200 body: String -> String
  (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn httpRetry429 body: String retryAfterSec: Int64 -> String
  (str "HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nRetry-After: " (stringFromInt64 retryAfterSec)
       "\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn occurrencesOf seen: (List Seen) model: String -> Int64
  (listLength (filter (fn [(s Seen)] -> Bool (= s.model model)) seen))

; (:m the upstream sees the gateway config's :name field ("retry-target"/"fast-target"), not the gateway alias (mRetry/mFast); mRetry's first hit is a transient 429 with a 2 s Retry-After, its second hit, and every mFast hit, is a plain 200)
fn replyFor model: String occurrence: Int64 -> String
  (if (and (= model "retry-target") (= occurrence 1))
    (httpRetry429 "{\"error\":\"Upstream model provider is temporarily unavailable\"}" 2)
    (httpOk200 (completion model)))

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ! stepStub! w: World conn: StubConn ready: (List (Pair Int64 Int64)) -> World
  (if (not (ready? ready conn.fd)) (withStubs w (listAppend w.stubs (list conn)) w.seen)
    (match (fdRead conn.fd 65536)
      ((err _) (do (fdClose conn.fd) w))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose conn.fd) w)
          (let [(input (str conn.input chunk))]
            (match (parseHttpBody input)
              ((none) (withStubs w (listAppend w.stubs (list (with conn :input input))) w.seen))
              ((some body)
                (let [(model (modelOf body))
                      (occurrence (+ 1 (occurrencesOf w.seen model)))
                      (seen (listAppend w.seen (list (Seen :model model :atMs (nowMs!)))))]
                  (do (writeAll! conn.fd (replyFor model occurrence)) (fdClose conn.fd)
                    (withStubs w w.stubs seen))))))))))

fn ! stepClient! c: Client ready: (List (Pair Int64 Int64)) -> Client
  (if (or c.done (not (ready? ready c.fd))) c
    (match (fdRead c.fd 65536)
      ((err _) (do (fdClose c.fd) (with c :done true :doneMs (nowMs!))))
      ((ok chunk)
        (if (stringEmpty? chunk)
          (do (fdClose c.fd) (with c :done true :doneMs (nowMs!)))
          (with c :response (str c.response chunk) :done false :doneMs 0)))))

fn ! stepWorld! w: World ready: (List (Pair Int64 Int64)) -> World
  (let [(accepted (if (ready? ready w.listener)
                    (match (sockAccept w.listener)
                      ((ok fd) (withStubs w (listAppend w.stubs (list (StubConn :fd fd :input ""))) w.seen))
                      ((err _) w))
                    w))
        (stubbed (fold (fn [(acc World) (conn StubConn)] -> World (stepStub! acc conn ready)) (withStubs accepted (list) accepted.seen) accepted.stubs))]
    (withClients stubbed (map (fn [(c Client)] -> Client (stepClient! c ready)) stubbed.clients)))


fn watchOf w: World -> (List (Pair Int64 Int64))
  (listAppend (list (pair w.listener 1))
    (listAppend (map (fn [(s StubConn)] -> (Pair Int64 Int64) (pair s.fd 1)) w.stubs)
      (map (fn [(c Client)] -> (Pair Int64 Int64) (pair c.fd 1)) (filter (fn [(c Client)] -> Bool (not c.done)) w.clients))))

fn ! pump! w: World until: (fn [World] -> Bool) deadline: Int64 -> World
  (if (or (until w) (>= (nowMs!) deadline)) w
    (match (fdPoll (watchOf w) 20)
      ((err _) (pump! w until deadline))
      ((ok ready) (pump! (stepWorld! w ready) until deadline))))

fn ! send! w: World model: String tag: String -> World
  (let [(body (str "{\"model\":\"" model "\",\"messages\":[{\"role\":\"user\",\"content\":\"" tag "\"}]}"))
        (request (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: "
                      (stringFromInt64 (stringLength body)) "\r\n\r\n" body))]
    (match (tcpConnect w.gatewayPort)
      ((err _) (withClients w (listAppend w.clients (list (Client :fd -1 :tag tag :sentMs (nowMs!) :response "connect failed" :done true :doneMs (nowMs!))))))
      ((ok fd)
        (do (writeAll! fd request)
          (withClients w (listAppend w.clients (list (Client :fd fd :tag tag :sentMs (nowMs!) :response "" :done false :doneMs 0))))))))

fn clientOf w: World tag: String -> Client
  (optionOr (listHead (filter (fn [(c Client)] -> Bool (= c.tag tag)) w.clients))
    (Client :fd -1 :tag tag :sentMs 0 :response "" :done false :doneMs 0))

fn clientsDone? w: World tags: (List String) -> Bool
  (listAll? (fn [(t String)] -> Bool (clientOf w t).done) tags)

fn seenOnce? w: World model: String -> Bool
  (>= (occurrencesOf w.seen model) 1)

fn ! waitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (match (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none)
      ((some port) (if (> port 0) port (do (sleepMs 20) (waitPort! path (- attempts 1)))))
      ((none) (do (sleepMs 20) (waitPort! path (- attempts 1))))))

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))

fn ! nativeCliCacheEnvRow! -> String
  (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")))

fn gatewayConfig base: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id retryProv :kind openai :base \"" base "\" :timeoutSec 30"
       " :retry (:max 2 :baseMs 100 :capMs 5000)))"
       " :models ((:model :id mRetry :provider retryProv :name \"retry-target\") (:model :id mFast :provider retryProv :name \"fast-target\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mFast))))) :uses ((:use :for default :profile default)))\n")


; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "mktemp/rm -rf migrated off bare processRun to fr/shellOut too, so this file reaches zero bare child starts rather than adding a baseline row; rule spawnSafety's own frozen baseline is legacy debt for files that predate it, not a standing allowance a new file gets to claim")
fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/retryConcurrencyTest.XXXXXX" 5000) "")))
        (listener (resultOr (tcpListen 0) -1))
        (stubPort (resultOr (sockLocalPort listener) 0))
        (base (str "http://127.0.0.1:" (stringFromInt64 stubPort) "/v1"))
        (wrote (and (ok? (dirCreate (str temp "/.asl")))
                 (ok? (fileWrite (str temp "/.asl/gateway.asn") (gatewayConfig base)))))
        (host (hostExe!))
        (server (resultOr (realPath "asl/packages/asl-gateway/src/server.asl") ""))
        (readyPath (str temp "/ready"))
        ; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "both fds redirected to files at the shell level, before exec; fr/spawn's own stdout/stderr pipes (opened on the outer /bin/sh -c process, before the exec replaces its image) end up with their write end re-pointed at these files instead, so the pipes this test never drains stay empty for the gateway's whole life -- no backpressure risk")
        (command (str "exec " host " run " server " serve --port 0 --upstream " base " --ready " readyPath " 1>" temp "/gateway.out 2>" temp "/gateway.err"))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
                   (str "ASL_CALIBRATION_INDEX=" temp "/absent.asn") (nativeCliCacheEnvRow!)))
        ; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "fix NOSELFHOST-RETRYCONC: a bare procSpawnv here was an un-bounded, un-tree-tracked child start (rule spawnSafety); fr/spawn is the same asl/tools/fleet/run.asl every other fleet caller starts children through, and its killTree! below (rather than a bare negative-pid procKill) takes the whole process tree this one row of /bin/sh -c ... could have grown, not just the shell's own pid")
        (running (fr/spawn 0 (fr/job (list "/bin/sh" "-c" command) (resultOr (realPath ".") ".") env)))
        (pid (match running ((ok r) r.pid) ((err _) 0)))
        (gatewayPort (if (> pid 0) (waitPort! readyPath 500) 0))
        (w0 (World :listener listener :gatewayPort gatewayPort :stubs (list) :seen (list) :clients (list)))

        (aStart (nowMs!))
        (w1 (send! w0 "mRetry" "a1"))
        (w2 (pump! w1 (fn [(x World)] -> Bool (seenOnce? x "retry-target")) (+ (nowMs!) 3000)))

        (bStart (nowMs!))
        (w3 (pump! (send! w2 "mFast" "b1") (fn [(x World)] -> Bool (clientsDone? x (list "b1"))) (+ (nowMs!) 5000)))
        (bDoneMs (- (clientOf w3 "b1").doneMs aStart))

        (w4 (pump! w3 (fn [(x World)] -> Bool (clientsDone? x (list "a1"))) (+ aStart 15000)))
        (aDoneMs (- (clientOf w4 "a1").doneMs aStart))

        (killed (if (> pid 0) (do (fr/killTree! pid) true) false))
        (pipesClosed (match running ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (closed (do (map (fn [(s StubConn)] -> Bool (do (fdClose s.fd) true)) w4.stubs)
                  (map (fn [(c Client)] -> Bool (if c.done true (do (fdClose c.fd) true))) w4.clients)
                  (fdClose listener) true))
        (gatewayErr (resultOr (fileReadString (str temp "/gateway.err")) ""))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and wrote (> gatewayPort 0)) (str "gateway started on a scratch HOME, " gatewayErr))
      (assert (stringStartsWith? (clientOf w3 "b1").response "HTTP/1.1 200") (str "mFast answers 200 while mRetry is still backing off: " (clientOf w3 "b1").response " " gatewayErr))
      (assert (< bDoneMs 5000) (str "mFast finishes on its own, unaffected by mRetry's still-pending backoff, after " bDoneMs " ms"))
      (assert (clientsDone? w4 (list "a1")) (str "mRetry eventually gets a response after its retry: " gatewayErr))
      (assert (stringStartsWith? (clientOf w4 "a1").response "HTTP/1.1 200") (str "mRetry's retried attempt succeeds: " (clientOf w4 "a1").response))
      ; (:m since GW-FREE-RETRY-3, u/UpstreamResponse/u/httpFailure carry real headers through server.asl's failureReply into retryAfterHeaderOf, so the stub's Retry-After: 2 header is now the applied delay, not the baseMs/capMs jittered fallback; aDoneMs is asserted against that known 2000 ms floor)
      (assert (>= aDoneMs 2000) (str "mRetry's parked wait honors the stub's Retry-After: 2 header, took " aDoneMs " ms"))
      (assert (< bDoneMs aDoneMs) (str "mFast (" bDoneMs " ms) finishes strictly before mRetry (" aDoneMs " ms): mRetry always costs at least one extra upstream round trip plus its Retry-After wait, and is the real proof the reactor served mFast while mRetry was still parked, not blocked behind it"))
      (assert (and killed (and pipesClosed (and closed removed))) "the gateway process tree, its spawn pipes, sockets and temp dir are all cleaned up")
      true))
