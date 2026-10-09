(module asl-net/reactor
  :x [Reactor ReactorRegistration ReactorEvent
      makeReactor reactorRegister reactorUnregister reactorPoll reactorNextEvent!
      reactorActiveCount EVENT_READ EVENT_WRITE EVENT_ERROR isRegistered?
      Server Connection HttpEvent ServerConfig ProcEntry
      httpListen! reactorStep! httpRespond! httpClose! httpStreamChunk! reactorAddProc! tryParseRequests int64ToHex
      serverConnCount makeServerConfig
      mkRequestEvent mkClosedEvent mkErrorEvent mkProcDoneEvent mkProcTimeoutEvent mkProcErrorEvent
      reactorPollTimeoutMs responseHeaders writeAll!]
  :i [(asl-http/http11 :a http)])

fn EVENT_READ -> Int64
  1
fn EVENT_WRITE -> Int64
  2
fn EVENT_ERROR -> Int64
  4

(schema ReactorRegistration
  (:f fd Int64)
  (:f interestMask Int64)
  (:f tag String))

(schema ReactorEvent
  (:f fd Int64)
  (:f readyMask Int64)
  (:f tag String))

(schema Reactor
  (:f registrations (List ReactorRegistration))
  (:f eventQueue (List ReactorEvent))
  (:f maxEvents Int64)
  (:f activeCount Int64))

fn makeReactor maxEvents: Int64 -> Reactor
  (let [(boundedMax (if (<= maxEvents 0) 1024 maxEvents))]
    (Reactor :registrations (list) :eventQueue (list) :maxEvents boundedMax :activeCount 0))

fn reactorActiveCount reactor: Reactor -> Int64
  reactor.activeCount

fn isRegistered? regs: (List ReactorRegistration) targetFd: Int64 -> Bool
  (listAny? (fn [(r ReactorRegistration)] (= r.fd targetFd)) regs)

fn reactorRegister reactor: Reactor fd: Int64 interestMask: Int64 tag: String -> (Result Reactor String)
  (if (or (< fd 3) (> fd 256))
    (err "ERR_REACTOR_INVALID_FD")
    (if (<= interestMask 0)
      (err "ERR_REACTOR_INVALID_INTEREST_MASK")
      (let [(regs reactor.registrations)]
        (if (isRegistered? regs fd)
          (err "ERR_REACTOR_ALREADY_REGISTERED")
          (let [(newReg (ReactorRegistration :fd fd :interestMask interestMask :tag tag))
                (updatedRegs (listAppend regs (list newReg)))
                (newCount (+ reactor.activeCount 1))]
            (ok (with reactor :registrations updatedRegs :activeCount newCount)))))))

fn reactorUnregister reactor: Reactor targetFd: Int64 -> (Result Reactor String)
  (if (or (< targetFd 3) (> targetFd 256))
    (err "ERR_REACTOR_INVALID_FD")
    (let [(regs reactor.registrations)]
      (if (not (isRegistered? regs targetFd))
        (err "ERR_REACTOR_NOT_REGISTERED")
        (let [(filtered (filter (fn [(r ReactorRegistration)] (!= r.fd targetFd)) regs))
              (newCount (- reactor.activeCount 1))]
          (ok (with reactor :registrations filtered :activeCount newCount))))))

fn readyMaskFor ready: (List (Pair Int64 Int64)) fd: Int64 -> (Option Int64)
  (mt (listHead (filter (fn [(p (Pair Int64 Int64))] (= (pairFirst p) fd)) ready))
    ((none) (none))
    ((some p) (some (pairSecond p))))

fn ! reactorPoll reactor: Reactor timeoutMs: Int64 -> (Result (Pair Reactor (List ReactorEvent)) String)
  (if (< timeoutMs 0)
    (err "ERR_REACTOR_INVALID_TIMEOUT")
    (let [(regs reactor.registrations)]
      (mt (fdPoll (map (fn [(r ReactorRegistration)] (pair r.fd r.interestMask)) regs) timeoutMs)
        ((err e) (err (str "ERR_REACTOR_POLL: " e)))
        ((ok ready)
          (let [(events (fold (fn [(acc (List ReactorEvent)) (r ReactorRegistration)]
                                (mt (readyMaskFor ready r.fd)
                                  ((none) acc)
                                  ((some m) (listAppend acc (list (ReactorEvent :fd r.fd :readyMask m :tag r.tag))))))
                              (list) regs))]
            (ok (pair (with reactor :registrations regs :eventQueue events)
                      events)))))))

