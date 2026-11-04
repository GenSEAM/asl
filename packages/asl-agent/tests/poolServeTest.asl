(module aslAgent/tests/poolServeTest
  :x [runTests]
  :i [(aslAgent/sessionPool :a sp) (aslAgent/poolServe :a ps) (asl-tools/fleet/run :a fr)])

; (:m :ref SE5-SERVE-ENTRY :do "the control socket of one pool process, on a scripted in-process hub: submit queues (:queued), a duplicate or a path-like id is refused, a receipt is running until the session ends and then a file-backed done with its result, 40 sessions with memCap 4 all leave a receipt file while the pool holds no finished session in memory, (:status) reports the counters and (:stop) sets the stop flag")
(schema Stub
  (:f fd Int64)
  (:f input String)
  (:f replyAt Int64))

(schema Hub
  (:f listener Int64)
  (:f stubs (List Stub))
  (:f seen Int64))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

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

fn okReply -> String
  (let [(body "ok")]
    (str "HTTP/1.1 200 OK\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn withStubs h: Hub stubs: (List Stub) -> Hub
  (with h :stubs stubs)

fn withSeen h: Hub seen: Int64 -> Hub
  (with h :seen seen)

fn ! stepStub! h: Hub s: Stub ready: (List (Pair Int64 Int64)) delayMs: Int64 -> Hub
  (cond
    ((> s.replyAt 0)
      (if (>= (nowMs!) s.replyAt)
        (do (fdWrite s.fd (okReply)) (fdClose s.fd) (withSeen h (+ h.seen 1)))
        (withStubs h (listAppend h.stubs (list s)))))
    ((not (ready? ready s.fd)) (withStubs h (listAppend h.stubs (list s))))
    (else
      (match (fdRead s.fd 65536)
        ((err _) (do (fdClose s.fd) h))
        ((ok chunk)
          (if (stringEmpty? chunk) (do (fdClose s.fd) h)
            (let [(input (str s.input chunk))]
              (withStubs h (listAppend h.stubs (list (Stub :fd s.fd :input input :replyAt (if (complete? input) (+ (nowMs!) delayMs) 0)))))))))))

fn ! stepHub! h: Hub ready: (List (Pair Int64 Int64)) delayMs: Int64 -> Hub
  (let [(accepted (if (ready? ready h.listener)
                    (match (sockAccept h.listener)
                      ((ok fd) (withStubs h (listAppend h.stubs (list (Stub :fd fd :input "" :replyAt 0)))))
                      ((err _) h))
                    h))]
    (fold (fn [(acc Hub) (s Stub)] -> Hub (stepStub! acc s ready delayMs)) (withStubs accepted (list)) accepted.stubs))

fn hubWatch h: Hub -> (List (Pair Int64 Int64))
  (cons (pair h.listener 1) (map (fn [(s Stub)] -> (Pair Int64 Int64) (pair s.fd 1)) h.stubs))

; (:m :ref POOL-SERVE :do "scripted turn function: state left:K counts the turns still to send, the reply content is ignored")
fn doneWith r: String -> sp/Turn
  (sp/Turn :state "end" :request none :exec none :result (some r))

fn shellExec script: String timeoutS: Int64 -> sp/Exec
  (sp/Exec :argv (list "/bin/sh" "-c" script) :cwd "/tmp" :env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin"))) :timeoutS timeoutS :maxDesc 8)

fn turnFn state: String reply: String -> sp/Turn
  (cond
    ((= state "gate") (sp/Turn :state "gated" :request none :exec (some (shellExec "sleep 1; echo gate" 20)) :result none))
    ((= state "gated") (doneWith reply))
    ((= state "kill") (sp/Turn :state "killed" :request none :exec (some (shellExec "sleep 30" 1)) :result none))
    ((= state "killed") (doneWith reply))
    ((= state "nobin") (sp/Turn :state "nobinDone" :request none :exec (some (sp/Exec :argv (list "/nonexistent/binary") :cwd "/tmp" :env (list) :timeoutS 5 :maxDesc 0)) :result none))
    ((= state "nobinDone") (doneWith reply))
    (else
      (let [(left (optionOr (stringToInt64 (optionOr (stringSlice state 5 (stringLength state)) "0")) 0))]
        (if (<= left 0) (doneWith "(:ok)")
          (sp/Turn :state (str "left:" (stringFromInt64 (- left 1))) :request (some "{\"m\":1}") :exec none :result none)))))

fn ! pumpServe! s: ps/Serve h: Hub until: (fn [ps/Serve] -> Bool) deadline: Int64 -> (Pair ps/Serve Hub)
  (if (or (until s) (>= (nowMs!) deadline)) (pair s h)
    (match (fdPoll (listAppend (hubWatch h) (ps/serveWatch s)) 10)
      ((err _) (pumpServe! s h until deadline))
      ((ok ready) (pumpServe! (ps/serveStep! s ready turnFn (nowMs!)) (stepHub! h ready 40) until deadline))))

fn ! readLine! fd: Int64 acc: String attempts: Int64 -> String
  (if (or (<= attempts 0) (stringContains? acc "\n")) acc
    (match (fdPoll (list (pair fd 1)) 20)
      ((err _) acc)
      ((ok r) (if (listEmpty? r) (readLine! fd acc (- attempts 1))
                (match (fdRead fd 65536)
                  ((ok chunk) (if (stringEmpty? chunk) acc (readLine! fd (str acc chunk) (- attempts 1))))
                  ((err _) acc))))))

; (:m :ref SE5-SERVE-ENTRY :do "client and server share this thread: the line is sent, then server and hub are stepped for 100 ms, then the reply line is read")
fn ! ask! s: ps/Serve h: Hub sock: String line: String -> (Pair (Pair ps/Serve Hub) String)
  (match (unixConnect sock)
    ((err e) (pair (pair s h) (str "CONNECTFAILED " e)))
    ((ok fd)
      (let [(sent (fdWrite fd (str line "\n")))
            (out (pumpServe! s h (fn [(x ps/Serve)] -> Bool false) (+ (nowMs!) 100)))
            (text (readLine! fd "" 50))
            (closed (fdClose fd))]
        (pair out (stringTrim text)))))

fn ! receiptsReady! dir: String ids: (List String) -> Bool
  (listAll? (fn [(id String)] -> Bool (fileExists? (ps/receiptPath dir id))) ids)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/poolServeTest.XXXXXX" 5000) "")))
        (hubSock (str temp "/hub.sock"))
        (ctlSock (str temp "/ctl.sock"))
        (rdir (str temp "/receipts"))
        (made (and (ok? (dirCreate rdir)) (ok? (dirCreate (str temp "/spill")))))
        (hubL (resultOr (unixListen hubSock) -1))
        (ctlL (resultOr (unixListen ctlSock) -1))
        (h0 (Hub :listener hubL :stubs (list) :seen 0))
        (s0 (ps/newServe ctlL (sp/newPool hubSock 4 4 60000 (str temp "/spill")) rdir))
        (r1 (ask! s0 h0 ctlSock "(:submit :unit \"u1\" :state \"left:30\")"))
        (r2 (ask! (pairFirst (pairFirst r1)) (pairSecond (pairFirst r1)) ctlSock "(:submit :unit \"u1\" :state \"left:30\")"))
        (r3 (ask! (pairFirst (pairFirst r2)) (pairSecond (pairFirst r2)) ctlSock "(:submit :unit \"../x\" :state \"left:1\")"))
        (r4 (ask! (pairFirst (pairFirst r3)) (pairSecond (pairFirst r3)) ctlSock "(:receipt :unit \"u1\")"))
        (w1 (pumpServe! (pairFirst (pairFirst r4)) (pairSecond (pairFirst r4)) (fn [(x ps/Serve)] -> Bool (receiptsReady! rdir (list "u1"))) (+ (nowMs!) 10000)))
        (r5 (ask! (pairFirst w1) (pairSecond w1) ctlSock "(:receipt :unit \"u1\")"))
        (ids (map (fn [(i Int64)] -> String (str "m" (stringFromInt64 i))) (range 0 40)))
        (batch (fold (fn [(acc (Pair ps/Serve Hub)) (id String)] -> (Pair ps/Serve Hub)
                       (pairFirst (ask! (pairFirst acc) (pairSecond acc) ctlSock (str "(:submit :unit \"" id "\" :state \"left:1\")"))))
                 (pairFirst r5) ids))
        (r6 (ask! (pairFirst batch) (pairSecond batch) ctlSock "(:status)"))
        (w2 (pumpServe! (pairFirst (pairFirst r6)) (pairSecond (pairFirst r6)) (fn [(x ps/Serve)] -> Bool (receiptsReady! rdir ids)) (+ (nowMs!) 20000)))
        (finalServe (pairFirst w2))
        (r7 (ask! finalServe (pairSecond w2) ctlSock "(:status)"))
        (r8 (ask! (pairFirst (pairFirst r7)) (pairSecond (pairFirst r7)) ctlSock "(:stop)"))
        (stopped (pairFirst (pairFirst r8)))
        (reply1 (pairSecond r1)) (reply2 (pairSecond r2)) (reply3 (pairSecond r3)) (reply4 (pairSecond r4)) (reply5 (pairSecond r5))
        (status1 (pairSecond r6)) (status2 (pairSecond r7)) (reply8 (pairSecond r8))
        (closed (do (map (fn [(st Stub)] -> Bool (do (fdClose st.fd) true)) (pairSecond w2).stubs) (fdClose hubL) (fdClose ctlL) true))
        (allReceipts (receiptsReady! rdir ids))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and made (stringContains? reply1 "(:queued :unit \"u1\")")) (str "submit is queued: " reply1))
      (assert (stringContains? reply2 "duplicate") (str "a duplicate id is refused: " reply2))
      (assert (stringContains? reply3 "bad id") (str "a path-like id is refused: " reply3))
      (assert (stringContains? reply4 ":state \"running\"") (str "a receipt before the end is running: " reply4))
      (assert (and (stringContains? reply5 ":state \"done\"") (stringContains? reply5 "(:ok)")) (str "the receipt is done with the result: " reply5))
      (assert allReceipts "all 40 sessions left a receipt file")
      (assert (<= (listLength (sp/poolDone finalServe.pool)) 0) "no finished session stays in memory")
      (assert (<= finalServe.pool.peakMem 4) (str "memCap 4 held: " (stringFromInt64 finalServe.pool.peakMem)))
      (assert (and (stringContains? status1 "(:pool :active") (stringContains? status2 ":waiting 0")) (str "status reports the counters: " status1 " / " status2))
      (assert (and stopped.stop (stringContains? reply8 "stopping")) (str "stop sets the flag: " reply8))
      (assert (and closed removed) "sockets closed and temp dir removed")
      true))
