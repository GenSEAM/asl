(module asl-net/tests/loopHttpTest
  :x [runTests]
  :i [(asl-net/reactor :a r)])


fn writeAll! fd: Int64 data: String offset: Int64 -> (Result Int64 String)
  (if (>= offset (stringLength data)) (ok offset)
    (let [(chunk (optionOr (stringSlice data offset (stringLength data)) ""))]
      (mt (fdWrite fd chunk)
        ((err e) (err e))
        ((ok n)
          (if (<= n 0) (err "ERR_WRITE_ZERO")
            (writeAll! fd data (+ offset n)))))))

fn readAll! fd: Int64 acc: String deadline: Int64 -> String
  (if (> (monotonicNs) deadline) acc
    (mt (fdPoll (list (pair fd 1)) 50)
      ((err _) acc)
      ((ok ready)
        (if (listEmpty? ready) acc
          (mt (fdRead fd 4096)
            ((err _) acc)
            ((ok data)
              (if (= (stringLength data) 0) acc
                (readAll! fd (str acc data) deadline))))))))

fn waitForEof! fd: Int64 deadline: Int64 -> Bool
  (if (> (monotonicNs) deadline) false
    (mt (fdPoll (list (pair fd 1)) 50)
      ((err _) false)
      ((ok ready)
        (if (listEmpty? ready) (waitForEof! fd deadline)
          (mt (fdRead fd 4096)
            ((err _) false)
            ((ok data)
              (if (= (stringLength data) 0) true
                (waitForEof! fd deadline))))))))

fn stepUntilEvents! server: r/Server maxSteps: Int64 -> (Pair r/Server (List r/HttpEvent))
  (if (<= maxSteps 0) (pair server (list))
    (mt (r/reactorStep! server 100)
      ((err _) (pair server (list)))
      ((ok result)
        (let [(srv (pairFirst result))
              (evts (pairSecond result))]
          (if (> (listLength evts) 0)
            (pair srv evts)
            (stepUntilEvents! srv (- maxSteps 1)))))))

fn stepCollectEvents! server: r/Server maxSteps: Int64 collected: (List r/HttpEvent) -> (Pair r/Server (List r/HttpEvent))
  (if (<= maxSteps 0) (pair server collected)
    (mt (r/reactorStep! server 50)
      ((err _) (pair server collected))
      ((ok result)
        (let [(srv (pairFirst result))
              (evts (pairSecond result))]
          (stepCollectEvents! srv (- maxSteps 1) (listAppend collected evts))))))


fn testPipelining! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(req1 "GET /first HTTP/1.1\r
Host: localhost\r
\r
")
                      (req2 "GET /second HTTP/1.1\r
Host: localhost\r
\r
")
                      (bodyRequest (str (stringReplace req1 "Host: localhost" "Host: localhost\r\nContent-Length: 5") "hello"))
                      (pipelined (str bodyRequest req2))
                      (_ (writeAll! clientFd pipelined 0))
                      (res (stepCollectEvents! server 30 (list)))
                      (srv (pairFirst res))
                      (evts (pairSecond res))
                      (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) evts))
                      (paths (map (fn [(e r/HttpEvent)] e.path) requests))
                      (firstRequest (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")))
                      (connId (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")).connId)
                      (response (r/httpRespond! srv connId 200 (list) "alive"))]
                  (assert (>= (listLength requests) 2) (str "pipelining: expected >= 2 request events, got " (stringFromInt64 (listLength requests))))
                  (assert (= (optionOr (listHead paths) "") "/first") "pipelining: first request path")
                  (assert (= (optionOr (listGet paths 1) "") "/second") "pipelining: second request path")
                  (assert (= firstRequest.body "hello") "pipelining: Content-Length body delivered exactly")
                  (assert (ok? response) "pipelining: the request connection stays registered for its response")
                  (do (fdClose clientFd) (fdClose srv.listenerFd) true)))))))))