fn popEvent reactor: Reactor -> (Pair Reactor (Option ReactorEvent))
  (mt (listHead reactor.eventQueue)
    ((none) (pair reactor (none)))
    ((some firstEvt)
      (pair (with reactor :eventQueue (optionOr (listTail reactor.eventQueue) (list)))
            (some firstEvt))))

fn ! reactorNextEvent! reactor: Reactor -> (Result (Pair Reactor (Option ReactorEvent)) String)
  (if (listEmpty? reactor.eventQueue)
    (mt (reactorPoll reactor 0)
      ((err e) (err e))
      ((ok polled) (ok (popEvent (pairFirst polled)))))
    (ok (popEvent reactor)))


(schema ServerConfig
  (:f maxHeaderBytes Int64)
  (:f clientTimeoutMs Int64)
  (:f maxConnections Int64))

fn makeServerConfig -> ServerConfig
  (ServerConfig :maxHeaderBytes 8192 :clientTimeoutMs 30000 :maxConnections 128)

(schema Connection
  (:f fd Int64)
  (:f connId Int64)
  (:f buffer String)
  (:f lastActivityNs Int64)
  (:f chunkedMode Bool))

(schema ProcEntry
  (:f handle Int64)
  (:f stdoutFd Int64)
  (:f stderrFd Int64)
  (:f stdout String)
  (:f stderr String)
  (:f deadlineNs Int64))

(schema Server
  (:f listenerFd Int64)
  (:f nextConnId Int64)
  (:f connections (List Connection))
  (:f procs (List ProcEntry))
  (:f config ServerConfig))

(schema HttpEvent
  (:f kind String)
  (:f connId Int64)
  (:f method String)
  (:f path String)
  (:f headers (List (Pair String String)))
  (:f body String)
  (:f statusCode Int64)
  (:f handle Int64)
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String)
  (:f reason String))

fn mkRequestEvent cid: Int64 m: String p: String hdrs: (List (Pair String String)) b: String -> HttpEvent
  (HttpEvent :kind "request" :connId cid :method m :path p :headers hdrs :body b :statusCode 0 :handle 0 :exitCode 0 :stdout "" :stderr "" :reason "")

fn mkClosedEvent cid: Int64 -> HttpEvent
  (HttpEvent :kind "closed" :connId cid :method "" :path "" :headers (list) :body "" :statusCode 0 :handle 0 :exitCode 0 :stdout "" :stderr "" :reason "")

fn mkErrorEvent cid: Int64 code: Int64 r: String -> HttpEvent
  (HttpEvent :kind "error" :connId cid :method "" :path "" :headers (list) :body "" :statusCode code :handle 0 :exitCode 0 :stdout "" :stderr "" :reason r)

fn mkProcDoneEvent h: Int64 ec: Int64 sout: String serr: String -> HttpEvent
  (HttpEvent :kind "procDone" :connId 0 :method "" :path "" :headers (list) :body "" :statusCode 0 :handle h :exitCode ec :stdout sout :stderr serr :reason "")

fn mkProcTimeoutEvent h: Int64 sout: String serr: String r: String -> HttpEvent
  (HttpEvent :kind "procTimeout" :connId 0 :method "" :path "" :headers (list) :body "" :statusCode 0 :handle h :exitCode 0 :stdout sout :stderr serr :reason r)

fn mkProcErrorEvent h: Int64 r: String -> HttpEvent
  (HttpEvent :kind "procError" :connId 0 :method "" :path "" :headers (list) :body "" :statusCode 0 :handle h :exitCode 0 :stdout "" :stderr "" :reason r)

