(module aslGateway/tests/retrySessionHangTest
  :x [runTests]
  :i [(asl-json/json :a j) (aslGateway/pyText :a pt) (asl-tools/fleet/run :a fr)])

; (:m :tags (retry) :do "GW-RETRY-OCGO-HANG: reproduces the reported hang for a provider that declares :sessionHeader (OpenCode's x-opencode-session) and a :pool batch window (mirroring the real modal provider's settings, which an opencodeGo-style scratch config can inherit by copying the same template) combined with :retry. Root cause confirmed by this test before the fix: a provider's :pool window exists to amortize a serverless cold start across concurrent arrivals, so the FIRST request into an idle lane deliberately waits up to :windowMs before dispatch. A retried attempt is not a sibling arrival -- retryOrFinish already slept once, so by the time it resubmits, the lane has gone idle again (the prior batch settled and scaled down), and the retry pays the full :windowMs a second time, parked in the pool's own queue (not connTimer/connBucketWait), with nothing logged while it waits. Across :max retries this compounds past any attempt timeout with little to no gateway output, matching the reported symptom exactly. The stub also records the session header it saw on each hit, confirming that header stays stable across the retry (it does -- the header was never the bug)")

(schema StubConn
  (:f fd Int64)
  (:f input String))

(schema Seen
  (:f model String)
  (:f atMs Int64)
  (:f sessionHeader String))

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

; (:m x-opencode-session is read straight out of the raw request head, case-insensitively on the header name, exactly as curl would send whatever withSessionHeader/ensureSessionHeader put there)
fn headerValueOf raw: String name: String -> (Option String)
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) none)
    ((some end)
      (let [(head (optionOr (stringSlice raw 0 end) ""))
            (prefix (str (stringLower name) ":"))
            (hit (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? (stringLower line) prefix)) (stringSplit head "\r\n"))))]
        (optionMap (fn [(line String)] -> String (stringTrim (optionOr (stringSlice line (stringLength prefix) (stringLength line)) ""))) hit))))

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

fn httpBadRequest400 body: String -> String
  (str "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn occurrencesOf seen: (List Seen) model: String -> Int64
  (listLength (filter (fn [(s Seen)] -> Bool (= s.model model)) seen))

; (:m model's upstream :name is "retry-target"; a request arriving with no session header at all is a stub-side bug, not the gateway's -- ensureSessionHeader always supplies one -- so that branch exists only to make a dropped header visible as a 400 instead of a silent miscount; the first genuine hit is a transient 429 with a 1 s Retry-After (kept small so a correctly-working retry finishes fast), every hit after that is a plain 200)
fn replyFor model: String occurrence: Int64 sess: String -> String
  (if (stringEmpty? sess) (httpBadRequest400 "{\"error\":\"missing session header\"}")
    (if (and (= model "retry-target") (= occurrence 1))
      (httpRetry429 "{\"error\":\"Upstream model provider is temporarily unavailable\"}" 1)
      (httpOk200 (completion model))))

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
                      (sess (optionOr (headerValueOf input "x-opencode-session") ""))
                      (occurrence (+ 1 (occurrencesOf w.seen model)))
                      (seen (listAppend w.seen (list (Seen :model model :atMs (nowMs!) :sessionHeader sess))))]
                  (do (writeAll! conn.fd (replyFor model occurrence sess)) (fdClose conn.fd)
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

fn ! waitPort! path: String attempts: Int64 -> Int64
  (if (<= attempts 0) 0
    (match (optionOr (resultToOption (resultMap (fileReadString path) (fn [(t String)] -> (Option Int64) (stringToInt64 (stringTrim t))))) none)
      ((some port) (if (> port 0) port (do (sleepMs 20) (waitPort! path (- attempts 1)))))
      ((none) (do (sleepMs 20) (waitPort! path (- attempts 1))))))

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))