fn testOversizedHeaders! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 128 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(bigHeader (stringJoin (map (fn [_] "X") (range 0 300)) ""))
                      (req (str "GET /big HTTP/1.1\r
Host: localhost\r
X-Big: " bigHeader "\r
\r
"))
                      (_ (writeAll! clientFd req 0))
                      (res (stepCollectEvents! server 30 (list)))
                      (srv (pairFirst res))
                      (evts (pairSecond res))
                      (errors (filter (fn [(e r/HttpEvent)] (= e.kind "error")) evts))]
                  (assert (>= (listLength errors) 1) "oversized headers: got error event")
                  (let [(errEvent (optionOr (listHead errors) (r/mkErrorEvent 0 0 "")))
                        (_ (writeAll! clientFd "X" 0))
                        (retryRes (stepCollectEvents! srv 1 (list)))
                        (srvRetry (pairFirst retryRes))
                        (repeatErrors (filter (fn [(e r/HttpEvent)] (= e.kind "error")) (pairSecond retryRes)))
                        (sent (mt (r/httpRespond! srvRetry errEvent.connId 431 (list) "too large") ((err _) false) ((ok _) true)))
                        (closedRes (r/httpClose! srvRetry errEvent.connId))
                        (srvClosed (mt closedRes ((err _) srvRetry) ((ok s) s)))
                        (reply (readAll! clientFd "" (+ (monotonicNs) 2000000000)))
                        (eof (waitForEof! clientFd (+ (monotonicNs) 1000000000)))]
                    (assert (= errEvent.statusCode 431) "oversized headers: status code 431")
                    (assert (= (listLength repeatErrors) 0) "oversized headers: error buffer is cleared before another read")
                    (assert sent "oversized headers: 431 response sent")
                    (assert (stringContains? reply "HTTP/1.1 431") "oversized headers: wire response")
                    (assert (ok? closedRes) "oversized headers: close succeeds after reply")
                    (assert (= (r/serverConnCount srvClosed) 0) "oversized headers: connection removed after reply")
                    (assert eof "oversized headers: peer observes EOF after 431 reply"))
                  (do (fdClose clientFd) (fdClose srv.listenerFd) true)))))))))


fn testSlowClientTimeout! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 200 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(r1 (stepCollectEvents! server 5 (list)))
                      (srv1 (pairFirst r1))
                      (_ (assert (>= (r/serverConnCount srv1) 1) "slow client: connection accepted"))
                      (_ (sleepMs 350))
                      (r2 (stepCollectEvents! srv1 10 (list)))
                      (srv2 (pairFirst r2))
                      (evts (pairSecond r2))
                      (closedEvts (filter (fn [(e r/HttpEvent)] (= e.kind "closed")) evts))]
                  (assert (>= (listLength closedEvts) 1) "slow client: got closed event from timeout")
                  (do (fdClose clientFd) (fdClose srv2.listenerFd) true)))))))))


fn respondChunked! srv: r/Server connId: Int64 clientFd: Int64 -> Bool
  (mt (r/httpRespond! srv connId 200 (list (pair "Transfer-Encoding" "chunked")) "")
    ((err e) (do (assert false (str "httpRespond: " e)) (fdClose clientFd) (fdClose srv.listenerFd) false))
    ((ok srv2)
      (mt (r/httpStreamChunk! srv2 connId "hello world")
        ((err e) (do (assert false (str "chunk1: " e)) (fdClose clientFd) (fdClose srv2.listenerFd) false))
        ((ok srv3)
          (mt (r/httpStreamChunk! srv3 connId "!")
            ((err e) (do (assert false (str "chunk2: " e)) (fdClose clientFd) (fdClose srv3.listenerFd) false))
            ((ok srv4)
              (mt (r/httpStreamChunk! srv4 connId "")
                ((err e) (do (assert false (str "chunk-end: " e)) (fdClose clientFd) (fdClose srv4.listenerFd) false))
                ((ok srv5)
                  (let [(deadline (+ (monotonicNs) 2000000000))
                        (received (readAll! clientFd "" deadline))]
                    (assert (stringContains? received "200 OK") (str "chunked: got 200 OK: " (optionOr (stringSlice received 0 80) received)))
                    (assert (stringContains? received "Transfer-Encoding: chunked\r\n") "chunked: transfer encoding header")
                    (assert (not (stringContains? received "Content-Length:")) "chunked: no conflicting length")
                    (assert (stringContains? received "\r\nb\r\nhello world\r\n") "chunked: exact hexadecimal framing")
                    (assert (stringContains? received "0\r
\r
") "chunked: terminating chunk")
                    (do (fdClose clientFd) (fdClose srv5.listenerFd) true))))))))))

fn testChunkedTransfer! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(req "GET /stream HTTP/1.1\r
Host: localhost\r
\r
")
                      (_ (writeAll! clientFd req 0))
                      (r1 (stepUntilEvents! server 20))
                      (srv1 (pairFirst r1))
                      (evts1 (pairSecond r1))
                      (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) evts1))
                      (_ (assert (>= (listLength requests) 1) "chunked: got request event"))
                      (connId (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")).connId)]
                  (respondChunked! srv1 connId clientFd)))))))))