fn serverConnCount server: Server -> Int64
  (listLength server.connections)

fn httpListen! port: Int64 config: ServerConfig -> (Result Server String)
  (mt (tcpListen port)
    ((err e) (err (str "ERR_LISTEN: " e)))
    ((ok listenerFd)
      (mt (fdNonBlocking listenerFd true)
        ((err e) (do (fdClose listenerFd) (err (str "ERR_NONBLOCK: " e))))
        ((ok _)
          (ok (Server
            :listenerFd listenerFd
            :nextConnId 1
            :connections (list)
            :procs (list)
            :config config))))))

fn acceptNewClients! server: Server nowNs: Int64 -> (Pair Server (List HttpEvent))
  (mt (sockAccept server.listenerFd)
    ((err _) (pair server (list)))
    ((ok clientFd)
      (if (>= (listLength server.connections) server.config.maxConnections)
        (do (fdClose clientFd) (pair server (list)))
        (mt (fdNonBlocking clientFd true)
          ((err _) (do (fdClose clientFd) (pair server (list))))
          ((ok _)
            (let [(cid server.nextConnId)
                  (conn (Connection :fd clientFd :connId cid :buffer "" :lastActivityNs nowNs :chunkedMode false))
                  (newServer (with server :nextConnId (+ cid 1) :connections (listAppend server.connections (list conn))))]
              (pair newServer (list))))))))

fn removeConn conns: (List Connection) targetFd: Int64 -> (List Connection)
  (filter (fn [(c Connection)] (!= c.fd targetFd)) conns)

fn findConnByFd conns: (List Connection) targetFd: Int64 -> (Option Connection)
  (let [(found (filter (fn [(c Connection)] (= c.fd targetFd)) conns))]
    (listHead found))

fn chunkedBodyEnd buf: String pos: Int64 -> (Result (Option Int64) String)
  (let [(rest (optionOr (stringSlice buf pos (stringLength buf)) ""))]
    (mt (stringIndexOf rest "\r\n")
      ((none) (ok (none)))
      ((some lineEnd)
        (let [(sizeLine (optionOr (stringSlice rest 0 lineEnd) ""))
              (sizeText (mt (stringIndexOf sizeLine ";") ((some semi) (optionOr (stringSlice sizeLine 0 semi) "")) ((none) sizeLine)))
              (dataStart (+ pos (+ lineEnd 2)))]
          (mt (parseHexSize (stringTrim sizeText) 0 0)
            ((none) (err "ERR_HTTP_INVALID_CHUNK_SIZE"))
            ((some size)
              (if (= size 0)
                (let [(trailers (optionOr (stringSlice buf dataStart (stringLength buf)) ""))]
                  (if (stringStartsWith? trailers "\r\n")
                    (ok (some (+ dataStart 2)))
                    (mt (stringIndexOf trailers "\r\n\r\n")
                      ((none) (ok (none)))
                      ((some t) (ok (some (+ dataStart (+ t 4))))))))
                (let [(dataEnd (+ dataStart size))]
                  (cond
                    ((< (stringLength buf) (+ dataEnd 2)) (ok (none)))
                    ((!= (optionOr (stringSlice buf dataEnd (+ dataEnd 2)) "") "\r\n") (err "ERR_HTTP_INVALID_CHUNK_TERMINATION"))
                    (else (chunkedBodyEnd buf (+ dataEnd 2))))))))))))

fn parseHexSize text: String i: Int64 acc: Int64 -> (Option Int64)
  (if (>= i (stringLength text))
    (if (= i 0) (none) (some acc))
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))
          (digit (stringIndexOf "0123456789abcdef" (stringLower c)))]
      (mt digit
        ((none) (none))
        ((some d) (if (> acc 34359738367) (none) (parseHexSize text (+ i 1) (+ (* acc 16) d)))))))

