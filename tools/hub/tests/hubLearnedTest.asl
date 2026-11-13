(module asl-tools/hub/tests/hubLearnedTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (aslGateway/tests/gatewayStartKit :a sk) (aslGateway/server :a srv)])

; (:m :ref ORCH-HUB-STATUS :do "GET /hub/status on a running hub: idle it reports no streams and no admit samples; with two clients on one rpm 12 model one is parked, so one stream waits and the bucket shows a queue of 1; after both are answered the admit wait has 2 samples with p50 0 and p95 near the 5 s refill")
(schema StubConn
  (:f fd Int64)
  (:f input String))

(schema Client
  (:f fd Int64)
  (:f tag String)
  (:f response String)
  (:f done Bool))

(schema World
  (:f listener Int64)
  (:f stubs (List StubConn))
  (:f seenMs (List Int64))
  (:f clients (List Client)))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ready? ready: (List (Pair Int64 Int64)) fd: Int64 -> Bool
  (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) fd)) ready)

fn contentLength head: String -> Int64
  (fold (fn [(acc Int64) (line String)] -> Int64
          (if (stringStartsWith? (stringLower line) "content-length:")
            (optionOr (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) ""))) acc) acc))
    0 (stringSplit head "\r\n"))

fn bodyComplete? raw: String -> Bool
  (match (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some end) (>= (- (stringLength raw) (+ end 4)) (contentLength (optionOr (stringSlice raw 0 end) "")))))

fn okReply -> String
  (let [(body "{\"id\":\"stub\",\"object\":\"chat.completion\",\"model\":\"m1-target\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"ok\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")]
    (str "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn ! writeAll! fd: Int64 data: String -> Bool
  (if (stringEmpty? data) true
    (match (fdWrite fd data)
      ((err _) false)
      ((ok n) (if (<= n 0) false (writeAll! fd (optionOr (stringSlice data n (stringLength data)) ""))))))

fn ! stepStub! w: World conn: StubConn ready: (List (Pair Int64 Int64)) -> World
  (if (not (ready? ready conn.fd)) (with w :stubs (listAppend w.stubs (list conn)))
    (match (fdRead conn.fd 65536)
      ((err _) (do (fdClose conn.fd) w))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose conn.fd) w)
          (let [(input (str conn.input chunk))]
            (if (not (bodyComplete? input)) (with w :stubs (listAppend w.stubs (list (with conn :input input))))
              (do (writeAll! conn.fd (okReply)) (fdClose conn.fd)
                (with w :seenMs (listAppend w.seenMs (list (nowMs!)))))))))))

fn ! stepClient! c: Client ready: (List (Pair Int64 Int64)) -> Client
  (if (or c.done (not (ready? ready c.fd))) c
    (match (fdRead c.fd 65536)
      ((err _) (do (fdClose c.fd) (with c :done true)))
      ((ok chunk)
        (if (stringEmpty? chunk) (do (fdClose c.fd) (with c :done true))
          (with c :response (str c.response chunk))))))

fn ! stepWorld! w: World ready: (List (Pair Int64 Int64)) -> World
  (let [(accepted (if (ready? ready w.listener)
                    (match (sockAccept w.listener)
                      ((ok fd) (with w :stubs (listAppend w.stubs (list (StubConn :fd fd :input "")))))
                      ((err _) w))
                    w))
        (stubbed (fold (fn [(acc World) (conn StubConn)] -> World (stepStub! acc conn ready)) (withStubs accepted (list)) accepted.stubs))]
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

fn request -> String
  (let [(body "{\"model\":\"m1\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")]
    (str "POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: "
         (stringFromInt64 (stringLength body)) "\r\n\r\n" body))

fn ! send! w: World conn: (Result Int64 String) tag: String -> World
  (match conn
    ((err e) (with w :clients (listAppend w.clients (list (Client :fd -1 :tag tag :response (str "connect failed " e) :done true)))))
    ((ok fd) (do (writeAll! fd (request))
               (with w :clients (listAppend w.clients (list (Client :fd fd :tag tag :response "" :done false)))))))

fn clientsDone? w: World -> Bool
  (listAll? (fn [(c Client)] -> Bool c.done) w.clients)

fn ok200? w: World -> Bool
  (listAll? (fn [(c Client)] -> Bool (stringStartsWith? c.response "HTTP/1.1 200")) w.clients)

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))

fn ! nativeCliCacheEnvRow! -> String
  (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")))

fn gatewayConfig base: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id stubProv :kind openai :base \"" base "\" :timeoutSec 30))"
       " :models ((:model :id m1 :provider stubProv :name \"m1-target\" :rpm 12))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))\n")

fn envOf temp: String -> (List String)
  (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) (str "ASL_GATEWAY_ROOT=" temp)
        (str "ASL_CALIBRATION_INDEX=" temp "/absent.asn") (nativeCliCacheEnvRow!))

; (:m :ref ORCH-HUB-STATUS :do "children start only through fr/spawn with both fds redirected to files, and are killed as a tree at the end of the test")
fn ! start! temp: String command: String -> Int64
  (match (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " command)) (resultOr (realPath ".") ".") (envOf temp)))
    ((err _) 0)
    ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) r.pid)))