fn sendSSE! srv: r/Server connId: Int64 clientFd: Int64 -> Bool
  (mt (r/httpRespond! srv connId 200 (list (pair "Content-Type" "text/event-stream") (pair "Transfer-Encoding" "chunked") (pair "Cache-Control" "no-cache")) "")
    ((err e) (do (assert false (str "SSE header: " e)) (fdClose clientFd) (fdClose srv.listenerFd) false))
    ((ok srv2)
      (mt (r/httpStreamChunk! srv2 connId "data: {\"seq\":1}

")
        ((err e) (do (assert false (str "SSE chunk1: " e)) (fdClose clientFd) (fdClose srv2.listenerFd) false))
        ((ok srv3)
          (mt (r/httpStreamChunk! srv3 connId "data: {\"seq\":2}

")
            ((err e) (do (assert false (str "SSE chunk2: " e)) (fdClose clientFd) (fdClose srv3.listenerFd) false))
            ((ok srv4)
              (let [(deadline (+ (monotonicNs) 2000000000))
                    (received (readAll! clientFd "" deadline))]
                (assert (stringContains? received "text/event-stream") "SSE: Content-Type")
                (assert (stringContains? received "{\"seq\":1}") "SSE: first event")
                (assert (stringContains? received "{\"seq\":2}") "SSE: second event")
                (do (fdClose clientFd) (fdClose srv4.listenerFd) true))))))))

fn testSSE! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(req "GET /events HTTP/1.1\r
Host: localhost\r
Accept: text/event-stream\r
\r
")
                      (_ (writeAll! clientFd req 0))
                      (r1 (stepUntilEvents! server 20))
                      (srv1 (pairFirst r1))
                      (evts1 (pairSecond r1))
                      (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) evts1))
                      (_ (assert (>= (listLength requests) 1) "SSE: got request"))
                      (connId (optionOr (listHead requests) (r/mkRequestEvent 0 "" "" (list) "")).connId)]
                  (sendSSE! srv1 connId clientFd)))))))))


fn spawnChild! script: String -> (Result (Pair Int64 (Pair Int64 Int64)) String)
  (mt (procSpawnv (list "/bin/sh" "-c" script) (none) (none))
    ((err e) (err e))
    ((ok sp) (do (fdClose sp.stdin) (ok (pair sp.pid (pair sp.stdout sp.stderr))))))

fn withChild! server: r/Server script: String timeoutMs: Int64 -> (Result (Pair r/Server Int64) String)
  (mt (spawnChild! script)
    ((err e) (err e))
    ((ok child)
      (mt (r/reactorAddProc! server (pairFirst child) (pairFirst (pairSecond child)) (pairSecond (pairSecond child)) timeoutMs)
        ((err e) (err e))
        ((ok srv) (ok (pair srv (pairFirst child)))))))

fn procEvents evts: (List r/HttpEvent) kind: String -> (List r/HttpEvent)
  (filter (fn [(e r/HttpEvent)] (= e.kind kind)) evts)