fn requestLength buf: String headerLen: Int64 -> (Result (Option Int64) String)
  (mt (http/parseHttpRequest (optionOr (stringSlice buf 0 headerLen) ""))
    ((err e) (err e))
    ((ok head)
      (if (= (stringLower (optionOr (http/getHeaderFromHeaders head.headers "Transfer-Encoding") "")) "chunked")
        (chunkedBodyEnd buf headerLen)
        (mt (http/getHeaderFromHeaders head.headers "Content-Length")
          ((none) (ok (some headerLen)))
          ((some text)
            (mt (stringToInt64 (stringTrim text))
              ((none) (err "ERR_HTTP_INVALID_CONTENT_LENGTH"))
              ((some n)
                (cond
                  ((< n 0) (err "ERR_HTTP_INVALID_CONTENT_LENGTH"))
                  ((< (stringLength buf) (+ headerLen n)) (ok (none)))
                  (else (ok (some (+ headerLen n))))))))))))

fn tryParseRequests conn: Connection maxHeaderBytes: Int64 -> (Pair Connection (List HttpEvent))
  (let [(buf conn.buffer)
        (headerEnd (stringIndexOf buf "\r\n\r\n"))]
    (mt headerEnd
      ((none)
        (if (> (stringLength buf) maxHeaderBytes)
          (pair conn (list (mkErrorEvent conn.connId 431 "ERR_HEADER_TOO_LARGE")))
          (pair conn (list))))
      ((some endIdx)
        (if (> endIdx maxHeaderBytes)
          (pair conn (list (mkErrorEvent conn.connId 431 "ERR_HEADER_TOO_LARGE")))
          (mt (requestLength buf (+ endIdx 4))
            ((err e) (pair conn (list (mkErrorEvent conn.connId 400 e))))
            ((ok complete) (mt complete
            ((none) (pair conn (list)))
            ((some reqLen)
              (let [(rawReq (optionOr (stringSlice buf 0 reqLen) ""))
                    (rest (optionOr (stringSlice buf reqLen (stringLength buf)) ""))]
                (mt (http/parseHttpRequest rawReq)
                  ((err e) (pair conn (list (mkErrorEvent conn.connId 400 e))))
                  ((ok parsed)
                    (let [(evt (mkRequestEvent conn.connId parsed.method parsed.path parsed.headers.entries parsed.body))
                          (updatedConn (with conn :buffer rest))]
                      (if (> (stringLength rest) 0)
                        (let [(moreRes (tryParseRequests updatedConn maxHeaderBytes))]
                          (pair (pairFirst moreRes) (cons evt (pairSecond moreRes))))
                        (pair updatedConn (list evt)))))))))))))))

fn readFromConn! conn: Connection nowNs: Int64 maxHeaderBytes: Int64 -> (Pair Connection (List HttpEvent))
  (mt (fdRead conn.fd 4096)
    ((err _)
      (pair conn (list (mkClosedEvent conn.connId))))
    ((ok data)
      (if (= (stringLength data) 0)
        (pair conn (list (mkClosedEvent conn.connId)))
        (let [(updated (with conn :buffer (str conn.buffer data) :lastActivityNs nowNs))]
          (tryParseRequests updated maxHeaderBytes)))))

fn checkTimeouts! conns: (List Connection) nowNs: Int64 timeoutNs: Int64 -> (Pair (List Connection) (List HttpEvent))
  (fold (fn [(acc (Pair (List Connection) (List HttpEvent))) (c Connection)]
    (if (> (- nowNs c.lastActivityNs) timeoutNs)
      (do (fdClose c.fd)
        (pair (pairFirst acc) (listAppend (pairSecond acc) (list (mkClosedEvent c.connId)))))
      (pair (listAppend (pairFirst acc) (list c)) (pairSecond acc))))
    (pair (list) (list)) conns)

fn drainFd! fd: Int64 acc: String -> (Result (Pair String Bool) String)
  (mt (fdRead fd 65536)
    ((err e) (if (= e "wouldBlock") (ok (pair acc false)) (err e)))
    ((ok data) (if (= (stringLength data) 0) (ok (pair acc true)) (drainFd! fd (str acc data)))))

fn closeProcFds! p: ProcEntry -> Unit
  (do (fdClose p.stdoutFd) (fdClose p.stderrFd) ())