fn ! seenCount! w: World -> Int64
  (listLength w.seenMs)

fn getRequest -> String
  "GET /hub/status HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"

fn ! sendGet! w: World conn: (Result Int64 String) tag: String -> World
  (match conn
    ((err e) (withClients w (listAppend w.clients (list (Client :fd -1 :tag tag :response (str "connect failed " e) :done true)))))
    ((ok fd) (do (writeAll! fd (getRequest))
               (withClients w (listAppend w.clients (list (Client :fd fd :tag tag :response "" :done false)))))))

fn clientOf w: World tag: String -> Client
  (optionOr (listHead (filter (fn [(c Client)] -> Bool (= c.tag tag)) w.clients)) (Client :fd -1 :tag tag :response "" :done false))

fn tagDone? w: World tag: String -> Bool
  (clientOf w tag).done

fn ! statusAt! w: World sock: String tag: String -> World
  (pump! (sendGet! w (unixConnect sock) tag) (fn [(x World)] -> Bool (tagDone? x tag)) (+ (nowMs!) 5000))

; (:m :ref ORCH-AIMD-LIVE :do "a hub whose home holds ratesByName.asn: the bucket of the named model refills at the learned rate (config 12, learned 600), and a second hub with no such file keeps the configured 12")
fn near a: Float64 b: Float64 -> Bool
  (< (abs (- a b)) 0.001)

fn ! bucketRowAt! temp: String learned: Bool -> String
  (let [(listener (resultOr (tcpListen 0) -1))
        (base (str "http://127.0.0.1:" (stringFromInt64 (resultOr (sockLocalPort listener) 0)) "/v1"))
        (sock (str temp "/hub.sock"))
        (wrote (and (ok? (dirCreate (str temp "/.asl/run/hub")))
                 (and (ok? (fileWrite (str temp "/.asl/gateway.asn") (gatewayConfig base)))
                   (and (ok? (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sock "\" :upstream \"" base "\")\n")))
                     (if learned (ok? (fileWrite (str temp "/.asl/run/hub/ratesByName.asn") "(:rate :alias \"m1-target\" :rpm 600.0)\n")) true)))))
        (daemonPid (start! temp (str (hostExe!) " run " (resultOr (realPath "asl/tools/hub/main.asl") "") " serve --ready " temp "/hub.ready 1>" temp "/hub.out 2>" temp "/hub.err")))
        (up (and (> daemonPid 0) (sk/waitFile! (str temp "/hub.ready") daemonPid (str temp "/hub.err"))))
        (w0 (World :listener listener :stubs (list) :seenMs (list) :clients (list)))
        (sent (send! w0 (unixConnect sock) "a"))
        (served (pump! sent (fn [(x World)] -> Bool (tagDone? x "a")) (+ (nowMs!) 8000)))
        (status (statusAt! served sock "st"))
        (text (str (if (and wrote up) "" "NOTUP ") (clientOf status "st").response))
        (killed (if (> daemonPid 0) (do (fr/killTree! daemonPid) true) false))
        (closed (do (map (fn [(s StubConn)] -> Bool (do (fdClose s.fd) true)) status.stubs)
                  (map (fn [(c Client)] -> Bool (if c.done true (do (fdClose c.fd) true))) status.clients)
                  (fdClose listener) true))]
    (if (and killed closed) text "CLEANUPFAILED"))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/hubLearnedTest.XXXXXX" 5000) "")))
        (withRate (bucketRowAt! (str temp "/a") true))
        (without (bucketRowAt! (str temp "/b") false))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (stringContains? withRate ":model \"m1-target\" :rpm 600.0") (str "a learned rate replaces the configured rpm of the bucket: " withRate))
      (assert (stringContains? without ":model \"m1-target\" :rpm 12.0") (str "no store keeps the configured rpm: " without))
      (assert (and (near (srv/hubLearnedFrom "(:rate :alias \"m\" :rpm 24.0 :cfg 20.0)\n" "m" 20.0) 24.0) (near (srv/hubLearnedFrom "(:rate :alias \"m\" :rpm 24.0 :cfg 20.0)\n" "m" 100.0) 24.0)) "a bucket at its configured rpm takes the learned rate (a free model still rises)")
      (assert (near (srv/hubLearnedFrom "(:rate :alias \"m\" :rpm 24.0 :cfg 20.0)\n" "m" 4.288) 4.288) "a bucket paced below its config (subscription pace) is not lifted by a throttled-only learned rate")
      (assert (near (srv/hubLearnedFrom "(:rate :alias \"m\" :rpm 3.0 :cfg 20.0)\n" "m" 4.288) 3.0) "a paced bucket still takes a lower learned rate after real 429s")
      (assert (and (near (srv/hubLearnedFrom "(:rate :alias \"m\" :rpm 24.0 :cfg 20.0)\n" "other" 20.0) 20.0) (near (srv/hubLearnedFrom "" "m" 20.0) 20.0)) "an unlisted model or an absent store keeps the incoming rpm")
      (assert removed "temp dir removed")
      true))

fn withStubs w: World stubs: (List StubConn) -> World
  (with w :stubs stubs)

fn withClients w: World clients: (List Client) -> World
  (with w :clients clients)