fn testProcDone! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (withChild! server "echo hello-proc; echo to-err >&2; exit 3" 5000)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "spawn: " e)) false))
          ((ok added)
            (let [(res (stepCollectEvents! (pairFirst added) 20 (list)))
                  (srv2 (pairFirst res))
                  (procDones (procEvents (pairSecond res) "procDone"))
                  (evt (optionOr (listHead procDones) (r/mkProcDoneEvent 0 0 "" "")))]
              (assert (= (listLength procDones) 1) "procDone: exactly one procDone event")
              (assert (= evt.handle (pairSecond added)) "procDone: event carries the child pid")
              (assert (= evt.exitCode 3) "procDone: exit code 3")
              (assert (= evt.stdout "hello-proc\n") "procDone: stdout is hello-proc")
              (assert (= evt.stderr "to-err\n") "procDone: stderr is to-err")
              (assert (listEmpty? srv2.procs) "procDone: the child leaves the server")
              (do (fdClose srv2.listenerFd) true)))))))

fn testProcTimeout! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (withChild! server "sleep 30 & echo $!; wait" 300)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "spawn: " e)) false))
          ((ok added)
            (let [(t0 (monotonicNs))
                  (first (r/reactorStep! (pairFirst added) 10))
                  (firstMs (/ (- (monotonicNs) t0) 1000000))
                  (srv1 (mt first ((ok p) (pairFirst p)) ((err _) (pairFirst added))))
                  (res (stepCollectEvents! srv1 30 (list)))
                  (srv2 (pairFirst res))
                  (totalMs (/ (- (monotonicNs) t0) 1000000))
                  (timeouts (procEvents (pairSecond res) "procTimeout"))
                  (evt (optionOr (listHead timeouts) (r/mkProcTimeoutEvent 0 "" "" "")))
                  (grandchild (optionOr (stringToInt64 (stringTrim evt.stdout)) 0))]
              (assert (< firstMs 1000) (str "procTimeout: a step with a running child returns promptly, took " (stringFromInt64 firstMs) " ms"))
              (assert (= (listLength timeouts) 1) "procTimeout: exactly one procTimeout event")
              (assert (< totalMs 10000) (str "procTimeout: the 30 s child is ended at its 300 ms deadline, not waited for; took " (stringFromInt64 totalMs) " ms"))
              (assert (and (= evt.handle (pairSecond added)) (= evt.reason "killed")) (str "procTimeout: the child was killed: " evt.reason))
              (assert (err? (procWaitPid (pairSecond added) true)) "procTimeout: the child is already reaped")
              (assert (and (> grandchild 1) (err? (procKill grandchild "SIGCONT"))) "procTimeout: the grandchild in the child's group is gone")
              (assert (listEmpty? srv2.procs) "procTimeout: the child leaves the server")
              (do (fdClose srv2.listenerFd) true)))))))

fn testProcError! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (spawnChild! "exit 0")
          ((err e) (do (fdClose server.listenerFd) (assert false (str "spawn: " e)) false))
          ((ok child)
            (mt (r/reactorAddProc! server (procSelf) (pairFirst (pairSecond child)) (pairSecond (pairSecond child)) 5000)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "reactorAddProc: " e)) false))
              ((ok srv1)
                (let [(res (stepCollectEvents! srv1 3 (list)))
                      (srv2 (pairFirst res))
                      (errors (procEvents (pairSecond res) "procError"))]
                  (procWaitPid (pairFirst child) false)
                  (assert (= (listLength errors) 1) "procError: a wait failure is reported exactly once")
                  (assert (stringContains? (optionOr (listHead errors) (r/mkProcErrorEvent 0 "")).reason "wait failed") "procError: the reason names the wait")
                  (assert (listEmpty? srv2.procs) "procError: the entry is dropped")
                  (do (fdClose srv2.listenerFd) true)))))))))