fn stepProc! p: ProcEntry nowNs: Int64 -> (Pair (Option ProcEntry) (List HttpEvent))
  (mt (drainFd! p.stdoutFd p.stdout)
    ((err e) (do (closeProcFds! p) (pair (none) (list (mkProcErrorEvent p.handle (str "stdout read failed: " e))))))
    ((ok outRes)
      (mt (drainFd! p.stderrFd p.stderr)
        ((err e) (do (closeProcFds! p) (pair (none) (list (mkProcErrorEvent p.handle (str "stderr read failed: " e))))))
        ((ok errRes)
          (let [(sout (pairFirst outRes))
                (serr (pairFirst errRes))
                (running (with p :stdout sout :stderr serr))]
            (mt (procWaitPid p.handle true)
              ((err e) (do (closeProcFds! p) (pair (none) (list (mkProcErrorEvent p.handle (str "wait failed: " e))))))
              ((ok status)
                (mt status
                  ((some code)
                    (let [(tailOut (mt (drainFd! p.stdoutFd sout) ((ok r) (pairFirst r)) ((err _) sout)))
                          (tailErr (mt (drainFd! p.stderrFd serr) ((ok r) (pairFirst r)) ((err _) serr)))]
                      (do (closeProcFds! p) (pair (none) (list (mkProcDoneEvent p.handle code tailOut tailErr))))))
                  ((none)
                    (if (and (> p.deadlineNs 0) (> nowNs p.deadlineNs))
                      (let [(killed (procKill (- 0 p.handle) "SIGKILL"))
                            (reaped (procWaitPid p.handle false))
                            (reason (mt killed
                                      ((err e) (str "kill failed: " e))
                                      ((ok _) (mt reaped ((err e) (str "killed; reap failed: " e)) ((ok _) "killed")))))]
                        (do (closeProcFds! p) (pair (none) (list (mkProcTimeoutEvent p.handle sout serr reason)))))
                      (pair (some running) (list))))))))))))

fn checkProcs! server: Server nowNs: Int64 -> (Pair Server (List HttpEvent))
  (let [(result (fold (fn [(acc (Pair (List ProcEntry) (List HttpEvent))) (p ProcEntry)]
                  (let [(step (stepProc! p nowNs))]
                    (pair (mt (pairFirst step) ((some kept) (listAppend (pairFirst acc) (list kept))) ((none) (pairFirst acc)))
                          (listAppend (pairSecond acc) (pairSecond step)))))
                  (pair (list) (list)) server.procs))]
    (pair (with server :procs (pairFirst result))
      (pairSecond result)))

fn processConnEvents! server: Server readyFds: (List (Pair Int64 Int64)) nowNs: Int64 -> (Pair Server (List HttpEvent))
  (let [(maxHdr server.config.maxHeaderBytes)]
    (fold (fn [(acc (Pair Server (List HttpEvent))) (rp (Pair Int64 Int64))]
      (let [(fd (pairFirst rp))
            (srv (pairFirst acc))]
        (mt (findConnByFd srv.connections fd)
          ((none) acc)
          ((some conn)
            (let [(res (readFromConn! conn nowNs maxHdr))
                  (updatedConn (pairFirst res))
                  (newEvents (pairSecond res))
                  (hasClosed (listAny? (fn [(ev HttpEvent)] (= ev.kind "closed")) newEvents))
                  (hasError (listAny? (fn [(ev HttpEvent)] (= ev.kind "error")) newEvents))
                  (eventConn (if hasError (Connection :fd updatedConn.fd :connId updatedConn.connId :buffer "" :lastActivityNs updatedConn.lastActivityNs :chunkedMode updatedConn.chunkedMode) updatedConn))
                  (newConns (if hasClosed
                    (do (fdClose updatedConn.fd) (removeConn srv.connections fd))
                    (map (fn [(c Connection)] (if (= c.fd fd) eventConn c)) srv.connections)))
                  (newSrv (Server :listenerFd srv.listenerFd :nextConnId srv.nextConnId
                    :connections newConns :procs srv.procs :config srv.config))]
              (pair newSrv (listAppend (pairSecond acc) newEvents)))))))
      (pair server (list)) readyFds))