; (:m the two deliberate differences from retryConcurrencyTest.asl's gatewayConfig: :sessionHeader "x-opencode-session" on the provider (mirroring the real opencodeGo provider row), and a :pool block shaped exactly like the real modal provider's (just a smaller :windowMs so a correctly-working retry still finishes in a few seconds, not ~7); combined with the same shape of :retry block. config.asl's gatewayV2Entry! inherits :pool from the provider onto every model unconditionally (no per-model override exists), so this one block applies to mRetry with no further wiring needed)
fn gatewayConfig base: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id sessHdrProv :kind openai :base \"" base "\" :sessionHeader \"x-opencode-session\" :timeoutSec 30"
       " :retry (:max 2 :baseMs 100 :capMs 2000) :pool (:windowMs 2000 :peakCount 4 :bypassWhileBusy true :requestTimeoutMs 30000)))"
       " :models ((:model :id mRetry :provider sessHdrProv :name \"retry-target\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (mRetry))))) :uses ((:use :for default :profile default)))\n")

; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "mktemp/rm -rf migrated off bare processRun to fr/shellOut too, so this file reaches zero bare child starts rather than adding a baseline row; rule spawnSafety's own frozen baseline is legacy debt for files that predate it, not a standing allowance a new file gets to claim")
fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/retrySessionHangTest.XXXXXX" 5000) "")))
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
        (env (listAppend (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
                   (str "ASL_CALIBRATION_INDEX=" temp "/absent.asn")) (fr/cacheEnv!)))
        ; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "fix NOSELFHOST-RETRYCONC: a bare procSpawnv here was an un-bounded, un-tree-tracked child start (rule spawnSafety); fr/spawn is the same asl/tools/fleet/run.asl every other fleet caller starts children through, and its killTree! below (rather than a bare negative-pid procKill) takes the whole process tree this one row of /bin/sh -c ... could have grown, not just the shell's own pid")
        (running (fr/spawn 0 (fr/job (list "/bin/sh" "-c" command) (resultOr (realPath ".") ".") env)))
        (pid (match running ((ok r) r.pid) ((err _) 0)))
        (gatewayPort (if (> pid 0) (waitPort! readyPath 500) 0))
        (w0 (World :listener listener :gatewayPort gatewayPort :stubs (list) :seen (list) :clients (list)))

        (start (nowMs!))
        ; (:m bounded red proof per rule spawnSafety: pre-fix, the retry resubmits into the pool and pays :windowMs a second time; 10 s is a generous outer bound that turns a genuine unbounded hang into a deterministic red failure rather than blocking the runner, never a measurement of which code path ran -- that proof is an event, not a duration, and lives in chatParityTest.asl's retriedTransportOp/firstTransportOpOfRetryConfig, which assert the retried attempt's effect is effHttp, never effPoolHttp again)
        (w1 (pump! (send! w0 "mRetry" "a1") (fn [(x World)] -> Bool (clientsDone? x (list "a1"))) (+ start 10000)))

        (killed (if (> pid 0) (do (fr/killTree! pid) true) false))
        (pipesClosed (match running ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (closed (do (map (fn [(s StubConn)] -> Bool (do (fdClose s.fd) true)) w1.stubs)
                  (map (fn [(c Client)] -> Bool (if c.done true (do (fdClose c.fd) true))) w1.clients)
                  (fdClose listener) true))
        (gatewayErr (resultOr (fileReadString (str temp "/gateway.err")) ""))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and wrote (> gatewayPort 0)) (str "gateway started on a scratch HOME, " gatewayErr))
      (assert (clientsDone? w1 (list "a1")) (str "a request to a :sessionHeader+:pool provider with :retry configured must finish within 10 s, not hang past it: " gatewayErr))
      (assert (stringContains? (clientOf w1 "a1").response "HTTP/1.1 200") (str "the retried call eventually succeeds: " (clientOf w1 "a1").response " " gatewayErr))
      (assert (>= (occurrencesOf w1.seen "retry-target") 2) (str "the stub must see both the original 429 and the retried call, saw " (occurrencesOf w1.seen "retry-target") " hit(s)"))
      (assert (listAll? (fn [(s Seen)] -> Bool (not (stringEmpty? s.sessionHeader))) w1.seen) "every hit the stub saw (including the retry) carried a non-empty x-opencode-session header")
      (assert (stringContains? gatewayErr "[Gateway Retry]") (str "the gateway's own retry-decision log line must appear once the 429 is classified as transient: " gatewayErr))
      (assert (and killed (and pipesClosed (and closed removed))) "the gateway process tree, its spawn pipes, sockets and temp dir are all cleaned up")
      true))