fn testRequestBodies! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(_ (writeAll! clientFd "POST /v1/chat/completions HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\n\r\nhe" 0))
                      (first (stepCollectEvents! server 10 (list)))
                      (_ (writeAll! clientFd (str "llo" "POST /chunked HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5;ext=1\r\npedia\r\n0\r\n\r\n" "GET /after HTTP/1.1\r\nHost: localhost\r\n\r\n") 0))
                      (second (stepCollectEvents! (pairFirst first) 20 (list)))
                      (srv (pairFirst second))
                      (evts (listAppend (pairSecond first) (pairSecond second)))
                      (requests (filter (fn [(e r/HttpEvent)] (= e.kind "request")) evts))
                      (errors (filter (fn [(e r/HttpEvent)] (= e.kind "error")) evts))
                      (blank (r/mkRequestEvent 0 "" "" (list) ""))]
                  (assert (= (listLength (filter (fn [(e r/HttpEvent)] (= e.kind "request")) (pairSecond first))) 0) "bodies: no request event before the Content-Length body is complete")
                  (assert (listEmpty? errors) "bodies: no error events")
                  (assert (= (listLength requests) 3) (str "bodies: expected 3 request events, got " (stringFromInt64 (listLength requests))))
                  (assert (and (= (optionOr (listHead requests) blank).method "POST") (= (optionOr (listHead requests) blank).body "hello")) "bodies: Content-Length POST body is hello")
                  (assert (and (= (optionOr (listGet requests 1) blank).path "/chunked") (= (optionOr (listGet requests 1) blank).body "Wikipedia")) "bodies: chunked POST body is decoded")
                  (assert (and (= (optionOr (listGet requests 2) blank).path "/after") (= (optionOr (listGet requests 2) blank).body "")) "bodies: the pipelined GET after the bodies parses")
                  (do (fdClose clientFd) (fdClose srv.listenerFd) true)))))))))


fn ! testPeerDisconnectClosesServerFd! -> Bool
  (let [(cfg (r/ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 5000 :maxConnections 128))]
    (mt (r/httpListen! 0 cfg)
      ((err e) (do (assert false (str "httpListen failed: " e)) false))
      ((ok server)
        (mt (sockLocalPort server.listenerFd)
          ((err e) (do (fdClose server.listenerFd) (assert false (str "sockLocalPort: " e)) false))
          ((ok port)
            (mt (tcpConnect port)
              ((err e) (do (fdClose server.listenerFd) (assert false (str "tcpConnect: " e)) false))
              ((ok clientFd)
                (let [(accepted (stepCollectEvents! server 10 (list)))
                      (srv1 (pairFirst accepted))
                      (serverFd (mt (listHead srv1.connections) ((some c) c.fd) ((none) -1)))
                      (_ (fdClose clientFd))
                      (afterClose (stepCollectEvents! srv1 10 (list)))
                      (srv2 (pairFirst afterClose))
                      (closedEvts (filter (fn [(e r/HttpEvent)] (= e.kind "closed")) (pairSecond afterClose)))]
                  (assert (> serverFd 2) "peer disconnect: the connection was accepted")
                  (assert (= (listLength closedEvts) 1) "peer disconnect: exactly one closed event")
                  (assert (= (r/serverConnCount srv2) 0) "peer disconnect: the connection is removed")
                  (assert (err? (fdClose serverFd)) "peer disconnect: the reactor closed the server-side fd")
                  (do (fdClose srv2.listenerFd) true)))))))))



fn ! runTests -> Bool
  (do
    (assert (testPipelining!) "testPipelining! passed")
    (assert (testOversizedHeaders!) "testOversizedHeaders! passed")
    (assert (testSlowClientTimeout!) "testSlowClientTimeout! passed")
    (assert (testChunkedTransfer!) "testChunkedTransfer! passed")
    (assert (testSSE!) "testSSE! passed")
    (assert (testProcDone!) "testProcDone! passed")
    (assert (testProcTimeout!) "testProcTimeout passed")
    (assert (testProcError!) "testProcError passed")
    (assert (testRequestBodies!) "testRequestBodies passed")
    (assert (testPeerDisconnectClosesServerFd!) "testPeerDisconnectClosesServerFd passed")
    true)