fn reactorPollTimeoutMs procs: (List ProcEntry) nowNs: Int64 requestedMs: Int64 -> Int64
  (fold (fn [(best Int64) (p ProcEntry)] -> Int64
          (let [(deadline p.deadlineNs)]
            (if (<= deadline 0) best
              (if (<= deadline nowNs) 0
                (let [(untilDeadline (max 1 (/ (- deadline nowNs) 1000000)))]
                  (if (< best 0) untilDeadline (min best untilDeadline)))))))
        requestedMs procs)

fn reactorStep! server: Server timeoutMs: Int64 -> (Result (Pair Server (List HttpEvent)) String)
  (let [(nowNs (monotonicNs))
        (timeoutNs (* server.config.clientTimeoutMs 1000000))
        (toRes (checkTimeouts! server.connections nowNs timeoutNs))
        (activeConns (pairFirst toRes))
        (timeoutEvents (pairSecond toRes))
        (srv1 (with server :connections activeConns))
        (procRes (checkProcs! srv1 nowNs))
        (srv2 (pairFirst procRes))
        (procEvents (pairSecond procRes))
        (pollPairs (cons (pair srv2.listenerFd 1) (map (fn [(c Connection)] (pair c.fd 1)) srv2.connections)))]
    (mt (fdPoll pollPairs (reactorPollTimeoutMs srv2.procs nowNs timeoutMs))
      ((err e) (err e))
      ((ok readyPairs)
        (let [(listenerReady (listAny? (fn [(rp (Pair Int64 Int64))] (= (pairFirst rp) srv2.listenerFd)) readyPairs))
              (accRes (if listenerReady (acceptNewClients! srv2 nowNs) (pair srv2 (list))))
              (srv3 (pairFirst accRes))
              (connReadyPairs (filter (fn [(rp (Pair Int64 Int64))] (!= (pairFirst rp) srv3.listenerFd)) readyPairs))
              (connRes (processConnEvents! srv3 connReadyPairs nowNs))
              (srv4 (pairFirst connRes))
              (connEvents (pairSecond connRes))]
          (ok (pair srv4 (listAppend timeoutEvents (listAppend procEvents connEvents))))))))

fn writeAll! fd: Int64 data: String offset: Int64 deadlineNs: Int64 -> (Result Unit String)
  (if (>= offset (stringLength data)) (ok (do))
    (let [(chunk (optionOr (stringSlice data offset (stringLength data)) ""))]
      (mt (fdWrite fd chunk)
        ((err e)
          (if (!= e "wouldBlock") (err e)
            (let [(leftMs (/ (- deadlineNs (monotonicNs)) 1000000))]
              (if (<= leftMs 0) (err "ERR_WRITE_TIMEOUT")
                (mt (fdPoll (list (pair fd 2)) leftMs)
                  ((err pe) (err pe))
                  ((ok _) (writeAll! fd data offset deadlineNs)))))))
        ((ok n)
          (if (<= n 0) (err "ERR_WRITE_ZERO")
            (writeAll! fd data (+ offset n) deadlineNs))))))

fn writeDeadline! server: Server -> Int64
  (+ (monotonicNs) (* server.config.clientTimeoutMs 1000000))

fn hasHeader? headers: (List (Pair String String)) name: String -> Bool
  (listAny? (fn [(h (Pair String String))] -> Bool (= (stringLower (stringTrim (pairFirst h))) name)) headers)

fn responseHeaders headers: (List (Pair String String)) body: String -> (List (Pair String String))
  (let [(chunked (listAny? (fn [(h (Pair String String))] -> Bool
                             (and (= (stringLower (stringTrim (pairFirst h))) "transfer-encoding") (= (stringLower (stringTrim (pairSecond h))) "chunked"))) headers))]
    (cond
      (chunked (filter (fn [(h (Pair String String))] -> Bool (!= (stringLower (stringTrim (pairFirst h))) "content-length")) headers))
      ((hasHeader? headers "content-length") headers)
      (else (listAppend headers (list (pair "Content-Length" (stringFromInt64 (stringLength body))))))))

