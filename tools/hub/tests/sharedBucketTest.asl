(module asl-tools/hub/tests/sharedBucketTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/readyWait :a sk)])

; (:m :ref ORCH-SHARED-BUCKET :do "gates the one-per-node daemon on a scratch HOME: it listens on the unix socket named in HOME/.asl/hub.asn with mode 0600, a second instance is refused by the lock, and two clients of one model through it share exactly one token bucket; the control runs the same two clients through two separate gateway processes, each with its own bucket, and sees two admissions in the same window")
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

; (:m :ref ORCH-SHARED-BUCKET :do "children start only through fr/spawn with both fds redirected to files, and are killed as a tree at the end of the test")
fn ! start! temp: String command: String -> Int64
  (match (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " command)) (resultOr (realPath ".") ".") (envOf temp)))
    ((err _) 0)
    ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) r.pid)))

fn ! seenCount! w: World -> Int64
  (listLength w.seenMs)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/hubTest.XXXXXX" 5000) "")))
        (listener (resultOr (tcpListen 0) -1))
        (base (str "http://127.0.0.1:" (stringFromInt64 (resultOr (sockLocalPort listener) 0)) "/v1"))
        (sock (str temp "/hub.sock"))
        (wrote (and (ok? (dirCreate (str temp "/.asl")))
                 (and (ok? (fileWrite (str temp "/.asl/gateway.asn") (gatewayConfig base)))
                   (ok? (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sock "\" :upstream \"" base "\")\n"))))))
        (host (hostExe!))
        (daemonCmd (str host " run " (resultOr (realPath "asl/tools/hub/main.asl") "") " serve --ready " temp "/hub.ready 1>" temp "/hub.out 2>" temp "/hub.err"))
        (daemonPid (start! temp daemonCmd))
        (up (and (> daemonPid 0) (sk/waitFile! (str temp "/hub.ready") daemonPid (str temp "/hub.err"))))
        (w0 (World :listener listener :stubs (list) :seenMs (list) :clients (list)))
        (a1 (send! (send! w0 (unixConnect sock) "a") (unixConnect sock) "b"))
        (a2 (pump! a1 (fn [(x World)] -> Bool false) (+ (nowMs!) 3000)))
        (admittedShared (seenCount! a2))
        (parkedShared (not (clientsDone? a2)))
        (a3 (pump! a2 clientsDone? (+ (nowMs!) 12000)))
        (drainedShared (and (clientsDone? a3) (and (ok200? a3) (= (seenCount! a3) 2))))
        (killedDaemon (if (> daemonPid 0) (do (fr/killTree! daemonPid) true) false))
        (gwA (start! temp (str host " run " (resultOr (realPath "asl/packages/asl-gateway/src/server.asl") "") " serve --port 0 --upstream " base " --ready " temp "/gwA.ready 1>" temp "/gwA.out 2>" temp "/gwA.err")))
        (gwB (start! temp (str host " run " (resultOr (realPath "asl/packages/asl-gateway/src/server.asl") "") " serve --port 0 --upstream " base " --ready " temp "/gwB.ready 1>" temp "/gwB.out 2>" temp "/gwB.err")))
        (portOf (fn [(name String) (pid Int64)] -> Int64 (sk/waitPortErr! (str temp "/" name ".ready") pid (str temp "/" name ".err"))))
        (portA (portOf "gwA" gwA))
        (portB (portOf "gwB" gwB))
        (b0 (World :listener listener :stubs (list) :seenMs (list) :clients (list)))
        (b1 (send! (send! b0 (tcpConnect portA) "a") (tcpConnect portB) "b"))
        (b2 (pump! b1 (fn [(x World)] -> Bool false) (+ (nowMs!) 3000)))
        (admittedSeparate (seenCount! b2))
        (killedGw (do (if (> gwA 0) (fr/killTree! gwA) 0) (if (> gwB 0) (fr/killTree! gwB) 0) true))
        (daemonErr (resultOr (fileReadString (str temp "/hub.err")) ""))
        (closed (do (map (fn [(s StubConn)] -> Bool (do (fdClose s.fd) true)) (listAppend a3.stubs b2.stubs))
                  (map (fn [(c Client)] -> Bool (if c.done true (do (fdClose c.fd) true))) (listAppend a3.clients b2.clients))
                  (fdClose listener) true))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and wrote up) (str "daemon ready on a scratch HOME: " daemonErr))
      (assert (= admittedShared 1) (str "two clients of one model through the daemon get one bucket's worth of admissions in the window, got " (stringFromInt64 admittedShared)))
      (assert parkedShared "the second client is parked on the shared bucket, not answered")
      (assert drainedShared "the parked client is answered 200 once the bucket refills")
      (assert (= admittedSeparate 2) (str "control: two separate gateways each admit one in the same window, got " (stringFromInt64 admittedSeparate)))
      (assert (and killedDaemon (and killedGw (and closed removed))) "processes, sockets and the temp dir are cleaned up")
      true))

fn withStubs w: World stubs: (List StubConn) -> World
  (with w :stubs stubs)

fn withClients w: World clients: (List Client) -> World
  (with w :clients clients)