fn findConnById conns: (List Connection) targetId: Int64 -> (Option Connection)
  (let [(found (filter (fn [(c Connection)] (= c.connId targetId)) conns))]
    (listHead found))

fn httpRespond! server: Server connId: Int64 statusCode: Int64 headers: (List (Pair String String)) body: String -> (Result Server String)
  (mt (findConnById server.connections connId)
    ((none) (err "ERR_CONN_NOT_FOUND"))
    ((some conn)
      (let [(response (http/formatHttpResponse (http/makeResponse statusCode (cond ((= statusCode 200) "OK") ((= statusCode 204) "No Content") ((= statusCode 400) "Bad Request") ((= statusCode 404) "Not Found") ((= statusCode 431) "Request Header Fields Too Large") ((= statusCode 408) "Request Timeout") ((= statusCode 500) "Internal Server Error") (else "Unknown")) (http/makeHeaders (responseHeaders headers body)) body)))]
        (mt (writeAll! conn.fd response 0 (writeDeadline! server))
          ((err e) (err (str "ERR_RESPOND: " e)))
          ((ok _) (ok server))))))

fn int64ToHex value: Int64 -> String
  (if (< value 16) (optionOr (stringSlice "0123456789abcdef" value (+ value 1)) "0")
    (str (int64ToHex (/ value 16)) (optionOr (stringSlice "0123456789abcdef" (- value (* (/ value 16) 16)) (+ (- value (* (/ value 16) 16)) 1)) "0")))

fn httpClose! server: Server connId: Int64 -> (Result Server String)
  (mt (findConnById server.connections connId)
    ((none) (err "ERR_CONN_NOT_FOUND"))
    ((some conn)
      (mt (fdClose conn.fd)
        ((err e) (err e))
        ((ok _)
          (ok (with server :connections (removeConn server.connections conn.fd)))))))

fn httpStreamChunk! server: Server connId: Int64 chunk: String -> (Result Server String)
  (mt (findConnById server.connections connId)
    ((none) (err "ERR_CONN_NOT_FOUND"))
    ((some conn)
      (if (stringEmpty? chunk)
        (mt (writeAll! conn.fd "0\r
\r
" 0 (writeDeadline! server))
          ((err e) (err (str "ERR_STREAM: " e)))
          ((ok _)
            (let [(updatedConns (map (fn [(c Connection)] (if (= c.connId connId) (Connection :fd c.fd :connId c.connId :buffer c.buffer :lastActivityNs c.lastActivityNs :chunkedMode false) c)) server.connections))]
              (ok (with server :connections updatedConns)))))
        (let [(hexLen (int64ToHex (stringLength chunk)))
              (frame (str hexLen "\r
" chunk "\r
"))]
          (mt (writeAll! conn.fd frame 0 (writeDeadline! server))
            ((err e) (err (str "ERR_STREAM: " e)))
            ((ok _)
              (let [(updatedConns (map (fn [(c Connection)] (if (= c.connId connId) (Connection :fd c.fd :connId c.connId :buffer c.buffer :lastActivityNs c.lastActivityNs :chunkedMode true) c)) server.connections))]
                (ok (with server :connections updatedConns)))))))))

fn reactorAddProc! server: Server pid: Int64 stdoutFd: Int64 stderrFd: Int64 timeoutMs: Int64 -> (Result Server String)
  (mt (fdNonBlocking stdoutFd true)
    ((err e) (err (str "stdout non-blocking: " e)))
    ((ok _)
      (mt (fdNonBlocking stderrFd true)
        ((err e) (err (str "stderr non-blocking: " e)))
        ((ok _)
          (let [(deadlineNs (if (<= timeoutMs 0) 0 (+ (monotonicNs) (* timeoutMs 1000000))))
                (entry (ProcEntry :handle pid :stdoutFd stdoutFd :stderrFd stderrFd :stdout "" :stderr "" :deadlineNs deadlineNs))]
            (ok (with server :procs (listAppend server.procs (list entry)))))))))
